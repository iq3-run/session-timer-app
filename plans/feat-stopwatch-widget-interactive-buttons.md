# Feat: ストップウォッチウィジェット（Android）の開始/一時停止・リセットボタン対応

Issue: #62（親: #1）

## Scope（ユーザーと合意済み）

- 対象は `StopwatchWidgetProvider` の1パネルのみ。他の3ウィジェット（次の予定・完了までカウントダウン・現在時刻）は表示専用のまま変更しない。
- ボタンは「開始/一時停止」「リセット」の2つ。RemoteViewsはロングプレス/ダブルタップを検出できないため、issue本文どおり別ボタンとして分離する。
- リセットボタンは確認なしで即座に実行する（2段階確認UIは今回作らない）。誤タップのリスクはあるが、ユーザーの判断でシンプルさを優先。
- リセットは既存の `StopwatchController.reset()` をそのまま使い、連動する `TimerController.reset()` も一緒に呼ぶ（アプリ内長押しリセットと同じ挙動）。ウィジェット専用の「ストップウォッチのみリセット」メソッドは作らない。
- ボタンの見た目は既存ウィジェットと同じくテキスト/絵文字グリフ（▶ / ⏸ / ⟲ 相当）。新規ベクターアイコンは作らない。

## Out of scope

- iOS対応（既存の `feat-home-widget-android.md` から継続）。
- 他の3ウィジェットへのインタラクティブ操作追加。
- ウィジェットサイズ・レイアウトの複数バリエーション。

## 背景：フォアグラウンド/バックグラウンドの状態競合（issueで要検討とされていた点）

`home_widget` 0.9.3 の `registerInteractivityCallback` はウィジェットのボタンタップ時に**アプリのUIとは別のFlutterEngine/Dart isolate**をバックグラウンドで起動する（同一OSプロセス内だが別isolate。`HomeWidgetBackgroundWorker.kt` 参照）。このisolateは独自に `SharedPreferences.getInstance()` を呼ぶため、ディスク上の最新値は読める。

問題は逆方向：アプリがフォアグラウンドで**起動済み**の状態でウィジェットのボタンをタップした場合、アプリ側の `StopwatchController`/`TimerController` は

- `SharedPreferences.getInstance()`（legacyプラグイン、isolateごとに値をメモリキャッシュ）
- `_lastGood`（コントローラ内の直近ミューテーション結果のキャッシュ）

の両方を古いまま持ち続け、ウィジェット経由の変更に気づかない。ユーザーがアプリに戻ってきた時点で画面が古い経過時間を表示し続け、そのままアプリ内で次の操作をすると `_lastGood` を起点に上書き（ウィジェット側の変更をロスト）してしまう。

### 対応方針

`AppLifecycleState.resumed` を検知したら、`StopwatchController`/`TimerController` それぞれに `reloadFromDisk()` を追加し、`SharedPreferences.reload()` → 再読込 → `_lastGood`/`state` を更新する。既存の `_mutate` と同じ直列化キュー（`_mutationQueue`）に乗せることで、フォアグラウンド側で同時に走っている他のミューテーションとの競合順序を保証する（reloadが割り込んでロスト・アップデートを起こさない）。

両コントローラの `_mutate`/`_mutateNow`/`_lastGood` 構造はほぼ同一で、共通化（`MutationQueueNotifier<T>` 化）は既に別途検討済みだが見送り済み（`.claude/agent-memory` 参照）。今回もその方針を踏襲し、共通化はせず各コントローラに同じ形の `reloadFromDisk()` を個別実装する（スコープ外の大規模リファクタは行わない）。

`StopwatchState`/`TimerState` は `==` を実装していない（同値比較不可）ため、変更の有無を比較せず、resumeのたびに無条件で `_lastGood`/`state` をディスク値で上書きする。実質的な変更がなくても `AsyncData` の再emitが起きるだけで実害はない。

## Android native側の実装

