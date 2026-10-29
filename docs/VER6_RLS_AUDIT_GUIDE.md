# Ver.6の既存Supabase権限診断（2026-10-29）

## 何が分かったか
過去の試作用 `schema.sql` をレビューし、`receipts_insert` と `receipts_update` のRLSが直接操作を許す構成を確認しました。Supabaseの公式ドキュメントによると、権限（GRANT）とRLSは**別の制御**で、RLSポリシーだけでは必ずしもデータへの直接書込みは防げません。

もし現在のDBでも `authenticated` ロールに受領テーブルの直接INSERT/UPDATE/DELETEが付与されていたら、REST APIから専用RPCを迂回する余地があります。ただし、DBトリガーがチェックしていれば防げることもあるため、実DBを確認するまでは脆弱性を断定しません。

同様に、`public.order_receipt_totals` のビューは `security_invoker=true` または十分に制限されたGRANT/RLSかを確認する必要があります。

## 読み取り専用診断ファイル
1. `supabase/diagnostics/ver6_readonly_security_snapshot.sql` — RLS、テーブル操作権限、ポリシー、関数実行権限、ビュー、トリガーの**メタデータだけ**を一覧化。
2. `supabase/diagnostics/ver6_readonly_receipt_rpc_source.sql` — 受領RPCの関数定義を読むだけ（データの中身は読まない）。関数内に秘密情報が書かれている可能性があるため、共有前に内容を確認。

## 実行方法
Supabaseの**試験用**プロジェクトのSQL Editorに診断SQLを貼り付け、「Run」を押す。**必ずSELECTだけで構成されていることを確認する**。結果に氏名・認証トークン・鍵が含まれていないか確認してから共有する。

Supabase連携が有効であれば、ChatGPTから読み取り専用のSQLを使い、結果を比較して診断できます。連携時もユーザーの明示的な承認なしにDB変更は行いません。

## 次の判断
- 受領テーブルの直接書き込み権限がある場合、まず現行3つの受領RPCの定義・SQL権限を調べてから、書き込みのGRANTを絞る移行計画を策定する。いきなりREVOKEすると既存機能を停止させる可能性がある。
- 管理者以外の他人の受領修正拒否、数量上限、同時受領、audit_logsをテストする。
- 招待・端末登録に対して、同様の権限設計と実機失効テストが通るまで本番接続しない。

## 出典
- https://supabase.com/docs/guides/database/postgres/row-level-security
- https://supabase.com/docs/guides/database/functions

**状況：コード上の事前診断まで。実データベースのSQLは未実行。公開中のVer.5/Ver.6やDBの内容に変更なし。**
