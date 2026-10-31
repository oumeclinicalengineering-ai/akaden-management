# Ver.6 G1 追加監査：インデックス・制約・ビュー

2026-10-30、既存Supabaseの構造情報のみを読み取り専用で確認。個人情報、注文・受領データ、認証キー、パスワードは取得していない。

## 新たに確認した項目

- publicの4業務テーブルにインデックス計8件：audit_logs（主キー、changed_at降順）、orders（主キー、reference_no一意、request_date降順）、profiles（主キー）、receipts（主キー、order_id）。
- orders.quantity は1以上100000000以下、versionは正数、reference_noは一意、item_nameは空白のみ禁止。
- receipts.quantity は正数、personは空白のみ禁止。receipts.order_idはorders.idへの外部キー（削除制限）。
- profiles.roleはstaffまたはadmin、profiles.user_idはauth.users.idに対応（ユーザー削除時に連動削除）。
- audit_logs.actionはINSERT/UPDATE/DELETEのいずれか。
- order_receipt_totalsビューの最新オプションはsecurity_invoker=true。

## 継続して不足する事項

- 本番と同一の完全DDL・関数本文をローカルで再現するためのレビュー済み資料。
- PUBLIC・継承・列・シーケンス・既定権限を含めたGRANT付与元。
- ローカルでの実JWTと業務RLS/RPCの一連の操作試験。
- 本番の発注数量ガード未適用に対する検証済み適用・ロールバック計画。

RLSの全文について今回の再取得は安全性チェックにより制限されたため、前回の確認結果を参照し、今回再確認したとは記載しない。これらの情報だけでG1合格とは判定しない。

## Codexへの引き継ぎ

G1台帳に確認済みインデックス・制約・ビュー設定を反映し、未検証の権限と業務RPCの実動作は未検証として維持する。推測で完全スキーマを作成しない。Ver.5・main・本番Supabase変更、マージ、本番公開、有料リソース作成は禁止。PR #4はDraftを維持。
