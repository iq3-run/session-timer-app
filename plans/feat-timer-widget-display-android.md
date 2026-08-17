# Feat: タイマーウィジェット（Android・表示専用版）

Issue: #63（親: #1）のうち「表示専用版」のみ。操作可能版（開始／+30秒／+1分／リセットボタン）は
本PRの完了後に新規issueを切って別PRで対応する（#63本文が要求する2種類のうち1つ目）。

## Scope（ユーザーと合意済み）

- 新規 `TimerWidgetProvider`（1×2セル、既存4ウィジェットと同じ最小サイズ）を追加。
  `TimerController` の残り時間をカウントダウン表示する。タップでアプリを開く（既存3表示専用ウィジェット
  と同じ、操作ボタンは持たない）。
- 「タイマー進行に合わせた背景の点滅」は、本体アプリの `FlashOverlay`（3秒間で6回明滅するストロー
  ブ）をネイティブで忠実に再現するのではなく、**単発の背景色反転**で近似する：タイマーの残り
  5/3/1/0分（`lib/features/flash/flash_event.dart` の `timerFlashPointsMinutes` + 完了瞬間と同じ4
  ポイント）それぞれについて、その瞬間で終わる3秒間（`flashAnimationDuration` と同じ長さ）だけ
  ウィジェット全体を琥珀色一色に切り替える（本体の `FlashOverlay` が全画面を不透明な琥珀色で覆うのと
  同じ見た目のメタファーを踏襲し、明滅はさせない）。
- 既にタイマーが動いている状態でウィジェットを追加した場合、追加後に迎える将来のポイントのみ発火
  する（過去に過ぎたポイントは発火しない — spec 3-1節の既存方針と同じ）。

## Out of scope

- 操作可能版（開始／+30秒／+1分／リセットボタン）。別issue・別PRで対応。
- iOS対応（既存の `feat-home-widget-android.md` から継続する既知のOut of scope）。
- ブート後の点滅アラームの引き継ぎ。`notification_service.dart` が exact alarm 通知について
  「ブートレシーバーは置かず、アプリ起動のたびに全予約を作り直す」という既存方針（既知のギャップとして
  受容済み）を、このウィジェット独自の点滅アラームにも同様に適用する。端末再起動後、アプリを開く（また
  はウィジェットの30分ごとの定期更新）まで、再起動前に予約していた点滅は発火しない。

## 技術方針

### なぜ単発の背景色反転にしたか

`AppWidgetProvider`（`RemoteViews`）は連続アニメーションをネイティブでサポートしない。本体と同じ
3秒6回のストローブを再現するには、数百ms間隔で `AlarmManager` を多数起動する必要があり、バッテリー
負荷・OS側のバッチ処理（Doze等）による正確なタイミングの不保証の両面でリスクが高い。ユーザーと協議の
上、既存の exact alarm 通知基盤（#39, `SCHEDULE_EXACT_ALARM` 権限は宣言済み）を流用した「ポイントごと
に1回、開始・終了の2回だけアラームを起動して背景色を切り替える」方式を採用する。

### 時刻計算：NTPオフセットの扱い

`TimerState.targetEpochMs` はアプリ内で `DateTime.now()`（端末生時刻、NTP未補正）を起点に計算・永続
化される一方、`HomeWidgetTimeMath`（他3ウィジェット共通）は表示用の「補正後now」を
`System.currentTimeMillis() + ntpOffsetMs` として扱う——これは既存3ウィジェットが既に踏襲している変換
であり、本ウィジェットもそれに合わせる。

`AlarmManager.RTC_WAKEUP` のトリガー時刻は端末の生時刻（`System.currentTimeMillis()` 基準）である必要
があるため、「補正後の瞬間」`instant`（`targetEpochMs - minutesBefore*60000`）を端末生時刻に変換するに
は `instant - ntpOffsetMs` を使う（`correctedNow = deviceNow + ntpOffsetMs` の逆算）。

### 新規ファイル（Android native）

- `TimerWidgetProvider.kt`: `HomeWidgetProvider`。`onUpdate` で `TimerWidgetSync.apply(...)` を呼ぶ。
  `onDisabled`（最後の1個が削除された時）で `TimerWidgetFlashScheduler.cancelAll` を呼び、アラームを
  リークさせない。
- `TimerWidgetSync.kt`: `widgetData` から `targetEpochMs`/`ntpOffsetMs` を読み、
  - 現在時刻がどれかのフラッシュウィンドウ内かを判定し、`RemoteViews` を構築（フラッシュ中は
    ラベル/カウントダウンを隠して背景を琥珀色に、それ以外は通常表示）
  - `TimerWidgetFlashScheduler.reschedule(...)` を呼んで次回以降のアラームを再設定
  （他3ウィジェットが使う `HomeWidgetChronometerPanel` は共有しない——`StopwatchWidgetProvider` が
  「ボタンを持つので共有パネルの前提が崩れる」という理由で独立しているのと同じ理由で、こちらは
  「フラッシュ状態を持つので」独立させる）
