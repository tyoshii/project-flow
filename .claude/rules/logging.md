---
paths:
  - "**/*.sh"
  - "bin/project-flow"
---

# ログ出力規約

## ログ関数（lib/helpers.sh 定義）

- `log_info` — 通常の処理ログ
- `log_error` — エラー（stderr に出力）
- `log_warn` — 警告
- `log_debug` — デバッグ（`PROJECT_FLOW_DEBUG=1` 時のみ出力）

## タイムスタンプ形式

`[YYYY-MM-DD HH:MM:SS] [LEVEL] メッセージ`

## 出力先パターン

- **ユーザーに見せる情報**: `log_info ... | tee -a "$LOG_FILE"` （stdout + ファイル両方）
- **デバッグ情報**: `log_debug ... >> "$LOG_FILE"` （ファイルのみ）
- **Claude 出力の記録**: `echo "$claude_output" >> "$LOG_FILE"` （ファイルのみ、監査用）

## 使い分けの指針

- ポーリングループの開始/終了 → `log_debug`（スパム防止）
- issue の処理開始/完了 → `log_info | tee -a`
- Claude 実行の開始/完了 → `log_info | tee -a`
- エラー発生 → `log_error | tee -a`
