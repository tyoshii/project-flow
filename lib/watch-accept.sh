#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/init.sh"

LOG_FILE="$LOG_DIR/accept.log"
log_info "Accept watcher started" | tee -a "$LOG_FILE"

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
  log_info "Checking for Accept issues..." | tee -a "$LOG_FILE"

  items=$(get_items_by_status "$STATUS_ACCEPT")
  count=$(echo "$items" | jq 'length')

  if [[ "$count" -eq 0 ]]; then
    log_info "No issues in Accept" | tee -a "$LOG_FILE"
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
            add_issue_comment "$issue_number" "🤖 Accept: Failed to merge PR #${pr_number}. Please check manually."
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
      add_issue_comment "$issue_number" "🤖 Accept: PR merged & issue closed."
      log_info "Issue #${issue_number} -> Done" | tee -a "$LOG_FILE"
    done
  fi

  log_info "Next check in ${POLL_INTERVAL}s..." | tee -a "$LOG_FILE"
  sleep "$POLL_INTERVAL"
done
