# Feat: タイマーウィジェット（Android・操作可能版）

Issue: #70（親: #63 → #1）。#63本文が要求する2種類のうち「操作可能版（大サイズ）」。表示専用版
（#69・`TimerWidgetProvider`）はそのまま変更しない。

## Scope（ユーザーと合意済み）

- 新規 `TimerControlWidgetProvider`（Kotlin）を追加。開始／+30秒／+1分／リセットの4ボタンを持ち、
  アプリを開かずにタイマーを操作できる。
- 背景の点滅演出（残り5/3/1/0分の琥珀色フラッシュ）は持たない。点滅は表示専用版（#69）だけの役割
  という、issue #63本文の当初の役割分担をそのまま踏襲する。
- ボタンの挙動（`RemoteViews`はタップしか検出できず長押しを区別できないため、既存の
  `TimerController`のタップ/長押し2挙動のどちらか一方を割り当てる。ユーザーと確定）：
  - **開始**：モード/時間pickerを開けないため、デフォルト設定（通常モード・5分 ==
    `timer_section.dart`の`_defaultSetupDuration`と同じ）で`quickStart(Duration(minutes: 5))`。
  - **+30秒／+1分**：`addTime(amount)`（アプリ内タップ挙動と同じ：動作中なら延長、停止中なら
    ちょうどその分で新規スタート）。
  - **リセット**：`reset()`（アプリ内長押しリセットと同じ、モードは保持）。
- #62で導入済みのボタン→`HomeWidgetBackgroundIntent`→バックグラウンドコールバック→
  コントローラ呼び出しの仕組みをそのまま流用する。`HomeWidgetBackgroundReceiver`は#62で
  `AndroidManifest.xml`に登録済みのため、追加のManifest変更は新規ウィジェットプロバイダの
  `<receiver>`1件のみ。

## 副作用として一緒に直す既存バグ（ユーザーと合意済み・スコープに含める）

`home_widget`の`registerInteractivityCallback`はネイティブ側にコールバックハンドルを1つしか
保持できない（呼ぶたびに前回の登録を上書きする——`home_widget-0.9.3`の実装で確認済み）。このため
本PRで新設するタイマーウィジェットの背景コールバックを、ストップウォッチウィジェット用の既存
コールバックとは別に単純に`registerInteractivityCallback`する、という実装はできない。

これを直す過程で、以下の既存バグ（#69がmainにマージされた時点から存在。#70固有ではない）も
同じ統合ポイントの修正で一緒に直す：

- `StopwatchController.reset()`は連動して`TimerController.reset()`も呼ぶ
  （`stopwatch_controller.dart`のコメント参照）。しかし`stopwatch_widget_callback.dart`の
  `_pushUpdatedStateToWidget`はストップウォッチの状態しかウィジェットストアに書き戻していない
  ため、**ストップウォッチウィジェットのリセットボタンを押すと、タイマーウィジェット（#69）の
  表示がアプリを開くまで古いまま**になっていた。

## 技術方針

### 単一コールバックのディスパッチ

- 新規 `lib/features/home_widget/home_widget_background_callback.dart`：`@pragma('vm:entry-point')`
  を持つ唯一のエントリポイント`homeWidgetBackgroundCallback(Uri? uri)`。`uri.host`
  （`"stopwatch"`/`"timer"`）で`stopwatchWidgetBackgroundCallback`/`timerWidgetBackgroundCallback`
  に振り分けるだけの薄いディスパッチャ。
- `main.dart`の`_registerStopwatchWidgetCallback`を`_registerHomeWidgetBackgroundCallback`に
  改名し、上記ディスパッチャを登録するよう変更する。
- 各ウィジェット別のコールバック関数（`stopwatchWidgetBackgroundCallback`/
  `timerWidgetBackgroundCallback`）自体は`vm:entry-point`のまま維持し、既存テストがそのまま
  直接呼び出せる形を崩さない（実際にプラグインへ登録されるのはディスパッチャの方だけ）。

### 新規: `lib/features/home_widget/timer_widget_callback.dart`

`stopwatch_widget_callback.dart`と同型。`uri.pathSegments.first`（`"start"`/`"add30"`/`"add60"`/
`"reset"`）でタイマーコントローラのメソッドを呼び分ける。

呼び出し後、タイマー状態に加えてストップウォッチ状態も`syncStopwatch`で書き戻す
（`quickStart`・動作中でない状態からの`addTime`はどちらも`_autoStartStopwatchIfNeeded()`経由で
ストップウォッチを起動しうるため、こちらもタイマー側から見た「一緒に直す」対称対応）。

### 修正: `lib/features/home_widget/stopwatch_widget_callback.dart`

`_pushUpdatedStateToWidget`が、既存のストップウォッチ状態の書き戻しに加えて`syncTimer`も呼ぶ
ように変更（上記「一緒に直す既存バグ」参照）。

### 修正: `lib/features/home_widget/home_widget_sync_service.dart`

