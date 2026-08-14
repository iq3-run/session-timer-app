# Feat: 日程設定画面のピッカー改善（ロケール対応・日付編集・1行化）

Issue: <https://github.com/iq3-run/session-timer-app/issues/52>

## Scope（`docs/20260812_追加仕様.txt` 準拠、2026-08-14）

1. カレンダーピッカー（`showDatePicker`）が端末と同じロケールになるように
   する。困難な場合は日本語固定でよい。
2. 「日程設定」の一覧から、既存イベントの日付を編集できるようにする。編集
   時のピッカーは、現在設定されている日付が初期選択された状態で開く。
3. 追加フォームの「番号」「WE等の種別プルダウン」「日付選択」「追加」を
   1行にまとめる（現状は番号欄だけ2行目に落ちている）。

## 1. ロケール対応（`lib/app.dart`）

- `flutter_localizations`（SDK依存）を追加。
- `MaterialApp` に `localizationsDelegates: GlobalMaterialLocalizations.delegates`
  と `supportedLocales` を追加。
- 端末ロケールへの追従は `localeListResolutionCallback` で行う：端末の優先
  ロケール列を順に見て `GlobalMaterialLocalizations.delegate.isSupported`
  （flutter_localizationsが翻訳を同梱している言語かどうか）に最初に一致した
  ものを採用し、どれも該当しなければ `Locale('ja')` に固定する。
  `supportedLocales` はこのコールバックがある限り解決結果を制限しないが、
  宣言として `[Locale('ja'), Locale('en')]` を設定する。
- これは `showDatePicker` だけでなく、アプリ内の他のMaterialピッカー/ダイ
  アログの文言にも同様に効く（既存の日本語ハードコードのUI文言自体は変更
  しない——影響は`MaterialLocalizations`が提供する部品のみ）。

## 2. 既存日程の日付編集（`session_schedule_settings_screen.dart` / `session_event_controller.dart`）

- `SessionEventController` に `setManualNumber` と同じ形の
  `setDate(String id, DateTime date)` を追加（`_replaceEvent`を再利用、
  id不一致はno-op）。
- `_EventRow` の日付表示 `Text` を `InkWell`（`key: editDate_<id>`）でラップ
  し、タップで `showDatePicker(initialDate: event.date, ...)` を開く。選択
  されたら `setDate` を呼ぶ。番号編集（`editNumber_<id>`）と同じ「タップで
  即編集」パターンに揃える——確認ダイアログは挟まない。
- 対象は全イベント種別（OR/WE/WD/CR/SS/CS）。番号と異なり日付の編集に型に
  よる制限はない。
- ついでに、追加フォーム自身の日付ボタン（まだ登録前の一時選択）も、既に
  日付を選んだ状態で再度タップした場合は `initialDate` をその選択済みの日
  付にする（現状は常に `DateTime.now()`）。「編集時のピッカーは設定されて
  いる日付が初期状態」という同じ原則を、確定前の一時選択にも一貫させる小
  さな追従修正。

## 3. 追加フォームの1行化（`_AddEventForm`）

- 現状: 1行目に `[種別プルダウン, 日付ボタン, 追加ボタン]`、2行目に（WE/WD/
  SS選択時のみ）番号入力欄。
- 変更後: 1行に `[番号入力欄（該当型のときのみ）, 種別プルダウン, 日付ボタ
  ン, 追加ボタン]` を並べる。番号欄は固定幅の `SizedBox`、プルダウンは
  引き続き `Expanded` で残りの幅を吸収する。
- 番号欄が横に収まるよう、ラベルを現状の「番号（空欄なら自動採番）」から
  短い「番号」に変更（キーは不変、既存テストは文言でなくキーで検証してい
  るため影響なし）。
- プルダウンの選択中ラベル（`_typeNames`、例:
  「オリエンテーション(OR)」）が長いため、番号欄の分だけ幅が狭くなること
  でのオーバーフローを避けるため、項目の `Text` に
  `overflow: TextOverflow.ellipsis` を付与する。

## テストへの影響

- `test/features/schedule/session_event_controller_test.dart`: `setDate`
  のユニットテスト（更新される・id不一致でno-op）を追加。
- `test/features/schedule/session_schedule_settings_screen_test.dart`:
  一覧行の日付タップで編集ピッカーが開き、選択すると日付が更新されること
  を追加。既存の `_pickDateAndAdd` ヘルパー（`find.text('OK')`）はこのテ
  ストファイルが独自の `MaterialApp`（`app.dart`を経由しない）を使ってい
  るため、ロケール変更の影響を受けず無改修で通る想定。
- 新規 `test/app_test.dart`: `_resolveLocale`
  （テスト用に`@visibleForTesting`で公開）が、サポート対象ロケールを優先
  リストの先頭から探して採用すること、どれも対象外なら`ja`にフォールバッ
  クすることを検証。

## Verification

- `dart format` / `flutter analyze` / `flutter test` / debug build
- `code-reviewer` サブエージェント + Gemini CLI ローカルレビュー（push前）
- BlueStacks/実機で: ①端末ロケールに応じてピッカーの文言が変わること（また
  は日本語固定になっていること） ②一覧の日付をタップして編集し、ピッカー
  が現在の日付から開くこと ③追加フォームが1行に収まり、種別を切り替えても
  レイアウトが崩れないことを目視確認。
