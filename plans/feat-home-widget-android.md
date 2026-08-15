# Feat: ホーム画面ウィジェット（Android、4パネル独立配置）

Issue: <https://github.com/iq3-run/session-timer-app/issues/54>

## Scope (confirmed with the user before starting)

- 4種類の表示を、それぞれ**独立したAndroidホーム画面ウィジェット**として実装する。
  ユーザーはこの中から必要なものだけを選んでホーム画面に追加できる。
  1. ストップウォッチの経過時間
  2. 次のターゲット時刻（指定時刻）までの残り時間
  3. 完了までのカウントダウン
  4. 現在時刻のみのシンプル表示
- 対象は **Android のみ**。iOSは将来対応したいが、現時点でテスト環境がないため
  今回は対象外（着手時に別issueを起票する）。

## Out of scope

- iOS（App Group / WidgetKit）対応。
- ウィジェット上でのインタラクティブ操作（スタート/ストップボタン等）。タップは
  アプリを開くだけの単純な導線とする。
- アプリ内設定画面からのウィジェット外観カスタマイズ。
- ウィジェットサイズ・配置の複数バリエーション（今回は各ウィジェット固定サイズ
  1種類のみ）。

## アーキテクチャ方針：2グループに分かれる

4つのウィジェットは、更新の駆動方式で2グループに分かれる。

- **グループA（Flutter側の状態変化をネイティブに同期し、ネイティブ側の
  `Chronometer` が自走してカウントする）**：経過時間・次ターゲット残り時間・
  完了までのカウントダウン。
  - `Chronometer.setBase()` に `SystemClock.elapsedRealtime()` 基準の値を
    設定すると、以後は `AppWidgetManager` からの明示的な再描画なしに端末が
    1秒ごとにビューを再描画してくれる。これにより「動き続ける表示」を
    `updatePeriodMillis` の頻繁な発火（電池消費・Androidの最小更新間隔制約）
    なしに実現できる。
  - カウントダウン系は `Chronometer.setCountDown(true)`（API 24+、本アプリの
    minSdkは要確認だが対象範囲内）を使う。ゼロ到達後に停止させず、
    `formatCountdown` が既に採用している「マイナス表記で超過時間を継続表示」
    という既存UXと挙動を揃える。
- **グループB（ネイティブが完全に自走、Flutter側の同期不要）**：現在時刻のみ。
  - RemoteViewsに `TextClock`（`android:format24Hour`）を直接配置するだけで、
    OS標準の時計ウィジェットと同じ仕組みで自走する。`home_widget` パッケージ
    経由のデータ同期は一切不要。

## Design decisions requiring implementation-time judgment（PRで明示）

1. **NTPオフセットを同期する。** 本アプリは `now_provider.dart` で
   `ntpOffsetMsProvider` による補正後時刻を「アプリの正式なnow」として扱って
   いる（`lib/core/clock/ntp_sync_controller.dart`）。ネイティブ側が
   `Chronometer` のbaseを計算する際に端末の生の `System.currentTimeMillis()`
   のみを使うと、NTP補正が効いているケースでアプリ本体の表示とウィジェットの
   表示がズレる。そのためグループAの同期データには対象epoch値に加えて
   `ntpOffsetMs`（`ref.watch(ntpOffsetMsProvider)`）も含め、ネイティブ側で
   `System.currentTimeMillis() + ntpOffsetMs` を「補正後now」として使う。
   NTP再同期でオフセットが変わった場合に備え、`HomeWidgetScheduler` は
   `ntpOffsetMsProvider` の変化も監視し、変化時にグループA全体を再同期する。
2. **「次のターゲット」の定義。** `time_targets_section.dart` を見る限り、
   アプリ本体のUIは全ターゲットを並列表示するのみで「次の1件」という概念を
   持っていない。ウィジェット用に新規の純粋関数
   `nextTimeTarget(List<TimeTarget> targets, DateTime now)` を追加し、
   （`TimeTargetsController` が返す、epochMs昇順ソート済みリストの中で）
   `epochMs > now` を満たす最初の1件を返す。該当なしなら `null`
   （未設定表示 `--:--` と同じ扱い）。
3. **タップ時の挙動はアプリを開くのみ。** `home_widget` パッケージの
   `HomeWidgetLaunchIntent` でMainActivityへの `PendingIntent` を
   `RemoteViews.setOnClickPendingIntent` に設定する。ウィジェット単体での
   スタート/ストップ操作は今回のスコープ外（Out of scope参照）。
4. **新規ランタイム権限は不要。** `AppWidgetProvider` の登録はManifestの
   `<receiver>` 宣言のみで完結する。
5. **初回同期前（新規インストール直後にウィジェットだけ先に追加された場合）は
   ネイティブ側で「データなし」のプレースホルダ表示にフォールバックする。**
   `home_widget` のAndroid側データストアはアプリ本体の
   `shared_preferences`（`flutter_shared_preferences` ファイル）とは別の
   専用SharedPreferencesファイルであり、`HomeWidget.saveWidgetData` で
   明示的にpushしない限り空。ネイティブ側は値の欠落をクラッシュではなく
   プレースホルダで処理する。
