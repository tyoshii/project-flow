#!/usr/bin/env bash
# init.sh — 各スクリプト共通の初期化
# 使い方: source "$(dirname "${BASH_SOURCE[0]}")/init.sh"
# 環境変数 PROJECT_FLOW_CONF が設定されていればそれを使う

PROJECT_FLOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$PROJECT_FLOW_DIR/lib/config.sh"

# PROJECT_FLOW_CONF が指定されていればそのディレクトリに cd してからロード
if [[ -n "${PROJECT_FLOW_CONF:-}" ]]; then
  cd "$(dirname "$PROJECT_FLOW_CONF")"
fi

load_project_config
source "$PROJECT_FLOW_DIR/lib/helpers.sh"
