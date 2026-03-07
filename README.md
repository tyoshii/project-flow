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
Usage: project-flow <command>

Commands:
  setup    Setup in current directory (repo root)
  run      Start pollers (tmux session)
  stop     Stop pollers
  attach   Attach to running tmux session
  status   Show running project-flow sessions
  logs     Tail log files

Workflow:
  Backlog → Analysis → Dev → Review → QA → Accept → Done
             (Claude)   (Claude)  (Claude)  (Human)  (Auto)
```

### Quick Start

```bash
# 1. Setup (creates GitHub Project & .project-flow.conf)
cd ~/repos/my-project
project-flow setup

# 2. Add status options in GitHub Project settings:
#    Backlog, Analysis, Dev, Review, QA, Accept, Done

# 3. Start pollers
project-flow run

# 4. Add issues to the Project board and move to Analysis
#    → Claude handles the rest automatically
```

### Commands

```bash
project-flow setup     # Create .project-flow.conf & GitHub Project
project-flow run       # Start tmux session with all pollers
project-flow attach    # Attach to running tmux session
project-flow stop      # Stop tmux session
project-flow status    # List running project-flow sessions
project-flow logs      # Tail log files
```