6. **同期はイベント駆動のpushのみ**（`HomeWidget.saveWidgetData` +
   `HomeWidget.updateWidget(androidName: ...)`）。ただし取りこぼし対策として
   `*_widget_info.xml` の `updatePeriodMillis` に安全網として30分
   （Android自体が許容する実質的な最小間隔）を設定する。この定期更新は
   ネットワークもFlutter起動も伴わず、直近にpushされ保存済みの値から
   `Chronometer` baseを再計算するだけなので電池コストは無視できる。

## 新規依存パッケージ

- `home_widget`（`flutter pub add home_widget`）。グループA (1〜3) のみで
  使用。グループB (現在時刻) は `TextClock` のみで完結するため、この
  パッケージを経由したデータ同期は行わない。

## 新規モジュール: `lib/features/home_widget/`

### `next_time_target.dart`

```dart
TimeTarget? nextTimeTarget(List<TimeTarget> targets, DateTime now) {
  final nowEpochMs = now.millisecondsSinceEpoch;
  for (final target in targets) {
    if (target.epochMs > nowEpochMs) return target;
  }
  return null;
}

final nextTimeTargetProvider = Provider<TimeTarget?>((ref) {
  final targets = ref.watch(timeTargetsControllerProvider).value ?? const [];
  return nextTimeTarget(targets, DateTime.now());
});
```

`notification_event_source.dart` の既存パターンに合わせ、`nowProvider` は
watchしない（対象リストが変化した時だけ再評価すれば十分。`now`が進むだけで
「次の1件」が変わるケースは、その時点のターゲットがネイティブ側の
`Chronometer` カウントダウンで自然にマイナス表示へ遷移するため、Flutter側の
再pushは不要）。

### `home_widget_gateway.dart`

`home_widget` パッケージの静的メソッド呼び出しを直接使わず、
`NotificationService` が `FlutterLocalNotificationsPlugin` を注入できる形に
しているのと同じ理由（テスト容易性）で薄いインターフェースを挟む。

```dart
abstract class HomeWidgetGateway {
  Future<void> saveWidgetData(String key, Object? value);
  Future<void> updateWidget({required String androidName});
}

class HomeWidgetPluginGateway implements HomeWidgetGateway {
  @override
  Future<void> saveWidgetData(String key, Object? value) =>
      HomeWidget.saveWidgetData(key, value);

  @override
  Future<void> updateWidget({required String androidName}) =>
      HomeWidget.updateWidget(androidName: androidName);
}

final homeWidgetGatewayProvider = Provider<HomeWidgetGateway>(
  (ref) => HomeWidgetPluginGateway(),
);
```

### `home_widget_sync_service.dart`

```dart
class HomeWidgetSyncService {
  HomeWidgetSyncService(this._gateway);
  final HomeWidgetGateway _gateway;

  Future<void> syncStopwatch(StopwatchState s, int ntpOffsetMs) async {
    await _gateway.saveWidgetData(
      'stopwatch_accumulated_ms',
      s.accumulatedMs.toString(),
    );
    await _gateway.saveWidgetData(
      'stopwatch_running_since_epoch_ms',
      s.runningSinceEpochMs?.toString(),
    );
    await _gateway.saveWidgetData('ntp_offset_ms', ntpOffsetMs.toString());
    await _gateway.updateWidget(androidName: 'StopwatchWidgetProvider');
  }

  Future<void> syncNextTarget(TimeTarget? target, int ntpOffsetMs) async {
    await _gateway.saveWidgetData(
      'next_target_epoch_ms',
      target?.epochMs.toString(),
    );
    await _gateway.saveWidgetData('ntp_offset_ms', ntpOffsetMs.toString());
    await _gateway.updateWidget(androidName: 'NextTargetWidgetProvider');
  }

  Future<void> syncCompletion(DateTime? target, int ntpOffsetMs) async {
    await _gateway.saveWidgetData(
      'completion_target_epoch_ms',
      target?.millisecondsSinceEpoch.toString(),
    );
    await _gateway.saveWidgetData('ntp_offset_ms', ntpOffsetMs.toString());
    await _gateway.updateWidget(androidName: 'CompletionCountdownWidgetProvider');
  }
}
```

（キー名・シグネチャは実装時に確定。3メソッドとも `ntp_offset_ms` を
毎回書き込むのは冗長だが、各ウィジェットは独立した `AppWidgetProvider`
プロセスから読まれるため、共有キーを都度書いておく方が「片方だけ古い
オフセットを参照する」不整合より安全、という判断。数値を全て
`.toString()` で文字列化しているのは、`home_widget` プラグインの
プラットフォームチャネル越しに送った数値がネイティブ側の型付き
`SharedPreferences` ゲッターと食い違い `ClassCastException` になるのを
避けるため — 詳細は実装した `home_widget_sync_service.dart` の
docコメントを参照。）

### `home_widget_scheduler.dart`

`NotificationScheduler`（`lib/features/notifications/notification_scheduler.dart`）
と同じ形の薄いラッパーウィジェット。

