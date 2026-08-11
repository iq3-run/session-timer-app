# Feat: セッションスケジュール画面を「一覧」と「日程設定」に分割

Issue: <https://github.com/iq3-run/session-timer-app/issues/48>

## Scope（2026-08-12、ユーザーとの事前確認事項）

3点要望のうち2点目。現行の `SessionScheduleScreen`（issue #44/PR #45）は登録
フォーム・削除ボタン・週末間/今日からの一覧表が1画面に同居しており、CRは
「今日のCR」+「次回CR」の最大2件しか出ない。これを次の2画面に分割する。

- **「セッションスケジュール」**（既存の名前・既存の入口＝`ClockScreen`右上
  のアイコンを維持）: 週末間/今日からの計算結果を表示する**読み取り専用の一
  覧画面**。登録フォーム・行ごとの削除ボタンは撤去し、代わりに「日程設定」
  へのナビゲーションボタンを設置する。
- **「日程設定」**（新設。「セッションスケジュール」画面から遷移）: イベン
  トの追加・削除、および**全件一覧**（CRも含め、過去・未来問わず全イベン
  ト）を表示・管理する。

### 表示/非表示トグル

- 「日程設定」画面の一覧の各行に、「セッションスケジュール」に出す/出さな
  いを選べるトグルを追加する。
- **対象**（トグルあり）: OR、2番目以降のWE（2WE, 3WE, ...）、WD、SS。
- **対象外**（常に表示、トグル無し）: 1WE（最初のWE）、CS。
- **CRは対象外**: 現行通り「今日のCR」+「次回CR」のみの自動選別のままとし、
  表示/非表示の概念自体を持たせない（トグルUIも出さない）。

### 重要な設計判断：非表示は「表示」のみに影響し、計算には影響しない

あるイベントを非表示にしても、週末間/今日からの日数計算・番号採番（1WE,
2WE, ...）は**非表示のイベントも含めた全イベントに対してそのまま計算する**
（データが消えるわけではなく、あくまで「セッションスケジュール」画面の行を
描画しないだけ）。理由：非表示のWD等を計算チェーンから除外すると、隣接する
表示中イベントの「週末間」日数が実態と異なる値になってしまう（例：2WE・3WE
の間にあるWDを非表示にしても、2WE→3WEの間の実日数は変わらないので、表示上
だけWDの行を消す）。

実装上は `buildScheduleRows` の既存ロジック（`assignSequenceNumbers` → chain
構築 → gap計算）を一切変更せず、**最後にフィルタを1段挟んで非表示行を落と
す**だけにする。「今日」の合成マーカー挿入 (`_withTodayMarker`) はフィルタ
後の行に対して行う（非表示にした日に他の表示行がなければ「今日」だけの行が
挿入される、という自然な結果になる）。

## 新設: `SessionEvent.visible`

`lib/features/schedule/session_event.dart` にフィールド追加:

```dart
class SessionEvent {
  SessionEvent({
    required this.id,
    required this.type,
    required DateTime date,
    this.visible = true,
  }) : date = DateTime(date.year, date.month, date.day);

  final bool visible; // 「セッションスケジュール」に出すかどうか。
  // OR/2番目以降のWE/WD/SSのみ意味を持つ（1WE/CS/CRは常に表示扱いで無視する
  // — session_chain.dart 側で判定する）。

  // toJson: 'visible' キーは false のときだけ出力（デフォルトtrueは省略、
  // TimerState等の既存方針を踏襲）
  // tryFromJson: 'visible' が無ければ true、bool以外なら不正データとして
  // null（他フィールドと同じ「壊れたデータは丸ごと弾く」方針）
}
```

## `session_chain.dart` の変更

`buildScheduleRows` に非表示フィルタを追加する（`assignSequenceNumbers`・
chain構築・gap計算は変更しない）:

```dart
List<ScheduleRow> buildScheduleRows(List<SessionEvent> events, DateTime today) {
  final numbers = assignSequenceNumbers(events);
  final chainEvents = events.where((e) => _chainTypes.contains(e.type)).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  final chainRows = _buildChainRows(chainEvents, numbers, today)
      .where((row) => _isVisibleOnScheduleScreen(row.event!, numbers))
      .toList();

  final merged = [...chainRows, ..._crRows(events, today)]
    ..sort((a, b) => a.date.compareTo(b.date));
  return _withTodayMarker(merged, today);
}

bool _isVisibleOnScheduleScreen(SessionEvent event, Map<String, int> numbers) {
  if (event.type == SessionEventType.completion) return true;
  if (event.type == SessionEventType.weekend && numbers[event.id] == 1) {
    return true;
  }
  return event.visible;
}
```

