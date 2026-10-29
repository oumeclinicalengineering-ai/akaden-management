# Ver.6 ライブDB権限・RLS監査サマリー（2026-10-29）

> **公開可能な非機密メタデータの要約のみ。** 個人情報、発注・受領行データ、パスワード、トークン、APIキー、接続文字列、関数全文は含めない。既存DBに対する操作は SELECT のみ。これは完全なスキーマダンプではなく、**本番同等のローカル環境を再現できたことを意味しない**。

## 現行のRLS
対象: public.orders / receipts / profiles / audit_logs。4表とも RLS有効、FORCE RLS無効。

|表|ポリシー|操作|概要（先行監査の式と今回のポリシー名を照合）|
|---|---|---|---|
|orders|orders_select|SELECT|有効利用者のみ|
|orders|orders_insert|INSERT|有効利用者かつ created_by = auth.uid()|
|orders|orders_update|UPDATE|有効利用者で、作成者または管理者。USING/WITH CHECKともこの条件|
|receipts|receipts_select|SELECT|有効利用者のみ|
|profiles|profiles_select|SELECT|自分のプロフィールまたは管理者|
|profiles|profiles_admin_update|UPDATE|管理者。USING/WITH CHECKとも管理者|
|audit_logs|audit_select|SELECT|管理者のみ|

今回のpg_policies照会で7件すべてPERMISSIVE、操作と名称を確認。式の全文は過去の読取監査に基づくため、**全ポリシーの最新の式・対象ロールを独立に再照合する必要あり**。

## テーブルの実効権限（PostgreSQL has_table_privilege）
- authenticated: orders SELECT/INSERT/UPDATE/DELETE = true、profiles SELECT/INSERT/UPDATE/DELETE = true、audit_logs SELECT/INSERT/UPDATE/DELETE = true。receipts は SELECT=true、INSERT/UPDATE/DELETE=false。
- anon: 上記4表の SELECT はいずれも true。ただし SELECT GRANT があっても、実際に取得できる行はRLSの認証条件に依存する。
- **注意**: audit_logs/orders/profilesの過剰なテーブル権限は明示的なGRANT・継承・PUBLIC権限も含む実効値であり、RLSだけでTRUNCATE等を守ることはできない。過去監査で不要なTRUNCATE等の権限を検出しており、将来の最小権限化の対象。ここでは権限を変更しない。

## 関数EXECUTE権限
|public関数|anon|authenticated|備考|
|---|---|---|---|
|add_receipt|不可|可|SECURITY DEFINER|
|change_receipt|不可|可|SECURITY DEFINER|
|cancel_receipt|不可|可|SECURITY DEFINER|
|is_active_user / is_admin|可|可|SECURITY DEFINER、不要な匿名許可を後日検討|
|record_audit / create_profile_for_user|可|可|SECURITY DEFINERのトリガー関数。直接実行許可の是正候補|

認証済み受領は専用RPCを通す設計。受領3RPCの実行とRLSを現状の本番で試験したものではない。関数は所有者権限で実行されるため、内部のauth.uid()と認可判定の保全が重要。

## 監査トリガー
- public.orders の orders_audit = 有効
- public.receipts の receipts_audit = 有効
- 発注数量と受領済み合計の整合性を検証する orders_quantity_receipt_guard は**現行DBに存在しない**。PR #3のDRAFTは未適用。

## Codex向け次の作業
1. この概要と既存VER6-LIVE-SCHEMA-CONTRACT-20261029.mdを比較し、差異・未確認事項を一覧にする。
2. **RLSの正確なロールと式、GRANTの付与元、Auth関連トリガー、全関数の所有者と完全定義、関連ビュー**はまだ未確認。合成SQLから本番相当の挙動を推定しないこと。
3. 権限是正SQLおよび受領数量ガードは使い捨てローカルPostgreSQLでのみ試験し、既存Supabaseへ適用しない。
4. その後、完全なレビュー済み非機密定義が揃ったら、ローカルSupabaseで架空2ユーザー・実JWT・RLS・業務RPCを検証する。
5. Ver.5、main、Supabase本番、課金リソースを変更せず、PR #4をDraftのまま維持。

### 調査の限界
認証ログイン、データ書き込み、各ロールでの実APIアクセス、実機スマートフォン操作は実行していない。監査資料の公開は、完全なスキーマ/RLS再現を保証しない。
