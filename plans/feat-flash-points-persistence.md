# Feat: フラッシュポイント追加/削除の実配線・永続化

Issue: <https://github.com/iq3-run/session-timer-app/issues/26>

## Scope（2026-08-09、ユーザーとの事前確認事項）

- 初期値は既存の12点固定リスト（`defaultCompletionFlashPointsMinutes`）を
  そのまま使う。ユーザーはそこから自由に追加/削除できる。
- 追加/削除の結果は`SharedPreferences`で永続化し、アプリ再起動をまたいで
  保持する（`TimeTargetsController`と同じパターン）。
- 通知の個別ON/OFF相当のフラグ（`notifyEnabled`等）は**本issueでは用意しない**。
  それは別issue #22の責務。本issueは`List<int>`（分リスト）の実配線に限定する。

## 新設: `FlashPointsController`

`lib/features/flash/flash_points_controller.dart`

`TimeTargetsController`（`lib/features/targets/time_targets_controller.dart`）
と同じ設計をそのまま踏襲する：

```dart
const flashPointsMinutesJsonKey = 'flash_points_minutes_json';

final flashPointsControllerProvider =
    AsyncNotifierProvider<FlashPointsController, List<int>>(
      FlashPointsController.new,
    );

class FlashPointsController extends AsyncNotifier<List<int>> {
  Future<void> _mutationQueue = Future.value();
  final Completer<void> _initialLoad = Completer<void>();
  List<int> _lastGood = const [];

  @override
  Future<List<int>> build() async { ... }

  Future<void> addPoint(int minutes) => _mutate(
    (points) => points.contains(minutes) ? points : [...points, minutes],
  );

  Future<void> removePoint(int minutes) =>
      _mutate((points) => points.where((m) => m != minutes).toList());

  // _mutate/_mutateNow/_persistenceFailure: TimeTargetsControllerと同一パターン
}
```

- 永続化フォーマットはJSON配列（`jsonEncode(points)`/`jsonDecode`で`List<int>`
  に変換、非intの要素は`whereType<int>()`で除外）。`TimeTarget.toJson/tryFromJson`
  ほど複雑なオブジェクトではないため、`TimeTarget`のような専用モデルクラスは
  作らない。
- ソート順は持たない（保存順そのまま）。表示側（チップ行・設定シート）が
  それぞれ必要な順序でソートする（既存の`FlashPointsSettingsSection`・
  `FlashPointsChipRow`は元々ローカルで降順ソートしていたロジックをそのまま
  流用できる）。

### 起動時ルール（`_applyStartupRules`、2026-08-09にユーザーとすり合わせて確定）

`build()`時（アプリ起動時のみ、継続的なチェックではない）に、現在の
`CompletionTimeController`の状態（`ref.read(completionTimeControllerProvider.future)`
による一度きりの読み取り。`ref.watch`ではない — 起動後に完了時刻が変わっても
このルールを再トリガーしないため）と突き合わせて以下を適用する：

2026-08-09、ユーザーが以下の表で最終確認：

| | | 未設定 | 過ぎてる | 過ぎていない・◯分前は過ぎている | 過ぎていない・◯分前は過ぎていない |
|---|---|---|---|---|---|
| デフォルト | 存在 | そのまま | そのまま | そのまま | そのまま |
| デフォルト | 存在していない | 復活 | 復活 | 復活 | **消えたまま** |
| カスタム | 存在 | そのまま | 削除 | 削除 | そのまま |
| カスタム | 存在していない | - | - | - | - |

（行=デフォルト/カスタムかつ現在リストに存在するか、列=起動時の完了時刻の
状態。「◯分前」はその点自身の実時刻＝完了時刻－分数）

- **既に存在するデフォルトは常にそのまま**（何があっても削除されない）。
- **存在しないデフォルトは、完了時刻が未設定なら無条件に復活**（比較材料が
  ないため）。完了時刻が設定されていれば、**その点自身の実時刻が現在時刻を
  過ぎていれば復活、まだ先なら消えたまま**（＝存在しないからといって
  無条件で即復活するわけではない）。
- **存在するカスタムの点は、完了時刻が未設定ならそのまま**。完了時刻が
  設定されていれば、その点自身の実時刻を過ぎていれば削除、まだ先ならそのまま。
- **存在しないカスタムの点は何もしない**（ユーザーが追加しない限り自動では
  増えない）。

