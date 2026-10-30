# Ver.6 ローカル実Authライフサイクル試験

## 方法

PR #3の `.github/workflows/real-gotrue-local-test.yml` を参考に、CLI 2.122.0を固定し、GitHub Actionsの一時ディレクトリとDockerだけにSupabaseを起動します。遠隔プロジェクトへのlinkやSQL適用は行いません。不要なサービスとQR工程を除外し、finally/alwaysで架空ユーザーとローカルスタックを削除します。作業対象はPR #4のみです。

`scripts/test-ver6-local-auth.mjs` はNode標準fetchを使用し、実GoTrueのHTTP APIを呼びます。接続先は `http://127.0.0.1:54321` の完全一致を要求し、リダイレクトは拒否します。キーはローカルCLIの出力だけから取得し、CIログでマスクします。本番キーは使用しません。

架空の確認済みユーザー2名をローカル管理APIで作成し、各人についてパスワードログイン、保存セッションのaccess tokenによるgetUser、refresh tokenによる復元、ログアウト、ログアウト後のrefresh拒否を検査します。2名のIDが異なることも検査する計11項目です。セッションの保存/復元はメモリー内のJSONで、ブラウザーやsupabase-jsの自動復元ではありません。トークンはファイル・ログに出しません。

ログアウト後でもaccess tokenが期限まで利用できる可能性を考慮し、「すべてのJWTが即時無効化された」とは判定しません。検査対象はrefreshセッションの失効です。

## 検証結果

コードコミット `ed552b1` の[push側実Auth CI](https://github.com/oumeclinicalengineering-ai/akaden-management/actions/runs/40862246687)と[PR側実Auth CI](https://github.com/oumeclinicalengineering-ai/akaden-management/actions/runs/40862254128)は両方成功しました。架空2ユーザーの11項目を完了し、ユーザー削除とスタック削除を含むジョブが成功しています。ローカル再実行した既存Node動作テスト18件・静的チェック・模擬2ブラウザー共有試験も成功。確認した失敗テストは0件です。

## 不足定義と未検証

業務の完全なRLS式・対象ロール、GRANT付与元、RPC/認可ヘルパー/監査/プロフィール生成の完全定義・所有者、ビュー、列DEFAULTなどは依然不足しています。詳細はVER6-RLS-GRANT-COMPARISON.md、VER6-LOCAL-AUTH-REUSE-PLAN.mdを参照してください。

今回、業務テーブルや推測したRLS/RPCは作成しません。実Auth成功時も、スタッフ/管理者/無効ユーザーの業務認可、受領・発注・同時操作、ブラウザーの自動復元、実機、メール送信、本番設定との一致は未検証です。これまでの合成PostgreSQL試験の範囲と区別します。

## 次の作業

完全な非機密業務定義のレビュー後にのみ、今回のローカルAuthスタックへ定義を適用し、架空2ユーザーの実JWTで業務試験へ進めます。本番への適用・有料リソース作成・main統合は対象外です。
