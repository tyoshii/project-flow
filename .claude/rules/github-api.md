# GitHub API 規約

## GraphQL の使い方

- `gh api graphql` で GitHub GraphQL API を呼び出す
- `--jq` でレスポンスをフィルタリング
- Organization と User の両方に対応する（org で失敗したら user にフォールバック）

## Project V2 API パターン

- `get_project_id()`: Project のノード ID を取得
- `get_status_field()`: Status フィールドの ID とオプション一覧を取得
- `get_items_by_status()`: 特定ステータスの issue 一覧を取得
- `move_item_to_status()`: issue のステータスを変更

これらは `lib/helpers.sh` に定義済み。新しい GraphQL クエリを追加する場合は helpers.sh に関数として追加する。

## gh CLI の使い方

- Issue 操作: `gh issue create`, `gh issue close`, `gh issue comment`
- PR 操作: `gh pr create`, `gh pr merge`, `gh pr review`, `gh pr diff`, `gh pr view`
- リポジトリは `--repo "$REPO"` で明示指定する
