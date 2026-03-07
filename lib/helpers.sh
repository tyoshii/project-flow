#!/usr/bin/env bash
# helpers.sh — GitHub Project GraphQL ヘルパー関数群
# config.sh が事前に source されていること

# Project の node ID を取得
get_project_id() {
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
    --jq '.data.organization.projectV2.id' 2>/dev/null) && [[ -n "$result" ]] && echo "$result" && return

  # organization でなければ user でフォールバック
  gh api graphql -f query='
    query($owner: String!, $number: Int!) {
      user(login: $owner) {
        projectV2(number: $number) {
          id
        }
      }
    }
  ' -f owner="$OWNER" -F number="$PROJECT_NUMBER" \
    --jq '.data.user.projectV2.id'
}

# Status フィールドの ID と各オプション ID を取得
get_status_field() {
  local project_id
  project_id=$(get_project_id)

  gh api graphql -f query='
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
    --jq '.data.node.fields.nodes[] | select(.name == "'"$STATUS_FIELD_NAME"'")'
}

# 特定ステータスの issue 一覧を取得
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

# issue のステータスを変更
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
    echo "ERROR: Status option '$target_status' not found" >&2
    return 1
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

# issue の詳細情報を取得（本文・コメント）
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

# issue にコメントを追加
add_issue_comment() {
  local issue_number="$1"
  local comment_body="$2"
  gh issue comment "$issue_number" --repo "$REPO" --body "$comment_body"
}

# issue を Project に追加
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

# リポジトリのローカルパスを決定
get_repo_path() {
  if [[ -n "$LOCAL_REPO_PATH" && -d "$LOCAL_REPO_PATH" ]]; then
    echo "$LOCAL_REPO_PATH"
  else
    local repo_dir="$HOME/repos/$REPO_NAME"
    if [[ ! -d "$repo_dir" ]]; then
      log_info "リポジトリをクローン中: $REPO → $repo_dir"
      git clone "git@github.com:${REPO}.git" "$repo_dir"
    fi
    echo "$repo_dir"
  fi
}

# Claude を実行して出力を返す
run_claude() {
  local pane_title="$1"
  local prompt="$2"
  local allowed_tools="$3"
  local work_dir="$4"

  local tmp_dir
  tmp_dir=$(mktemp -d)
  local prompt_file="$tmp_dir/prompt.txt"
  local output_file="$tmp_dir/output.txt"

  echo "$prompt" > "$prompt_file"

  log_info "🤖 ${pane_title} 開始"
  (cd "$work_dir" && cat "$prompt_file" | claude --allowedTools ${allowed_tools} 2>/dev/null > "$output_file")
  log_info "🤖 ${pane_title} 完了"

  cat "$output_file" 2>/dev/null || echo ""
  rm -rf "$tmp_dir"
}

# ログ出力ヘルパー
log() {
  local level="$1"
  shift
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
}

log_info() { log "INFO" "$@"; }
log_error() { log "ERROR" "$@"; }
log_warn() { log "WARN" "$@"; }