### `AndroidManifest.xml`

`home_widget` のバックグラウンド呼び出しを受け取るための `HomeWidgetBackgroundReceiver` をアプリのManifestに追加する（プラグイン自体のManifestは空で自動マージされないため必須）。

```xml
<receiver
    android:name="es.antonborri.home_widget.HomeWidgetBackgroundReceiver"
    android:exported="false">
    <intent-filter>
        <action android:name="es.antonborri.home_widget.action.BACKGROUND" />
    </intent-filter>
</receiver>
```

`android:exported="false"`：ウィジェットからのブロードキャストは常にアプリ自身のPendingIntent経由で送られ、他アプリから直接起動される必要がないため（`exported="true"` にする例がプラグインのサンプルにはあるが、本アプリの他レシーバの慣例（`ScheduledNotificationReceiver` も `exported="false"`）に合わせる）。

### `stopwatch_widget_layout.xml`

既存の1×2セル（110dp×90dp）にボタン2つを追加で収めるのは窮屈なため、このウィジェットのみ `stopwatch_widget_info.xml` のサイズを広げる（issueのScopeで「必要ならウィジェット自体のサイズ変更も含めて再検討」と合意済み）。他の3ウィジェットは1×2のまま変更しない。現状の縦積み（ラベル→Chronometer→placeholder）はそのまま維持しつつ、下部に横並びの2ボタンを追加する:

（CodeRabbitレビューで、当初の110dp×110dp（2×2セル）だと48dp四方のボタン2つ＋12dp間隔＋コンテナのpadding/marginが幅方向で収まらない（108dp+padding16dp+margin8dp=132dp＞110dp）という指摘を受け、`minWidth`/`targetCellWidth`を150dp/3セルに広げて修正。さらに`resizeMode="horizontal|vertical"`でユーザーが再縮小できてしまう点も指摘を受け、`minResizeWidth`/`minResizeHeight`を`minWidth`/`minHeight`と同じ値に設定し、ボタンが収まる最小サイズより縮小できないようにした。

その後BlueStacks実機確認で、150dp幅でもボタン2つ（合計48+48=96dpの中身、実測では周辺の余白を含めさらに広い領域）が実際には**ボタンごと丸ごとview階層から消える**という、単なる見切れではない不具合を確認した（詳細は「動作確認（BlueStacks実機確認）」節）。最終的に `minWidth`/`minResizeWidth` を220dp、`targetCellWidth` を4に広げて解決。`minHeight`/`minResizeHeight`/`targetCellHeight` は110dp/2セルのまま変更なし。)

```text
[経過時間ラベル]
[Chronometer/placeholder]  ← フォントサイズを28sp→20sp程度に縮小して余白確保
[▶/⏸ ボタン] [⟲ ボタン]
```

（Chronometer/placeholderとボタン行を1つの横並びLinearLayout（`layout_weight`で時刻を可変幅、ボタンを固定幅）にまとめる案も試したが、BlueStacks実機ではChronometerが weight 付きの入れ子LinearLayout内で意図通り展開されず、結局placeholderが単独行にはみ出す挙動になった。実際にレンダリングされる構造に合わせ、素直に3段の縦積み（ラベル／時刻／ボタン行）のまま確定した。）

- ボタンは `TextView`（`android:clickable` は不要、`setOnClickPendingIntent` で十分）または `Button` の軽量版。既存の文字ベースの見た目に合わせ、装飾は最小限（背景は透明かうっすら、フォントサイズは16sp程度）。
- コンテナ全体の `widget_container` に既存どおり「アプリを開く」の `PendingIntent` を設定したまま、2つのボタンには個別に `setOnClickPendingIntent` を設定する。RemoteViewsは子ビュー自身のクリックリスナーが親のものより優先されるため、ボタン領域だけタップ時の挙動が上書きされる（他の3ウィジェットと同じ「タップで開く」動線は温存）。

