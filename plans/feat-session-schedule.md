# Feat: セッションスケジュール管理（種別つきイベント・週末間日数計算）

Issue: <https://github.com/iq3-run/session-timer-app/issues/44>

## Scope（2026-08-11、ユーザーとの事前確認事項）

- 既存の`WeekendMilestone`（`lib/features/settings/weekend_milestone.dart`、
  ラベル＋日付のみのUI専用モデル。永続化・日数計算とも未実装）は**廃止**し、
  種別つきの新モデル`SessionEvent`に置き換える。
- 種別: OR / WE / WD / CR / SS / CS の6種。OR・CSは単一のみ（UI側で1件制約）、
  WE・WD・SS・CRは複数可。
- 通し番号（1WE, 2WEなど）はWE・WD・SSのみ、**日付昇順の並び順**で自動採番する
  （追加順ではない）。CRには通し番号を付けない（曜日固定なし、個別に日付入力）。
- 所要日数: OR/WD/CR/SS/CS=1日。WEは1番目(1WE)のみ3日、2番目以降2日。
- 表示・編集は新規専用画面にまとめる。設定シート内の既存セクションは削除し、
  ホーム画面（歯車アイコン付近）に新画面への導線を追加する。
- 永続化は全件保持（過去の項目も削除しない）。チェーン計算・「直前からの
  日数」計算に過去の項目が必要なため、`TimeTargetsController`等の「期限切れは
  再起動時に削除」ルールはこの機能には適用しない。

## 日数・週数の計算式（2026-08-11、ユーザーとすり合わせ確定）

2点間（`from`の最終日 → `to`の初日）について：

- **日数** = `(to.開始日 − from.終了日).inDays − 1`
- **週数** = その範囲（from終了日の翌日 〜 to開始日の前日）に含まれる金曜日の
  数 ＋（`to`の開始日自体が金曜なら+1）

「今日」も同様に一方の端点として扱える（直前セッション→今日、今日→直後
セッション）。

### 検証済み例

- 1WE(8/21〜8/23, 3日間) → 1WD(9/5)：`8/24〜9/4`=12日、金曜(8/28,9/4)の2件
  =2W
- OR(8/7) → 1WE(8/21)：`8/8〜8/20`=13日、金曜(8/14)の1件＋着地日8/21が金曜
  のため+1 =2W
- 今日(8/11) → 1WE(8/21)：`8/12〜8/20`=9日、金曜(8/14)の1件＋着地日8/21が
  金曜のため+1 =2W

## 新設: データモデル・計算ロジック

`lib/features/schedule/`ディレクトリを新設する。

### `session_event.dart`

```dart
enum SessionEventType { orientation, weekend, workday, classroom, specialSession, completion }

class SessionEvent {
  SessionEvent({required this.id, required this.type, required this.date});

  final String id;
  final SessionEventType type;
  final DateTime date; // 日付のみ（時刻は00:00に正規化）

  int durationDays({required bool isFirstWeekend}) {
    if (type != SessionEventType.weekend) return 1;
    return isFirstWeekend ? 3 : 2;
  }

  DateTime endDate({required bool isFirstWeekend}) =>
      date.add(Duration(days: durationDays(isFirstWeekend: isFirstWeekend) - 1));

  static SessionEvent? tryFromJson(Map<String, dynamic> json) { ... }
  Map<String, dynamic> toJson() => { ... };
}
```

`FlashPointConfig.tryFromJson`と同じ「1件のパース失敗が全体を巻き込まない」
方針。`isFirstWeekend`を呼び出し側から渡す設計にするのは、「1番目」の判定が
リスト全体のソート結果に依存する（単体では決まらない）ため。

### `session_event_numbering.dart`

WE・WD・SSの通し番号を日付昇順で採番する純粋関数：

```dart
/// 種別ごとに日付昇順で1始まりの番号を振る。同日付の同種別イベントは
/// 元のリスト順（＝id順、追加順）でタイブレークする。
Map<String, int> assignSequenceNumbers(List<SessionEvent> events);
```

（キー=`SessionEvent.id`、値=通し番号。OR/CR/CSは対象外なのでマップに現れない）

### `session_gap_calculation.dart`

日数・週数計算の純粋関数：

```dart
class GapResult {
  const GapResult({required this.days, required this.weeks});
  final int days; // 負の場合は呼び出し側で「表示しない」判断をする
  final int weeks;
}

/// from（終了日）→ to（開始日）の日数・週数。
/// 週数 = fromEnd+1〜toStart-1の範囲に含まれる金曜日の数 + (toStartが金曜なら+1)
GapResult calculateGap({required DateTime fromEnd, required DateTime toStart});
```

### `session_chain.dart`

表の行を組み立てるロジック：