- `TimerWidgetFlashPoints.kt`: `MINUTES_BEFORE`（`[5, 3, 1, 0]`。Dart側 `timerFlashPointsMinutes` +
  完了瞬間0分とミラー）と `FLASH_WINDOW_MS`（3000L。`flashAnimationDuration` とミラー）を持ち、
  `targetEpochMs`/`ntpOffsetMs`/現在時刻から「今フラッシュ中か」を判定する純関数を提供。
- `TimerWidgetFlashScheduler.kt`: `TimerWidgetFlashPoints` の各ウィンドウについて、開始・終了それぞれ
  `AlarmManager.setExactAndAllowWhileIdle`（Android 12+で許可されていなければ `setAndAllowWhileIdle`
  にフォールバック — `notification_service.dart` の `_scheduleMode()` と同じ判定方針）で
  `TimerWidgetFlashReceiver` 宛のブロードキャストを予約する。`reschedule` は毎回全予約をキャンセルして
  作り直す（`NotificationService.rescheduleAll` の cancel-and-rebuild と同じ方針）。
- `TimerWidgetFlashReceiver.kt`: アラーム発火時に `TimerWidgetProvider` の現在の `appWidgetIds` を
  引き直し、`HomeWidgetPlugin.getData(context)` で `widgetData` を取得して `TimerWidgetSync.apply` を
  再実行するだけの薄いレシーバー（`exported=false`）。

### レイアウト・リソース

- `timer_widget_layout.xml`: 既存 `completion_countdown_widget_layout.xml` を踏襲（`widget_container`
  / `chronometer` / `placeholder`）。ラベル `TextView` にも `R.id.label` を付与し、フラッシュ中は
  `GONE` にできるようにする。
- `home_widget_background_flash.xml`（新規drawable）: 既存 `home_widget_background.xml` と同じ形状で
  塗り色のみ `@color/home_widget_amber` に変更。
- `timer_widget_info.xml`: 既存3表示専用ウィジェットと同じ `110dp × 90dp`（1×2セル相当）。
- `strings.xml`: `home_widget_label_timer`（ウィジェット内ラベル）、`widget_picker_label_timer`・
  `widget_picker_description_timer`（ウィジェットピッカー用）。
- `HomeWidgetKeys.kt` に `TIMER_TARGET_EPOCH_MS` を追加。
- `AndroidManifest.xml` に `TimerWidgetProvider`（`exported=true`、ピッカー用`label`）と
  `TimerWidgetFlashReceiver`（`exported=false`）の `<receiver>` を追加。

### Dart側

- `lib/features/home_widget/home_widget_sync_service.dart`: `syncTimer(TimerState?, int ntpOffsetMs)`
  を追加。`timerTargetEpochMsKey`/`timerWidgetAndroidName` は他3種と同じ命名規則。
- `lib/features/home_widget/home_widget_scheduler.dart`: `timerControllerProvider` の変更を購読して
  `_syncTimer` を呼ぶ（既存の stopwatch/next-target/completion と同じ形）。`_syncAll` にも追加し、
  起動時・NTPオフセット再同期時にも他3種と一緒に送る。

## テスト

- `test/features/home_widget/home_widget_sync_service_test.dart`: `syncTimer` のグループを追加
  （targetEpochMsのstring化・null送信・updateWidget呼び出しを既存3グループと同じ形で検証）。
- `test/features/home_widget/home_widget_scheduler_test.dart`: 既存の resume 系テストに影響しないこと
  を確認しつつ、`timerControllerProvider` の状態変化で `syncTimer` 相当の呼び出しが発生することを
  検証するテストを追加（既存の stopwatch/next-target/completion 用テストがあれば同じ形に合わせる。
  なければ新規追加）。
- Android nativeコード（Kotlin）はこのリポジトリに既存のユニットテストがなく、本PRでも追加しない
  （既存3ウィジェット・ストップウォッチウィジェットも同様）。BlueStacks実機で目視確認する
  （Android 9/API 28のため `targetCellWidth`/`targetCellHeight` のランチャー挙動自体は検証できない
  — 既知の制約、`project_home-widget-android-followups.md` 参照）。

## ドキュメント

- `README.md`: ウィジェット一覧を4種→5種に更新し、`TimerWidgetProvider.kt` の行を追加。