### `StopwatchWidgetProvider.kt`

- `HomeWidgetChronometerPanel.update` の代わりに、この1ウィジェットだけ専用の描画ロジックに分ける（他の2ウィジェットと共有していたパネルはタップ全面が「開く」前提だったため、ボタン付きレイアウトは共有しない）。
- ボタンの `PendingIntent` は `HomeWidgetBackgroundIntent.getBroadcast(context, uri)` で発行し、`uri` に操作を区別するスキームを載せる:
  - トグル: `Uri.parse("homewidget://stopwatch/toggle")`
  - リセット: `Uri.parse("homewidget://stopwatch/reset")`
- トグルボタンのラベルは実行中かどうか（`runningSinceEpochMs != null`）で `⏸`/`▶` を切り替える。
- `onUpdate` は既存どおり `widgetData`（`home_widget` 専用SharedPreferences）から `accumulatedMs`/`runningSinceEpochMs`/`ntpOffsetMs` を読み、Chronometerの base計算は既存の `HomeWidgetTimeMath.countUpBase` を再利用する。

## Dart側の実装

### 新規: `lib/features/home_widget/stopwatch_widget_callback.dart`

`home_widget` のバックグラウンドisolateから呼ばれるエントリポイント。トップレベル関数＋`@pragma('vm:entry-point')`（AOTビルドでツリーシェイクされないために必須）。

```dart
@pragma('vm:entry-point')
Future<void> stopwatchWidgetBackgroundCallback(Uri? uri) async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  try {
    // "homewidget://stopwatch/toggle" の "toggle" は uri.host ではなく
    // 最初のpathセグメント（uri.host は "stopwatch" 固定）。
    switch (uri?.pathSegments.firstOrNull) {
      case 'toggle':
        await container.read(stopwatchControllerProvider.notifier).toggle();
      case 'reset':
        await container.read(stopwatchControllerProvider.notifier).reset();
    }
    // 更新後の状態を home_widget 側のストアにも即反映し、RemoteViewsを再描画させる
    final state = await container.read(stopwatchControllerProvider.future);
    final ntpOffsetMs = await container.read(ntpOffsetMsProvider.future); // 既存の永続化値を読むのみ、再同期はしない
    await container
        .read(homeWidgetSyncServiceProvider)
        .syncStopwatch(state, ntpOffsetMs);
  } finally {
    container.dispose();
  }
}
```

- 別isolateなので、フォアグラウンドの `ProviderContainer`（`main()` で作った方）とは完全に別インスタンス。ここで作る `ProviderContainer` はこの呼び出し1回限りで使い捨て、`finally` で必ず `dispose()` する。
- `ntpOffsetMsProvider` が `SharedPreferences` 由来で同期的に読めない場合は、`home_widget` 側ストアから直接 `HomeWidgetGateway`/`HomeWidget.getWidgetData` で読む形に置き換える（実装時に既存の `ntpOffsetMsProvider` の実体を確認して確定する）。

### `main()` での登録

`HomeWidget.registerInteractivityCallback(stopwatchWidgetBackgroundCallback)` を、既存の `_autoSyncNtpAtStartup` と同様に `main()` から起動時に呼ぶ（ベストエフォート、失敗してもアプリ起動は継続）。

### `StopwatchController`/`TimerController` への `reloadFromDisk()` 追加

```dart
Future<void> reloadFromDisk() {
  final previous = _mutationQueue;
  final result = previous.then((_) => _reloadNow());
  _mutationQueue = result.catchError((_) {});
  return result;
}

Future<void> _reloadNow() async {
  if (!_initialLoad.isCompleted) await _initialLoad.future;
  try {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs.reload();
    final onDisk = _readPersisted(prefs);
    _lastGood = onDisk;
    state = AsyncData(onDisk);
  } on Exception catch (e) {
    debugPrint('StopwatchController: reloadFromDisk failed: $e');
  }
}
```

