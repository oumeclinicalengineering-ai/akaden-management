# Ver.6 QR対面登録・端末失効：無料SQLテスト実装（2026-10-29）

## 今回作成したもの（GitHub開発用ブランチ限定）
- `supabase/migrations/20261029_device_sessions_DRAFT.sql`：端末セッションIDの承認一覧、失効・操作履歴、管理者専用失効RPC。
- `supabase/migrations/20261029_device_cutover_DRAFT.sql`：既存の `is_active_user()` / `is_admin()` と profiles RLSに、セッションID承認チェックを組み込む草案。
- `supabase/migrations/20261029_device_enrollment_approval_DRAFT.sql`：QRの1回限りの申請、対面の確認コード、管理者承認、申請端末限定の1回限りの引換え処理と監査ログ。
- `tests/postgres/device_fixture.sql`、`device_assertions.sql`、`qr_approval_assertions.sql`：架空のユーザーとセッションで実行する拒否・許可テスト。
- `.github/workflows/device-revocation-test.yml`、`qr-approval-test.yml`：公開GitHubリポジトリの標準ランナー＋一時PostgreSQL 17だけを使用。Supabaseの有料開発ブランチは不要。

## エンドツーエンドで未実装の部分（必須）
1. **ブラウザー・スマートフォンとEdge Functionとの接続**：QR画面、申請画面、管理者承認画面、CORS、レート制限は未実装。
2. **Supabase Auth正式フロー**：QRトークンの所持だけでログインはさせない。管理者対面承認後、サーバーで正当なSupabase Auth認証フローを用いてログインセッションを発行する必要がある。メールOTP/マジックリンク、管理者発行リンクなど公式方式を検証する。
3. **実ユーザーの本人確認とセッションIDの結び付け**：承認を受けたユーザーIDと、その端末で発行された実際のAuth `session_id` をサーバーで検証してから `register_approved_device_session` を呼ぶ。端末から渡されたユーザーIDやセッションIDをそのまま信用してはいけない。
4. **管理者初回セッションの承認（ブートストラップ）**：カットオーバー後に管理者まで締め出さないよう、安全な初回登録・復旧方法が必要。
5. **本物のSupabase Auth・Edge Functions・RLS／全RPCの試験**：今回のGitHub ActionsはPostgreSQLの模擬環境で、GoTrue、PostgREST、実ブラウザーを起動していない。
6. **機種変更時のAuthセッション失効**：アプリ内のDBアクセスはRLSで即時拒否する設計。Authのリフレッシュトークン/セッション自体の停止は、Supabaseの公式サインアウト・失効方式も検証する。Authの既存アクセストークンは有効期限まで署名検証に通るので、DB側のブロックが必要。

## 運用
- QR有効期限：最大10分
- 一回限り：招待の申請は1回、承認後の引換えは1回
- 管理者がスタッフの端末に表示された確認コードを対面で照合し承認
- 確認コードの間違いは5回まで
- 端末失効は管理者の**承認済みセッション**のみ操作可
- 監査ログには利用者/セッションID・操作種別・時刻を記録し、QR原文や秘密鍵は保存しない

## 安全上の留意点
- `app_private` スキーマはSupabase APIの公開スキーマに追加しない。
- 管理者/スタッフの端末トークン・service_role鍵をQR、GitHub Pages、GitHub Actions、公開リポジトリに保存しない。
- Edge Functionを本番にデプロイする前に、API認証、レート制限、CORS、監査、運用復旧計画を実装し検証する。
- SQLドラフトを**現行Supabaseへ適用してはいけない**。 `device_cutover_DRAFT.sql` は未承認のすべての既存セッションを遮断するため、現段階で実行するとスタッフ・管理者がログイン後にデータへアクセスできなくなる。

## 公式仕様
- https://supabase.com/docs/guides/auth/sessions — JWTにはAuthセッションIDがある
- https://supabase.com/docs/guides/auth/signout — サインアウト後もaccess tokenは期限まで有効
- https://supabase.com/docs/guides/auth/auth-email-passwordless — 公式メールパスワードレス方式
- https://supabase.com/docs/guides/functions/auth — Edge Functionsの認証方式

**状態：DB草案と無料自動テストの段階。実環境でQR初回登録・端末失効はまだ利用不可。**