「過ぎてる」（完了時刻自体が起動時に超過）は実質的に「どの点の実時刻も
過ぎている」場合と同じ結果になる（完了時刻自体が過去なら、そこから
さらに分数を引いた実時刻はより過去になるため）。また
`CompletionTimeController.build()`が起動時に超過した完了時刻を未設定へ
自動リセットする関係で、`FlashPointsController`が読み取る時点では
「過ぎてる」という状態は実際には観測されない（`completionTarget`は
`null`になっているはず）— 保険的なハンドリングとして実装はしているが、
実運用で通る経路ではない。

## 既存コードの変更

### `lib/features/flash/flash_event.dart`

`completionFlashEvents`が`defaultCompletionFlashPointsMinutes`を直接参照する
のをやめ、呼び出し側から分リストを受け取る：

```dart
List<FlashEvent> completionFlashEvents(
  CompletionTimeState? completion,
  List<int> minutesBefore,
) { ... }
```

`defaultCompletionFlashPointsMinutes`定数自体は`FlashPointsController`の
シード値として引き続き使うので残す。

### `lib/features/flash/flash_queue_controller.dart`

`build()`内で`ref.watch(flashPointsControllerProvider).value ?? const []`を
読み、`completionFlashEvents(completion, flashPoints)`に渡す。

### `lib/features/notifications/notification_event_source.dart`

同様に`flashPointsControllerProvider`を`ref.watch`して渡す。

### `lib/features/flash/flash_points_chip_row.dart`

モジュールレベルの`_sortedFlashPointsMinutes`（一度だけ計算される固定リスト）
を廃止。`_FlashPointsChipRowState.build()`内で
`ref.watch(flashPointsControllerProvider).value ?? const []`を読み、
降順ソートして使う（既存のソートロジックはそのまま）。リストが空の場合は
`SizedBox.shrink()`を返す（既存の「対象時刻未設定なら何も描画しない」の
ガードと同様）。

### `lib/features/settings/settings_sheet.dart` / `flash_points_settings_section.dart`

`SettingsSheet`が持っていたephemeralな`_flashPointMinutes`
フィールドと`_addFlashPoint`/`_removeFlashPoint`メソッドを削除し、
`FlashPointsSettingsSection`への`minutes`/`onAdd`/`onRemove`を
`flashPointsControllerProvider`から取得・呼び出す形に差し替える
（`SettingsSheet`を`StatefulWidget`から`ConsumerStatefulWidget`に変更）。
`FlashPointsSettingsSection`自体（Stateless、propsで受け取る設計）は変更不要。

## テストへの影響

- `test/features/flash/flash_event_test.dart` — `completionFlashEvents`の
  呼び出し全箇所に第2引数（分リスト）を追加。既存の期待値
  （`defaultCompletionFlashPointsMinutes.length + 1`等）はそのまま
  `defaultCompletionFlashPointsMinutes`を渡せば変更不要。
- `test/features/flash/flash_queue_controller_test.dart` — `_buildContainer`
  ヘルパーに`flashPoints`パラメータ（デフォルト値
  `defaultCompletionFlashPointsMinutes`）を追加し、
  `flashPointsControllerProvider.overrideWith(() => _FixedFlashPointsController(flashPoints))`
  を`overrides`に含める（`_FixedCompletionController`等と同じ
  fixtureパターンで`_FixedFlashPointsController`を新設）。
- `test/features/flash/flash_points_chip_row_test.dart` — 同様に
  `flashPointsControllerProvider`のoverrideを`_pump`ヘルパーに追加。
- `test/features/notifications/notification_event_source_test.dart` — 同様。
- `test/features/settings/settings_sheet_test.dart` — `SettingsGearButton`を
  `ProviderScope`で包み、`sharedPreferencesProvider`が実際のI/Oをしないよう
  `SharedPreferences.setMockInitialValues({})`をテスト側で呼ぶ
  （`TimeTargetsController`のテストと同じセットアップ）。
- 新規：`test/features/flash/flash_points_controller_test.dart` —
  `TimeTargetsController`のテスト（`_FlakyStore`含む）と同じ構成で、
  初回起動時のデフォルトシード・追加・削除・重複追加の無視・永続化失敗時の
  挙動をカバーする。

## Verification

- `dart format`
- `flutter analyze`
- `flutter test`
- debug build
- BlueStacks/実機で設定シートからフラッシュポイントを追加/削除し、
  ①チップ行の表示に反映される ②アプリを再起動しても保持される
  ことを目視確認。
