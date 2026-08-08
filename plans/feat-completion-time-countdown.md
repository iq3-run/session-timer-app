# 実装計画: 現在時刻表示・完了時刻カウントダウン・永続化

Issue: #4（親: #1）

## 対象

- 現在時刻表示（HH:MM:SS）
- 完了時刻カウントダウン（タップで直接ネイティブ時刻ピッカーを開く、✕で解除）
- 完了時刻の永続化（spec 3-7節）: epochミリ秒で保存、再起動後もカウントダウン中の状態で復帰、既に超過していた場合は未設定に戻す

## 実装しないこと

- **発火済みフラッシュの記録の永続化**: issue本文では本Issueで型を用意する想定だったが、フラッシュ機能自体（発火条件・キューイング）がまだ存在しないため、未使用のフィールドを先行して持たせるのはYAGNIに反すると判断し、フラッシュ機能のIssue（タイマー/フラッシュ実装時）でまとめて追加する
- 指定時刻リスト、ストップウォッチ、タイマー、フラッシュ演出、設定シート（いずれも別Issue）
- NTP時刻同期（端末時刻をそのまま使用。NTP補正は別Issueで`nowProvider`に差し込む）

## 状態管理・永続化の設計

- `sharedPreferencesProvider`（`FutureProvider<SharedPreferences>`）: `SharedPreferences.getInstance()`をラップ。他のproviderはこれに依存する
- `nowProvider`（`StreamProvider<DateTime>`）: 1秒ごとにティックする時計。現在時刻表示・カウントダウン計算の両方が購読する
- `completionTimeControllerProvider`（`AsyncNotifierProvider<CompletionTimeController, CompletionTimeState>`）:
  - 初期化時に`SharedPreferences`から`completion_time_epoch_ms`を読み込み、現在時刻を過ぎていれば`null`（未設定）にリセットして保存し直す
  - `setTarget(DateTime)` / `clear()`で状態更新と同時に永続化
  - 保存値は絶対時刻（epochミリ秒）。日付またぎやタイムゾーンの影響を受けない

## UI

- `lib/features/clock/current_time_display.dart`: 現在時刻のみを表示する小さいwidget（`nowProvider`購読）
- `lib/features/completion/completion_countdown_section.dart`: 完了時刻ブロック（カウントダウン表示 + タップで`showTimePicker`を直接開く + ✕クリアボタン）
- `lib/features/clock/clock_screen.dart`: 上記2つを縦に並べるホーム画面に置き換え（プレースホルダーの"SESSION TIMER"テキストを削除）

ネイティブの時刻ピッカーは、Flutter標準の`showTimePicker`（Material）を用いる。タップした瞬間にダイアログを介さず直接ピッカーが開く点はプロトタイプの挙動と同じ（中間の確認ダイアログを挟まない)。

## テスト

- `test/features/completion/completion_time_controller_test.dart`: `SharedPreferences.setMockInitialValues`を使い、(a) 未設定からの`setTarget`→永続化、(b) 保存済みの未来時刻からの復元、(c) 保存済みの過去時刻（超過済み）からの起動時リセット、を検証
- `test/widget_test.dart`: `SharedPreferences.setMockInitialValues`でモックし、アプリがクラッシュせず現在時刻表示・完了カウントダウン表示が現れることを確認

## 動作確認方法

`flutter analyze` / `dart format --set-exit-if-changed` / `flutter test` / `flutter build apk --debug`
