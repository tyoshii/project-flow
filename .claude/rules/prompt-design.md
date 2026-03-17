---
paths:
  - "prompts/**"
---

# プロンプトテンプレート設計

## 構造

各プロンプトは以下の構成を持つ:

1. ロール定義（あなたは〜です）
2. コンテキスト説明
3. タスク手順
4. 判定タグの定義と使い方
5. 出力フォーマット
6. 重要な注意事項

## 判定タグ

watcher スクリプトが Claude 出力を grep で解析するため、出力の1行目に判定タグを記載するルールになっている。

- Analysis: `[QUESTIONS]`, `[SPLIT]`, `[READY]`, `[SKIP_TO_QA]`
- Review: `[LGTM]`, `[CHANGES_REQUESTED]`
- Dev: 判定タグなし（PR URL の有無で判定）

新しいタグを追加する場合は、対応する watcher の case 文も更新すること。

## SPLIT 用の HTML コメント構造

```
<!-- SPLIT_START -->
<!-- SUB_ISSUE title="タイトル" -->
本文
<!-- /SUB_ISSUE -->
<!-- SPLIT_END -->
```

watch-analysis.sh がこの構造をパースしてサブ issue を自動作成する。
