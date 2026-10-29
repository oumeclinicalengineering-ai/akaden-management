# Ver.6 本番Supabaseの読み取り専用契約確認（2026-10-29）

**目的**: CodexのローカルAuth・RPC・RLS試験を再開するための非機密な仕様要約。これはデータのエクスポートやスキーマ復元ファイルではない。実際の関数全文・個人情報・レコード・キーはこの公開リポジトリには置かない。

## 実際に確認した内容
- SELECTのみで information_schema.columns、pg_constraint、pg_proc の関数定義、pg_trigger を確認。データ行、Authアカウント、パスワード、JWTは取得せず、既存環境への書込みもなし。
- テーブル: public.profiles(user_id,display_name,role,active,created_at); orders(id,reference_no,department,item_name,manufacturer,model,quantity,unit,purpose,request_date,order_date,due_date,deleted,created_by,updated_by,version,created_at,updated_at); receipts(id,order_id,receipt_date,quantity,person,memo,created_by,updated_by,created_at,updated_at); audit_logs(id,table_name,record_id,action,actor_id,before_data,after_data,changed_at)。
- orders.quantity: 1～100000000、reference_no UNIQUE、orders.version>0。receipts.quantity>0、personは非空、profiles.roleはstaff/admin。
- orders/receipts のINSERT/UPDATE/DELETEを監査するトリガーあり。**本番ordersに受領総数と発注数量を照合するトリガーはまだ存在しない**（数量ガードはドラフトのみ）。
- public.add_receipt(p_order_id uuid,p_quantity integer,p_receipt_date date,p_person text,p_memo text DEFAULT '') RETURNS uuid: 有効ログイン、数量・必須項目チェック、対象orders行を FOR UPDATE、合計受領数+追加数量<=注文数量で登録。
- public.change_receipt(p_receipt_id uuid,p_quantity integer,p_receipt_date date,p_person text,p_memo text DEFAULT '') RETURNS void: 有効ログイン、本人または管理者確認、orders行を FOR UPDATE、他の受領合計と新数量が注文数量以下かを検査。
- public.cancel_receipt(p_receipt_id uuid) RETURNS void: 有効ログイン、本人または管理者確認、ordersとreceipts行をロックし削除。監査トリガーあり。
- is_active_user()/is_admin() は auth.uid() に関連づくprofiles.active/roleを確認。RPCは SECURITY DEFINER、空 search_path を指定。
- RLSと権限は過去に読み取り監査済みだが、今回pg_policies/GRANTの再取得がツール保護によりブロックされたため**今の完全な権限スナップショットは未取得**。推測で補完しない。

## ローカル試験で必須
1. 秘密を含まない、レビュー済みの**スキーマ定義とRLSポリシー全文**が別途必要。上の要約は完全なSQLエクスポートではなく、これだけで本番相当のAuth/RLSを再現したとは判断できない。
2. 同じorder行ロックを使用する受領3RPCと注文数量ガードの競合試験、所有者/管理者/無効利用者の認証・認可試験。
3. 注文のUPDATEが0件のときに画面が成功扱いしていないか、監査ログのactor_id、before_data、after_dataを検証。
4. Supabase CLI/GoTrueなどのローカル実環境は本番とは完全分離する。リモートへのlink/db push/db reset禁止。
5. 有料リソース作成・本番データ取得・Ver.5/main変更・PR #4マージ禁止。すべて架空データ。

## ブロッカー
- 実際のRLS・GRANTを含むレビュー済み完全スキーマ定義がまだ揃っていない。
- 実Auth/実RPC接続による成功はまだ未確認。
- 本番のorders数量ガードが未適用であり、運用可とは判断できない。
