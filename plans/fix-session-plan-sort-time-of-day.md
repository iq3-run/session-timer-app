# 実装計画: セッションの流れのソートを時刻（時分）のみにする

Issue: #92（親: #1）

## 対象

`SessionPlanController._sorted`が`startEpochMs`（日付込みの絶対時刻）で昇順ソートしている
ため、日付を跨いで登録したセッション同士では「日付→時刻」の順になり、直感に反する表示
（例:「19:00, 9:00, 13:30, 17:30」）になる。日付を無視して時刻（時分）のみでソートする。

## 実装

### `lib/features/session_plan/session_plan_controller.dart`

- `_sorted`の比較キーを`startEpochMs`から、`startTime`の時分（`hour * 60 + minute`）に変更する
- 絶対時刻（epoch）での比較が必要な箇所（`current_session_resolution.dart`の
  `resolveCurrentSession`）は、渡された`sessions`リストの並び順に依存せず自前で
  `endTime`/`startEpochMs`から再計算しているため、この変更の影響を受けない

## 実装しないこと

- `resolveCurrentSession`（「現在のセッションを設定」の自動選択ロジック）の変更（絶対時刻
  判定のままで正しく動作するため対象外）
- データモデル自体の変更（`SessionPlanEntry`は引き続き絶対epochで保存する。表示順のみの
  変更）

## テスト

- `test/features/session_plan/session_plan_controller_test.dart`: 日付を跨ぐ2件
  （例: 今日19:00・明日9:00）を登録した場合に、時刻順（9:00→19:00）で並ぶことを確認する
  回帰テストを追加する（現状は日付順で19:00が先に来てしまうことを再現できる形で書く）

## 動作確認方法

`dart format` / `flutter analyze` / `flutter test`
