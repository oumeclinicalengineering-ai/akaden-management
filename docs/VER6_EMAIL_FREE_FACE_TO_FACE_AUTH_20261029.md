# 赤伝管理Ver.6：メールを使わない対面QR初回ログイン（試作・未配備）

作成日：2026-10-29。**本番利用禁止、実Supabaseへ適用していません。**
開発PR：https://github.com/oumeclinicalengineering-ai/akaden-management/pull/3

## 実現したい運用
職員の個別メールアドレスへの認証メール送信を使わない。管理者が対面で職員・端末・申請番号を確認し、既存スタッフのSupabase Authユーザーに**公式GoTrue認証セッションを発行する**。初回承認後は従来どおりセッションが維持され、端末紛失時はDB側で当該セッションのアクセスを止める。

### 予定フロー（開発用画面に実装）
1. 管理者は承認済み管理者端末からVer.6 QR登録画面にログインし、既存スタッフを選択して**10分・1回限りのQR**を発行。
2. スタッフは同じ場所でQRを読み取り、**「メールを使わず登録申請する」**を押す。この時点でログイン不要。端末に32-byte乱数の秘密情報と6桁番号が生成され、秘密情報はそのタブの `sessionStorage` のみで保持。QR情報もアドレスバーから消去する。
3. 管理者は**対面**でスタッフ本人・承認待ち一覧のスタッフ名と申請・スマートフォンの6桁番号を確認し承認。認証コードの誤入力は5回まで。
4. スタッフが **「承認を確認してログイン・端末登録」**を押す。未承認・違うブラウザの秘密情報・期限切れ・再利用はサーバーで拒否。
5. サーバーは同一申請について**一度だけ**認証情報発行権を取得し、`auth.admin.getUserById` で登録済みユーザーの既存メールを取得（**送信しない**）。`auth.admin.generateLink({type:'magiclink',email})` で既存アカウント用の一回限りの認証 `hashed_token` を生成。戻りのユーザーIDが申請対象と一致することも確認。
6. 発行された `hashed_token` をその端末へ一度だけ返す。**これはログイン用の秘密情報なので、ログ・URL・localStorageに保存しない。** スタッフのブラウザから `supabase.auth.verifyOtp({token_hash,type:'magiclink'})` を呼び、公式Supabase Authのログインセッションを取得。**JWTやAuthセッションを独自生成しない。**
7. 既存の認証済み `ver6-enrollment-api` が `auth.getUser(jwt)`・JWT `session_id` とユーザーIDをチェックして、`finalize_approved_device_enrollment` が `auth.sessions` と照合。端末登録と監査履歴を1トランザクションで確定。
8. Ver.6に移動。機種変更・紛失時は管理者の旧端末無効化RPCとRLSが対象セッションを拒否。管理者の最終利用端末は通常操作で無効化できない。

## 今回のGitHub変更
- `supabase/migrations/20261029_face_to_face_auth_claim_DRAFT.sql`：承認済み・未期限切れ・未利用・対象スタッフ有効・申請元ブラウザの256bit秘密を照合する一回限りのRPC。
- `supabase/functions/ver6-face-to-face-enrollment/index.ts`：未認証QR申請・管理者承認後の一回限りAuthトークン受け渡し。**デフォルトOFF**：`QR_ENROLLMENT_ENABLED` と `QR_FACE_TO_FACE_ENABLED` の両方が `true` のときに限る。オリジンのHTTPS一致も必須。
- `supabase/config.toml`：未認証QRブートストラップのみ `verify_jwt=false`。承認や端末登録の権限がある既存の`ver6-enrollment-api`は `verify_jwt=true` を維持。
- `ver6-qr-registration-dev.html`：**「メールを使わず登録申請する」**と**「承認を確認してログイン・端末登録」**ボタン。従来メール方式は開発用の折りたたみメニューとして残す。
- `tests/postgres/qr_face_to_face_assertions.sql`：承認前、誤った秘密、匿名・一般ユーザーによるRPC直呼び、再利用、期限切れ、監査履歴の検証。
- `tests/browser/face-to-face-qr-mock.mjs`：iPhone/Android相当の画面幅で、**実メールも実Supabaseも使わず**AuthとEdge APIを模擬して操作を検証。

## 安全上の重要制約・未完了事項
- **実際のSupabase Authの `generateLink` → `verifyOtp` を未検証。** 無料PostgreSQL＋ブラウザモックテストの成功は、実GoTrueを使ったログイン成功の保証ではありません。
- Supabase FreeのメールSMTP制限は、この方式では発行メールを送信しないので直接は利用しません。ただし、**Auth自体のレート制限、無料枠、`generateLink` の既存ユーザーでの動作・メール確認済み状態の扱い**は実環境検証が必要です。
- 初回スタッフは **既存のAuthアカウント** と `profiles` の有効スタッフ行が必要。スタッフが自分で新規アカウントを作ることは想定しません。
- ログインの根拠は **管理者の人間による対面本人確認**。メール所有の証明にはなりません。なりすまし対策として部署内の本人確認ルール、管理者教育、操作履歴・二名確認の要否を検討してください。
- 生成されたAuthトークンは本人確認済みブラウザの秘密情報によって保護されますが、マルウェア・QRや画面の盗撮・端末共有・なりすまし管理者・XSS・通信攻撃のリスクはゼロではありません。**トークンが漏れた場合はアカウントを乗っ取られる可能性があります。**
- サーバーのOriginチェックはブラウザーの誤接続防止であり、**認証やレート制限の代わりになりません**。匿名Edge FunctionにはIP/アカウント別の持続的なレート制限・Bot対策を追加してから配備する必要があります。
- `credential_claimed_at` を設定してから `generateLink` に失敗すると、ログインしないままQRが使用済みになります。**安全側で再利用させず、管理者に新しいQRを出してもらう**。使いかけのリクエストの再オープンは認めない。
- QRを発行する管理者自身の初回承認は、別に作成したSQL Editor専用bootstrapを使用。これが実施されていない環境ではQR発行操作は動きません。
- SQLの `device_cutover_DRAFT.sql` を現行DBにそのまま適用するとすべての未承認端末が締め出される。**この段階で実行しない**。
- Edge Functionは**未配備**。現行Ver.5/Ver.6とSupabase DB/Auth/メール設定は変更なし。追加料金のかかるSupabaseブランチやプロジェクトも作成なし。

## 次の工程（安全確認）
1. 無料自動テストでSQL・ブラウザー・Edge関数の静的型チェックをすべて成功させる。
2. 匿名APIのレート制限・管理者承認の厳格化・監査・ブートストラップ・RLS/RPC全面レビューを実施。
3. **別のテスト専用Auth環境**で `generateLink` → `verifyOtp` → `auth.sessions` → RLS を架空スタッフで実測。費用が発生する開発環境は勝手に作らない。
4. iPhone Safari/Android Chrome実機操作、QR読み取り、機種変更、失効、ネットワーク断、バックアップ/ロールバックを検証。
5. 院内運用・セキュリティ責任者による本番導入承認。

公式資料：
- https://supabase.com/docs/reference/javascript/auth-admin-generatelink
- https://supabase.com/docs/reference/javascript/auth-verifyotp
- https://supabase.com/docs/guides/auth/sessions
- https://supabase.com/docs/guides/functions/auth

**本番未配備・PR #3はDraftのまま維持。**