- `timerControlWidgetAndroidName = 'TimerControlWidgetProvider'`を追加。
- `syncTimer`が`timerWidgetAndroidName`（表示専用版）に加えて`timerControlWidgetAndroidName`
  （本PRの操作可能版）も`updateWidget`する。両方とも同じ`TIMER_TARGET_EPOCH_MS`キーを読むが、
  別々に登録された`AppWidgetProvider`なので個別に`updateWidget(androidName: ...)`が要る。

### 新規ファイル（Android native）

- `TimerControlWidgetProvider.kt`：`HomeWidgetProvider`。`widgetData`から
  `TIMER_TARGET_EPOCH_MS`/`NTP_OFFSET_MS`を読み、カウントダウン表示と4ボタンの
  `PendingIntent`（`homewidget://timer/{start,add30,add60,reset}`）を設定する。
  `TimerWidgetSync`は共有しない（フラッシュ状態機械を持つ理由で独立している
  `TimerWidgetSync`に対し、こちらはボタンを持つ理由で独立——`StopwatchWidgetProvider`が
  `HomeWidgetChronometerPanel`を共有しないのと同じ構図）。カウントダウンのbase計算は
  `TimerWidgetSync`と同じ理由（在アプリ表示が素の`DateTime.now()`基準）で
  `ntpOffsetMs = 0L`のまま`HomeWidgetTimeMath.countDownBase`を呼ぶ。
- `timer_control_widget_layout.xml`：ラベル／Chronometer・placeholder／ボタン2行×2列
  （開始・リセット／+30秒・+1分）。`stopwatch_widget_layout.xml`と同じ理由で縦積み構造
  （Chronometerを weight 付き横並び行に混ぜると実機で意図通り展開されない、既知の制約）。
- `timer_control_widget_info.xml`：ボタン4つ分の面積を確保するため
  `stopwatch_widget_info.xml`（220dp×110dp、4×2セル）より縦に広い初期値
  `220dp×180dp`（4×3セル相当）から開始し、`minResizeWidth`/`minResizeHeight`も同値に固定
  （ユーザーがボタンの入らないサイズへ縮小できないようにする、stopwatchと同じ方針）。
  正確な値はBlueStacks実機確認で調整する（stopwatchウィジェットで実際に「幅不足でボタンが
  view階層ごと消える」実バグが見つかった前例があるため、初期値は暫定と明記する）。
- `AndroidManifest.xml`：`TimerControlWidgetProvider`の`<receiver>`（`exported=true`、
  ピッカー用`label`）を追加。`HomeWidgetBackgroundReceiver`は#62で登録済みのため変更不要。
- `strings.xml`：`home_widget_timer_start_glyph`/`_description`、
  `home_widget_timer_reset_glyph`/`_description`（開始・リセットはグリフのみで自己説明的でない
  ためcontentDescriptionが必要、stopwatchと同じ理由）、`home_widget_timer_add30_label`/
  `home_widget_timer_add1min_label`（+30秒/+1分はボタンの可視テキスト自体が説明になるため
  別途descriptionは追加しない）、`widget_picker_label_timer_control`/
  `widget_picker_description_timer_control`。

## Out of scope

- iOS対応（既存の`feat-home-widget-android.md`から継続）。
- 表示専用版（#69）への変更。今回は完全に別の新規ウィジェットとして追加する。
- 操作可能版への背景点滅演出の追加（#63本文どおり点滅は表示専用版のみの役割）。

## Tests

- 新規`test/features/home_widget/timer_widget_callback_test.dart`：`start`/`add30`/`add60`/`reset`
  それぞれのURIで正しい`TimerController`メソッドが呼ばれ、`syncTimer`と`syncStopwatch`の両方が
  呼ばれることを検証（`stopwatch_widget_callback_test.dart`と同じフェイクチャンネル方式）。
- 新規`test/features/home_widget/home_widget_background_callback_test.dart`：`host`が
  `"stopwatch"`/`"timer"`/未知の値それぞれで正しい委譲先（またはno-op）になることを検証。
- 既存`test/features/home_widget/stopwatch_widget_callback_test.dart`を更新：
  `updatedAndroidNames`の期待値に`timerWidgetAndroidName`/`timerControlWidgetAndroidName`を
  追加（`_pushUpdatedStateToWidget`が両方書き戻すようになったため）。
- 既存`test/features/home_widget/home_widget_sync_service_test.dart`の`syncTimer`グループに、
  `timerControlWidgetAndroidName`への`updateWidget`呼び出しも検証するテストを追加。
- `main.dart`は既存どおりテスト対象外（このリポジトリに`main.dart`用のテストはない）。
- Android nativeコード（Kotlin）は既存3ウィジェット・ストップウォッチウィジェット・
  タイマー表示専用ウィジェットと同様、自動テストを追加せずBlueStacks実機で目視確認する。

## ドキュメント

- `README.md`：ウィジェット一覧を5種→6種に更新し、`TimerControlWidgetProvider.kt`の行と
  操作可能である旨の説明を追加。
