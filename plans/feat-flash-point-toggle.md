# Feat: フラッシュポイントごとのフラッシュ/通知ON/OFF

Issue: <https://github.com/iq3-run/session-timer-app/issues/22>

## Scope（2026-08-09、ユーザーとの事前確認事項）

issue #22 は当初「完了カウントダウン12点固定・通知チェックボックスのみ」で書か
れていたが、#26/#28 でフラッシュポイントが動的なユーザー編集リストになったこと
を受けて次の設計に更新し、この plan で実装する（詳細な経緯は issue #22 のコメン
ト参照）。

- 対象は完了カウントダウンのフラッシュポイント（`FlashPointsController` が持つ
  リスト）のみ。指定時刻・タイマーの通知は対象外（常にON固定のまま、変更しな
  い）。
- 各ポイントに **フラッシュON/OFF** ・ **通知ON/OFF** の2つのトグルを持たせる
  （issue #26 コメントの次フェーズ候補②案）。
- **制約**: フラッシュOFFのポイントは通知も強制OFFになり、通知トグルは操作不
  可（フラッシュしないのに通知だけ来る状態を防ぐ）。
- フラッシュポイントの追加/削除・デフォルト12点の起動時復活ルール（#26/#28で
  実装済みの `_applyStartupRules`）は**変更しない**。デフォルトの昇格/降格・永
  続削除（issue #26 コメントの①案）は対象外のまま。
- 設定シートの既存の単一グローバル通知トグル（`NotificationSettingsSection`、
  PR #25 で追加した UI-only プレースホルダー）は**削除**し、ポイント別の2トグ
  ルに置き換える。

## 新設: `FlashPointConfig`

`lib/features/flash/flash_point_config.dart`（`TimeTarget`と同じ設計パター
ン: `tryFromJson`/`toJson`/`copyWith`）

```dart
class FlashPointConfig {
  const FlashPointConfig({
    required this.minutes,
    this.flashEnabled = true,
    this.notifyEnabled = true,
  });

  static FlashPointConfig? tryFromJson(Map<String, dynamic> json) {
    final minutes = json['minutes'];
    final flashEnabled = json['flashEnabled'];
    final notifyEnabled = json['notifyEnabled'];
    if (minutes is! int || minutes <= 0) return null;
    if (flashEnabled is! bool || notifyEnabled is! bool) return null;
    return FlashPointConfig(
      minutes: minutes,
      flashEnabled: flashEnabled,
      notifyEnabled: notifyEnabled,
    );
  }

  final int minutes;
  final bool flashEnabled;
  final bool notifyEnabled;

  Map<String, dynamic> toJson() =>
      {'minutes': minutes, 'flashEnabled': flashEnabled, 'notifyEnabled': notifyEnabled};

  FlashPointConfig copyWith({bool? flashEnabled, bool? notifyEnabled}) {
    return FlashPointConfig(
      minutes: minutes,
      flashEnabled: flashEnabled ?? this.flashEnabled,
      // flashEnabled が false になる更新は notifyEnabled も強制 false にする
      // （制約はここで一元的に守る — 呼び出し側の条件分岐に頼らない）。
      notifyEnabled: (flashEnabled == false)
          ? false
          : (notifyEnabled ?? this.notifyEnabled),
    );
  }
}
```

## `FlashPointsController` の変更

`lib/features/flash/flash_points_controller.dart` — 状態の型を `List<int>` か
ら `List<FlashPointConfig>` に変更する。`AsyncNotifier`・mutation-queue パター
ン（`_mutationQueue`/`_lastGood`/`_mutateNow`）自体は変更なし。

- 永続化フォーマット: `jsonEncode(points.map((p) => p.toJson()).toList())`。
  読み込み側は `decoded.whereType<Map>().map(...).nonNulls`（`tryFromJson` が
  `null` を返す要素はスキップ — 壊れたデータは1件落ちるだけで全体は保持する
  既存方針を踏襲）。
