#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/init.sh"

LOG_FILE="$LOG_DIR/dev.log"
log_info "Dev watcher started" | tee -a "$LOG_FILE"

while true; do
  log_debug "Checking for Dev issues..." >> "$LOG_FILE"

  items=$(get_items_by_status "$STATUS_DEV")
  count=$(echo "$items" | jq 'length')

  if [[ "$count" -eq 0 ]]; then
    log_debug "No issues in Dev" >> "$LOG_FILE"
  else
    log_info "Found ${count} issue(s) in Dev" | tee -a "$LOG_FILE"

    echo "$items" | jq -c '.[]' | while read -r item; do
      item_id=$(echo "$item" | jq -r '.itemId')
      issue_number=$(echo "$item" | jq -r '.number')
      issue_title=$(echo "$item" | jq -r '.title')

      log_info "Starting implementation for issue #${issue_number} (${issue_title})..." | tee -a "$LOG_FILE"

      details=$(get_issue_details "$issue_number")
      title=$(echo "$details" | jq -r '.title')
      body=$(echo "$details" | jq -r '.body // ""')
      labels=$(echo "$details" | jq -r '[.labels.nodes[].name] | join(", ")')
      comments=$(echo "$details" | jq -r '.comments.nodes[] | "[\(.author.login) at \(.createdAt)]: \(.body)"' 2>/dev/null || echo "")

      repo_path=$(get_repo_path)
      safe_title=$(echo "$issue_title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | head -c 50)
      branch_name="issue-${issue_number}-${safe_title}"

      prompt="$(cat "$PROMPTS_DIR/dev.md")

## Issue #${issue_number}
Title: ${title}
Body:
${body}

Labels: ${labels}

Comments (including analysis results):
${comments}

## Repository Info
- Repo: ${REPO}
- Branch name to use: ${branch_name}
- Base branch: main
"

      log_info "Running Claude for issue #${issue_number} (worktree: ${branch_name})..." | tee -a "$LOG_FILE"

      claude_output=$(run_claude \
        "Dev #${issue_number}" \
        "$prompt" \
        '"Bash" "Read" "Edit" "Write" "Glob" "Grep" "WebSearch" "WebFetch"' \
        "$repo_path" \
        "$branch_name") || {
        log_error "Claude execution failed for issue #${issue_number}" | tee -a "$LOG_FILE"
        reason=$(echo "$claude_output" | tail -30 | head -c 2000)
        summary=$(summarize_failure "$claude_output" "implementation")
        comment_body="🤖 Dev: $(msg "dev.failed_execution")

### $(msg "dev.failure_summary")
${summary}

<details><summary>$(msg "dev.claude_output")</summary>

\`\`\`
${reason}
\`\`\`

</details>"
        add_issue_comment "$issue_number" "$comment_body"
        move_item_to_status "$item_id" "$STATUS_BACKLOG"
        continue
      }

      log_info "Claude output for issue #${issue_number}:" >> "$LOG_FILE"
      echo "$claude_output" >> "$LOG_FILE"

      pr_url=$(echo "$claude_output" | grep -oE 'https://github.com/[^/]+/[^/]+/pull/[0-9]+' | head -1 || echo "")

      if [[ -n "$pr_url" ]]; then
        log_info "Issue #${issue_number}: PR created -> moving to Review ($pr_url)" | tee -a "$LOG_FILE"
        comment_body="🤖 Dev: $(printf "$(msg "dev.success")" "$pr_url")"
        add_issue_comment "$issue_number" "$comment_body"
        move_item_to_status "$item_id" "$STATUS_REVIEW"
      else
        log_warn "Issue #${issue_number}: No PR URL found -> moving back to Backlog" | tee -a "$LOG_FILE"
        reason=$(echo "$claude_output" | tail -30 | head -c 2000)
        summary=$(summarize_failure "$claude_output" "PR creation")
        comment_body="🤖 Dev: $(msg "dev.failed_pr")

### $(msg "dev.failure_summary")
${summary}

<details><summary>$(msg "dev.claude_output")</summary>

\`\`\`
${reason}
\`\`\`

</details>"
        add_issue_comment "$issue_number" "$comment_body"
        move_item_to_status "$item_id" "$STATUS_BACKLOG"
      fi

      log_debug "Issue #${issue_number} processing complete" >> "$LOG_FILE"
    done
  fi

  log_debug "Next check in ${POLL_INTERVAL}s..." >> "$LOG_FILE"
  sleep "$POLL_INTERVAL"
done
