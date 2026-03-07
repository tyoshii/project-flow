#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/init.sh"

LOG_FILE="$LOG_DIR/review.log"
log_info "Review watcher started" | tee -a "$LOG_FILE"

get_linked_pr() {
  local issue_number="$1"
  local pr_url
  pr_url=$(gh api "repos/${REPO}/issues/${issue_number}/comments" \
    --jq '.[].body' 2>/dev/null \
    | grep -oE 'https://github.com/[^/]+/[^/]+/pull/[0-9]+' \
    | tail -1 || echo "")

  if [[ -z "$pr_url" ]]; then
    pr_url=$(gh api "repos/${REPO}/issues/${issue_number}/timeline" \
      --jq '.[] | select(.event == "cross-referenced") | .source.issue.pull_request.html_url // empty' \
      2>/dev/null | tail -1 || echo "")
  fi
  echo "$pr_url"
}

while true; do
  log_debug "Checking for Review issues..." >> "$LOG_FILE"

  items=$(get_items_by_status "$STATUS_REVIEW")
  count=$(echo "$items" | jq 'length')

  if [[ "$count" -eq 0 ]]; then
    log_debug "No issues in Review" >> "$LOG_FILE"
  else
    log_info "Found ${count} issue(s) in Review" | tee -a "$LOG_FILE"

    echo "$items" | jq -c '.[]' | while read -r item; do
      item_id=$(echo "$item" | jq -r '.itemId')
      issue_number=$(echo "$item" | jq -r '.number')
      issue_title=$(echo "$item" | jq -r '.title')

      log_info "Starting review for issue #${issue_number} (${issue_title})..." | tee -a "$LOG_FILE"

      pr_url=$(get_linked_pr "$issue_number")

      if [[ -z "$pr_url" ]]; then
        log_warn "Issue #${issue_number}: No linked PR found -> moving back to Dev" | tee -a "$LOG_FILE"
        add_issue_comment "$issue_number" "🤖 Review: No linked PR found. Moving back to Dev."
        move_item_to_status "$item_id" "$STATUS_DEV"
        continue
      fi

      pr_number=$(echo "$pr_url" | grep -oE '[0-9]+$')
      pr_diff=$(gh pr diff "$pr_number" --repo "$REPO" 2>/dev/null || echo "")
      pr_info=$(gh pr view "$pr_number" --repo "$REPO" --json title,body,files,commits 2>/dev/null || echo "{}")

      details=$(get_issue_details "$issue_number")
      title=$(echo "$details" | jq -r '.title')
      body=$(echo "$details" | jq -r '.body // ""')
      comments=$(echo "$details" | jq -r '.comments.nodes[] | "[\(.author.login) at \(.createdAt)]: \(.body)"' 2>/dev/null || echo "")

      prompt="$(cat "$PROMPTS_DIR/review.md")

## Issue #${issue_number}
Title: ${title}
Body:
${body}

## PR #${pr_number}
URL: ${pr_url}
PR Info:
${pr_info}

## Diff
\`\`\`diff
${pr_diff}
\`\`\`

## Issue Comments (context):
${comments}
"

      log_info "Running Claude to review PR #${pr_number}..." | tee -a "$LOG_FILE"

      repo_path=$(get_repo_path)
      claude_output=$(run_claude \
        "Review #${issue_number} (PR #${pr_number})" \
        "$prompt" \
        '"Bash(read-only:*)" "Read" "Glob" "Grep" "WebSearch" "WebFetch"' \
        "$repo_path") || {
        log_error "Claude execution failed for PR #${pr_number}" | tee -a "$LOG_FILE"
        continue
      }

      log_info "Claude output for PR #${pr_number}:" >> "$LOG_FILE"
      echo "$claude_output" >> "$LOG_FILE"

      action=$(echo "$claude_output" | grep -oE '\[(LGTM|CHANGES_REQUESTED)\]' | head -1 || echo "[LGTM]")

      case "$action" in
        "[LGTM]")
          log_info "PR #${pr_number}: LGTM -> moving to QA" | tee -a "$LOG_FILE"
          gh pr review "$pr_number" --repo "$REPO" --approve --body "🤖 Auto-review: LGTM

${claude_output}" 2>/dev/null || true
          add_issue_comment "$issue_number" "🤖 Review: LGTM — moving to QA. Please review PR #${pr_number}."
          move_item_to_status "$item_id" "$STATUS_QA"
          ;;

        "[CHANGES_REQUESTED]")
          log_info "PR #${pr_number}: Changes requested -> moving back to Dev" | tee -a "$LOG_FILE"
          gh pr review "$pr_number" --repo "$REPO" --request-changes --body "🤖 Auto-review: Changes Requested

${claude_output}" 2>/dev/null || true
          add_issue_comment "$issue_number" "🤖 Review: Changes requested on PR #${pr_number}. Moving back to Dev."
          move_item_to_status "$item_id" "$STATUS_DEV"
          ;;
      esac

      log_debug "Issue #${issue_number} processing complete" >> "$LOG_FILE"
    done
  fi

  log_debug "Next check in ${POLL_INTERVAL}s..." >> "$LOG_FILE"
  sleep "$POLL_INTERVAL"
done