`_crRows` は変更しない（CRに`visible`は適用しない）。

## `session_event_controller.dart` の変更

新設メソッド:

```dart
Future<void> setVisible(String id, {required bool visible}) {
  return _mutate((events) => [
    for (final e in events)
      if (e.id == id)
        SessionEvent(id: e.id, type: e.type, date: e.date, visible: visible)
      else
        e,
  ]);
}
```

## 画面分割

### `lib/features/schedule/session_schedule_screen.dart`（既存ファイルを縮小）

- `_AddEventForm` と `_deleteButton`（行の×ボタン）を削除。
- 代わりに画面上部に「日程設定」への `IconButton`（`Icons.settings_outlined`
  等）を設置し、`SessionScheduleSettingsScreen` へ `Navigator.push`。
- `_ScheduleTable`（週末間/今日から表示）はそのまま維持。

### `lib/features/schedule/session_schedule_settings_screen.dart`（新設）

- 既存の `_AddEventForm`（型・日付・追加ボタン）をこのファイルに移設、その
  まま流用。
- 全件一覧（`ref.watch(sessionEventControllerProvider)` の生リストを日付順
  にソートしただけの、`buildScheduleRows` を通さないシンプルな一覧。CRも含
  め全件出す）。各行:
  - ラベル（型+番号）。`session_chain.dart`の`_label`を`sessionEventLabel`
    として公開し、`assignSequenceNumbers`の結果と合わせてこのファイルから
    そのまま再利用する（複製すると2画面でWE番号等が食い違うリスクがある
    ため、ロジックは1箇所に保つ）。CRは番号なしで固定 "CR"）
  - 日付
  - 表示/非表示トグル（`Switch`）: OR・2番目以降のWE・WD・SSのみ表示。1WE・
    CS・CRは「常に表示」の静的テキストのみでトグルは出さない。
  - 削除ボタン（×、既存の`_deleteButton`をそのまま移設）

### `lib/features/schedule/session_schedule_entry_button.dart`

変更なし（引き続き `SessionScheduleScreen` を開く）。

## テストへの影響

- `test/features/schedule/session_event_test.dart`: `visible`
  デフォルトtrue・`toJson`が`false`時のみキーを出す・`tryFromJson`の
  round-trip/不正値拒否のテストを追加。
- `test/features/schedule/session_event_controller_test.dart`: `setVisible`
  のユニットテスト追加（id一致のみ更新・永続化されること）。
- `test/features/schedule/session_chain_test.dart`: 非表示イベントが行から
  消えること／1WE・CS・CRは`visible:false`でも消えないこと／非表示でも
  週末間・今日からの日数計算自体は変わらないこと、を追加。
- `test/features/schedule/session_schedule_screen_test.dart`: 既存テスト
  （add/delete系）は新設の設定画面側のテストに移動。このファイルには
  「一覧のみ・追加/削除UIが無いこと」「日程設定への遷移ボタンがあること」
  を残す。
- 新規: `test/features/schedule/session_schedule_settings_screen_test.dart`
  — 追加/削除（移設した既存テストベース）＋表示/非表示トグルの操作テスト
  （トグルOFFにした行が「セッションスケジュール」画面側で消えること、1WE/
  CS/CRにはトグルが無いこと）。

## Verification

- `dart format` / `flutter analyze` / `flutter test` / debug build
- `code-reviewer` サブエージェント + Gemini CLI ローカルレビュー（両方、push
  前に実施するのが原則）。Gemini CLIがクォータ切れの場合は黙ってスキップせ
  ず、その都度ユーザーに確認を取った上でのみ省略する（本PRでは前PR #47と同
  じ理由でクォータ切れ、ユーザーに確認の上でスキップ。PR説明に明記する）
- BlueStacks/実機で: ①「セッションスケジュール」に登録フォーム・削除ボタン
  が無いこと ②「日程設定」で追加・削除・トグル操作ができること ③トグル
  OFFにした行が「セッションスケジュール」側から消え、週末間/今日からの数値
  は変わらないこと ④1WE・CS・CRにはトグルが出ないこと、を目視確認。
