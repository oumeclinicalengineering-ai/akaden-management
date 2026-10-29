# Ver.6 実Supabase Authの事前確認と無料スマホ画面試験 — 2026-10-29

**重要：この報告は読み取り専用調査＋GitHub開発ブランチ上の変更です。Supabase Authの設定、メールテンプレート、公開中のVer.5/Ver.6、DB、Edge Functionsへの変更は行っていません。**

## 現行の接続先（機密情報なし）
- 組織プラン：**Free**（Supabase接続から確認）
- 対象Supabaseプロジェクト作成日：**2026-10-23**（2026-06-03のメールテンプレ制限導入後）
- プロジェクト状態：ACTIVE_HEALTHY
- 接続先には公開用APIキー（publishable / 旧anon）が有効。**キーの文字列はこの文書に保存しない。**
- Edge Functions：現時点で **0件**。開発中のQR登録APIは未配備。
- 実DBの `auth.sessions` に `id`、`user_id`、`not_after` 列があることを読み取り専用で確認済み。
- 実DBの `app_private.approved_device_sessions` は未作成。QR登録のDB変更は未実行。
- **確認できていないもの**：Auth > Email Templates の実際のメール本文、カスタムSMTPの有無、Auth > URL Configuration のredirect URL。現在の接続経由では管理画面内のこれらの設定を直接読み取れないため、確認済みとは扱わない。

## 2026年のFreeプランの重要制限
Supabase公式Changelog（2026-06-03）によると、**この日より後に作成したFreeプロジェクトで標準SMTPを使う場合、Authメールテンプレートは変更不可**。Supabase公式SMTPガイドでは、標準SMTPは**プロジェクトのチームメンバーにのみ配信**、現在の制限は**プロジェクト全体で2通/時間**であり、業務運用には推奨されない。

このため、2026-10-23作成の当プロジェクトで「メールの6桁OTPを自由に職員へ送る」案は、**標準SMTPかつFreeのままでは実現できない**。メールアカウントへのリンクは標準テンプレートで送れる場合があるが、やはり送信先と送信回数制限があり、**病院スタッフ全員への本番配布に使えるとは考えない**。

現行Auth設定に独自SMTPが導入されていれば制限は変わり得る。実SMTP設定を無断変更しない。

### 今回の画面改修
- `ver6-qr-registration-dev.html` の認証方式は**Magic Link（メールのログインリンク）を初期選択**。
- 設定済みの独自SMTPと `{{ .Token }}` メールテンプレートがある場合のみ、6桁OTPを選択できる（実際の有効/無効判定は今後のAuth設定確認が必要）。
- Supabase Auth公式の `signInWithOtp` を `options.shouldCreateUser:false` で実行し、新規登録の無断作成を防止。
- Magic Linkの戻り先を `location.origin+location.pathname` に指定。**本番で使用する場合はSupabase Authentication > URL ConfigurationにそのHTTPSページを許可URLとして登録する必要がある**。現時点では設定変更していない。
- `detectSessionInUrl:true` を設定し、メールリンクによるリダイレクトからSupabase Authセッションを取り込めるよう変更。
- 既存Ver.6と同じAuth storage keyを使用し、**公開用のURLと公開用キーのみ**ブラウザのローカル設定へ保存して、同一ブラウザの別タブでログインリンクを開いた際に初期化できるよう修正。**QRトークン・ブラウザー秘密・パスワードはlocalStorageへ保存しない。**
- スマホに「ログイン状態を確認」を追加。メールアプリからログインリンクを開いた後、**元のQRページに戻って**ログインを確認する。
- **別ブラウザ間（iPhone SafariとChrome等）ではsessionStorageが共有されないため、QRの情報が失われる可能性がある**。必ず実機で検証すること。

## 無料のブラウザー自動テスト
- `.github/workflows/qr-mobile-mock.yml`: 公開GitHubリポジトリの標準Actionsランナーで、Chromiumを起動し、iPhone相当 390×844 と Android相当 360×800 の表示・タッチ操作を**模擬**。
- `tests/browser/mobile-qr-mock.mjs`: プロジェクトURL・公開用キーは**偽物**、Supabase SDKのAuth関数とEdge APIを**すべてモック**。ログインリンク送信設定、QRフラグメントの消去、管理者QR発行、登録申請、承認、旧端末失効、スマホの横スクロール、JavaScriptエラーを検証。
- **Supabaseの本番DB/実Auth/メール送信にはアクセスしない。**
- Chromiumのモバイル画面を模擬しているだけで、**iPhone SafariやAndroid Chromeの実機テストではない**。

## この段階で必要な現地確認（手動）
1. **Supabase > Authentication > Email Templates > Magic Link**：現在の標準リンクか、`{{ .Token }}`入りの専用OTPテンプレートか（編集はせず閲覧）。
2. **Authentication > SMTP Settings**：標準SMTPかカスタムSMTPか（資格情報は共有しない）。
3. **Authentication > URL Configuration**：将来のVer.6登録用ページを認証リダイレクト先に許可できるか（今は設定変更しない）。
4. **Authアカウント**：架空のスタッフで、メールアドレスが確認済みか、公開メールで安全に試験できるか（実メールの送信テストはまだ行わない）。
5. **実機**：iPhone Safari、Android Chromeで、QRをカメラから開く、メールから元のブラウザへ戻る、失効後の旧端末を確認する。

## 次の意思決定
- **Freeプラン標準SMTPのまま運用**：チームメンバー以外へのメール認証が制限されるため、職員向けログイン方式を再設計する必要がある。
- **既存の信頼済みSMTPを使用できる**：病院の承認・プライバシー・料金・送信制限を確認してメール認証を本格検証する。
- **対面認証を中心とした別方式**：Supabase Auth公式のセッション発行手段を利用し、QR/承認だけで本人認証を不正に偽造できない方式を別途実装・検証する（現在は未実装）。

公式参考：
- https://supabase.com/changelog/46599-changes-to-email-template-customisation-on-free-tier
- https://supabase.com/docs/guides/auth/auth-smtp
- https://supabase.com/docs/guides/auth/auth-email-passwordless
- https://supabase.com/docs/guides/auth/testing-auth-flows

**この文書に実スタッフメール、患者情報、APIキー、OTP、SQL変更、料金のかかるブランチの生成は含めない。**
