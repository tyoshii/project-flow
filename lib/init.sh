#!/usr/bin/env bash
# init.sh — Common initialization for watcher scripts
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/init.sh"
# Uses PROJECT_FLOW_CONF env var if set

PROJECT_FLOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$PROJECT_FLOW_DIR/lib/config.sh"

# If PROJECT_FLOW_CONF is set, cd to its directory before loading config
if [[ -n "${PROJECT_FLOW_CONF:-}" ]]; then
  cd "$(dirname "$PROJECT_FLOW_CONF")"
fi

load_project_config
source "$PROJECT_FLOW_DIR/lib/helpers.sh"
