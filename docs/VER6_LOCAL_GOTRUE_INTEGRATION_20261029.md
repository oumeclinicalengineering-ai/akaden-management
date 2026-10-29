# 赤伝管理Ver.6：実GoTrue/Authの無料隔離結合テスト（2026-10-29）

**開発用・本番未適用。** PR #3はDraftを維持し、Ver.5/Ver.6試験版/接続済みSupabaseは変更しない。

## 追加したファイル
- .github/workflows/real-gotrue-local-test.yml：GitHub標準Ubuntuランナーで一時Supabaseを起動し、テスト後に削除。
- tests/auth/local-gotrue-integration.test.ts：GoTrue、PostgREST、公式Authセッションの実接続テスト。
- tests/auth/local-auth-probe.sql：一時RLSテーブル。本番用マイグレーションではない。

Supabase CLI 2.122.0、supabase-js 2.57.0 に固定。クラウドのSupabase新規プロジェクトは作らずローカルDockerを利用。患者データ・実スタッフ・SMTP・実プロジェクト秘密情報は使用しない。公開リポジトリの標準GitHub-hosted Ubuntuは無料対象。有料ランナー、外部ストレージ、Actions成果物・キャッシュは使わない。

Auth URLは localhost:54321、DBは localhost:54322 に限定。テストでは、本物のアクセストークン、リフレッシュトークン、hashed_token、秘密鍵をファイルやログに記録しない。終了時にローカルDBを破棄。

## 自動チェック（成功して初めて確認済みとする）
1. ローカルAuthで架空の確認済みスタッフを管理者APIから登録（メール送信なし）。
2. generateLink による、既存スタッフ用の本物の magiclink 認証情報発行。
3. 未ログインのブラウザにセッションがないこと。
4. verifyOtp による本物のAuthセッション発行。
5. getUserによるトークン検証、sub・session_idの照合。
6. 一時PostgreSQL RLSで匿名0件・本人1件を確認。
7. 同じ認証トークンの再利用拒否。
8. auth.sessions の実レコードと本人ID・セッションIDの一致。
9. 正式管理者Auth・6桁承認・元ブラウザーclaim・正式スタッフAuth・端末登録・失効を実ハンドラーとRPCで接続。

## 未完了
- 本番設定・既存業務テーブル全体のRLS、実Authを含む管理者復旧、実スマホ操作、長時間のセッション維持。
- 本番クラウドAuthとの設定差異、既存スタッフのメール確認済み状態。
- 本番SQL権限修正・バックアップ取得・ロールバック実施。

## 次の作業
全工程の実装・隔離試験の結果は下記に記録する。本番GRANT/RLS、実機、バックアップ・ロールバックの確認は別作業とし、本番への適用やデプロイはこのワークフローでは実行しない。

参考:
https://supabase.com/docs/reference/javascript/auth-admin-generatelink
https://supabase.com/docs/reference/javascript/auth-verifyotp
https://supabase.com/docs/guides/local-development/cli/getting-started
https://docs.github.com/en/billing/concepts/product-billing/github-actions

## 正式管理者Authを含む全工程テストの追加

`tests/auth/local-qr-full-chain.test.ts` は、使い捨てローカルSupabaseの実GoTrue・PostgREST・PostgreSQLを使用する。Edgeハンドラーを直接呼び出すが、Supabaseクライアント、Auth、RPCをモックしない。Edgeランタイムへのデプロイやスマートフォン実機の試験ではない。

架空の管理者を公式 `generateLink → verifyOtp → getUser` でログインさせ、その実在する `auth.sessions` 行だけをテスト用管理者端末としてbootstrapする。その後は実ハンドラーを経由し、QR発行、匿名申請、先頭ゼロを含む6桁コード承認、元ブラウザーによる一度限りのclaim、スタッフの公式Authログイン、端末登録、RLSアクセス、失効を検証する。

異常系は承認前claim、未登録管理者端末、誤コードと5回ロック、QR再利用・期限切れ、別ブラウザー、並行claim/finalize、Auth認証情報再利用、偽セッション・別人・二重登録、未登録端末、失効後も有効なJWT、最後の管理者端末保護を含む。登録直前のアカウント無効化・役割変更は隔離SQLの回帰テストでも検証する。

