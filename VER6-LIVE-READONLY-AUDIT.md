# Ver.6 実接続前の読み取り専用監査（2026-10-29）

## 調査範囲
- 接続済みSupabaseの pg_policy と pg_proc を SELECT のみで確認。
- 既存のVer.5、main、Supabaseデータ・設定・認証・RLS・SQL・GitHub Pagesは変更していない。
- 実データの取得、ログイン、RPC呼び出し、書込みテストは実施していない。

## 確認できたこと
1. orders, receipts, profiles, audit_logs でRLSが有効であり、ordersにはSELECT/INSERT/UPDATE、receiptsにはSELECTのポリシーがある。
2. add_receipt/change_receipt/cancel_receipt は authenticated 実行可能、anon 実行不可。
3. add_receipt は有効ユーザー確認、数量上限確認、orders行FOR UPDATE、受領済合計照合を行う。
4. change_receipt は本人または管理者を確認し、同じorders行ロックを使い、受領済合計を照合する。
5. cancel_receipt は本人または管理者を確認し、対象のorders行とreceipts行をロックする。
6. is_active_user/is_admin はprofilesのactiveとroleを参照する。

## 運用を止める未解決事項
**重要：orders更新のDB側数量保証が不足。** orders_update RLSは所有者/管理者の変更権限を制限するが、発注数量を受領済合計以上に保つ条件はない。フロントの検査は別端末の同時受領やAPI直接呼出で回避できる。orders.quantity >= 1 のCHECKはあっても、受領済合計との整合性は保証されない。
- 対応候補はPR #3の未適用ドラフト `20261029_order_quantity_guard_DRAFT.sql` にある。
- **このファイルを実Supabaseへ適用してはいけない。** 先に隔離した使い捨てPostgreSQLで、同時受領、発注数量減額、ロールバック、監査ログ、RLSを確認する。
- 受領RPCの実接続、同時アクセス、JWT/セッション、スマホ実機、画面からの編集・取消、管理者操作は未検証。
- SECURITY DEFINER関数の一部がanonに実行許可されている問題はPR #3の監査対象であり、簡易版の統合条件に含める。
- 既存のSupabaseプロジェクトに試験データを投入しないこと。

## 次の作業
1. PR #4 のブラウザ自動テストとCIを維持する。
2. PR #3 の発注数量ガードSQLを**実DBには適用せず**独立PostgreSQL17で検証。
3. スキーマ/RPC/RLSを複製した隔離検証環境が利用可能か、費用ゼロで確認。なければ実接続試験は保留する。
4. 架空の2アカウントで発注5個→分納3個→受領2個→超過拒否と、同時受領・同時減額・権限制御を確認する。
5. 結果が揃うまでPR #4はDraftのまま、本番へのマージ禁止。
