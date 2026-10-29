# 赤伝管理 Ver.6｜現行Supabaseの権限監査・最小権限化の手順（2026-10-29）

**状態：読み取り専用で現行DBを確認済み。修正SQLはGitHubのDraft PR #3だけに保存し、現行Supabaseでは実行していない。**  
対象：Supabaseプロジェクト `rqgzcjkvpxveeflkpiib`。ユーザー・患者・注文・受領・監査ログのレコードは読み取っていない。

## 実DBで確認できた事項
- `orders`・`receipts`・`profiles`・`audit_logs` の4テーブルすべて **RLS有効**。
- 受領データ：`authenticated` は `receipts` の直接 `INSERT/UPDATE/DELETE` 不可。受領追加・修正・取消は専用RPC `add_receipt` / `change_receipt` / `cancel_receipt` を使用。
- 3つのRPCはいずれも `SECURITY DEFINER` で、`anon` の実行不可、`authenticated` の実行可。関数定義を読み取り確認したところ、`auth.uid()`・有効ユーザー確認・数量上限・ロック・作成者/管理者の編集取消制限を実装。
- `orders`：`authenticated` に直接 `SELECT/INSERT/UPDATE` が必要（Ver.6プレビューの赤伝一覧・新規登録と整合）。既存のRLS `orders_insert`・`orders_update` は登録者または管理者を確認。
- `profiles`：管理者の `UPDATE` と、本人・管理者の `SELECT` がRLSで許可。これらは削除せず残す。
- `audit_logs`：閲覧できるのはRLS上の管理者。スタッフの直接更新権限は不要。
- `order_receipt_totals` ビューは **`security_invoker=true`**。基礎テーブルのRLSを継承する設定なので維持。
- ただし4テーブルに `anon` / `authenticated` の **`TRUNCATE`・`TRIGGER`・`REFERENCES`・`MAINTAIN`** 等の過剰なGRANTが存在。特に `TRUNCATE` はRLSの対象外。外部の通常のPostgREST画面がこの権限を直接使えると確認したわけではないが、SQL権限として不要なため最小化が妥当。
- `service_role` は4テーブルの権限を明示的に付与されているため、今回のドラフトはそのロールの権限を変更しない。

## 安全な修正案
`supabase/migrations/20261029_existing_tables_least_privilege_DRAFT.sql`

| テーブル／ビュー | 匿名 `anon` | ログイン `authenticated` |
|---|---|---|
| `public.orders` | 全操作禁止 | `SELECT`、`INSERT`、`UPDATE` |
| `public.receipts` | 全操作禁止 | `SELECT` のみ（追加・修正・取消はRPC） |
| `public.profiles` | 全操作禁止 | `SELECT`、`UPDATE`（RLSで管理者のみ更新） |
| `public.audit_logs` | 全操作禁止 | `SELECT` のみ（RLSで管理者のみ） |
| `public.order_receipt_totals` | 全操作禁止 | `SELECT` のみ（`security_invoker=true` を維持） |

**この修正案は既存のデータ、RLS定義、トリガー、Auth、受領RPCの内容を変更しない。**
同時に `DELETE`、`TRUNCATE`、`TRIGGER`、`REFERENCES`、`MAINTAIN` 等の不要なDB権限を外す。**`GRANT` によってRLSを回避させるものではない。**

## 無料で行った検証
- `tests/postgres/least_privilege_fixture.sql`：実DBと同種の過大なGRANT/RLSを架空の注文・職員・受領・監査ログに再現。
- `tests/postgres/least_privilege_assertions.sql`：権限判定に加え、`authenticated` ロールが実際に監査ログを `TRUNCATE` できないこと、監査ログに偽のレコードを追加できないこと、受領データを直接INSERTできないこと、赤伝のINSERT/UPDATE/SELECT、スタッフ情報の管理者更新、監査トリガーが引き続き動作することを検証。
- `.github/workflows/least-privilege-test.yml`：標準GitHub Actions＋使い捨てPostgreSQL 17だけを利用し、**実Supabaseには一切アクセスしない**。

## 本番適用前の必須条件
1. 現行のGRANTを `pg_catalog` / `aclexplode` で読み取り専用スナップショット化し、変更前の権限を復旧できる形で保管する。患者・注文データの抽出は不要。
2. テストが成功し、Ver.6の画面と既存の受領RPCを別環境で実操作できることを確認する。
3. 使用中のサードパーティツールが、`anon` のビューSELECTやテーブルの不要な権限に依存していないかを確認する。
4. バックアップ・ロールバック手順を準備し、病院管理者から明示承認を得てから、本番で修正する。ChatGPTが独断で本番SQLを適用しない。
5. 本番適用後はRLS、ビュー、管理者・スタッフの画面、Authサインアップトリガー・監査ログ・受領RPCを確認する。
6. Supabase Security Advisorを再取得し、匿名実行可能な `SECURITY DEFINER` 関数は既存の別ドラフト（`20261029_order_quantity_guard_DRAFT.sql`）で対応を検討する。受領RPCは業務で必要なため、単純にEXECUTEを禁止しない。
7. `orders.quantity` を受領済み数量未満へ変更できないようにするトリガーも別ドラフトにあるが、本番未実装。今回の最小GRANT化だけでは防止されない。

## 重要な区別
- SQLのテーブル権限（GRANT）は、RLSによるレコードの可否とは別。RLSは `TRUNCATE` を防がない。
- PostgreSQLの `TRUNCATE` 権限があることは、通常の公開Web画面に全件削除APIが存在することと同義ではない。
- `record_audit()`・`create_profile_for_user()` はTRIGGER戻り値の関数で、通常のユーザーRPCとして実行できる普通の関数とは異なる。Security Advisorの警告は一律に「直ちに攻撃可能」を意味しない。
- **実環境への変更はゼロ**。この報告をもって「本番の権限が修正済み」とみなさない。

参考：
- https://supabase.com/docs/guides/database/postgres/row-level-security
- https://supabase.com/docs/guides/database/functions
- https://www.postgresql.org/docs/current/ddl-rowsecurity.html
- https://www.postgresql.org/docs/current/sql-grant.html
