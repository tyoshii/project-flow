#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/init.sh"

LOG_FILE="$LOG_DIR/accept.log"
log_info "Accept ウォッチャーを起動しました" | tee -a "$LOG_FILE"

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
  log_info "Accept ステータスの issue をチェック中..." | tee -a "$LOG_FILE"

  items=$(get_items_by_status "$STATUS_ACCEPT")
  count=$(echo "$items" | jq 'length')

  if [[ "$count" -eq 0 ]]; then
    log_info "Accept ステータスの issue はありません" | tee -a "$LOG_FILE"
  else
    log_info "Accept ステータスの issue が ${count} 件あります" | tee -a "$LOG_FILE"

    echo "$items" | jq -c '.[]' | while read -r item; do
      item_id=$(echo "$item" | jq -r '.itemId')
      issue_number=$(echo "$item" | jq -r '.number')
      issue_title=$(echo "$item" | jq -r '.title')

      log_info "Issue #${issue_number} (${issue_title}) を処理中..." | tee -a "$LOG_FILE"

      pr_url=$(get_linked_pr "$issue_number")

      if [[ -n "$pr_url" ]]; then
        pr_number=$(echo "$pr_url" | grep -oE '[0-9]+$')
        pr_state=$(gh pr view "$pr_number" --repo "$REPO" --json state --jq '.state' 2>/dev/null || echo "")

        if [[ "$pr_state" == "OPEN" ]]; then
          log_info "PR #${pr_number} をマージします..." | tee -a "$LOG_FILE"
          if gh pr merge "$pr_number" --repo "$REPO" --merge 2>>"$LOG_FILE"; then
            log_info "PR #${pr_number} のマージ完了" | tee -a "$LOG_FILE"
          else
            log_error "PR #${pr_number} のマージに失敗しました" | tee -a "$LOG_FILE"
            add_issue_comment "$issue_number" "🤖 Accept: PR #${pr_number} のマージに失敗しました。手動で確認してください。"
            continue
          fi
        else
          log_info "PR #${pr_number} は既に ${pr_state} です" | tee -a "$LOG_FILE"
        fi
      else
        log_warn "Issue #${issue_number}: 関連 PR が見つかりません" | tee -a "$LOG_FILE"
      fi

      gh issue close "$issue_number" --repo "$REPO" 2>>"$LOG_FILE" || true
      move_item_to_status "$item_id" "$STATUS_DONE"
      add_issue_comment "$issue_number" "🤖 Accept: PR マージ & クローズ完了。"
      log_info "Issue #${issue_number} → Done" | tee -a "$LOG_FILE"
    done
  fi

  log_info "${POLL_INTERVAL}秒後に再チェックします..." | tee -a "$LOG_FILE"
  sleep "$POLL_INTERVAL"
done
