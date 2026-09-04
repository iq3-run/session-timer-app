# 実装計画: セッションの流れ画面のフォント・ボタン配色をセッションスケジュール画面に合わせる

Issue: #88（親: #1）

## 対象

- `SessionPlanScreen`のセッション一覧行・「＋ セッションを追加」行のフォントを
  `SessionScheduleScreen`と揃える（サイズ・色）
- 「現在のセッションを設定」ボタンを黄色（アンバー）にする

## 現状の確認（実装前の調査結果）

- `SessionScheduleScreen`の`_ScheduleTable`（`DataTable`）のセルは明示的な`fontSize`を
  一切指定していない。`DataTable`はデフォルトで`Theme.of(context).textTheme.bodyMedium`
  （Material 3標準サイズ）を使う。アプリの`SessionTimerTheme.dark`は
  `textTheme: TextTheme(bodyMedium: TextStyle(color: SessionTimerColors.white))`で
  色だけを白にオーバーライドしている（サイズは指定なし＝Material標準のまま）
- `SessionPlanScreen`の`_rowTextStyle`（Issue #86で追加）は`TextStyle(color: muted, fontSize: 18)`
  という独自のハードコード値になっており、セッションスケジュール画面とは揃っていない
- アプリ内の他の主要アクションボタン（設定シート・タイマー設定・スケジュール設定など）は
  すべて`FilledButton`を使っている。Material 3の`FilledButton`は背景に
  `colorScheme.primary`（このアプリでは`SessionTimerColors.amber`）を使うため、
  自動的に黄色いボタンになる。`SessionPlanScreen`の「現在のセッションを設定」だけ
  `ElevatedButton`（背景はデフォルトで`colorScheme.surface`）を使っており、黄色くならない

## 実装

- `session_plan_screen.dart`の`_rowTextStyle`（ファイルスコープの`const`）を廃止し、
  `BuildContext`から`Theme.of(context).textTheme.bodyMedium!`を直接使うようにする
  （セッションスケジュール画面のセルと同じスタイルソースを参照することで、サイズ・色とも
  常に一致し続ける。ハードコードした数値の重複を避ける）
- `_SetCurrentSessionButton`の`ElevatedButton`を`FilledButton`に置き換える
  （他画面の主要アクションボタンと同じウィジェットにするだけで、テーマの
  `colorScheme.primary`＝アンバーが自動適用される）

## 実装しないこと

- `SessionTimerTheme`・共有の`SessionTimerTextStyles`自体の変更（他画面への影響を避ける）
- `colorScheme`のカスタマイズ（`FilledButton`への統一だけで黄色になるため不要）

## テスト

- 既存の`session_plan_screen.dart`にウィジェットテストが無いため（前例踏襲）、
  今回もフォント・ボタン配色の変更は目視確認のみとする
- `flutter analyze`・既存テストスイートで型・回帰の確認のみ行う

## 動作確認方法

`dart format` / `flutter analyze` / `flutter test` / `flutter build apk --debug`
