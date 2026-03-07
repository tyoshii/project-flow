#!/usr/bin/env bash
# init.sh — 各スクリプト共通の初期化
# 使い方: source "$(dirname "${BASH_SOURCE[0]}")/init.sh" "$@"

PROJECT_FLOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$PROJECT_FLOW_DIR/lib/config.sh"
load_project_config "${1:-}"
source "$PROJECT_FLOW_DIR/lib/helpers.sh"
