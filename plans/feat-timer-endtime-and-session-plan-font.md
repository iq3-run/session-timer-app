# 実装計画: タイマー終了時刻の表示とセッションの流れ画面のフォント拡大

Issue: #85, #86（親: #1）

## 対象

- タイマー稼働中（カウントダウン中・超過カウントアップ中いずれも）、ラベルに終了予定時刻を
  追記する: 「タイマー(21:45まで)」「連動タイマー(21:45まで)」。超過中は既存の「（超過）」
  表記の後ろに続ける: 「タイマー（超過）(21:45まで)」
- `SessionPlanScreen`のセッション一覧行・「＋ セッションを追加」行のフォントサイズを拡大する

## 実装

### タイマー終了時刻の表示

- `lib/features/timer/timer_section.dart`の`_TimerBodyState._label`はprivateでウィジェット
  外から直接テストできないため、`resolveTargetTitleEdit`（issue #79）・`resolveCurrentSession`
  （issue #78）と同じ方針で、ラベル文字列を組み立てる純粋関数を
  `lib/features/timer/timer_label.dart`に`timerLabel(TimerState? state, DateTime now)`
  として切り出す
  - `intl`の`DateFormat('H:mm')`（`time_targets_section.dart`・`session_plan_screen.dart`と
    同じフォーマット）で`state.targetTime`を整形し、稼働中のみ末尾に`(H:mmまで)`を追記する
  - 超過中は既存の「（超過）」表記を`modeLabel`の直後・`(H:mmまで)`の直前に挿入する
  - 未設定時は従来通り「タイマー」のみ
- `timer_section.dart`側は`_label`を削除し、`timerLabel(state, now)`を呼び出すだけにする

### セッションの流れ画面のフォント拡大（`lib/features/session_plan/session_plan_screen.dart`）

- `_SessionRow`・`_AddSessionRow`が使っている`SessionTimerTextStyles.label`（12px、他画面では
  大きな数値表示に添える補助キャプション用）を、この画面専用のより大きいスタイルに置き換える
  （18px。色は既存のmutedを維持し、サイズのみ変更）
- 画面固有のスタイルのため、共有の`SessionTimerTextStyles`は変更せず、
  `session_plan_screen.dart`内にプライベート定数として定義する

## 実装しないこと

- `SessionTimerTextStyles.label`自体の変更（他画面の見た目に影響するため対象外）
- AppBarタイトル・ボタン・ダイアログのテキストサイズ変更（Material標準サイズで既に
  `label`より大きく、今回のフィードバックの対象外と判断）

## テスト

- `test/features/timer/timer_label_test.dart`（新規）: 未設定・稼働中（通常/連動）・
  超過中（通常/連動）の各分岐で期待通りの文字列になることを直接ユニットテストする
- 既存の`session_plan_screen.dart`にウィジェットテストが無いため（前例踏襲）、
  フォントサイズ変更は目視確認のみとする

## 動作確認方法

`dart format` / `flutter analyze` / `flutter test` / `flutter build apk --debug`
