#!/usr/bin/env bash
# helpers.sh — GitHub Project GraphQL helper functions
# Requires config.sh to be sourced first

# Cached project ID (computed once per process)
_CACHED_PROJECT_ID=""

# Get Project node ID (cached)
get_project_id() {
  if [[ -n "$_CACHED_PROJECT_ID" ]]; then
    echo "$_CACHED_PROJECT_ID"
    return
  fi

  local result
  result=$(gh api graphql -f query='
    query($owner: String!, $number: Int!) {
      organization(login: $owner) {
        projectV2(number: $number) {
          id
        }
      }
    }
  ' -f owner="$OWNER" -F number="$PROJECT_NUMBER" \
    --jq '.data.organization.projectV2.id' 2>/dev/null) && [[ -n "$result" ]] && _CACHED_PROJECT_ID="$result" && echo "$result" && return

  # Fallback to user if not an organization
  result=$(gh api graphql -f query='
    query($owner: String!, $number: Int!) {
      user(login: $owner) {
        projectV2(number: $number) {
          id
        }
      }
    }
  ' -f owner="$OWNER" -F number="$PROJECT_NUMBER" \
    --jq '.data.user.projectV2.id')
  _CACHED_PROJECT_ID="$result"
  echo "$result"
}

# Cached status field JSON (computed once per process)
_CACHED_STATUS_FIELD=""

# Get Status field ID and option IDs (cached)
get_status_field() {
  if [[ -n "$_CACHED_STATUS_FIELD" ]]; then
    echo "$_CACHED_STATUS_FIELD"
    return
  fi

  local project_id
  project_id=$(get_project_id)

  local result
  result=$(gh api graphql -f query='
    query($projectId: ID!) {
      node(id: $projectId) {
        ... on ProjectV2 {
          fields(first: 20) {
            nodes {
              ... on ProjectV2SingleSelectField {
                id
                name
                options {
                  id
                  name
                }
              }
            }
          }
        }
      }
    }
  ' -f projectId="$project_id" \
    --jq '.data.node.fields.nodes[] | select(.name == "'"$STATUS_FIELD_NAME"'")')
  _CACHED_STATUS_FIELD="$result"
  echo "$result"
}

# Validate that all required statuses exist in the project
# Returns 0 if all OK, 1 if missing statuses found
validate_statuses() {
  local status_info
  status_info=$(get_status_field)

  if [[ -z "$status_info" ]]; then
    echo "ERROR: Status field '${STATUS_FIELD_NAME}' not found in Project #${PROJECT_NUMBER}." >&2
    return 1
  fi

  local available
  available=$(echo "$status_info" | jq -r '.options[].name')

  local required_statuses=(
    "$STATUS_BACKLOG"
    "$STATUS_ANALYSIS"
    "$STATUS_DEV"
    "$STATUS_REVIEW"
    "$STATUS_QA"
    "$STATUS_ACCEPT"
    "$STATUS_DONE"
  )

  local missing=()
  for status in "${required_statuses[@]}"; do
    if ! echo "$available" | grep -qx "$status"; then
      missing+=("$status")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Required statuses missing from Project #${PROJECT_NUMBER}:" >&2
    for m in "${missing[@]}"; do
      echo "  - $m" >&2
    done
    echo "" >&2
    echo "Add them at:" >&2
    echo "  https://github.com/orgs/${OWNER}/projects/${PROJECT_NUMBER}/settings" >&2
    echo "  (Personal: https://github.com/users/${OWNER}/projects/${PROJECT_NUMBER}/settings)" >&2
    echo "" >&2
    echo "Available statuses: $(echo "$available" | tr '\n' ', ' | sed 's/,$//')" >&2
    return 1
  fi

  return 0
}

# Get items by status
get_items_by_status() {
  local target_status="$1"
  local project_id
  project_id=$(get_project_id)

  gh api graphql -f query='
    query($projectId: ID!) {
      node(id: $projectId) {
        ... on ProjectV2 {
          items(first: 100) {
            nodes {
              id
              fieldValues(first: 20) {
                nodes {
                  ... on ProjectV2ItemFieldSingleSelectValue {
                    name
                    field {
                      ... on ProjectV2SingleSelectField {
                        name
                      }
                    }
                  }
                }
              }
              content {
                ... on Issue {
                  id
                  number
                  title
                  url
                }
              }
            }
          }
        }
      }
    }
  ' -f projectId="$project_id" \
    --jq '[.data.node.items.nodes[] |
      select(
        .content.number != null and
        (.fieldValues.nodes[] |
          select(.field.name == "'"$STATUS_FIELD_NAME"'" and .name == "'"$target_status"'")
        ) != null
      ) |
      {
        itemId: .id,
        contentId: .content.id,
        number: .content.number,
        title: .content.title,
        url: .content.url
      }
    ]' 2>/dev/null || echo '[]'
}

# Move item to a different status
move_item_to_status() {
  local item_id="$1"
  local target_status="$2"

  local project_id
  project_id=$(get_project_id)

  local status_info
  status_info=$(get_status_field)

  local field_id
  field_id=$(echo "$status_info" | jq -r '.id')

  local option_id
  option_id=$(echo "$status_info" | jq -r '.options[] | select(.name == "'"$target_status"'") | .id')

  if [[ -z "$option_id" ]]; then
    log_warn "Status option '$target_status' not found. Falling back to '${STATUS_BACKLOG}'."
    if [[ "$target_status" == "$STATUS_BACKLOG" ]]; then
      echo "ERROR: Fallback status '${STATUS_BACKLOG}' also not found. Cannot move item." >&2
      return 1
    fi
    option_id=$(echo "$status_info" | jq -r '.options[] | select(.name == "'"$STATUS_BACKLOG"'") | .id')
    if [[ -z "$option_id" ]]; then
      echo "ERROR: Fallback status '${STATUS_BACKLOG}' not found. Cannot move item." >&2
      return 1
    fi
  fi

  gh api graphql -f query='
    mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
      updateProjectV2ItemFieldValue(
        input: {
          projectId: $projectId
          itemId: $itemId
          fieldId: $fieldId
          value: { singleSelectOptionId: $optionId }
        }
      ) {
        projectV2Item {
          id
        }
      }
    }
  ' -f projectId="$project_id" \
    -f itemId="$item_id" \
    -f fieldId="$field_id" \
    -f optionId="$option_id" \
    --silent
}

# Get issue details (body, comments)
get_issue_details() {
  local issue_number="$1"

  gh api graphql -f query='
    query($owner: String!, $repo: String!, $number: Int!) {
      repository(owner: $owner, name: $repo) {
        issue(number: $number) {
          number
          title
          body
          labels(first: 10) {
            nodes { name }
          }
          comments(first: 50) {
            nodes {
              author { login }
              body
              createdAt
            }
          }
        }
      }
    }
  ' -f owner="$OWNER" -f repo="$REPO_NAME" -F number="$issue_number" \
    --jq '.data.repository.issue'
}

# Get linked PR URL for an issue
# Searches issue comments first, then timeline cross-references
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

# Add comment to issue
add_issue_comment() {
  local issue_number="$1"
  local comment_body="$2"
  gh issue comment "$issue_number" --repo "$REPO" --body "$comment_body"
}

# Add issue to Project
add_issue_to_project() {
  local content_id="$1"
  local project_id
  project_id=$(get_project_id)

  gh api graphql -f query='
    mutation($projectId: ID!, $contentId: ID!) {
      addProjectV2ItemById(
        input: {
          projectId: $projectId
          contentId: $contentId
        }
      ) {
        item {
          id
        }
      }
    }
  ' -f projectId="$project_id" \
    -f contentId="$content_id" \
    --jq '.data.addProjectV2ItemById.item.id'
}

# Get local repo path
get_repo_path() {
  if [[ -n "$LOCAL_REPO_PATH" && -d "$LOCAL_REPO_PATH" ]]; then
    echo "$LOCAL_REPO_PATH"
  else
    local repo_dir="$HOME/repos/$REPO_NAME"
    if [[ ! -d "$repo_dir" ]]; then
      log_info "Cloning repository: $REPO -> $repo_dir"
      git clone "git@github.com:${REPO}.git" "$repo_dir"
    fi
    echo "$repo_dir"
  fi
}

# Run Claude and return output
# Usage: run_claude <pane_title> <prompt> <allowed_tools> <work_dir> [worktree_name]
run_claude() {
  local pane_title="$1"
  local prompt="$2"
  local allowed_tools="$3"
  local work_dir="$4"
  local worktree_name="${5:-}"

  local tmp_dir
  tmp_dir=$(mktemp -d)
  local prompt_file="$tmp_dir/prompt.txt"
  local output_file="$tmp_dir/output.txt"

  echo "$prompt" > "$prompt_file"

  local worktree_flag=""
  if [[ -n "$worktree_name" ]]; then
    worktree_flag="--worktree $worktree_name"
  fi

  log_info "Starting ${pane_title}"
  (cd "$work_dir" && claude -p --dangerously-skip-permissions --allowedTools ${allowed_tools} ${worktree_flag} < "$prompt_file" 2>/dev/null > "$output_file")
  log_info "Finished ${pane_title}"

  cat "$output_file" 2>/dev/null || echo ""
  rm -rf "$tmp_dir"
}

# Log helpers
log() {
  local level="$1"
  shift
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
}

log_info() { log "INFO" "$@"; }
log_error() { log "ERROR" "$@"; }
log_warn() { log "WARN" "$@"; }
log_debug() {
  if [[ "${PROJECT_FLOW_DEBUG:-}" == "1" ]]; then
    log "DEBUG" "$@"
  fi
}

# Summarize Claude output for failure comments
# Uses Claude to analyze the output and explain what happened in the configured language
summarize_failure() {
  local claude_output="$1"
  local context="$2"  # e.g. "PR creation", "implementation"
  local lang="${LANGUAGE:-en}"

  local raw_tail
  raw_tail=$(echo "$claude_output" | tail -30 | head -c 2000)

  local summary
  summary=$(echo "以下はClaude Codeの出力です。この出力を分析して、なぜ${context}が失敗したのかを${lang}で簡潔に説明してください（3-5行程度）。技術的な原因と、次に何をすべきかを含めてください。

---
${raw_tail}" | claude -p 2>/dev/null || echo "")

  if [[ -z "$summary" ]]; then
    summary="(auto-summary unavailable)"
  fi

  echo "$summary"
}

# Count how many times a phase has processed this issue
# Usage: count_phase_attempts <issue_number> <phase>
# Counts comments matching "🤖 <Phase>:" pattern
count_phase_attempts() {
  local issue_number="$1"
  local phase="$2"

  gh api "repos/${REPO}/issues/${issue_number}/comments" \
    --jq "[.[] | select(.body | startswith(\"🤖 ${phase}:\") or startswith(\"## 🤖 ${phase}:\"))] | length" \
    2>/dev/null || echo "0"
}

# Check if issue has exceeded retry limit for a phase
# Returns 0 (true) if over limit, 1 (false) if OK
check_retry_limit() {
  local issue_number="$1"
  local item_id="$2"
  local phase="$3"
  local max_retries="${MAX_RETRIES:-3}"

  local attempts
  attempts=$(count_phase_attempts "$issue_number" "$phase")

  if [[ "$attempts" -ge "$max_retries" ]]; then
    log_warn "Issue #${issue_number}: ${phase} attempted ${attempts} times (limit: ${max_retries}). Escalating." | tee -a "$LOG_FILE"
    local comment_body
    comment_body="$(printf "$(msg "loop.detected")" "$phase" "$attempts")

$(msg "loop.history")
$(gh api "repos/${REPO}/issues/${issue_number}/comments" \
  --jq "[.[] | select(.body | startswith(\"🤖\")) | \"- \" + (.body | split(\"\n\") | .[0])] | join(\"\n\")" 2>/dev/null || echo "")"
    add_issue_comment "$issue_number" "$comment_body"
    move_item_to_status "$item_id" "$STATUS_BACKLOG"
    return 0
  fi

  return 1
}

# Get localized message
# Usage: msg "key"
# Messages are kept simple — the key itself is English, the function returns localized text
msg() {
  local key="$1"
  local lang="${LANGUAGE:-en}"

  case "$lang" in
    ja)
      case "$key" in
        "dev.success")          echo "実装完了 — PR %s を作成しました。Review に移動します。" ;;
        "dev.failed_execution") echo "実装失敗 — Claude 実行中にエラーが発生しました。Backlog に戻します。" ;;
        "dev.failed_pr")        echo "PR を作成できませんでした。Backlog に戻します。" ;;
        "dev.failure_summary")  echo "失敗の原因" ;;
        "dev.claude_output")    echo "Claude 出力（末尾30行）" ;;
        "review.no_pr")         echo "リンクされた PR が見つかりません。Dev に戻します。" ;;
        "review.lgtm")          echo "LGTM — QA に移動します。PR #%s をご確認ください。" ;;
        "review.changes")       echo "PR #%s に変更をリクエストしました。Dev に戻します。" ;;
        "review.fix_history")   echo "レビュー・修正の履歴" ;;
        "review.escalate")      echo "%sラウンドのレビュー・修正で完全には解決できませんでした。以下はレビューの履歴です。" ;;
        "review.escalate_qa")   echo "PR #%s のレビューを3ラウンド実施しました。解決できなかった指摘があります。QA に移動します — 人間の確認をお願いします。" ;;
        "accept.merge_failed")  echo "PR #%s のマージに失敗しました。手動で確認してください。" ;;
        "accept.done")          echo "PR をマージし、Issue をクローズしました。" ;;
        "analysis.questions")   echo "自動分析に質問があります。回答後、Analysis に戻してください。" ;;
        "analysis.split")       echo "サブ Issue を作成し、Backlog に追加しました:" ;;
        "analysis.split_move")  echo "元の Issue を Backlog に戻します。" ;;
        "analysis.ready")       echo "分析完了。Dev に移動します。" ;;
        "analysis.skip_qa")     echo "実装済みです。Dev/Review をスキップして QA に移動します。" ;;
        "loop.detected")        echo "🔁 **ループ検出**: %s フェーズが %s 回実行されました。自動処理を停止し、Backlog に戻します。人間の確認が必要です。" ;;
        "loop.history")         echo "### 自動処理の履歴" ;;
        *) echo "$key" ;;
      esac
      ;;
    *)
      case "$key" in
        "dev.success")          echo "Implementation complete — PR %s created. Moving to Review." ;;
        "dev.failed_execution") echo "Implementation failed — error during Claude execution. Moving back to Backlog." ;;
        "dev.failed_pr")        echo "Could not create PR. Moving back to Backlog." ;;
        "dev.failure_summary")  echo "Failure reason" ;;
        "dev.claude_output")    echo "Claude output (last 30 lines)" ;;
        "review.no_pr")         echo "No linked PR found. Moving back to Dev." ;;
        "review.lgtm")          echo "LGTM — moving to QA. Please review PR #%s." ;;
        "review.changes")       echo "Changes requested on PR #%s. Moving back to Dev." ;;
        "review.fix_history")   echo "Review & fix history" ;;
        "review.escalate")      echo "Could not fully resolve after %s rounds of review & fix. See review history below." ;;
        "review.escalate_qa")   echo "Reviewed PR #%s over 3 rounds. Some issues remain unresolved. Moving to QA — human review needed." ;;
        "accept.merge_failed")  echo "Failed to merge PR #%s. Please check manually." ;;
        "accept.done")          echo "PR merged & issue closed." ;;
        "analysis.questions")   echo "Automated analysis has questions. Please answer and move back to Analysis." ;;
        "analysis.split")       echo "Created sub-issues and added to Backlog:" ;;
        "analysis.split_move")  echo "Moving original issue back to Backlog." ;;
        "analysis.ready")       echo "Analysis complete. Moving to Dev." ;;
        "analysis.skip_qa")     echo "Implementation already complete. Skipping Dev/Review, moving to QA." ;;
        "loop.detected")        echo "🔁 **Loop detected**: %s phase has run %s times. Stopping automation and moving to Backlog. Human intervention required." ;;
        "loop.history")         echo "### Automation history" ;;
        *) echo "$key" ;;
      esac
      ;;
  esac
}
