# Feat: WE/WD/SS番号の自由入力

Issue: <https://github.com/iq3-run/session-timer-app/issues/50>

## Scope（2026-08-12、ユーザーとの事前確認事項）

3点要望のうち3点目。issue #48（画面分割）に乗る形で実装する。

- 「日程設定」の追加フォームに任意の番号入力欄を追加する。
  - 空欄なら現在通り自動採番（日付順、`assignSequenceNumbers`）。
  - 入力すればその番号で表示を上書きする。
  - **他のイベントの自動採番には影響しない**（純粋にそのイベント自身の表
    示上書き。重複・欠番のチェックや整合性調整は行わない）。
- 「日程設定」の一覧から、既存イベントの番号をタップして後編集できるよう
  にする。
- 対象はWE/WD/SSのみ（OR/CR/CSは番号を持たないため対象外）。1WE（最初の
  WE）も対象に含む——手動上書きは表示だけの話であり、issue #48の「1WEは
  常に表示」ルール（`_isVisibleOnScheduleScreen`/`_hasVisibilityToggle`の
  `numbers[event.id] == 1`判定）や3日間仕様（`isFirstWeekend`）には一切
  影響しない。これらは引き続き自動採番の結果だけを見る。

## `SessionEvent` の変更

`manualNumber: int?`（デフォルトnull、永続化対象、nullのときJSONキー省略）
を追加。`visible`と異なり本質的にnullableなフィールドなので、JSON上の明示
的な`null`は「キー欠落」と同じ扱い（許容）——`TimerState.targetEpochMs`と
同じパターン。0以下の値は不正データとして拒否。

## `session_chain.dart` の変更

`sessionEventLabel`: `numbers[event.id]`の代わりに
`event.manualNumber ?? numbers[event.id]`を使う。それ以外（
`_isVisibleOnScheduleScreen`・`_buildChainRows`の`isFirstWeekend`判定・
gap計算）は`numbers`（自動採番の結果）をそのまま使い続け、一切変更しない。

## `SessionEventController` の変更

- `addEvent(type, date, {int? manualNumber})` — 追加時に上書き番号を指定
  できるように拡張。
- 新設 `setManualNumber(String id, int? manualNumber)` — 既存イベントの
  上書き番号を設定/解除（`null`で解除）。
- 共通化: `setVisible`/`setManualNumber`が同じ「id一致で1件だけ差し替え
  る」ロジックを重複させないよう、`_replaceEvent`ヘルパーを追加。

## UI: `session_schedule_settings_screen.dart`

- 追加フォーム: 選択中の型がWE/WD/SS（`_numberedTypes`）のときだけ、日付
  行の下に番号入力欄（`TextField`, `key: scheduleManualNumberField`）を表
  示する。空欄なら自動、数値以外や0以下を入力すると追加ボタンを無効化す
  る。
- 一覧行: WE/WD/SSの番号ラベル部分を`GestureDetector`でタップ可能にし
  （`key: editNumber_<id>`）、`_ManualNumberDialog`（`TextField`+保存/
  キャンセル）を開く。保存時に`setManualNumber`を呼ぶ。空欄で保存すれば
  自動採番に戻る。無効な値（数値以外・0以下）では保存ボタンを無効化する
  （追加フォームと同じ検証ロジック）。

## テストへの影響

- `test/features/schedule/session_event_test.dart`: `manualNumber`の
  デフォルトnull・`toJson`が非null時のみキーを出す・`tryFromJson`の
  round-trip（null含む）・0以下や非int値の拒否のテストを追加。
- `test/features/schedule/session_event_controller_test.dart`:
  `addEvent`に`manualNumber`を渡すテスト、`setManualNumber`のユニットテ
  スト（設定・解除・id不一致でno-op）を追加。
- `test/features/schedule/session_chain_test.dart`:
  `sessionEventLabel`が`manualNumber`を優先すること、`manualNumber`が
  「1WEは常に表示」判定や`chainGap`に影響しないことを追加。
- `test/features/schedule/session_schedule_settings_screen_test.dart`:
  追加フォームの番号欄がWE/WD/SS選択時のみ出ること、無効な値で追加ボタン
  が無効化されること、一覧の番号タップで編集ダイアログが開き保存で反映
  されること、OR/CR/CSでは番号タップができないことを追加。

## Verification

- `dart format` / `flutter analyze` / `flutter test` / debug build
- `code-reviewer` サブエージェント + Gemini CLI ローカルレビュー（両方、push
  前に実施するのが原則）。Gemini CLIがクォータ切れの場合は黙ってスキップせ
  ず、その都度ユーザーに確認を取った上でのみ省略する
- BlueStacks/実機で: ①追加フォームでWE選択時のみ番号欄が出ること ②番号
  を指定して追加すると指定した番号でラベル表示されること ③一覧の番号を
  タップして編集・自動に戻せること ④OR/CR/CSには番号編集の導線が無いこ
  と、を目視確認。
