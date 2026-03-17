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

## Usage

```
Commands:
  setup      Setup in current directory (repo root)
  start      Start pollers in background [--debug] [--attach]
  stop       Stop pollers
  restart    Restart pollers [--debug] [--attach]
  attach     Attach to running tmux session
  tail       Tail log output from running pollers
  status     Show running project-flow sessions
  update     Update project-flow to latest version
```

### Quick Start

```bash
# 1. Setup (creates GitHub Project & .project-flow/config)
cd ~/repos/my-project
project-flow setup

# 2. Add status options in GitHub Project settings:
#    Backlog, Analysis, Dev, Review, QA, Accept, Done

# 3. Start pollers
project-flow start

# 4. Add issues to the Project board and move to Analysis
#    → Claude handles the rest automatically
```

### Commands

```bash
project-flow setup            # Create .project-flow/config & GitHub Project
project-flow start            # Start pollers (background)
project-flow start --attach   # Start and attach to tmux
project-flow stop             # Stop pollers
project-flow restart          # Stop and start again
project-flow attach           # Attach to tmux session
project-flow tail             # Follow log output
project-flow status           # List running sessions
project-flow update           # Pull latest version
```
