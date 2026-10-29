# Ver.6 QR対面承認から正式Auth・端末登録までの隔離結合試験計画

**STAGING ONLY / 本番未適用。** PR #3はDraftのまま維持する。Ver.5、公開Ver.6試験版、接続済みSupabaseには変更しない。

## 現状
- 実GoTrueの `generateLink → verifyOtp → getUser → auth.sessions` はGitHub Actionsで成功済み。
- QR承認、端末登録、失効は従来の模擬/隔離テストで検証済み。
- `tests/auth/local-qr-full-chain.test.ts` に実ハンドラー・実GoTrue・DRAFT RPCを接続した全工程テストを実装。軽量ローカル隔離環境で1件成功・0件失敗。Supabase CLI通常構成のActions結果と検証範囲は [実GoTrue結合試験記録](VER6_LOCAL_GOTRUE_INTEGRATION_20261029.md) を参照。

## 実装したCIの構成
1. GitHub標準Ubuntuランナーで使い捨てのSupabase CLIローカル環境を起動。接続先はlocalhostのみ許可。実スタッフ、患者データ、SMTP、クラウドのSupabaseプロジェクトを使用しない。
2. DRAFT SQLの依存関係（profiles、is_admin、invites、approved_device_sessions、requests、claim、finalize、rate budget）を確認し、ローカルに限って適用する。既存本番migrationを自動適用しない。
3. 架空の管理者とスタッフをローカルGoTrueに作成。管理者の正式Authセッションを登録済み端末としてテスト用にbootstrapする。
4. 管理者が対象スタッフにQR招待を発行。スタッフの申請に対し、**承認前のclaimは拒否**されることを確認。
5. 間違った6桁コードは拒否され、試行回数が記録されることを確認。正しいコードで管理者が承認。
6. 承認済みの元ブラウザ秘密情報でclaim成功。別ブラウザの秘密情報、期限切れ、二重claimは拒否。
7. 公式GoTrue `generateLink` → `verifyOtp` → `getUser` により、架空スタッフの正式Authセッションを取得。独自JWTを作らない。
8. `finalize_approved_device_enrollment` で本人ID、実在する `auth.sessions.id`、承認済みQR申請、元ブラウザ秘密情報を照合。偽セッション・別人・二重登録は拒否。
9. RLSで登録端末のアクセス許可、未登録端末の拒否を確認。旧端末の無効化後はJWTが有効でもRLSで拒否されることを確認。
10. 同時claim・同時finalize・最後の管理者端末の保護、監査ログを検証。テスト終了時はローカル環境を削除。

## 事前レビューで確認する設計上の注意
- `claim_approved_face_to_face_auth` は認証情報の発行前に一度限りで消費する。発行失敗時は新しいQRが必要となるため、スタッフ向けの再申請案内が必要。
- `finalize_approved_device_enrollment` のDB内チェックに加え、Edge側で `auth.getUser(access_token)` と署名検証済みJWTの `session_id` を照合すること。クライアント申告のUUIDだけを信用しない。
- 端末無効化はAuthトークン自体の削除ではない。保護対象の全RLS/RPCが承認端末判定を通る必要がある。
- `auth.sessions` の実行環境による差異、SQLの依存順、service_role判定を検証する。
- 6桁確認コードの総当たり対策と監査、匿名APIのレート制限、QR有効期限、ログの秘密情報漏えいを確認する。
- 本番のバックアップ/ロールバックは取得済みと推測せず、別途レビューする。

## 完了条件
GitHub Actionsで全工程が成功し、失敗ケースも期待通り拒否されること。実機Safari/Chromeおよび本番Supabaseへの適用は別の承認ゲートとする。**この計画書の追加だけではテスト成功としない。**
