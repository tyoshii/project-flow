---
paths:
  - "**/*.sh"
  - "bin/project-flow"
---

# シェルスクリプト規約

- 全スクリプトの先頭に `set -euo pipefail` を記述する
- 変数展開は常にダブルクォートで囲む: `"$var"` （意図的な分割が必要な場合を除く）
- ローカル変数は `local` で宣言する
- 関数名はスネークケース: `get_items_by_status`, `load_project_config`
- コマンド置換は `$()` を使う（バッククォート不可）
- `[[ ]]` を使う（`[ ]` は使わない）
- エラーメッセージは stderr に出力: `echo "ERROR: ..." >&2`
- スクリプトの先頭にコメントで目的を記述: `# filename.sh — 説明`
