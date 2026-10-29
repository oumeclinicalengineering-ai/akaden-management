# Ver.6 初回管理者端末・安全な立ち上げ手順（DRAFT / 未配備）

> **この文書とSQLはGitHub開発用ブランチだけにあります。現在のSupabaseデータベース、Auth設定、既存のVer.5・Ver.6には一切適用していません。**
> Supabaseの追加料金がかかる開発ブランチは作成しません。現状は公開GitHubリポジトリの標準Actions + 一時PostgreSQL（架空データ）で検証しています。

## 目的
スタッフ向けQR登録を開始する前に、最初の管理者端末を安全に登録する。管理者自身の最初の端末は、まだ承認済みセッションがないため通常のQR登録画面では承認できない。したがって**プロジェクトオーナーがSupabase SQL Editorから最初の1台を承認する**。

## 初回承認の安全設計
1. 管理者は既存の管理者メール・パスワードで自分の端末からログインする。
2. 開発用QR登録画面の「初回承認に必要なIDを確認」で **管理者ユーザーID** と **ログインセッションID** だけを表示。どちらもUUIDであり、パスワード、アクセストークン、リフレッシュトークンを表示しない。
3. SQL Editorの利用権限がある責任者が対面で管理者本人・端末を確認する。
4. 本番に適用する前にバックアップ、RLS/RPC監査、ロールバック計画を整える。別環境で十分な試験が完了し、承認された場合に限り `20261029_device_sessions_DRAFT.sql` と `20261029_admin_bootstrap_DRAFT.sql` の内容をレビュー・適用。
5. **適用後も手動操作が必要**：SQL Editorで本人確認済みの2つのUUIDが `public.profiles` の有効な管理者と `auth.sessions` の実在する同一ユーザーのセッションに一致することを確認する。
6. SQL Editorだけが実行可能な `app_private.initialize_first_admin_session(admin_user_id,session_id)` を **一回だけ** 実行する。架空のUUID・サンプル値を実データとして実行しない。
7. 成功後、管理者セッションが許可済みとして登録されたことと監査ログが1件増えたことを確認。2度目の呼び出しは拒否される。
8. **ここまで済むまで `20261029_device_cutover_DRAFT.sql` を適用しない。** 未承認の既存端末が一斉に締め出される危険がある。
9. RLS全面切替後は、承認済み管理者端末からQR発行・対面承認・スタッフ端末の無効化を行う。

### 読み取り専用の照合SQL（将来の運用例）
SQL Editorで使う場合、UUIDのプレースホルダーを **承認済み管理者が確認した値に置き換えてから** 実行する。下のサンプルはSELECTのみで変更しない。

```sql
SELECT p.user_id, p.role, p.active,
       s.id AS session_id,
       (s.not_after IS NULL OR s.not_after > now()) AS session_not_expired
FROM public.profiles p
JOIN auth.sessions s ON s.user_id = p.user_id
WHERE p.user_id = '<管理者UUID>'::uuid
  AND s.id = '<管理者セッションUUID>'::uuid;
```

結果がちょうど1件、`role='admin'`、`active=true`、`session_not_expired=true` のときだけレビューを続ける。**SQLが成功しただけで本人確認が済んだことにはならない。**

### SQLの権限・運用上の制限
- bootstrap SQLは `app_private` にある。ブラウザのSupabase Data APIに公開していない。
- `anon`、`authenticated`、`service_role` のEXECUTE権限は明示的に取り消し、`postgres` にのみ許可する設計。
- SQL Editorには高い管理権限が必要。病院の承認手順に従い、認証情報をチャットに貼り付けない。
- データベース内に1件のbootstrap履歴を保存するため、2回目は成功しない。
- 旧端末失効時には**最後の有効な管理者端末は無効化できない**ガードを設定。ただし物理的な紛失に備えた **管理者緊急復旧フロー** は別途実装・テストが必要であり、未完成の状態では運用開始しない。

## 無料テストで確認したこと
- スタッフ、匿名ロール、service_roleは初回承認操作を実行できない。
- スタッフのユーザーID・他人のセッションID・期限切れのセッションは拒否。
- 有効な管理者とそのAuthセッションだけ登録される。
- 2度目の初回登録は拒否。承認と操作履歴が一体で作成される。
- **RLS全面切替後でも初回管理者は利用可能**、同じ管理者の別セッションやスタッフの未承認端末は拒否。
- 最後の管理者端末の失効操作は拒否。

## 適用前の重要チェック
- 本物のSupabase Auth・Edge Functions・メールOTPと、GitHub Pagesの実機動作試験は未実施。
- 管理者の緊急復旧方法、ロールバック、RLS/RPC全経路の失効検証、同時登録競合テストが必要。
- 個人情報・患者情報を公開リポジトリに含めない。
- 自動テストが成功しても本番投入の承認にはならない。

公式参考: https://supabase.com/docs/guides/auth/sessions

**状態：SQLドラフト・スマートフォン用UI・無料テストを作成済み、Supabase本番へ未適用。**