既存の `_mutate`/`_mutateNow` と同型（直列化キューに乗せる）。ただし失敗時の扱いは `_mutateNow` とは異なり `AsyncError` にはしない（`debugPrint`のみ）。`reloadFromDisk()`は`HomeWidgetScheduler`から`unawaited(...)`で呼ばれるため、`_mutationQueue`側の`catchError`だけでは呼び出し元の未処理例外を防げない（`unawaited`はFutureを未消費のまま切り離すだけで、そのFuture自体が失敗すればuncaughtな非同期エラーとして表面化する）——`code-reviewer`サブエージェントのレビューで指摘され、実装済み。

### `HomeWidgetScheduler` に `WidgetsBindingObserver` を追加

```dart
class _HomeWidgetSchedulerState extends ConsumerState<HomeWidgetScheduler>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_syncAll(ref.read(ntpOffsetMsProvider)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(ref.read(stopwatchControllerProvider.notifier).reloadFromDisk());
    unawaited(ref.read(timerControllerProvider.notifier).reloadFromDisk());
  }
}
```

このクラスは既に「アプリ⇄ウィジェット」間の同期を一手に引き受けている場所なので、逆方向（ウィジェット→アプリ）のreloadもここに置く。

## 新規文字列リソース（`android/app/src/main/res/values/strings.xml`）

ボタンの `contentDescription` 用（視覚障害者向けTalkBack対応。既存ウィジェットには存在しない属性だが、タップで即座に副作用（リセット等）が起きるボタンには最低限つけておく）:

```xml
<string name="home_widget_stopwatch_toggle_start_description">開始</string>
<string name="home_widget_stopwatch_toggle_pause_description">一時停止</string>
<string name="home_widget_stopwatch_reset_description">リセット</string>
```

## ドキュメント更新

- `plans/feat-home-widget-android.md` の `## Out of scope` にある「ウィジェット上でのインタラクティブ操作（今回対象外）」の記述に、今回のissue #62で対応した旨の注記を追加する。
- README.md にAndroidウィジェットの説明があれば、ストップウォッチウィジェットが操作可能になったことを反映する（実装時に該当箇所を確認）。

## Tests

- `test/features/stopwatch/stopwatch_controller_test.dart`：`reloadFromDisk()` が
  - ディスク上の最新値で `state`/内部キャッシュを更新すること
  - 進行中の別ミューテーションの後ろに正しくキューイングされること（先に積まれた `toggle()` の結果を上書きしない）
  を検証するテストを追加。
- `test/features/timer/timer_controller_test.dart`：同様に `reloadFromDisk()` のテストを追加。
- 新規 `test/features/home_widget/stopwatch_widget_callback_test.dart`：`toggle`/`reset` それぞれのURIで正しいコントローラメソッドが呼ばれ、`HomeWidgetSyncService.syncStopwatch` が呼ばれることを検証（`ProviderContainer` をテスト用にoverrideしたfakeで確認）。
- `test/features/home_widget/home_widget_scheduler_test.dart`（既存があれば）に、`AppLifecycleState.resumed` で両コントローラの `reloadFromDisk()` が呼ばれることを確認するテストを追加。
- Kotlin側は既存プロジェクトにユニットテストの仕組みがないため自動テストは追加せず、BlueStacks（Android 9/API 28）での手動確認に委ねる。

## 動作確認（BlueStacks実機確認、2026-08-17）

CI/CodeRabbitレビューが完了しマージ可能な状態になった後、ユーザーの依頼でBlueStacks（emulator-5554、Android 9/API 28、Nova Launcher）上での実機確認を実施。`adb shell input draganddrop`でウィジェットピッカーからホーム画面へドラッグ配置し、`adb shell input swipe <x> <y> <x> <y> <duration>`（同一点への短時間swipe＝タップ代替。プレーンな`input tap`はこの環境で不安定なため）でボタン操作、`uiautomator dump`で実際のview階層・bounds・content-descriptionを確認、`logcat`で`HomeWidgetBackgroundWorker`のWorkManagerログを追跡する形で検証した。

