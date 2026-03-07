#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/init.sh"

LOG_FILE="$LOG_DIR/analysis.log"
log_info "Analysis ウォッチャーを起動しました" | tee -a "$LOG_FILE"

while true; do
  log_info "Analysis ステータスの issue をチェック中..." | tee -a "$LOG_FILE"

  items=$(get_items_by_status "$STATUS_ANALYSIS")
  count=$(echo "$items" | jq 'length')

  if [[ "$count" -eq 0 ]]; then
    log_info "Analysis ステータスの issue はありません" | tee -a "$LOG_FILE"
  else
    log_info "Analysis ステータスの issue が ${count} 件あります" | tee -a "$LOG_FILE"

    echo "$items" | jq -c '.[]' | while read -r item; do
      item_id=$(echo "$item" | jq -r '.itemId')
      issue_number=$(echo "$item" | jq -r '.number')
      issue_title=$(echo "$item" | jq -r '.title')

      log_info "Issue #${issue_number} (${issue_title}) を分析中..." | tee -a "$LOG_FILE"

      details=$(get_issue_details "$issue_number")
      title=$(echo "$details" | jq -r '.title')
      body=$(echo "$details" | jq -r '.body // ""')
      labels=$(echo "$details" | jq -r '[.labels.nodes[].name] | join(", ")')
      comments=$(echo "$details" | jq -r '.comments.nodes[] | "[\(.author.login) at \(.createdAt)]: \(.body)"' 2>/dev/null || echo "")

      prompt="$(cat "$PROMPTS_DIR/analysis.md")

## Issue #${issue_number}
Title: ${title}
Body:
${body}

Labels: ${labels}

Comments:
${comments}
"

      log_info "Claude を起動して Issue #${issue_number} を分析します..." | tee -a "$LOG_FILE"

      repo_path=$(get_repo_path)
      claude_output=$(run_claude \
        "Analysis #${issue_number}" \
        "$prompt" \
        '"Bash(read-only:*)" "Read" "Glob" "Grep" "WebSearch" "WebFetch"' \
        "$repo_path") || {
        log_error "Claude の実行に失敗しました (Issue #${issue_number})" | tee -a "$LOG_FILE"
        continue
      }

      log_info "Claude 出力 (Issue #${issue_number}):" >> "$LOG_FILE"
      echo "$claude_output" >> "$LOG_FILE"

      action=$(echo "$claude_output" | grep -oE '\[(QUESTIONS|SPLIT|READY)\]' | head -1 || echo "[READY]")

      case "$action" in
        "[QUESTIONS]")
          log_info "Issue #${issue_number}: 質問あり → Backlog に戻します" | tee -a "$LOG_FILE"
          comment_body="## 🤖 Analysis: 確認事項

${claude_output}

---
*自動分析による質問です。回答後、再度 Analysis に移動してください。*"
          add_issue_comment "$issue_number" "$comment_body"
          move_item_to_status "$item_id" "$STATUS_BACKLOG"
          ;;

        "[SPLIT]")
          log_info "Issue #${issue_number}: 分割推奨 → サブ issue を作成します" | tee -a "$LOG_FILE"

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

            log_info "サブ issue 作成: ${sub_title}" | tee -a "$LOG_FILE"
            sub_body_full="Parent: #${issue_number}

${sub_body}"
            new_issue_url=$(gh issue create --repo "$REPO" \
              --title "$sub_title" \
              --body "$sub_body_full" 2>>"$LOG_FILE") || continue

            log_info "作成完了: ${new_issue_url}" | tee -a "$LOG_FILE"
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
              log_info "Project に追加: #${new_issue_number} → Backlog" | tee -a "$LOG_FILE"
            fi
            created_issues="${created_issues}
- ${new_issue_url}"
          done

          rm -rf "$split_tmp"

          comment_body="## 🤖 Analysis: タスク分割

以下のサブ issue を作成し、Backlog に追加しました:
${created_issues}

---
*元 issue は Backlog に戻します。*"
          add_issue_comment "$issue_number" "$comment_body"
          move_item_to_status "$item_id" "$STATUS_BACKLOG"
          ;;

        "[READY]")
          log_info "Issue #${issue_number}: 分析完了 → Dev に移動します" | tee -a "$LOG_FILE"
          comment_body="## 🤖 Analysis: 実装計画

${claude_output}

---
*自動分析が完了しました。Dev フェーズに移行します。*"
          add_issue_comment "$issue_number" "$comment_body"
          move_item_to_status "$item_id" "$STATUS_DEV"
          ;;
      esac

      log_info "Issue #${issue_number} の処理が完了しました" | tee -a "$LOG_FILE"
    done
  fi

  log_info "${POLL_INTERVAL}秒後に再チェックします..." | tee -a "$LOG_FILE"
  sleep "$POLL_INTERVAL"
done
