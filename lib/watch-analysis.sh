#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/init.sh"

LOG_FILE="$LOG_DIR/analysis.log"
log_info "Analysis watcher started" | tee -a "$LOG_FILE"

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
  log_debug "Checking for Analysis issues..." >> "$LOG_FILE"

  items=$(get_items_by_status "$STATUS_ANALYSIS")
  count=$(echo "$items" | jq 'length')

  if [[ "$count" -eq 0 ]]; then
    log_debug "No issues in Analysis" >> "$LOG_FILE"
  else
    log_info "Found ${count} issue(s) in Analysis" | tee -a "$LOG_FILE"

    echo "$items" | jq -c '.[]' | while read -r item; do
      item_id=$(echo "$item" | jq -r '.itemId')
      issue_number=$(echo "$item" | jq -r '.number')
      issue_title=$(echo "$item" | jq -r '.title')

      # ループ検出: Analysis の試行回数チェック
      if check_retry_limit "$issue_number" "$item_id" "Analysis"; then
        continue
      fi

      log_info "Analyzing issue #${issue_number} (${issue_title})..." | tee -a "$LOG_FILE"

      details=$(get_issue_details "$issue_number")
      title=$(echo "$details" | jq -r '.title')
      body=$(echo "$details" | jq -r '.body // ""')
      labels=$(echo "$details" | jq -r '[.labels.nodes[].name] | join(", ")')
      comments=$(echo "$details" | jq -r '.comments.nodes[] | "[\(.author.login) at \(.createdAt)]: \(.body)"' 2>/dev/null || echo "")

      # Gather linked PR info
      pr_url=$(get_linked_pr "$issue_number")
      pr_context=""
      if [[ -n "$pr_url" ]]; then
        pr_number=$(echo "$pr_url" | grep -oE '[0-9]+$')
        pr_state=$(gh pr view "$pr_number" --repo "$REPO" --json state --jq '.state' 2>/dev/null || echo "UNKNOWN")
        pr_context="## Linked PR
- URL: ${pr_url}
- State: ${pr_state}
"
      fi

      prompt="$(cat "$PROMPTS_DIR/analysis.md")

## Issue #${issue_number}
Title: ${title}
Body:
${body}

Labels: ${labels}

${pr_context}
## Comments (chronological):
${comments}
"

      log_info "Running Claude for issue #${issue_number}..." | tee -a "$LOG_FILE"

      repo_path=$(get_repo_path)
      claude_output=$(run_claude \
        "Analysis #${issue_number}" \
        "$prompt" \
        '"Bash(read-only:*)" "Read" "Glob" "Grep" "WebSearch" "WebFetch"' \
        "$repo_path") || {
        log_error "Claude execution failed for issue #${issue_number}" | tee -a "$LOG_FILE"
        continue
      }

      log_info "Claude output for issue #${issue_number}:" >> "$LOG_FILE"
      echo "$claude_output" >> "$LOG_FILE"

      action=$(echo "$claude_output" | grep -oE '\[(QUESTIONS|SPLIT|READY|SKIP_TO_QA)\]' | head -1 || echo "[READY]")

      case "$action" in
        "[QUESTIONS]")
          log_info "Issue #${issue_number}: Questions found -> moving to Backlog" | tee -a "$LOG_FILE"
          comment_body="## 🤖 Analysis: Questions

${claude_output}

---
*$(msg "analysis.questions")*"
          add_issue_comment "$issue_number" "$comment_body"
          move_item_to_status "$item_id" "$STATUS_BACKLOG"
          ;;

        "[SPLIT]")
          log_info "Issue #${issue_number}: Split recommended -> creating sub-issues" | tee -a "$LOG_FILE"

          split_tmp=$(mktemp -d)
          echo "$claude_output" | sed -n '/<!-- SPLIT_START -->/,/<!-- SPLIT_END -->/p' > "$split_tmp/section.txt"
          created_issues=""

          sub_idx=0
          current_title=""
          while IFS= read -r line; do
            if echo "$line" | grep -q '<!-- SUB_ISSUE title='; then
              sub_idx=$((sub_idx + 1))
              current_title=$(echo "$line" | sed 's/.*title="\([^"]*\)".*/\1/')
              echo "$current_title" > "$split_tmp/title_${sub_idx}.txt"
              : > "$split_tmp/body_${sub_idx}.txt"
            elif echo "$line" | grep -q '<!-- /SUB_ISSUE -->'; then
              current_title=""
            elif [[ -n "$current_title" ]]; then
              echo "$line" >> "$split_tmp/body_${sub_idx}.txt"
            fi
          done < "$split_tmp/section.txt"

          for i in $(seq 1 "$sub_idx"); do
            sub_title=$(cat "$split_tmp/title_${i}.txt" 2>/dev/null || echo "")
            sub_body=$(cat "$split_tmp/body_${i}.txt" 2>/dev/null || echo "")
            if [[ -z "$sub_title" ]]; then continue; fi

            log_info "Creating sub-issue: ${sub_title}" | tee -a "$LOG_FILE"
            sub_body_full="Parent: #${issue_number}

${sub_body}"
            new_issue_url=$(gh issue create --repo "$REPO" \
              --title "$sub_title" \
              --body "$sub_body_full" 2>>"$LOG_FILE") || continue

            log_info "Created: ${new_issue_url}" | tee -a "$LOG_FILE"
            new_issue_number=$(echo "$new_issue_url" | grep -oE '[0-9]+$')
            new_content_id=$(gh api graphql -f query='
              query($owner: String!, $repo: String!, $number: Int!) {
                repository(owner: $owner, name: $repo) {
                  issue(number: $number) { id }
                }
              }
            ' -f owner="$OWNER" -f repo="$REPO_NAME" -F number="$new_issue_number" \
              --jq '.data.repository.issue.id' 2>>"$LOG_FILE")
            if [[ -n "$new_content_id" ]]; then
              new_item_id=$(add_issue_to_project "$new_content_id")
              move_item_to_status "$new_item_id" "$STATUS_BACKLOG"
              log_info "Added to project: #${new_issue_number} -> Backlog" | tee -a "$LOG_FILE"
            fi
            created_issues="${created_issues}
- ${new_issue_url}"
          done

          rm -rf "$split_tmp"

          comment_body="## 🤖 Analysis: Task Split

$(msg "analysis.split")
${created_issues}

---
*$(msg "analysis.split_move")*"
          add_issue_comment "$issue_number" "$comment_body"
          move_item_to_status "$item_id" "$STATUS_BACKLOG"
          ;;

        "[READY]")
          log_info "Issue #${issue_number}: Analysis complete -> moving to Dev" | tee -a "$LOG_FILE"
          comment_body="## 🤖 Analysis: Implementation Plan

${claude_output}

---
*$(msg "analysis.ready")*"
          add_issue_comment "$issue_number" "$comment_body"
          move_item_to_status "$item_id" "$STATUS_DEV"
          ;;

        "[SKIP_TO_QA]")
          log_info "Issue #${issue_number}: Already resolved -> skipping to QA" | tee -a "$LOG_FILE"
          comment_body="## 🤖 Analysis: Skipping to QA

${claude_output}

---
*$(msg "analysis.skip_qa")*"
          add_issue_comment "$issue_number" "$comment_body"
          move_item_to_status "$item_id" "$STATUS_QA"
          ;;
      esac

      log_debug "Issue #${issue_number} processing complete" >> "$LOG_FILE"
    done
  fi

  log_debug "Next check in ${POLL_INTERVAL}s..." >> "$LOG_FILE"
  sleep "$POLL_INTERVAL"
done
