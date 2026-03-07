#!/usr/bin/env bash
# config.sh — プロジェクト設定のロード
#
# 使い方: source config.sh <owner/repo>
# プロジェクト固有の設定は ~/.project-flow/projects/<owner>__<repo>.conf に保存される

set -euo pipefail

PROJECT_FLOW_HOME="${PROJECT_FLOW_HOME:-$HOME/.project-flow}"
PROJECT_FLOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# プロジェクト引数の処理
load_project_config() {
  local project_arg="${1:-}"

  if [[ -z "$project_arg" ]]; then
    echo "ERROR: プロジェクトを指定してください (例: owner/repo)" >&2
    return 1
  fi

  # owner/repo を分解
  REPO="$project_arg"
  OWNER=$(echo "$project_arg" | cut -d'/' -f1)
  REPO_NAME=$(echo "$project_arg" | cut -d'/' -f2)

  # プロジェクト固有の設定ファイルパス
  local safe_name="${OWNER}__${REPO_NAME}"
  PROJECT_CONF_FILE="${PROJECT_FLOW_HOME}/projects/${safe_name}.conf"

  # デフォルト値
  PROJECT_NUMBER=""
  STATUS_FIELD_NAME="Status"
  STATUS_BACKLOG="Backlog"
  STATUS_ANALYSIS="Analysis"
  STATUS_DEV="Dev"
  STATUS_REVIEW="Review"
  STATUS_QA="QA"
  STATUS_ACCEPT="Accept"
  STATUS_DONE="Done"
  POLL_INTERVAL=60
  LOCAL_REPO_PATH=""

  # プロジェクト固有の設定を読み込み（あれば上書き）
  if [[ -f "$PROJECT_CONF_FILE" ]]; then
    source "$PROJECT_CONF_FILE"
  fi

  # ディレクトリ
  LOG_DIR="${PROJECT_FLOW_HOME}/logs/${safe_name}"
  PROMPTS_DIR="${PROJECT_FLOW_DIR}/prompts"

  # tmux セッション名
  TMUX_SESSION="pf-${safe_name}"

  mkdir -p "$LOG_DIR"
}

# プロジェクト設定を保存
save_project_config() {
  mkdir -p "$(dirname "$PROJECT_CONF_FILE")"
  cat > "$PROJECT_CONF_FILE" << EOF
# project-flow config for ${REPO}
PROJECT_NUMBER="${PROJECT_NUMBER}"
STATUS_FIELD_NAME="${STATUS_FIELD_NAME}"
STATUS_BACKLOG="${STATUS_BACKLOG}"
STATUS_ANALYSIS="${STATUS_ANALYSIS}"
STATUS_DEV="${STATUS_DEV}"
STATUS_REVIEW="${STATUS_REVIEW}"
STATUS_QA="${STATUS_QA}"
STATUS_ACCEPT="${STATUS_ACCEPT}"
STATUS_DONE="${STATUS_DONE}"
POLL_INTERVAL="${POLL_INTERVAL}"
LOCAL_REPO_PATH="${LOCAL_REPO_PATH}"
EOF
}
