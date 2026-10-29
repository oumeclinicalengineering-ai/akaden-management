# 追加費用なしの検証環境（GitHub Actions）

既存のGitHubリポジトリは**public**です。GitHubの公式料金案内では、公開リポジトリの標準GitHubホストランナー（`ubuntu-latest`）は無料です。

このWorkflowはGitHub Actions内で一時的なPostgreSQL 17コンテナを起動します。毎回空のDBを用意し、架空の注文・受領データだけを使って、ドラフトSQLの動作を確認します。

- **Supabaseの開発ブランチや新プロジェクトは作りません。**
- **既存のSupabaseへのネットワーク接続や秘密情報は使用しません。**
- ワークフロー完了後は一時コンテナが破棄されます。
- テストはDB権限維持、数量不整合の拒否、受領済数量ちょうどへの更新、監査トリガーの動作、プロフィール作成トリガーの動作を検証します。

**検証範囲の限界:** Supabase Auth、実際のRLS・RPC、同時操作、端末QR登録・端末失効の実機試験まで網羅するものではありません。PostgreSQLの簡易モデルです。GitHub Actionsの無料条件はリポジトリ公開・標準ランナーであることが前提。リポジトリを非公開に変更したり大型ランナーを選択した場合は料金条件が変わります。

GitHub公式資料：
- https://docs.github.com/en/billing/concepts/product-billing/github-actions
- https://docs.github.com/en/actions/tutorials/use-containerized-services/create-postgresql-service-containers

**運用上の注意：** 公開リポジトリで実データや鍵をテストに使用しないでください。
