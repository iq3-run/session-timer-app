# 実装計画: 1日のセッションの流れを登録できる

Issue: #78（関連: #79、実装済み・マージ済み）

## 対象

- セッション（開始時刻＋所要時間[デフォルト3.5h]または終了時刻）のリストを事前登録・
  編集・削除できる専用画面を追加する
- 「現在のセッションを設定」操作で、登録済みセッションから完了時刻に一番近いものを自動選択し、
  完了時刻・指定時刻（issue #79の指定時刻リストの1エントリ）を自動で切り替える

## 実装しないこと

- セッションごとのタイトル入力（issue #79はTimeTarget向けの機能。セッション自体は
  開始〜終了の時刻表記のみで一覧表示する）
- 日付をまたいだ自動リセット（ユーザーが手動削除するまで保持する — issue本文と異なり
  "1日" という枠を厳密に区切らない設計にした。会話で確認済み）
- リストの並び替えUI（常に開始時刻の昇順で表示・保存する。ドラッグ並び替えは不要）

## データモデル・永続化

- `SessionPlanEntry`（`lib/features/session_plan/session_plan_entry.dart`）:
  `{id: String, startEpochMs: int, endEpochMs: int}`のイミュータブルクラス。
  `TimeTarget`/`SessionEvent`と同じ`tryFromJson`/`toJson`/`copyWith`パターンを踏襲
  （不正な1件だけ捨てて残りは救う）
- `defaultSessionDuration = Duration(hours: 3, minutes: 30)`（3.5h、issue本文のデフォルト値）
- `SessionPlanController`（`lib/features/session_plan/session_plan_controller.dart`、
  `AsyncNotifierProvider<SessionPlanController, List<SessionPlanEntry>>`）:
  - `TimeTargetsController`と同じ「`_mutationQueue`で直列化」「`_lastGood`から構築」設計を踏襲
  - `build()`は起動時の期限切れ除去を**行わない**（会話で確認済み：手動削除まで保持）
  - `addSession(DateTime start, DateTime end)` / `updateSession(id, start, end)` /
    `removeSession(id)`。常に`startEpochMs`昇順でソートして保存
  - 永続化キー: `session_plan_json`（SharedPreferences、JSON文字列）

## 「現在のセッションを設定」の選択ロジック（純粋関数）

`lib/features/session_plan/current_session_resolution.dart`に切り出し、ウィジェットを介さず
直接ユニットテストする（`resolveTargetTitleEdit`と同じ方針）。

```dart
typedef CurrentSessionResolution = ({
  SessionPlanEntry session,
  DateTime completionTarget, // == session.endTime
  DateTime? autoTargetStart, // null なら指定時刻側の自動エントリをクリアする
});

CurrentSessionResolution? resolveCurrentSession(
  List<SessionPlanEntry> sessions,
  DateTime now,
)
```

- `endTime`が`now`より後（＝まだ完了していない）セッションのうち、`endTime`が最も近いものを
  `session`として選ぶ。該当なし（リスト空 or 全セッション完了済み）なら`null`
- `session.startTime`が`now`より後（まだ開始していない）なら`autoTargetStart = session.startTime`
- 開始済みなら、開始時刻順で`session`の次に来るセッションの`startTime`を`autoTargetStart`にする。
  次が無ければ`autoTargetStart = null`

## 既存コントローラとの連携

- `TimeTargetsController`に、固定idで1件を作成/上書きする`upsertTarget(String id, DateTime time, {String? title})`
  を追加する（`addTarget`は毎回`UniqueKey()`でidを生成するため、"常に同じ1件を更新" という
  今回の要件には使えない）
- 自動管理エントリのidは`lib/features/session_plan/session_plan_controller.dart`で
  `const autoSessionTargetId = 'session-plan:auto';`として固定
- `autoTargetStart`が`null`の場合は、既存の`removeTarget(autoSessionTargetId)`をそのまま使って
  クリアする（存在しなければ何もしない、既存のidマッチ削除がそのまま使える）
- タイトルは固定文言「次のセッション開始」を付与し、ユーザーが手動追加した指定時刻と
  見分けられるようにする

## UI

- `lib/features/session_plan/session_plan_entry_button.dart`: `SessionScheduleEntryButton`と
  同じ形の`IconButton`をクロック画面右上に追加し、`SessionPlanScreen`へ遷移する
- `lib/features/session_plan/session_plan_screen.dart`:
  - 登録済みセッション一覧（「H:mm〜H:mm」表記、タップで編集、✕で削除）
  - 「＋ セッションを追加」行：`showTimePicker`で開始時刻→ダイアログで
    「時間で指定（デフォルト3.5時間）」または「終了時刻を指定」を選ばせる
    - 時間で指定: 数値入力ダイアログ（デフォルト値 `3.5`）。分単位に換算して終了時刻を計算
    - 終了時刻を指定: `showTimePicker`をそのまま開く。開始時刻以前が選ばれたら
      `resolveNextOccurrence`と同じ考え方で翌日に繰り上げる
  - 画面上部に「現在のセッションを設定」ボタン：`resolveCurrentSession`を呼び、
    完了時刻コントローラと指定時刻コントローラ（`upsertTarget`/`removeTarget`）を更新する。
    該当セッションが無ければ何もしない（軽いフィードバックとしてSnackBarを出す）

## テスト

- `test/features/session_plan/session_plan_entry_test.dart`（新規）:
  toJson/tryFromJson・不正データの拒否
- `test/features/session_plan/session_plan_controller_test.dart`（新規）:
  追加・更新・削除・並び順、起動時に期限切れを除去し**ない**こと
  （`TimeTargetsController`との違いを明示的にテストする）
- `test/features/session_plan/current_session_resolution_test.dart`（新規）:
  空リスト・全セッション完了済み・未開始セッション選択・開始済み+次あり・開始済み+次なし、
  の各分岐を網羅
- `test/features/targets/time_targets_controller_test.dart`: `upsertTarget`の
  新規作成・既存id上書きの両方

## ドキュメント

- `docs/session-timer-spec.md`に本機能の説明を追加する

## 動作確認方法

`dart format` / `flutter analyze` / `flutter test` / `flutter build apk --debug`
