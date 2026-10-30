# Ver.6 G1: 追加読取監査 2026-10-30

この資料は公開可能な範囲の構造情報だけを記録する。利用者・発注・受領の行データ、パスワード、APIキー、トークン、接続文字列は含めない。読み取り専用調査であり、本番DBは変更していない。

## 確認できた事項
- public の業務テーブルは profiles, orders, receipts, audit_logs。列名、型、NULL、DEFAULTは information_schema.columns から確認。
- RLS対象ロールは7ポリシーすべて authenticated。
- orders_select: 有効利用者。orders_insert: 有効利用者かつ created_by=auth.uid()。orders_update: 有効利用者かつ作成者または管理者（USINGとWITH CHECKの両方）。
- receipts_select: 有効利用者。profiles_select: 本人または管理者。profiles_admin_update: 管理者（USINGとWITH CHECK）。audit_select: 管理者のみ。
- 受領RPCは add_receipt(uuid,integer,date,text,text) -> uuid、change_receipt(uuid,integer,date,text,text) -> void、cancel_receipt(uuid) -> void。いずれも SECURITY DEFINER、所有者 postgres。
- Authユーザー作成後にプロフィールを生成するトリガー、orders/receiptsにINSERT・UPDATE・DELETE監査トリガーが存在。
- order_receipt_totals ビューは削除されていない注文を対象に、注文数量、受領合計、残数量を集計する。
- 発注数量が受領済み合計を下回らないようにするDBトリガーは未適用。

## 残る不足情報と安全な次工程
- GRANTの正確な付与元（継承、PUBLIC、列、シーケンス、既定権限）とローカル復元用の完全な定義は未確認。
- 関数本文、ビューのオプションや権限、制約・インデックス等は既存監査資料と突合が必要。今回の要約を復元可能な完全スキーマとして扱わない。
- Codexは不足定義を推測で補完せず、既存の使い捨てローカルAuthおよびPostgreSQL試験を再利用し、レビュー済み定義だけをローカルに適用する。
- 実JWTを使った業務RLS、RPC、権限別アクセス、監査ログの実動作は未検証。G1は未達のまま。
- 本番Supabase、Ver.5、main、公開設定への変更・有料リソース作成は禁止。PR #4はDraftを維持。
