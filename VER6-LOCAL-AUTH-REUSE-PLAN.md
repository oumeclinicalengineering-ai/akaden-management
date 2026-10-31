# PR #3 ローカルAuth試験の再利用調査

参照したPR #3のHEAD: `02651c8ee7fffa8a38d6284e11252dd41a4a928a`。
git showで参照しただけでPR #3のSQLや設定は適用していません。

## 再利用可能な仕組み

|PR #3のファイル|再利用範囲|今回の注意点|
|---|---|---|
|.github/workflows/real-gotrue-local-test.yml|一時ディレクトリ、CLI 2.122.0、ローカルDocker起動、キーをログから除外、127.0.0.1限定、alwaysの削除|QR RPC読み込み・端末登録の工程は今回不要。ワークフロー全体をコピーしない|
|tests/auth/local-gotrue-integration.test.ts|supabase-js 2.57.0、架空ユーザー作成、getUser、JWTと実auth.sessions行照合|magiclink用。Ver.6のsignInWithPassword・2ユーザー・管理者操作の検証を別途用意する必要あり|
|tests/auth/local-auth-probe.sql|実auth.uid()/session_idを使うRLSプローブ|業務テーブルのRLSではないため、その成功でorders/receiptsの認可を判断しない|
|tests/postgres/least_privilege_fixture.sql|権限テストの構成・危険な権限への回帰試験の参考|一部ポリシーと権限の合成fixture。完全な実定義ではない|
|tests/postgres/fixture.sql|使い捨てDBの数量ガード試験|認可ヘルパーが常にtrue。実ユーザーの権限を再現しない|

既存のPR #3ではローカルAuth試験の成功が文書化されています。今回、それを再実行した・業務RPCを検証したとは扱いません。

## 不足定義の一覧（推測で補完しない）

- orders / receipts / profiles / audit_logs: 正確な型、NULL、DEFAULT、CHECK全文、外部キーと削除動作、UNIQUE、インデックス、所有者。
- 全対象表・ビュー: RLS有効/強制、ポリシー全文（対象ロール、操作、USING、WITH CHECK）、security_invoker等のビュー設定。
- publicスキーマ、表、列、シーケンス、関数のGRANT/REVOKEと既定権限。anon/authenticated/service_roleの正確な実効権限。
- add_receipt / change_receipt / cancel_receipt全文。引数・返却型は要約で確認済みだが、ロック順序、deleted確認、例外、監査・権限の詳細が必要。
- is_active_user / is_admin、プロフィール作成、監査の関数・トリガー全文、所有者、search_path。
- Authプロフィール生成と初期role/activeの決定、ローカル再現に必要なメール確認・パスワード認証設定。ユーザーレコードや秘密鍵は不要。

PR #3のDRAFTは変更案であり、現在の本番定義と同一とは扱いません。スキーマ契約要約と過去監査から完全SQLを生成しません。

## 今回のオフライン検証

既存画面処理をVMで実行するテストを3件追加: add_receiptの引数・数量型・受領者trimの契約、小数数量のRPC送信前拒否、RPC権限エラーの失敗表示。これらは実Auth/RLSではなくモックで送信契約とエラー伝達を検査します。
Node動作テストは合計18件。静的チェックと模擬ブラウザー共有試験も維持します。CI結果は当該コミットのActionsで確認してください。

## 再開条件

レビュー済みの完全な非機密SQL定義が揃ってから、独立ローカル環境に限定して適用し、架空スタッフ2名→片方をローカル管理者にする権限試験、実JWTでの発注/受領/修正/取消、無効ユーザー、同時操作を検証します。それまでは実認証・業務RLS・実RPC試験は未検証です。本番接続・リモートlink/db push/db reset・新規有料環境は不要です。
