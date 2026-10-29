# Ver.6 QR対面登録：スマホ画面＋メールOTP＋端末失効（2026-10-29）

## この段階で追加したもの（すべてGitHubの開発ブランチのみ）
- `ver6-qr-registration-dev.html`：iPhone/Android向けスタッフ画面（QR読取、メールOTP、申請、完了）、管理者画面（ログイン、スタッフ選択、QR発行、承認待ち、端末失効）。
- `vendor/qrcodejs/qrcode.min.js`：MITライセンスのQR生成ライブラリをローカルに保存。トークンを外部QR生成サイトに送らずブラウザ内で画像化。
- `supabase/functions/ver6-enrollment-api/index.ts`：JWTの `auth.getUser` 照合、管理者権限チェック、10分・1回限りのQR発行、スタッフ申請、管理者の承認、Authセッションへの結び付け、旧端末の無効化。
- `supabase/migrations/20261029_finalize_device_enrollment_DRAFT.sql`：承認済み申請を `auth.sessions` のユーザー/セッションIDと照合し、消費・端末登録・監査ログを一つのDBトランザクションで実行。
- `supabase/migrations/20261029_enrollment_admin_views_DRAFT.sql`：承認済み管理者専用の承認待ち・端末一覧RPC。
- CI：`qr-browser-check.yml` でHTML構文とEdge Functionの型チェック、`qr-approval-test.yml` でPostgreSQL上の拒否/認可テスト。

## 登録の運用（予定）
1. 管理者が既存の管理者アカウントにサインインし、スタッフを選択して一回限り・10分有効のQRを発行する。
2. スタッフが自分のスマートフォンでQRを読み取る。URLのフラグメントから招待情報を取得したら、外部JavaScriptの読み込み前にアドレスバーから消去する。
3. スタッフが**登録済みメールアドレス**へ届いたSupabase Authのワンタイムコードを入力して本人確認する。新規ユーザー自動作成は無効。
4. スタッフが登録申請。スマホ画面に6桁の確認番号が表示される。
5. 管理者が対面している本人と承認待ち一覧のスタッフ名・申請ID・スマホの確認番号を照合し、サーバー側で承認。
6. スタッフが完了操作。サーバーは**実際に認証したJWTとそのAuthセッションID**を検証し、承認済み申請・端末セッション登録・操作履歴をトランザクションで確定する。
7. 紛失・機種変更時は管理者が旧端末セッションを失効させ、データベース側のRLSとSQL関数で旧端末を拒否する。

## 配備前に解決すべき項目（重要）
- **このUIとEdge Functionは未配備。** ユーザーが現在のGitHub Pagesで試験版を閲覧できる状態ではない。
- **QR_ENROLLMENT_ENABLED はデフォルトOFF。** 先にEdge API、SQL、RLS、管理者の初回承認を独立した環境で検証し、明示的に有効化する必要がある。
- Supabaseのメールテンプレートをコード式OTPに設定する必要がある（テンプレートに `{{ .Token }}` を含める）。現行設定を変更しておらず、実メール受信テストも行っていない。
- **管理者の初回承認（ブートストラップ）** が未実装。これを用意せずに `20261029_device_cutover_DRAFT.sql` を既存プロジェクトに適用すると、すべての端末が認証後にデータへアクセスできなくなる恐れがある。
- 管理者用パスワードログインは移行期のみの暫定方式。スタッフは公式 `signInWithOtp` → `verifyOtp` を使用。
- Edge Functionsの入出力テスト、レート制限の競合試験、第三者からの攻撃シナリオ、実Supabase Auth・PostgREST・RLS、iPhone/Android実機の操作試験は未実施。
- `QR_ALLOWED_ORIGIN` は承認したHTTPSオリジンのみ、秘密鍵はサーバー環境変数のみ。ブラウザにはpublishable/anonキーのみ。
- QR・OTP・ブラウザー秘密・JWTをGitHub、Analytics、監査ログに保存しない。現行UIはQR画像を直接ブラウザ内生成し、QRトークンは `sessionStorage` で保持し、アドレスバーからすぐ削除。
- Supabase Authの発行したアクセストークンはセッション失効後も期限まで有効なことがある。登録済みデバイスのRLSチェックにより、**アプリのDBアクセス**を即時拒否する設計だが、Authセッション自体の停止は別途実装・テストする。
- 公開済みVer.5とVer.6試験ページを維持し、患者情報や実際の発注情報を使用しない。

## 無料での検証
GitHubが **public** のまま、標準GitHubホストランナーでActionsを実行する範囲は無料。PostgreSQLの一時コンテナが各実行後に消える。Supabaseの有料開発ブランチ・新規プロジェクトは作らない。メール送信数などSupabase Authの無料枠・制限は別途確認。

## 次の技術的作業
1. CIのすべての緑チェックを確認する。
2. 管理者初回端末を安全に承認する方式を設計・検証する。
3. 登録画面とEdge APIを独立した試験用URLへ配備し、架空スタッフによる実際のOTPメール送受信を検証する（既存DBへのSQL変更は事前レビューと明示承認が必要）。
4. 旧端末でのログイン継続・権限拒否・復旧手順を実機で確認する。

**状態：画面・サーバーコードを作成済み。CIは静的検査＋模擬PostgreSQL。実Supabase環境には変更なし。**

公式仕様：
- https://supabase.com/docs/guides/auth/auth-email-passwordless
- https://supabase.com/docs/guides/auth/sessions
- https://supabase.com/docs/guides/auth/signout
- https://supabase.com/docs/guides/functions/auth
