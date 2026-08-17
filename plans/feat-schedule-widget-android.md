# Feat: セッションスケジュールウィジェット（Android）

Issue: <https://github.com/iq3-run/session-timer-app/issues/64>

## Scope（ユーザーとの確認事項）

- 表示範囲は「セッションスケジュール画面の内容」に一致させる —
  `buildScheduleRows`（`lib/features/schedule/session_chain.dart`）が返す
  行をそのまま使う。独自に「全SessionEventを日付昇順」等の別ロジックは
  作らない。結果として：
  - チェーン系（OR/WE/WD/SS/CS）は過去分も含め全件、CRは「今日のCR」と
    「次回CR」の最大2行のみ、「今日」行が挿入される — 画面と完全に同じ
    集合・順序。
  - `SessionEvent.visible` によるアプリ内トグルも画面と同じ挙動でそのまま
    適用される（`buildScheduleRows`内部で既に絞り込み済み）。
- サイズは縦4×横3セル相当（`targetCellWidth=3`/`targetCellHeight=4`、
  API31+。`minWidth`/`minHeight`は`(cells×70dp)−30dp`の通常算出式で
  フォールバックを用意）。
- タップ時の挙動はヘッダー部分のみアプリを開く（他ウィジェットと同様、
  ウィジェット単体でのインタラクティブ操作は対象外）。リスト本体は
  `ListView`が占有するため、コンテナ全体をクリックターゲットにはできない
  （`StopwatchWidgetProvider`のボタン付きレイアウトと同様、ヘッダーTextView
  にのみ`setOnClickPendingIntent`を設定）。

## Out of scope

- iOS対応（既存6種と同じ理由で対象外）。
- ウィジェット上での個々の予定タップ時のアクション（詳細画面への遷移等）。
- アプリ内設定画面からの表示件数フィルタ等のカスタマイズ。

## アーキテクチャ：既存6種との違い

既存6種は「単純な`RemoteViews`更新」or「`Chronometer`自走」で完結して
いたが、本ウィジェットは可変長リストを表示するため
`RemoteViewsService`/`RemoteViewsFactory`（`ListView`をホストする標準の
Androidウィジェットリストパターン）が必要になる、唯一のケース。

### データ同期方式

`home_widget`パッケージの`HomeWidget.saveWidgetData`で全行をJSON
シリアライズして`HomeWidgetPreferences`（`es.antonborri.home_widget.
HomeWidgetPlugin.PREFERENCES`）に書き込み、`RemoteViewsFactory`が
`HomeWidgetPlugin.getData(context)`（publicなcompanion関数 —
`HomeWidgetProvider.onUpdate`が内部で使っているのと同じアクセサ）経由で
同じSharedPreferencesファイルを直接読む。ネイティブ側専用の別ストレージは
持たない（既存6種の同期パターンをそのまま踏襲）。

## Design decisions requiring implementation-time judgment（PRで明示）

1. **「今日」の日付境界の鮮度。** 既存のグループA/B（Chronometer自走・
   TextClock自走）と異なり、本ウィジェットは「どの行が今日か」を含めた
   表示内容そのものをFlutter側で計算済みのテキストとしてpushする方式
   （ネイティブ側でチェーン計算のロジックを再実装するのは過剰）。その
   ため、深夜0時をまたいでも新しい`buildScheduleRows`の再計算・再pushが
   行われない限り「今日」の表示は前日のまま固定される。これに対応する
   ため、`nowProvider`（1秒ごとに発火）を直接watchするのではなく、日付
   （年/月/日）が変化した時だけ値が変わる`scheduleWidgetTodayProvider`
   を新設し、日付が変わった瞬間にのみ再pushする（毎秒の同期は行わない）。
   ただしアプリプロセスが完全に終了している間は日付変化にも反応できない
   —既存6種の「アプリを開いた時に`initState`で1回同期」という前提と
   同じ範囲のトレードオフとして許容する。
2. **リスト項目のクリック不可。** `ListView`全体を`setOnClickPendingIntent`
   のターゲットにするとスクロール操作とタップ操作が競合するため、
   ヘッダー行のみタップ可能にする。個々の行のクリックアクション
   （`setPendingIntentTemplate`+`setOnClickFillInIntent`）は今回追加しない
   （Out of scope参照）。
3. **`hasStableIds()`は`false`。** 「今日」の合成行（`SessionEvent`を
   持たない）や日付変更に伴う行の増減があるため、位置ベースの安定IDを
   前提にできない。
4. **行の表示内容は`label`＋`date`のみ。** `chainGap`/`todayGap`
   （週末間／今日から日数）はウィジェットには含めない — issue本文の
   候補「種別・番号・日付」に合わせ、既存の`session_schedule_formatting.
   dart`の`formatScheduleDate`をそのままDart側で適用した文字列を
   ネイティブへ渡す（ネイティブ側で曜日ラベル配列を再実装しない）。
5. **NTPオフセットは同期しない。** 本ウィジェットは静的テキストのみで
   `Chronometer`を使わないため、既存グループAの`ntpOffsetMs`同期は不要
   （`nowProvider`が既にNTP補正込みの値を返すため、`scheduleWidgetToday
   Provider`の日付境界自体はNTP補正済み）。

## 新規/変更モジュール: `lib/features/home_widget/`