```dart
class ScheduleRow {
  const ScheduleRow({
    required this.event,       // nullなら「今日」単独行
    required this.label,       // "1WE", "次回CR", "今日" など
    required this.isToday,     // 赤線表示するか
    required this.chainGap,    // 週末間列（CR・今日行はnull）
    required this.todayGap,    // 今日から列（対象行以外はnull）
  });
  final SessionEvent? event;
  final String label;
  final bool isToday;
  final GapResult? chainGap;
  final GapResult? todayGap;
}

List<ScheduleRow> buildScheduleRows(List<SessionEvent> events, DateTime today);
```

`buildScheduleRows`の内部ロジック：

1. `events`を`type`ごとに分け、`assignSequenceNumbers`でWE/WD/SSの番号を採番。
2. チェーン対象（OR/WE/WD/SS/CS）を日付昇順に並べ、隣接ペアごとに`calculateGap`
   を適用して「週末間」列を埋める（先頭行のみnull）。
3. 直近過去・直近未来のWE/WD/SSを1件ずつ特定し、「今日」との`calculateGap`
   を「今日から」列に入れる（それ以外のWE/WD/SS行はnull）。
4. CRは、`date > today`で最小のものを「次回CR」行として追加（「今日から」を
   計算）。`date == today`のCRが存在すれば、それは別に強調行として追加する
   （次回CRの計算対象からは除く）。
5. CSがあれば「今日から」列を計算して追加。
6. `today`と一致するイベントが存在しない場合、日付順の該当位置に
   `event: null`の「今日」行を挿入する。存在する場合はその行の`isToday`を
   trueにする。

CR・今日行は「週末間」チェーンに含めない。

## 新設: 永続化

### `session_event_controller.dart`

`FlashPointsController`と同じ設計（mutation-queueパターン、JSON配列で
`SharedPreferences`に保存）を踏襲。過去項目の自動削除は行わない。

```dart
const sessionEventsJsonKey = 'session_events_json';

final sessionEventControllerProvider =
    AsyncNotifierProvider<SessionEventController, List<SessionEvent>>(
      SessionEventController.new,
    );

class SessionEventController extends AsyncNotifier<List<SessionEvent>> {
  // _mutationQueue / _initialLoad / _lastGood: FlashPointsControllerと同一パターン

  Future<void> addEvent(SessionEventType type, DateTime date) {
    // OR/CSはすでに1件存在する場合追加を拒否（no-op）
  }

  Future<void> removeEvent(String id) => _mutate(...);
}
```

## 新設: UI

### `session_schedule_screen.dart`

専用画面。上部にイベント追加フォーム（種別ドロップダウン＋日付ピッカー、
OR/CSはすでに1件あれば選択肢から無効化）、下部に`buildScheduleRows`の結果を
表形式（日付・ラベル・週末間・今日からの4列相当）で表示。今日の行は下線等で
強調。各行に削除ボタン。

### `session_schedule_entry_button.dart`

`SettingsGearButton`と同じ構造。`ClockScreen`の`SettingsGearButton`の隣に配置し、
タップで`Navigator.push`により`SessionScheduleScreen`を開く。

## 既存コードの変更

- `lib/features/clock/clock_screen.dart` — `SessionScheduleEntryButton`を
  `SettingsGearButton`と並べて配置。
- `lib/features/settings/settings_sheet.dart` — `WeekendMilestonesSettingsSection`
  の呼び出しと、`_milestones`/`_nextMilestoneId`/`_addMilestone`/`_removeMilestone`
  を削除。
- 削除: `lib/features/settings/weekend_milestone.dart`、
  `lib/features/settings/weekend_milestones_settings_section.dart`。
- `test/features/settings/settings_sheet_test.dart` — マイルストーン関連の
  6テストを削除（新画面側のテストに移す）。

## テスト計画

- `test/features/schedule/session_gap_calculation_test.dart` — 検証済み例3件
  ＋境界値（同日、金曜が範囲の両端にまたがるケースなど）。
- `test/features/schedule/session_event_numbering_test.dart` — 通し番号の
  日付昇順採番、同日タイブレーク。
- `test/features/schedule/session_chain_test.dart` — `buildScheduleRows`の
  各分岐（今日がイベントと一致/しない、CRが存在/しない、OR/CSが未設定の
  場合の表示など）。
- `test/features/schedule/session_event_controller_test.dart` —
  `flash_points_controller_test.dart`と同じ構成（追加・削除・永続化失敗・
  OR/CS重複拒否）。
- `test/features/schedule/session_schedule_screen_test.dart` — 画面遷移・
  追加フォーム・削除ボタンのwidgetテスト。

## Verification

- `dart format`
- `flutter analyze`
- `flutter test`
- debug build
- BlueStacks/実機で新画面からイベントを追加/削除し、①週末間・今日から列が
  仕様どおりに計算される ②アプリを再起動しても全件保持される ③今日の行が
  正しく強調されることを目視確認。
