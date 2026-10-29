# Ver.6 Supabase 実環境 RLS / SQL RPC 監査（2026-10-29）

**検査方法：** ChatGPTから接続済みSupabaseプロジェクトの `pg_class`, `pg_policies`, `pg_proc`, `pg_trigger`, `information_schema` を **SELECTのみ** で確認。セキュリティAdvisorsも参照。テーブルの個人/受領データは取得せず、データや権限の変更なし。

## 確認済み
- `profiles`, `orders`, `receipts`, `audit_logs` のRLSは有効。
- `authenticated` の `receipts` 直接 `INSERT`/`UPDATE`/`DELETE` 権限は **いずれもfalse**。旧初期スキーマの受領直接更新ポリシーも現在は存在しない。
- `receipts_select` は `is_active_user()` を要求。
- `add_receipt`: 認証・有効ユーザーを確認。対象order行 `FOR UPDATE` により同時受領を直列化し、受領合計が発注数量を超える場合を拒否。
- `change_receipt`: 本人/管理者を確認し、数量上限とorder行のロックを使用。
- `cancel_receipt`: 本人/管理者を確認。取消はDBのDELETE監査トリガーが記録。
- 上記3 RPCは `authenticated` が実行可能、`anon` は実行不可。
- `orders_audit` と `receipts_audit` トリガーは有効。
- `order_receipt_totals` は `security_invoker=true` を設定済み。基底テーブルのRLSが適用される設計。
- Edge Functions は現時点でゼロ。QR登録サーバー機能は未配備。

## 改善候補 1: 発注数量の直接変更
`authenticated` は `orders` の UPDATE 権限を持ち、RLSでは自身が作成した赤伝を更新できる。現在のordersトリガーは監査のみ。受領済数量より小さく発注数量を更新すると、発注数<受領数という不整合が発生し得る。**画面にボタンがなくてもAPIから可能**。
→ 対策案：order.quantity変更時のDBトリガーで `quantity >= SUM(receipts.quantity)` を強制。既存の受領RPCロックと整合する設計で要テスト。ドラフト `supabase/migrations/20261029_order_quantity_guard_DRAFT.sql`。

## 改善候補 2: SECURITY DEFINER関数の公開範囲
Supabase Advisors の WARN:
- `create_profile_for_user()`, `record_audit()`, `is_admin()`, `is_active_user()` が `anon` から実行許可。
- 上記に加え、3受領RPCが `authenticated` から実行許可。3 RPCはUIから必要なので単純REVOKEはしない。
- `create_profile_for_user` と `record_audit` はトリガー関数であり、通常のSQL関数として直接呼ぶ場合はPostgreSQLの制約がある。警告だけで特権昇格を断定しない。
→ 原則、不要な `anon` のEXECUTEを取り消し、トリガー専用関数は `authenticated` からの不要なEXECUTEも取り消すことをステージングで検証。

## 改善候補 3: 認証設定
Supabase Advisors に「漏えいパスワードの保護無効」の WARN あり。現行Ver.6はパスワード認証なので、該当設定の有効化を検討。パスワードレス化計画と独立に確認。

## 実運用前に行う動作試験（架空データ）
1. スタッフBが他人の受領履歴の変更/取消をRPCで実行→拒否。
2. 受領数量が発注数量を超過→拒否。
3. 同時受領で数量超過→拒否。
4. 発注数量を受領済数より小さく更新→**現在の実装では未確認**。保護トリガー導入後は拒否。
5. 無効ユーザーが3 RPCを呼び出す→拒否。
6. 監査ログがINSERT/UPDATE/DELETEを記録。
7. Adminのみがスタッフのプロフィール管理できる。
8. 端末失効後は全読み取り/書き込み/RPCが拒否（現状未実装）。

## 注意
これは静的メタデータとSQL関数コードのレビューであり、未承認アクセスの実行テストではない。**本番DBを変更していない**。修正SQLの適用は別途承認・バックアップ・ロールバック計画が必要。
