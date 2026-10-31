# 実スキーマ契約との比較結果

資料: VER6-LIVE-SCHEMA-CONTRACT-20261029.md。資料の要約を比較し、本番へ接続・SQL適用・データ取得はしていません。

## 一致と修正

- profilesのuser_id/display_name/role/active、発注登録の列名、受領表示の列名は要約と一致。
- add_receipt / change_receipt / cancel_receiptのRPC名・p_引数名は一致。addのuuid戻り値・他のvoid戻り値とも画面のエラー判定と矛盾しません。
- 発注修正の数量上限が漏れていたため、1～100000000の安全な整数、かつ受領合計以上に制限しました。
- 発注修正・論理取消は、更新後idをselectしてsingleで1行取得を要求します。RLS等で更新0件の場合もエラーとし、誤った成功表示を防ぎます。実PostgREST動作は未検証、PGRST116相当の模擬エラーで回帰確認しました。
- quantity下限・上限、受領quantity>0を使い捨てPostgreSQLのCHECKとトリガーで検証する5項目を追加しました。

## テストと範囲

Node動作テスト15件成功・0失敗、静的チェック成功。PostgreSQL境界5項目と既存競合6シナリオはGitHub Actionsの使い捨てPostgreSQL17で実行します。結果は当該コミットのActionsを参照してください。既存の模擬ブラウザー共有試験も維持します。

コードコミット `a17d6c0` の実行結果: PostgreSQLは[PR側40859881685](https://github.com/oumeclinicalengineering-ai/akaden-management/actions/runs/40859881685)・[push側40859875438](https://github.com/oumeclinicalengineering-ai/akaden-management/actions/runs/40859875438)とも成功。静的・Node動作テストも[PR側40859881870](https://github.com/oumeclinicalengineering-ai/akaden-management/actions/runs/40859881870)・[push側40859875478](https://github.com/oumeclinicalengineering-ai/akaden-management/actions/runs/40859875478)とも成功。模擬2ブラウザー共有試験はローカルで成功しました。

## 未解決・不足情報

要約は完全スキーマではないためreference_no UNIQUE、version、person非空、監査列などを含む本番全体を再現済みとはしません。既存合成SQLの監査は操作種別のみで、actor_id/before_data/after_dataは未検証です。

必要なのは、列型・NULL/DEFAULT・外部キーとCHECK全文、ビュー定義、トリガー全文、RPC/ヘルパーの関数全文・所有者・search_path・GRANT、RLSポリシー全文・適用ロール・USING/WITH CHECK・FORCE RLS、スキーマとテーブル/列/シーケンスの権限、関連Authトリガーです。Auth設定とローカル再現時の差異も必要です。実行データ・ユーザー一覧・秘密鍵は不要です。

完全なRLS定義は推測で補完しません。実Authログイン、スタッフ/管理者/無効ユーザーの認可、実RPCの同時操作は未検証のままです。
本番に受領総数ガードが未適用という資料の問題は残ります。今回の修正で本番の競合問題が解消したとは判断できません。
