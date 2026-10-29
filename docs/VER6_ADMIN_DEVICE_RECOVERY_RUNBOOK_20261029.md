# Ver.6 管理者端末を紛失した場合の緊急復旧手順（開発版・未配備）

> **2026年10月29日時点：本番未適用。** 以下は実運用の手順ではなく、SQLと無料自動テストで検証している設計です。Supabase本番の設定・発注データ・患者情報に変更は加えていません。

## 想定場面
最後の管理者端末を紛失・故障した場合、一般の管理者用「端末を無効化」機能だけでは最後の管理者端末を削除できません。これは管理者が全員締め出される事故を防ぐための仕様です。

復旧には **SupabaseプロジェクトのSQL Editorの管理権限を持つ責任者** が必要です。紛失した管理者自身による、QRだけでの自己復旧は許可しません。

## スタッフへ案内する流れ
1. 責任者に端末紛失・故障を速やかに報告し、病院のインシデント対応手順に従う。
2. 管理者本人を対面で確認し、新しいスマートフォン／PCで **既存のSupabase Authアカウント** にサインインする。登録用ページの「初回承認・紛失復旧用のIDを確認」から **ユーザーIDとセッションID** のみ表示する。
3. 責任者は専用の受付番号（例：`ME-2026-001`）を付与し、どの端末が失われたかを確認する。**パスワード、JWT、メールの認証コード、リフレッシュトークンをコピーしない**。
4. SQL Editor権限者が登録済みの管理者ユーザーIDと、今ログインした新端末のセッションIDが一致することを **読み取り専用SQL** で確認する（下記）。
5. **別途、正式な本番導入承認・バックアップ・検証後**、SQL Editorからだけ実行できる `app_private.recover_administrator_device` を実行する。通常のスタッフ画面・Edge Functionからは実行できない。
6. その管理者の**以前の端末セッションの赤伝データ閲覧・更新権限を失効**させ、新端末を承認する。別の管理者やスタッフの端末には触れない。復旧理由・受付番号・日時・失効件数を記録。
7. 復旧後、本人の新しい端末で赤伝Ver.6にアクセスできること、古い管理者端末ではRLS/RPCによって閲覧・更新できないことを確認する。
8. Supabase Auth自体の旧セッション停止も、Supabaseの公式セッション管理手順で別途行う。**SQLの復旧機能が保証するのは赤伝DBのアクセス拒否であり、Authのリフレッシュトークン失効ではない**。

## 読み取り専用の確認SQL（将来、責任者が実行）
下記はSELECTのみ。プレースホルダーを本人確認済みのIDに置き換えた後、SQL Editorで使用する。

```sql
SELECT
  p.user_id, p.role, p.active, s.id AS new_session_id,
  (s.not_after IS NULL OR s.not_after > now()) AS session_not_expired
FROM public.profiles p
JOIN auth.sessions s ON s.user_id=p.user_id
WHERE p.user_id='<確認済みの管理者UUID>'::uuid
  AND s.id='<新端末で確認したセッションUUID>'::uuid;
```

判定基準：結果が **1件**、`role='admin'`、`active=true`、`session_not_expired=true`。システム上の一致に加え、本人・端末の対面確認が必須。

## 本番適用の前提（現在は実行禁止）
- `20261029_device_sessions_DRAFT.sql` と `20261029_admin_bootstrap_DRAFT.sql`、初回管理者端末登録済み、RLSカットオーバーを完全検証済みであること。
- `20261029_admin_device_recovery_DRAFT.sql` は、`app_private` のSQL Editor専用関数と監査テーブルを作る開発案。一般ユーザー・`service_role`からは呼べない。
- バックアップ、権限・関数定義のレビュー、ロールバック、二名確認、実機テスト、院内運用承認が必要。
- **このSQLを現在の接続済みSupabaseにコピーして実行しないこと。**

## 将来のSQL Editor上の手動復旧例（参考・未実行）
```sql
-- これは書き込み処理です。未承認の状態で実行しない。
SELECT * FROM app_private.recover_administrator_device(
  '<確認済みの管理者UUID>'::uuid,
  '<新端末で確認したセッションUUID>'::uuid,
  'DEVICE_LOST',
  'ME-2026-001',
  true
);
```

この操作は、対象の管理者の過去に承認されたセッションをDBアクセスから失効させ、新たなAuthセッションを承認する。**同じセッションを使った再実行は拒否**。操作履歴は `app_private.admin_recovery_events` に記録する。

既存データモデルの `revoked_by` には、SQL Editor復旧時は技術上の互換性のため復旧対象管理者IDが入る。実際の操作責任者はSQL Editorのアクセス監査と `ticket_reference` で追跡し、`revocation_source='SQL_EDITOR_RECOVERY'` で通常の管理者操作と区別する。

## 無料で確認したテストケース
- スタッフ・一般ログイン・Edge Functionの `service_role` からの復旧を禁止
- 管理者以外、別ユーザーのセッション、期限切れ、受付番号の不備、対面確認未実施を拒否
- 同じセッションで二重復旧を拒否
- 対象管理者の旧端末だけを失効し、新端末が使える
- 別の管理者・スタッフの登録済み端末には影響させない
- 復旧理由・受付番号・失効数を記録
- Supabase Authが発行したセッションを削除／期限切れにした場合、残存JWTでも赤伝DBの参照を拒否するチェックを追加

## 今後の課題
- 実SupabaseのAuthセッション・Edge Functions・メールOTPでの結合テスト
- 業務上の二名確認、責任者の本人確認・受付番号採番、監査記録の保存期間
- Authログアウト／旧リフレッシュトークン停止と、失効時の残存JWTの実測
- 本番向けのバックアップ・ロールバック手順とiPhone/Android実機テスト

**現在の運用状況：設計・無料SQL自動テスト段階。Ver.6での実際の端末紛失復旧はまだ利用できません。**

参照：
- https://supabase.com/docs/guides/auth/sessions
- https://supabase.com/docs/guides/auth/signout