**発見した実バグ1（Critical・修正済み）**: 当初のminWidth=150dp設定で実機配置すると、ラベルとプレースホルダー（`--:--`）は表示されるが、**開始/一時停止・リセットボタンが丸ごとview階層から消える**（`uiautomator dump`のaccessibility treeにも一切現れない。単なる見切れ/クリッピングではない）。`flutter build apk --debug`のようなビルド時チェックでは検出できない、実機レンダリング時のみ再現する不具合だった。`minWidth`/`minResizeWidth`を220dp、`targetCellWidth`を4に広げたところ解消。原因（幅とボタン消失の直接的な因果関係）は完全には特定できていないが、複数回の再現実験で「150dp幅→消える／220dp幅→表示される」という結果は一貫して再現した。

**発見した実バグ2（Minor・修正せず、既知の制約として記録）**: `home_widget`プラグイン0.9.3の`HomeWidgetBackgroundWorker.kt`が`WorkManager.enqueueUniqueWork`を`ExistingWorkPolicy.APPEND`で呼んでいるため、**アプリを一度も起動していない状態でウィジェットのボタンを最初にタップすると（＝`HomeWidget.registerInteractivityCallback`がまだ登録されていない状態）、その1回目のWork失敗が以降すべてのボタンタップを永続的にブロックする**（アプリを後から起動してコールバック登録が完了しても直らない。`enqueueUniqueWork`のAPPENDチェーンが失敗したまま以降のWorkを一切実行しなくなるため）。実際のユーザーフロー（アプリを最低1回起動してからウィジェットを操作する、または最低1回起動した後に配置する）ではこの問題は再現しない（起動後に配置→即操作した場合はWorker成功を確認済み）。`home_widget`側のバグであり本PRのスコープ外と判断し、修正はしない。issue #68として追跡する。

確認した項目：

1. `dart format` / `flutter analyze` / `flutter test` — 全てクリーン
2. デバッグビルドをBlueStacksにインストールし、ホーム画面にストップウォッチウィジェットを追加 → ✅ ウィジェットピッカーで正しく「4x2」と表示され、配置後ボタン2つ・ラベル・時刻表示すべて正常にレンダリングされることを確認
3. アプリを閉じた状態で「開始/一時停止」ボタンをタップ → ✅ Chronometerが動き出し、グリフが▶→⏸に切り替わることを確認（アプリを一度起動済みの状態）
4. アプリを閉じたまま「リセット」ボタンをタップ → ✅ 表示が00:00に戻り、グリフが⏸→▶に戻ることを確認
5. ウィジェット経由で開始した状態のままアプリを開く（`am start`で既存タスクをforeground化＝resume相当）→ ✅ アプリ内の経過時間表示が「計測中」として widget 側の running 状態を正しく引き継いで表示（`reloadFromDisk()`の動作を確認）
6. ウィジェット全体のうちボタン以外の領域（ラベル部分）をタップした場合、従来どおりアプリが開くことを確認

## リスク・既知の制約

- BlueStacksはAndroid 9（API 28）のため、実機の新しいAndroidバージョンでのPendingIntent/RemoteViews挙動の差異は検証できない（既存の `project_home-widget-android-followups.md` の制約を踏襲）。`targetCellWidth`/`targetCellHeight`はAPI 31+でのみ`minWidth`/`minHeight`より優先されるため、この環境ではその挙動も未検証。
- `reloadFromDisk()` はresumeのたびに `SharedPreferences.reload()`（ディスクI/O）を伴う。頻繁なアプリ切り替えでの体感コストは軽微と想定するが、実測はしない。
- 上記「発見した実バグ2」（`home_widget`のWorkManager APPENDチェーン問題）は既知の制約として残す（issue #68で追跡）。
