#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/init.sh"

LOG_FILE="$LOG_DIR/accept.log"
log_info "Accept watcher started" | tee -a "$LOG_FILE"

while true; do
  log_debug "Checking for Accept issues..." >> "$LOG_FILE"

  items=$(get_items_by_status "$STATUS_ACCEPT")
  count=$(echo "$items" | jq 'length')

  if [[ "$count" -eq 0 ]]; then
    log_debug "No issues in Accept" >> "$LOG_FILE"
  else
    log_info "Found ${count} issue(s) in Accept" | tee -a "$LOG_FILE"

    echo "$items" | jq -c '.[]' | while read -r item; do
      item_id=$(echo "$item" | jq -r '.itemId')
      issue_number=$(echo "$item" | jq -r '.number')
      issue_title=$(echo "$item" | jq -r '.title')

      log_info "Processing issue #${issue_number} (${issue_title})..." | tee -a "$LOG_FILE"

      pr_url=$(get_linked_pr "$issue_number")

      if [[ -n "$pr_url" ]]; then
        pr_number=$(echo "$pr_url" | grep -oE '[0-9]+$')
        pr_state=$(gh pr view "$pr_number" --repo "$REPO" --json state --jq '.state' 2>/dev/null || echo "")

        if [[ "$pr_state" == "OPEN" ]]; then
          log_info "Merging PR #${pr_number}..." | tee -a "$LOG_FILE"
          if gh pr merge "$pr_number" --repo "$REPO" --merge 2>>"$LOG_FILE"; then
            log_info "PR #${pr_number} merged successfully" | tee -a "$LOG_FILE"
          else
            log_error "Failed to merge PR #${pr_number}" | tee -a "$LOG_FILE"
            add_issue_comment "$issue_number" "🤖 Accept: $(printf "$(msg "accept.merge_failed")" "$pr_number")"
            continue
          fi
        else
          log_info "PR #${pr_number} is already ${pr_state}" | tee -a "$LOG_FILE"
        fi
      else
        log_warn "Issue #${issue_number}: No linked PR found" | tee -a "$LOG_FILE"
      fi

      gh issue close "$issue_number" --repo "$REPO" 2>>"$LOG_FILE" || true
      move_item_to_status "$item_id" "$STATUS_DONE"
      add_issue_comment "$issue_number" "🤖 Accept: $(msg "accept.done")"
      log_info "Issue #${issue_number} -> Done" | tee -a "$LOG_FILE"
    done
  fi

  log_debug "Next check in ${POLL_INTERVAL}s..." >> "$LOG_FILE"
  sleep "$POLL_INTERVAL"
done
