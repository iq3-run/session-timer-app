# 実装計画: 指定時刻にタイトルを付けられる

Issue: #79

## 対象

- 指定時刻の追加・編集時に、任意のタイトルを入力できるようにする
- タイトルが設定されている場合、一覧表示は「(タイトル) H:mm」、通知・フラッシュのラベルは
  「(タイトル)になりました」「(タイトル)まで残り○分」に変わる。未設定の場合は従来通り
  「指定時刻 H:mm」「指定時刻になりました」「残り○分」のまま
- 指定時刻の通知・フラッシュを、従来の「ちょうどその瞬間だけ」から「15/10/5/3/2/1分前 +
  ちょうど」の事前通知付きに拡張する（画面フラッシュも同じタイミングで連動して光る）

## 実装しないこと

- Issue #78（1日のセッションの流れの事前登録）は別スコープ。今回は指定時刻1件ごとの
  タイトル付けのみ
- 事前通知の分数リストをユーザーがカスタマイズする機能（完了時刻のflashPointsのような
  設定画面）は追加しない。固定の[15, 10, 5, 3, 2, 1]分前とする
- home_widget（ホーム画面ウィジェット）へのタイトル反映は対象外。現状epochMsのみ参照して
  おり、影響を受けないため変更不要

## データモデル

- `TimeTarget`（`lib/features/targets/time_target.dart`）に`title`（`String?`）を追加
  - `tryFromJson`: `title`キーが存在し文字列型でない場合は不正としてnull扱い（従来同様
    1件だけ捨てて残りは救う）
  - `toJson`: titleがnullでない場合のみキーを含める（後方互換: 既存の保存データに
    titleがなくても読み込める）
  - `copyWith({int? epochMs, String? title, bool clearTitle = false})`: `clearTitle`で
    タイトルを明示的に消せるようにする（`title`をnullで渡しただけでは「変更なし」として
    扱われる既存の`epochMs`と同じ設計）

## コントローラ（`lib/features/targets/time_targets_controller.dart`）

- `addTarget(DateTime time, {String? title})`
- `updateTarget(String id, DateTime time, {String? title, bool clearTitle = false})`

## UI（`lib/features/targets/time_targets_section.dart`）

- 時刻ピッカーの後にタイトル入力ダイアログ（`TextField`、空欄可）を表示。追加時は空欄
  初期値、編集時は既存タイトルを初期値にする
- 一覧の各行はタイトルがあれば「(タイトル) H:mm」、なければ従来通り「指定時刻 H:mm」

## フラッシュ・通知（`lib/features/flash/flash_event.dart`）

- `targetFlashPointsMinutes = [15, 10, 5, 3, 2, 1]`を新設（`timerFlashPointsMinutes`と
  同じ形）
- `targetFlashEvents`を`_exactPlusMinutesBefore`ベースに書き換え、`exactLabel`/`labelFor`
  をタイトル有無で出し分ける
  - タイトルあり: 完了時「(タイトル)になりました」、事前「(タイトル)まで残り○分」
  - タイトルなし: 従来通り「指定時刻になりました」「残り○分」
- id形式が`target:{id}:{epochMs}`から`target:{id}:{epochMs}:{0|分}`に変わる
  （`_exactPlusMinutesBefore`の既存パターンに合わせる）

## 影響範囲の確認

- `notification_event_source.dart`・`flash_queue_controller.dart`は`targetFlashEvents`を
  そのまま呼んでいるだけなので変更不要（新しいイベント群が自動的に候補に乗る）
- 画面フラッシュと端末通知は同じ`targetFlashEvents`を共用しているため、事前通知の追加は
  両方に自動的に反映される（ユーザーとの合意事項）

## テスト

- `test/features/targets/time_target_test.dart`（新規）: title込み/なしの
  toJson・tryFromJson・copyWithのclearTitle
- `test/features/targets/time_targets_controller_test.dart`: addTarget/updateTargetの
  titleパラメータ
- `test/features/flash/flash_event_test.dart`: targetFlashEventsが15/10/5/3/2/1分前+
  ちょうどを返すこと、タイトル有無でラベルが変わること
- `test/features/flash/flash_queue_controller_test.dart`: 既存のtarget絡みテストのid形式
  （末尾`:0`）・firedIds空判定を新しい候補数に合わせて更新

## ドキュメント

- `docs/session-timer-spec.md`の指定時刻の記述（2節）を更新し、タイトル入力と事前通知の
  追加を反映する

## 動作確認方法

`dart format` / `flutter analyze` / `flutter test`（＋デバッグビルド）
