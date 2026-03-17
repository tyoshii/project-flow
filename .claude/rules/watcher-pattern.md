---
paths:
  - "lib/watch-*.sh"
---

# Watcher スクリプトの共通パターン

新しい watcher を作成・修正する際は、既存の watch-*.sh と同じ構造に従う。

## 基本構造

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/init.sh"

LOG_FILE="$LOG_DIR/<phase>.log"
log_info "<Phase> watcher started" | tee -a "$LOG_FILE"

while true; do
  items=$(get_items_by_status "$STATUS_<PHASE>")
  count=$(echo "$items" | jq 'length')

  if [[ "$count" -gt 0 ]]; then
    echo "$items" | jq -c '.[]' | while read -r item; do
      # item_id, issue_number, issue_title を取得
      # Claude を実行し、出力を判定タグで分岐
      # move_item_to_status で次のステータスに移動
    done
  fi

  sleep "$POLL_INTERVAL"
done
```

## 重要なポイント

- `init.sh` を source して config と helpers をロード
- `get_linked_pr()` は `helpers.sh` に定義済み。watcher 内で再定義しない
- Claude 実行は `run_claude` ヘルパーを使用
- ログは `tee -a "$LOG_FILE"` で stdout とファイル両方に出力
- Claude 出力から判定タグ (`[TAG]`) を grep で抽出して分岐
