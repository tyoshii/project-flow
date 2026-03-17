# コミット・PR ルール

## コミットメッセージ

- Conventional Commits 形式: `feat:`, `fix:`, `refactor:`, `docs:` 等
- 日本語 OK（既存コミット履歴に合わせる）
- Issue 番号がある場合は末尾に `(#123)` を付与

## PR

- `Closes #<issue-number>` を body に含める
- 変更内容のサマリーを記載
- セキュリティに関わる変更は明示的に記載

## コミットしてはいけないファイル

- `.project-flow.conf` — リポジトリ固有の設定（ユーザーが setup で生成）
- `.project-flow-logs/` — ランタイムログ
- `.env`, シークレットファイル
