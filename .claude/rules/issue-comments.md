---
paths:
  - "lib/watch-*.sh"
---

# Issue コメント書式

## プレフィックス

全ての自動コメントは `🤖 <Phase>:` で始める。

```
🤖 Analysis: ...
🤖 Dev: ...
🤖 Review: ...
🤖 Accept: ...
```

## Analysis フェーズのコメント構造

```markdown
## 🤖 Analysis: <Type>

<Claude の出力>

---
*<msg() によるローカライズされたステータスメッセージ>*
```

Type: `Questions`, `Task Split`, `Implementation Plan`, `Skipping to QA`

## Dev フェーズのエラーコメント構造

```markdown
🤖 Dev: <msg() のエラーメッセージ>

### <msg("dev.failure_summary")>
<summarize_failure() の出力>

<details><summary><msg("dev.claude_output")></summary>

\`\`\`
<Claude 出力の末尾30行>
\`\`\`

</details>
```

長文の Claude 出力は `<details>` タグで折りたたむ。

## メッセージのローカライズ

- 固定テキストは `msg()` 関数を使う
- 動的値（PR URL、issue 番号）は `printf` で埋め込む
- `add_issue_comment "$issue_number" "$comment_body"` で投稿
