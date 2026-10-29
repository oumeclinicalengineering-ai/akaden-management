# 赤伝 Ver.6｜匿名QR登録APIの不正利用対策・リリース前レビュー

作成日: 2026-10-29  
**開発ブランチのみ。現在のVer.5/Ver.6、接続中のSupabase本番DB/Auth/Edge Functionsは変更していません。**

## 今回開発・検証したもの

### 1. PostgreSQLによる持続的な回数制限
- SQLドラフト: `supabase/migrations/20261029_qr_abuse_rate_budgets_DRAFT.sql`
- DB関数: `public.consume_qr_enrollment_rate_budget(action,reference)`
- `service_role` 限定の実行権限。`anon` および `authenticated` からの直接呼び出しを禁止。
- `app_private.qr_enrollment_rate_budgets` に、同時実行しても限界値を超えて許可しない原子的な回数計測を実装。
- 原文のQR秘密情報はDBに保存せず、QRはSHA-256ハッシュで照合する。
- 無効なQRや存在しない申請IDごとに無制限のDB行を作成しない。

| 対象 | 1回の制限 | 集計期間 |
|---|---:|---|
| 匿名のQR申請（全体） | 最大120回 | 1分 |
| 承認後のログイン情報引換え（全体） | 最大90回 | 1分 |
| 同じQRへの申請試行 | 最大3回 | 10分 |
| 同じ承認申請IDへの引換え試行 | 最大6回 | 10分 |

値は**安全性と使いやすさの検証用の暫定設定**です。実運用時はスタッフ人数・施設の同時登録数・想定トラフィックに合わせて見直すこと。

### 2. 匿名Edge Functionへの実装
- 実装: `supabase/functions/ver6-face-to-face-enrollment/index.ts`
- QR申請/認証引換えの前に、必ずサーバーからDBの回数制限関数を呼ぶ。
- DBへの問い合わせが失敗した場合は**fail-closed**（503で停止）。
- 制限超過時は**429**と `Retry-After: 60` を返し、Supabase Authの資格情報発行処理を行わない。
- HTTPSの許可済みOriginのみ受け入れ、HTTPS以外のオリジンを拒否。
- 必要な2つのフラグ（`QR_ENROLLMENT_ENABLED` と `QR_FACE_TO_FACE_ENABLED`）が明示的に `true` でなければ動作しない。
- `service_role` 鍵はEdge Function内のサーバー環境変数にのみ配置し、静的HTML・公開GitHubに置かない。
- 認証に使える `hashed_token` は管理者対面承認・端末固有秘密照合・期限内・未利用がすべて成立した場合にのみ発行。ログやブラウザのURLに書き込まない。

### 3. 無料テスト
- `tests/postgres/qr_rate_budget_assertions.sql`：回数制限、時間経過後のリセット、存在しないIDのDB行増殖防止、直接呼出し権限の制限。
- `tests/edge/face_to_face_api_test.ts`：**実際のEdge HTTP処理関数**を呼び出し、Supabaseへの接続部分だけを模擬。認証前拒否、Origin不一致、POST以外の拒否、過剰アクセス429、DB障害時503、正式Authリンク生成の呼出し、承認前/再利用の拒否を確認。
- GitHub Actions：公開リポジトリの標準ランナー+使い捨てPostgreSQL/ Deno。
- **実Supabase Authでの `generateLink` → `verifyOtp` → セッション発行は未実施。模擬Authの成功と区別すること。**

## 接続済みSupabaseのSecurity Advisorの読み取り専用結果

2026-10-29時点で、現在の既存DBに以下の警告あり。**今回、新たに作ったものではなく、現在のプロジェクトに存在する警告**。

- 匿名ロール `anon` から実行可能な `SECURITY DEFINER` 関数：4件（`create_profile_for_user`、`record_audit`、`is_active_user`、`is_admin`）。
- 認証済みロールから実行可能な `SECURITY DEFINER` 関数：7件。そのうち `add_receipt`、`change_receipt`、`cancel_receipt` は業務に必要なRPCであるため、単純に `EXECUTE` を削除すると画面機能を壊す。**本体内で管理権限・対象伝票の所有権・端末承認を適切に検証しているかを個別に監査する必要がある。**
- Supabase Authの漏えいパスワード検出機能は無効（有効化の可否やプラン条件を確認し、別途承認の上で対応）。

匿名ロールの不要な実行権限と、トリガー専用関数の実行権限を厳しくするドラフトは `supabase/migrations/20261029_order_quantity_guard_DRAFT.sql` に存在し、無料SQL模擬テストで検証済み。**現在のSupabase DBには適用していない**。

セキュリティ警告の公式解説：
- https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable
- https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable
- https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection

## 重要な未解決事項（本番公開禁止）

1. **匿名APIは依然として外部から到達できる設計**。Originヘッダーは偽装可能で、それ自体は認証ではない。今回のDB回数制限は小規模な繰返し操作を抑えるもので、攻撃者が全体の回数枠を消費してスタッフ登録を妨害するDoSは防げない。公開前にSupabaseのネットワークレベルの保護、ボット対策、必要に応じたCAPTCHA/追加の認証を検討すること。
2. **自動掃除は未実装**。回数制限の対象QR/申請IDの履歴は増える。保存期間・運用監査を決めた上で、古いカウンタを定期的に削除する仕組みを設ける。
3. **認証生成は未実機検証**。公式 `auth.admin.generateLink` によるリンク作成はメール送信を行わないが、実際の既存Authスタッフ/メール確認済み状態/レート制限や `verifyOtp` との互換性をテスト専用環境で確認する必要がある。
4. **QRだけでログインさせない**。対面での本人確認・対象スタッフ名・確認番号の照合を必要とし、端末固有の256-bit秘密と有効期限もサーバーで判定する。
5. **管理者の初回承認、全RLS/RPC監査、バックアップ・ロールバック、旧Authセッション失効、端末紛失復旧の実機検証**が完了していない。
6. **無料GitHub ActionsとSupabaseのFree運用コストは別**。実際にEdge Functionを配備・呼び出すとSupabaseの利用枠に計上される。実配備前に無料枠・メール以外のAuth制限を確認する必要がある。

## 現在の結論

**GitHub開発ブランチのSQLと匿名Edge Function、Deno/ブラウザー模擬試験は改善済み。PR #3はDraftで本番未統合。現行サービス・データ・認証設定には変更なし。**

次の工程は、別の認証テスト環境で公式Supabase Authのログイン連携を実測し、全RLS/RPC経路を攻撃者視点で監査すること。利用者の費用承認や本番運用承認なしに、Supabaseの追加環境・有料ブランチ・本番設定変更をしない。