- **既存データとの互換性**: 旧フォーマット（`List<int>`の生JSON配列）は
  `Map`型チェックに失敗して全要素が弾かれ、空リストに degrade する。
  `_applyStartupRules`が空リストに対してデフォルト12点を無条件復活させるので、
  結果的に「デフォルトだけの状態にリセットされる」（カスタム点は失われる）。
  実機は開発中の自分のテスト用途のみで移行が必要なユーザーデータではないため、
  明示的なマイグレーションコードは書かない。
- `_isDefault`/`_defaultsToKeep`/`_customsToKeep`/`_hasPassed` は
  `FlashPointConfig.minutes` で比較するように書き換える（分数の集合演算という
  ロジック自体は変わらない）。
- デフォルトが復活する際は常に `FlashPointConfig(minutes: m)`（フラッシュ/通知
  とも ON）で生成する — 消えていた間のトグル状態を覚えておく仕組みは持たない
  （消えた時点で状態は失われる、という既存の「復活は fresh」という考え方と一
  貫）。
- `addPoint(int minutes)` は `FlashPointConfig(minutes: minutes)`（両方ON）を
  追加。重複判定は `minutes` の一致で行う（変更なし）。
- `removePoint(int minutes)` は `minutes` 一致で除去（変更なし）。
- 新設: `setFlashEnabled(int minutes, bool enabled)` — 該当ポイントを
  `copyWith(flashEnabled: enabled)` で置き換える（`copyWith`が制約を担保）。
- 新設: `setNotifyEnabled(int minutes, bool enabled)` — 該当ポイントの
  `flashEnabled` が `false` の場合は no-op（UI側もトグルを操作不可にするが、
  防御的に二重で守る）。それ以外は `copyWith(notifyEnabled: enabled)`。

## 既存コードの変更

### `lib/features/flash/flash_event.dart`

変更なし（`completionFlashEvents`は引き続き`List<int>`を受け取る — 呼び出し側
で`FlashPointConfig`から必要な`minutes`だけ抽出してから渡す）。

### `lib/features/flash/flash_queue_controller.dart`

```dart
final flashPoints = ref.watch(flashPointsControllerProvider).value ?? const [];
final flashEnabledMinutes = [
  for (final p in flashPoints)
    if (p.flashEnabled) p.minutes,
];
// ... completionFlashEvents(completion, flashEnabledMinutes)
```

フラッシュOFFのポイントはアニメーションのキューに一切乗らない。

### `lib/features/notifications/notification_event_source.dart`

同様に、フラッシュONかつ通知ONの点だけを抽出して`completionFlashEvents`に渡す
（`copyWith`の制約により`notifyEnabled: true`は常に`flashEnabled: true`を含意
するので、実質`p.notifyEnabled`だけの判定でも同じ結果になるが、意図を明示する
ため両方書く）:

```dart
final notifyMinutes = [
  for (final p in flashPoints)
    if (p.flashEnabled && p.notifyEnabled) p.minutes,
];
```

### `lib/features/flash/flash_points_chip_row.dart`

チップ行は「これから鳴るフラッシュ」を表す一覧なので、フラッシュOFFのポイント
は表示しない。`_sortDescending`に渡す前に`flashEnabled`でフィルタする:

```dart
final sortedPoints = _sortDescending([
  for (final p in ref.watch(flashPointsControllerProvider).value ?? const [])
    if (p.flashEnabled) p.minutes,
]);
```

### `lib/features/settings/flash_points_settings_section.dart`

`minutes: List<int>`を受け取る現在のシグネチャを`points: List<FlashPointConfig>`
に変更し、`onToggleFlash`/`onToggleNotify`コールバックを追加する。行のUIは共有の
`SettingsListItem`（削除ボタンのみのシンプルな行、`weekend_milestones_settings_
section.dart`とも共用）をこのセクション専用の行ウィジェットに差し替える
（`SettingsListItem`自体は他セクションで使われているため変更しない）:

```dart
class FlashPointsSettingsSection extends StatelessWidget {
  const FlashPointsSettingsSection({
    required this.points,
    required this.onAdd,
    required this.onRemove,
    required this.onToggleFlash,
    required this.onToggleNotify,
    super.key,
  });

  final List<FlashPointConfig> points;
  final ValueChanged<int> onAdd;
  final ValueChanged<int> onRemove;
  final void Function(int minutes, bool enabled) onToggleFlash;
  final void Function(int minutes, bool enabled) onToggleNotify;

  // build(): sorted by minutes desc (既存踏襲), each row = _FlashPointRow
}
```

`_FlashPointRow`（このファイル内プライベート）: ラベル + 「フラッシュ」スイッ
チ + 「通知」スイッチ（`flashEnabled == false`のとき`onChanged: null`で無効化
・視覚的にも`muted`色にする）+ 削除ボタン。コンパクトな`SwitchListTile`2つを横
並びではなく、幅の都合上`Row`+小さめの`Switch`+ラベルで実装する
（`NotificationSettingsSection`の`SwitchListTile`スタイルをベースに調整）。

### `lib/features/settings/settings_sheet.dart`

- `NotificationSettingsSection`の import・呼び出し・`_notifyEnabled`フィール
  ド・`_setNotifyEnabled`を削除。
- `_sections()`内の`FlashPointsSettingsSection`呼び出しを新シグネチャに合わせ、
  `points: ref.watch(flashPointsControllerProvider).value ?? const []`と
  `onToggleFlash`/`onToggleNotify`を`flashPointsControllerProvider.notifier`
  の`setFlashEnabled`/`setNotifyEnabled`にバインドする。

### `lib/features/settings/notification_settings_section.dart`

ファイルごと削除（グローバルトグルは#22のこのバージョンでは使わない）。

## テストへの影響

- `test/features/flash/flash_points_controller_test.dart` — 型が
  `List<int>`→`List<FlashPointConfig>`になるため、既存アサーション
  （`expect(points, contains(120))`等）を`points.map((p) => p.minutes)`越し
  の比較に書き換え。新規: `setFlashEnabled`/`setNotifyEnabled`のユニットテス
  ト（フラッシュOFF→通知も強制OFFになること、フラッシュOFFの点への
  `setNotifyEnabled`がno-opであること、フラッシュONに戻しても通知は自動で
  ONに戻らないこと）。
- `test/features/flash/flash_queue_controller_test.dart` /
  `test/features/flash/flash_points_chip_row_test.dart` /
  `test/features/notifications/notification_event_source_test.dart` — 各ファ
  イルの`flashPointsControllerProvider`オーバーライド用フィクスチャ
  （`_FixedFlashPointsController`等）が返す型を`List<FlashPointConfig>`に更
  新。加えてchip row・queue・notificationの3箇所それぞれで「フラッシュOFFの
  点は対象から除外される」「通知OFF（フラッシュON）の点はnotification候補か
  らだけ除外され、フラッシュ・チップには影響しない」ケースを追加。
- `test/features/settings/settings_sheet_test.dart` — 新しい2トグルUIに合わ
  せてウィジェットテストを更新（`NotificationSettingsSection`関連のケースは
  削除）。
- 新規: `test/features/flash/flash_point_config_test.dart` —
  `tryFromJson`/`toJson`/`copyWith`（特に`copyWith(flashEnabled: false)`が
  `notifyEnabled`も道連れでfalseにすること）。

## Verification

- `dart format`
- `flutter analyze`
- `flutter test`
- debug build
- BlueStacks/実機で設定シートから: ①あるポイントのフラッシュをOFFにすると、
  そのポイントのチップが消え、実際にフラッシュしないこと ②通知トグルがフラッ
  シュOFF中は操作不可であること ③フラッシュを再度ONにした後、通知トグルが
  OFFのままであること（自動で戻らない）④アプリ再起動後も設定が保持されるこ
  とを目視確認。