### `schedule_widget_rows.dart`（新規）

```dart
final scheduleWidgetTodayProvider = Provider<DateTime>((ref) {
  return ref.watch(
    nowProvider.select((async) => _dateOnly(async.value ?? DateTime.now())),
  );
});

final scheduleWidgetRowsProvider = Provider<List<ScheduleRow>>((ref) {
  final events = ref.watch(sessionEventControllerProvider).value ?? const [];
  final today = ref.watch(scheduleWidgetTodayProvider);
  return buildScheduleRows(events, today);
});
```

### `home_widget_sync_service.dart`（変更）

`syncSchedule(List<ScheduleRow> rows)`を追加。`scheduleEventsJsonKey`
（`schedule_events_json`）に`[{label, date, isToday}, ...]`をJSON
エンコードして書き込み、`scheduleWidgetAndroidName`
（`ScheduleWidgetProvider`）を`updateWidget`。

### `home_widget_scheduler.dart`（変更）

- `initState`の`_syncAll`に`_syncSchedule`を追加（既存4種と同様、起動時
  1回の初回同期）。
- `ref.listen(scheduleWidgetRowsProvider, ...)` で行データ変化時に
  `_syncSchedule`を呼ぶ。

## Platform (Android native)

### 新規Kotlinファイル

- `ScheduleWidgetProvider.kt`（`HomeWidgetProvider`継承）— `onUpdate`で
  `setRemoteAdapter`により`ScheduleWidgetService`をリストのデータソース
  として設定し、ヘッダーへ`setOnClickPendingIntent`、空リスト用の
  `setEmptyView`、最後に`notifyAppWidgetViewDataChanged`を呼ぶ。
- `ScheduleWidgetService.kt`（`RemoteViewsService`継承）— `onGetView
  Factory`で`ScheduleRemoteViewsFactory`を返すのみ。
- `ScheduleRemoteViewsFactory.kt`（`RemoteViewsService.RemoteViewsFactory`
  実装）— `onDataSetChanged`で`HomeWidgetPlugin.getData(context)`から
  `HomeWidgetKeys.SCHEDULE_EVENTS_JSON`をJSON文字列として読み、
  `org.json.JSONArray`でパースして内部リストへ保持。`getViewAt`は
  行ごとに`schedule_widget_list_item`をレイアウトし、`isToday`の行は
  文字色を`home_widget_amber`にする。

### `HomeWidgetKeys.kt`（変更）

`SCHEDULE_EVENTS_JSON = "schedule_events_json"`を追加。

### 新規リソース

- `layout/schedule_widget_layout.xml`（ヘッダーTextView + `ListView` +
  空リスト用プレースホルダTextView）
- `layout/schedule_widget_list_item.xml`（種別ラベル + 日付の横並び行）
- `xml/schedule_widget_info.xml`（`targetCellWidth=3`/`targetCellHeight=4`、
  `minWidth=180dp`/`minHeight=250dp`、`updatePeriodMillis=1800000`、
  `resizeMode="horizontal|vertical"`、`widgetCategory="home_screen"`）
- `values/strings.xml`に`widget_picker_label_schedule`/
  `widget_picker_description_schedule`/空リスト時プレースホルダ文字列を
  追加

### `AndroidManifest.xml`（変更）

- `<receiver android:name=".ScheduleWidgetProvider">`を追加（既存6種と
  同じ`<intent-filter>`/`<meta-data>`パターン）。
- `<service android:name=".ScheduleWidgetService" android:exported="false"
  android:permission="android.permission.BIND_REMOTEVIEWS" />`を追加
  （`RemoteViewsService`を使う全ウィジェットに必須のOS標準宣言）。

## Tests

- `test/features/home_widget/schedule_widget_rows_test.dart` —
  `scheduleWidgetRowsProvider`が`buildScheduleRows`と同じ結果を返すこと、
  `scheduleWidgetTodayProvider`が日付が変わった時だけ値を更新すること。
- `home_widget_sync_service_test.dart`に`syncSchedule`のテストを追加
  （フェイクゲートウェイ経由でキー/JSON内容/androidNameを検証）。
- `home_widget_scheduler_test.dart`にスケジュール変更時の同期テストを
  追加（既存の`timerControllerProvider`変化テストと同じ形）。
- ネイティブKotlin側（`RemoteViewsFactory`実装・レイアウトXML）はFlutter
  側のテストスイートではカバーできない。実機/エミュレータでの手動確認が
  必須（Verification参照）。

## Verification

- `dart format` / `flutter analyze` / `flutter test` / debug build
- 実機またはエミュレータでの手動確認：
  - ウィジェットをホーム画面に追加し、セッションスケジュール画面と同じ
    行・順序で表示されることを確認
  - スクロールで全件を閲覧できることを確認
  - 予定の追加/削除/非表示切替がウィジェットへ反映されることを確認
  - 日付が変わった際に「今日」表示が追従すること（アプリを開いた状態で
    日付変更をまたぐか、日付変更後にアプリを開いて確認）
  - 縦画面・横画面の両方でレイアウト崩れがないか確認
  - BlueStacksでの検証には注意（`docs/*dev-environment-notes*`参照。
    対応していない場合は実機での確認が必須である旨PRで明示する）
