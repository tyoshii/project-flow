# project-flow

GitHub Project のステータスをポーリングし、Claude Code が自動で issue の分析・実装・レビューを行うワークフローエンジン。

## ワークフロー

```
Backlog → Analysis → Dev → Review → QA → Accept → Done
           (Claude)   (Claude)  (Claude)  (人間)   (自動)
```

- **Analysis**: issue を分析し、実装計画を策定。不明点があれば質問、大きすぎれば分割。
- **Dev**: コードを実装し、PR を作成。
- **Review**: PR の diff をレビュー。LGTM なら QA へ、問題あれば Dev に差し戻し。
- **QA**: 人間が手動テスト。OK なら Accept に移動。
- **Accept**: 自動で PR マージ → issue クローズ → Done に移動。

## 前提条件

- [GitHub CLI (gh)](https://cli.github.com/) — ログイン済み
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) — Max プランまたは API キー
- [tmux](https://github.com/tmux/tmux)
- [jq](https://jqlang.github.io/jq/)

## インストール

```bash
curl -fsSL https://raw.githubusercontent.com/tyoshii/project-flow/main/install.sh | bash
```

## 使い方

```bash
# 1. セットアップ（GitHub Project を作成）
project-flow setup owner/repo

# 2. Web UI で Status フィールドに以下を追加:
#    Backlog, Analysis, Dev, Review, QA, Accept, Done

# 3. ポーラー起動
project-flow start owner/repo

# 4. issue を Project に追加して Backlog に配置
# 5. Analysis に移動すると自動処理が始まる
```

## その他のコマンド

```bash
project-flow stop owner/repo    # 停止
project-flow status              # 実行中のプロジェクト一覧
project-flow logs owner/repo    # ログ表示
```