```dart
class HomeWidgetScheduler extends ConsumerStatefulWidget {
  const HomeWidgetScheduler({required this.child, super.key});
  final Widget child;
  ...
}

class _HomeWidgetSchedulerState extends ConsumerState<HomeWidgetScheduler> {
  @override
  Widget build(BuildContext context) {
    final ntpOffsetMs = ref.watch(ntpOffsetMsProvider);
    final service = ref.read(homeWidgetSyncServiceProvider);

    ref.listen(stopwatchControllerProvider, (previous, next) {
      final value = next.value;
      if (value != null) unawaited(service.syncStopwatch(value, ntpOffsetMs));
    });
    ref.listen(nextTimeTargetProvider, (previous, next) {
      unawaited(service.syncNextTarget(next, ntpOffsetMs));
    });
    ref.listen(completionTimeControllerProvider, (previous, next) {
      final value = next.value;
      unawaited(service.syncCompletion(value?.targetTime, ntpOffsetMs));
    });
    // ntpOffsetMs自体の変化（再同期）でも全グループAを再push
    ref.listen(ntpOffsetMsProvider, (previous, next) {
      unawaited(_syncAll(next));
    });

    return widget.child;
  }

  Future<void> _syncAll(int ntpOffsetMs) async { ... } // 3メソッドをまとめて呼ぶ
}
```

`ref.listen` はデータ変化時のみ発火し初回ビルドでは発火しないため、
初回同期（アプリ起動直後に既存データをウィジェット側へ反映）は
`initState` で現在値を読んで `_syncAll` 相当を1回呼ぶ形で担保する。

## App wiring

`lib/app.dart` で `NotificationScheduler` と同様に `ClockScreen` をラップする
（ネストの順序はどちらが外でも機能に影響しないが、既存の
`NotificationScheduler` の外側に追加する）。

```dart
home: const NotificationScheduler(
  child: HomeWidgetScheduler(child: ClockScreen()),
),
```

## Platform (Android native)

### `pubspec.yaml`

- `home_widget` を追加。

### 新規Kotlinファイル（`android/app/src/main/kotlin/com/iq3run/session_timer/`）

- `StopwatchWidgetProvider.kt`
- `NextTargetWidgetProvider.kt`
- `CompletionCountdownWidgetProvider.kt`
- `CurrentTimeWidgetProvider.kt`（`home_widget` 非経由、`TextClock` のみ）

グループA 3クラスは `home_widget` パッケージが提供する `HomeWidgetProvider`
基底クラスを継承し、`onUpdate` で保存済みprefsから該当キーを読んで
`Chronometer.setBase()` / `setCountDown()` / `start()` を呼ぶ。

### 新規リソース（`android/app/src/main/res/`）

- `xml/stopwatch_widget_info.xml` ほか3種（`minWidth`/`minHeight`、
  `updatePeriodMillis="1800000"`、`resizeMode="horizontal|vertical"`、
  `widgetCategory="home_screen"`）
- `layout/stopwatch_widget_layout.xml` ほか3種（ラベル + `Chronometer`
  または `TextClock`）

### `AndroidManifest.xml`

`<application>` 内に4つの `<receiver>` を追加、各々
`android.appwidget.action.APPWIDGET_UPDATE` の `<intent-filter>` と
`android.appwidget.provider` の `<meta-data>` を持たせる。

## Tests

- `test/features/home_widget/next_time_target_test.dart` — 空リスト、全件過去、
  一部過去、複数件未来（ソート済み前提での先頭選択）のケース。
- `test/features/home_widget/home_widget_sync_service_test.dart` — フェイク
  `HomeWidgetGateway` を注入し、各 `syncXxx` が正しいキー/値・
  `androidName` で呼ばれることを検証（`NotificationService` のテストと同じ
  「注入されたゲートウェイ経由で検証」パターン）。
- `HomeWidgetScheduler` 自体のwidget testは作成しない
  （`ref.listen` + delegate呼び出しの配線のみ。`NotificationScheduler`
  と同じ判断）。
- ネイティブKotlin側（`AppWidgetProvider`実装・レイアウトXML）はFlutter側の
  テストスイートではカバーできない。実機/エミュレータでの手動確認が必須
  （Verification参照）。

## Verification

- `dart format` / `flutter analyze` / `flutter test` / debug build
- 実機またはエミュレータでの手動確認：
  - 4種のウィジェットをそれぞれホーム画面に追加し、表示・自走ティックを確認
  - ストップウォッチのトグル/リセットが数秒以内にウィジェットへ反映される
    ことを確認
  - 指定時刻の追加/削除で「次のターゲット」ウィジェットが追従することを確認
  - 完了時刻の設定/クリアで完了カウントダウンウィジェットが追従することを
    確認
  - アプリを強制終了してもウィジェット表示が残る（`Chronometer`
    自走のため）ことを確認
  - **BlueStacksでの検証には注意**: BlueStacksのランチャーがホーム画面
    ウィジェットの配置に対応していない可能性がある
    （`docs/*dev-environment-notes*` 参照）。対応していない場合は実機での
    確認が必須になる旨、PRで明示する。
