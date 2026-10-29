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

## 未完了
- QR対面承認RPC、claim RPC、finalize RPCを組み合わせた全工程。
- 本番と同一のRLS、端末失効、管理者復旧、実スマホ操作、セッション維持。
- 本番クラウドAuthとの設定差異、既存スタッフのメール確認済み状態。
- 本番SQL権限修正・バックアップ取得・ロールバック実施。

## 次の作業
CI成功を確認後、本番に触れずに本物のGoTrueとDRAFT版QR承認・端末管理SQLを完全隔離したローカルDBに組み合わせる。本番GRANT/RLSとバックアップ方法は読み取り専用で確認し、院内責任者の明示承認が得られるまで一切適用しない。

参考:
https://supabase.com/docs/reference/javascript/auth-admin-generatelink
https://supabase.com/docs/reference/javascript/auth-verifyotp
https://supabase.com/docs/guides/local-development/cli/getting-started
https://docs.github.com/en/billing/concepts/product-billing/github-actions

## 実GoTrue結合テストからの追加知見（2026-10-29）
- 一時GoTrueが発行した `hashed_token` は**56文字**、旧コードが期待した64文字hexではない。Edge APIと未公開のQR開発画面にのみ、URL-safe opaque token用の構文検証を別途追加した。既存のQR/端末秘密用hex64検証は維持。
- `generateLink` 後の実 `verifyOtp` と `getUser` は、テストのRLS判定に到達するまで正常に動作した。途中結果であり、CI全体成功とはまだ扱わない。
- 匿名側にはテーブルSELECTのGRANTがないため、`42501` 権限エラーは正しい拒否。RLSフィルターで空配列が返る場合と共に明示的に検査し、行が返った場合は必ず失敗させる。
- この修正を含むCIの結果が成功と判定されるまでは、本物のAuth全工程確認済みとは記載しない。
