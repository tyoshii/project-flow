# project-flow

GitHub Project のステータスをポーリングし、Claude Code が自動で issue の分析・実装・レビューを行うワークフローエンジン。

## 技術スタック

- 言語: Bash (シェルスクリプト)
- 依存: GitHub CLI (gh), tmux, jq, Claude Code CLI
- ビルド: 不要（スクリプト直接実行）

## ディレクトリ構成

```
bin/project-flow     # メイン CLI エントリポイント
lib/
  config.sh          # 設定ファイル読み込み (.project-flow.conf)
  init.sh            # watcher 共通初期化
  helpers.sh         # GitHub Project GraphQL ヘルパー、ログ、i18n
  watch-analysis.sh  # Analysis ステータスの issue を分析
  watch-dev.sh       # Dev ステータスの issue を実装 → PR 作成
  watch-review.sh    # Review ステータスの PR をレビュー
  watch-accept.sh    # Accept ステータスの PR をマージ → issue クローズ
prompts/
  analysis.md        # Analysis フェーズ用プロンプト
  dev.md             # Dev フェーズ用プロンプト
  review.md          # Review フェーズ用プロンプト
install.sh           # インストーラー
```

## ワークフロー

```
Backlog → Analysis → Dev → Review → QA → Accept → Done
           (Claude)   (Claude)  (Claude)  (人間)   (自動)
```

各 watcher が対応するステータスの issue をポーリングし、Claude Code を実行して次のステータスに進める。

## 基本コマンド

```bash
# テスト（テストフレームワークなし。手動で動作確認）
project-flow setup    # セットアップ
project-flow start    # ポーラー起動
project-flow stop     # 停止

# ShellCheck で lint
shellcheck bin/project-flow lib/*.sh
```
