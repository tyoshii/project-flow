#!/usr/bin/env bash
# install.sh — project-flow インストーラー
set -euo pipefail

INSTALL_DIR="${PROJECT_FLOW_INSTALL_DIR:-$HOME/.project-flow}"
REPO_URL="https://github.com/inuneko-okoku/project-flow.git"

echo "=== project-flow インストーラー ==="

# 前提条件チェック
check_deps() {
  local missing=()
  command -v gh >/dev/null 2>&1 || missing+=("gh (GitHub CLI)")
  command -v jq >/dev/null 2>&1 || missing+=("jq")
  command -v tmux >/dev/null 2>&1 || missing+=("tmux")
  command -v claude >/dev/null 2>&1 || missing+=("claude (Claude Code CLI)")
  command -v git >/dev/null 2>&1 || missing+=("git")

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: 以下のツールがインストールされていません:"
    for dep in "${missing[@]}"; do
      echo "  - $dep"
    done
    echo ""
    echo "インストール方法:"
    echo "  brew install gh jq tmux"
    echo "  Claude Code: https://docs.anthropic.com/en/docs/claude-code"
    exit 1
  fi

  # gh ログインチェック
  if ! gh auth status >/dev/null 2>&1; then
    echo "ERROR: gh にログインしてください: gh auth login"
    exit 1
  fi

  echo "✓ 依存ツールのチェック完了"
}

install_project_flow() {
  local src_dir="$INSTALL_DIR/src"

  if [[ -d "$src_dir" ]]; then
    echo "既存のインストールを更新中..."
    (cd "$src_dir" && git pull --ff-only 2>/dev/null) || {
      echo "git pull に失敗しました。再クローンします..."
      rm -rf "$src_dir"
      git clone "$REPO_URL" "$src_dir"
    }
  else
    echo "project-flow をインストール中..."
    mkdir -p "$INSTALL_DIR"
    git clone "$REPO_URL" "$src_dir"
  fi

  mkdir -p "$INSTALL_DIR/projects"

  # シンボリックリンクを作成
  local bin_dir="$HOME/.local/bin"
  mkdir -p "$bin_dir"

  ln -sf "$src_dir/bin/project-flow" "$bin_dir/project-flow"
  chmod +x "$src_dir/bin/project-flow" "$src_dir/lib/"*.sh

  echo "✓ インストール完了: $src_dir"

  # PATH チェック
  if ! echo "$PATH" | tr ':' '\n' | grep -qx "$bin_dir"; then
    echo ""
    echo "⚠ $bin_dir が PATH に含まれていません。以下を ~/.zshrc に追加してください:"
    echo '  export PATH="$HOME/.local/bin:$PATH"'
  fi
}

check_deps
install_project_flow

echo ""
echo "=== 使い方 ==="
echo "  project-flow setup owner/repo   # 初回セットアップ"
echo "  project-flow start owner/repo   # ポーラー起動"
echo "  project-flow stop owner/repo    # 停止"
echo "  project-flow status             # 実行中一覧"
