# RLS・GRANT監査サマリーとの比較

参照: VER6-RLS-GRANT-LIVE-AUDIT-20261029.md、既存スキーマ契約、PR #3のローカル試験資料。
本番への接続・権限変更・データ取得は行っていません。

## 整合性

|画面操作|資料の権限|結論|
|---|---|---|
|orders一覧/登録|authenticated SELECT/INSERT、有効利用者・created_by条件|送信列は一致、実RLSは未検証|
|orders修正/論理取消|UPDATEと作成者/管理者条件|画面は全行に操作を表示するがDB判定に従う。0件更新はsingleでエラー表示|
|receipts一覧|SELECT、有効利用者条件|整合|
|受領追加/修正/取消|直接DML不可、3RPCはauthenticated EXECUTE可|画面はRPC経由なので整合。本人/管理者判定の実行は未検証|
|profiles取得|本人または管理者SELECT|自分のuser_idを指定しており整合。無効ユーザーは画面のactiveでも拒否するが実RLS再現とは別|
|audit_logs|管理者SELECT|現画面は監査ログを取得しない|

資料上、必要なGRANTが欠けているという証拠はありません。一方、正確なポリシー式と対象ロールが未確認のためアクセス成功は保証しません。

## 過剰・不足・未検証

- 過剰候補: authenticatedのorders/profiles/audit_logsへのDELETE等、anonのSELECT、ヘルパー/トリガー関数のanon EXECUTE。GRANTの存在だけで行情報漏えいとは断定しません。
- TRUNCATE等はRLSで制限できないため、正確な実効権限・付与元を別途確認する必要があります。今回の資料は最新TRUNCATE実効値の完全一覧ではありません。
- 本番ordersの数量ガードが欠けている点は引き続き運用ブロッカーです。ローカルDRAFT試験の成功で本番修正済みとは扱いません。
- 不足定義: 全ポリシーの最新USING/WITH CHECK・対象ロール、PUBLIC/継承を含むGRANT付与元、関数全文/所有者、Auth関連トリガー、関連ビュー。既存の不足一覧を解消する完全定義は今回の要約にもありません。

## 追加したローカル試験

既存の使い捨てPostgreSQL17 fixtureに対し、SET ROLE authenticatedで数量ガードの拒否・境界値成功・受領直接更新拒否、SET ROLE anonで発注更新拒否を確認する4項目を追加しました。トランザクションをロールバックするため既存の競合試験データに影響しません。

これはDRAFT fixtureのテーブルGRANTとトリガーの検証です。本番でanon SELECTが許可される状態や全GRANTを再現していません。fixtureのis_admin/is_active_userは常にtrueなので、スタッフ・管理者・無効ユーザーを作っても正しい権限試験にはなりません。推測ポリシーを追加せず、これら3区分の実認証/RLS試験は未実施とします。

Node動作テスト18件、静的・模擬共有試験、既存SQL契約/競合試験を維持します。追加4項目はGitHub Actionsの使い捨てDBで実行します。失敗があれば結果を確認して修正します。

コードコミット `7a07bbe` の結果: Node18件成功・0失敗、静的チェック・ローカル模擬共有試験成功。PostgreSQLの追加4項目・既存数量境界5項目・競合6シナリオ・既存SQL検査は[PR側CI](https://github.com/oumeclinicalengineering-ai/akaden-management/actions/runs/40861269182)と[push側CI](https://github.com/oumeclinicalengineering-ai/akaden-management/actions/runs/40861260541)で成功。Node/静的CIもPR側40861269178・push側40861260455で成功。最終実行に失敗はありません。実認証3区分の検証は未実施です。

## 次の作業

レビュー済み完全定義が揃えば、PR #3のローカルAuth起動・秘密ログ抑制・削除を再利用し、実JWTでスタッフ/管理者/無効利用者と業務RPCを確認します。それまでは本番への接続・SQL適用やローカル権限の推測再現をしません。PR #4はDraftを維持します。