実HTTP経由では旧 `request.jwt.claim.role` の単独設定に依存できないため、DRAFT RPCの権限判定はSupabase標準の `auth.role()` に変更した。JSON形式のclaimsを使う回帰テストを追加した。端末登録時の有効staff再確認もDB側へ追加した。これらは開発用DRAFTの変更のみで、本番には適用していない。

ローカルでは静的チェック、Edgeテスト4件、型チェック、隔離PostgreSQLのapproval/finalize/face-to-face/rate/deviceの5スクリプトが成功した。フルSupabaseのPostgresイメージはクラウド環境のDocker容量制限に当たったが、同バージョンの実GoTrue v2.197.0・PostgREST v16.5とPostgreSQL 17の軽量隔離環境で全工程テスト1件が成功した（0件失敗）。GitHub ActionsではSupabase CLIの通常スタックを使い、結果を別途確認する。CLIの起動出力は一時キーを含むためCIログから除外し、一時接続情報をマスクして後処理で削除する。

初回CIで、接続URIを `PGDATABASE` に渡すとpsqlがURIを展開せず接続できないテスト側の不具合を再現した。`--dbname` 引数へ明示的に渡して修正した。失敗時には固定の検証条件名またはSQLSTATEと工程番号だけをActions注釈に出し、SQL・認証情報・生のDBエラーは出力しない。

### 今回の変更ファイル

- `.github/workflows/real-gotrue-local-test.yml`
- `scripts/check-qr-ui.mjs`
- `supabase/functions/ver6-enrollment-api/index.ts`
- `supabase/migrations/20261029_consume_enrollment_invite_DRAFT.sql`
- `supabase/migrations/20261029_device_enrollment_approval_DRAFT.sql`
- `supabase/migrations/20261029_device_sessions_DRAFT.sql`
- `supabase/migrations/20261029_face_to_face_auth_claim_DRAFT.sql`
- `supabase/migrations/20261029_finalize_device_enrollment_DRAFT.sql`
- `supabase/migrations/20261029_qr_abuse_rate_budgets_DRAFT.sql`
- `tests/auth/local-qr-chain.sql`
- `tests/auth/local-qr-full-chain.test.ts`
- `tests/postgres/device_fixture.sql`
- `tests/postgres/qr_finalize_assertions.sql`
- `tests/postgres/qr_rate_budget_assertions.sql`
- `docs/VER6_QR_FULL_CHAIN_LOCAL_TEST_PLAN_20261029.md`
- 本書

`index.html` と `ver6-preview.html` は変更していない。本番Supabaseへの接続・変更、追加課金サービス、実患者・職員データ、PRのReady化・main統合は実施していない。

### GitHub Actionsでの確認結果

コードコミット `8909c35` の [実GoTrue全工程CI #26](https://github.com/oumeclinicalengineering-ai/akaden-management/actions/runs/40854519685) は **Success**。実Auth単体、実在セッション行確認、正式管理者の6桁承認から端末登録・異常系までの全工程、使い捨てスタック削除がすべて成功した。コード変更前の実装・診断コミットは `3d37d58`、`7fab430`。初回の結合テスト失敗は上記のpsql接続指定修正で解消した。

同コミットのPR側で、QR静的検査、ブラウザー/API、モバイル模擬、QR SQL、端末失効、初期管理者、管理者復旧、既存権限、PostgreSQL hardeningもすべて成功した（実Authを含め10ワークフロー）。実機試験・Edgeランタイムへのデプロイ・本番適用の成功を示す結果ではない。PR #3はDraftを維持する。

## 初回試験時の知見（下記の全工程成功前の記録）
- 一時GoTrueが発行した `hashed_token` は**56文字**、旧コードが期待した64文字hexではない。Edge APIと未公開のQR開発画面にのみ、URL-safe opaque token用の構文検証を別途追加した。既存のQR/端末秘密用hex64検証は維持。
- `generateLink` 後の実 `verifyOtp` と `getUser` は、テストのRLS判定に到達するまで正常に動作した。途中結果であり、CI全体成功とはまだ扱わない。
- 匿名側にはテーブルSELECTのGRANTがないため、`42501` 権限エラーは正しい拒否。RLSフィルターで空配列が返る場合と共に明示的に検査し、行が返った場合は必ず失敗させる。
- この修正を含むCIの結果が成功と判定されるまでは、本物のAuth全工程確認済みとは記載しない。
