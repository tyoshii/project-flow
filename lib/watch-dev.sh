#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/init.sh"

LOG_FILE="$LOG_DIR/dev.log"
log_info "Dev ウォッチャーを起動しました" | tee -a "$LOG_FILE"

while true; do
  log_info "Dev ステータスの issue をチェック中..." | tee -a "$LOG_FILE"

  items=$(get_items_by_status "$STATUS_DEV")
  count=$(echo "$items" | jq 'length')

  if [[ "$count" -eq 0 ]]; then
    log_info "Dev ステータスの issue はありません" | tee -a "$LOG_FILE"
  else
    log_info "Dev ステータスの issue が ${count} 件あります" | tee -a "$LOG_FILE"

    echo "$items" | jq -c '.[]' | while read -r item; do
      item_id=$(echo "$item" | jq -r '.itemId')
      issue_number=$(echo "$item" | jq -r '.number')
      issue_title=$(echo "$item" | jq -r '.title')

      log_info "Issue #${issue_number} (${issue_title}) の実装を開始します..." | tee -a "$LOG_FILE"

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
- Local path: ${repo_path}
- Branch name to use: ${branch_name}
- Base branch: main
"

      log_info "Claude を起動して Issue #${issue_number} を実装します..." | tee -a "$LOG_FILE"

      claude_output=$(run_claude \
        "Dev #${issue_number}" \
        "$prompt" \
        '"Bash" "Read" "Edit" "Write" "Glob" "Grep" "WebSearch" "WebFetch"' \
        "$repo_path") || {
        log_error "Claude の実行に失敗しました (Issue #${issue_number})" | tee -a "$LOG_FILE"
        comment_body="🤖 Dev: 実装失敗 — Claude の実行中にエラーが発生しました。"
        add_issue_comment "$issue_number" "$comment_body"
        move_item_to_status "$item_id" "$STATUS_ANALYSIS"
        continue
      }

      log_info "Claude 出力 (Issue #${issue_number}):" >> "$LOG_FILE"
      echo "$claude_output" >> "$LOG_FILE"

      pr_url=$(echo "$claude_output" | grep -oE 'https://github.com/[^/]+/[^/]+/pull/[0-9]+' | head -1 || echo "")

      if [[ -n "$pr_url" ]]; then
        log_info "Issue #${issue_number}: PR 作成成功 → Review に移動します ($pr_url)" | tee -a "$LOG_FILE"
        comment_body="🤖 Dev: 実装完了 — PR ${pr_url} を作成しました。Review に移行します。"
        add_issue_comment "$issue_number" "$comment_body"
        move_item_to_status "$item_id" "$STATUS_REVIEW"
      else
        log_warn "Issue #${issue_number}: PR URL が見つかりません → Analysis に戻します" | tee -a "$LOG_FILE"
        comment_body="🤖 Dev: PR の作成に至りませんでした。Analysis に戻します。"
        add_issue_comment "$issue_number" "$comment_body"
        move_item_to_status "$item_id" "$STATUS_ANALYSIS"
      fi

      log_info "Issue #${issue_number} の処理が完了しました" | tee -a "$LOG_FILE"
    done
  fi

  log_info "${POLL_INTERVAL}秒後に再チェックします..." | tee -a "$LOG_FILE"
  sleep "$POLL_INTERVAL"
done
