#!/usr/bin/env bash
# install.sh — project-flow インストーラー
set -euo pipefail

INSTALL_DIR="${PROJECT_FLOW_INSTALL_DIR:-$HOME/.project-flow}"
REPO_URL="https://github.com/tyoshii/project-flow.git"

echo "=== project-flow インストーラー ==="

# パッケージマネージャを検出
detect_pkg_manager() {
  if command -v brew >/dev/null 2>&1; then
    echo "brew"
  elif command -v apt-get >/dev/null 2>&1; then
    echo "apt"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  elif command -v pacman >/dev/null 2>&1; then
    echo "pacman"
  else
    echo ""
  fi
}

# パッケージマネージャでツールをインストール
install_pkg() {
  local pkg="$1"
  local pkg_manager="$2"

  echo "  ${pkg} をインストール中..."
  case "$pkg_manager" in
    brew)   brew install "$pkg" ;;
    apt)    sudo apt-get install -y "$pkg" ;;
    dnf)    sudo dnf install -y "$pkg" ;;
    pacman) sudo pacman -S --noconfirm "$pkg" ;;
  esac
}

# 前提条件チェック & 自動インストール
check_deps() {
  # git は最初に必要（インストーラー自体が使う）
  if ! command -v git >/dev/null 2>&1; then
    echo "ERROR: git がインストールされていません。先に git をインストールしてください。"
    exit 1
  fi

  local pkg_manager
  pkg_manager=$(detect_pkg_manager)

  # brew でインストール可能なツール
  local brew_tools=("gh" "jq" "tmux")
  local missing=()

  for tool in "${brew_tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing+=("$tool")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    if [[ -z "$pkg_manager" ]]; then
      echo "ERROR: 以下のツールがインストールされていません:"
      for dep in "${missing[@]}"; do
        echo "  - $dep"
      done
      echo ""
      echo "パッケージマネージャ (brew, apt, dnf, pacman) が見つかりません。手動でインストールしてください。"
      exit 1
    fi

    echo "不足しているツールをインストールします (${pkg_manager})..."
    for tool in "${missing[@]}"; do
      install_pkg "$tool" "$pkg_manager"
    done
  fi

  # Claude Code CLI
  if ! command -v claude >/dev/null 2>&1; then
    if command -v npm >/dev/null 2>&1; then
      echo "  Claude Code CLI をインストール中..."
      npm install -g @anthropic-ai/claude-code
    else
      echo "ERROR: claude (Claude Code CLI) がインストールされていません。"
      echo "  インストール方法: https://docs.anthropic.com/en/docs/claude-code"
      exit 1
    fi
  fi

  # gh ログインチェック
  if ! gh auth status >/dev/null 2>&1; then
    echo "gh にログインしてください:"
    gh auth login
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
