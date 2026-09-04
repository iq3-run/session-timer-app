# 実装計画: セッションの流れ画面のソート確認と削除ボタンのタップ領域修正

Issue: #90（親: #1）

## 対象

「セッションの流れ、開始時刻順にソートする。削除できるようにする。」という依頼への対応。

## 調査結果（実装前）

- **ソート**: `SessionPlanController._sorted`で既に開始時刻昇順ソートが実装済み（issue #78）。
  バグなし。回帰防止のウィジェットテストを追加するのみ
- **削除**: ロジック自体（`removeSession`・`onPressed`の配線）は正しいが、`_SessionRow`の
  Stackの実質的な高さ（1行テキスト分、約20〜27px）が✕ボタンのMaterial 3最小タップ領域
  （48×48px）より小さく、ボタンの下側がはみ出す。`WidgetTester.tap()`で実際にタップする
  形のウィジェットテストで、ヒットテストが意図した✕ボタンに届かないことを確認した。
  同じパターンの`TimeTargetsSection`の行（実質高さ約50px以上）では再現しないことも確認済み
  （比較用のアドホックテストで検証、コミットはしていない）

## 実装

### 削除ボタンのタップ領域修正（`lib/features/session_plan/session_plan_screen.dart`）

- `_SessionRow`の`Stack`を`SizedBox(height: 48, child: Stack(...))`で包み、✕ボタンの
  最小タップ領域（48px）を行の高さとして確保する
- `key: Key('removeSession_${session.id}')`を✕ボタンに付与する
  （`flash_points_settings_section.dart`の`Key('removeFlashPoint_$m')`と同じ命名規則。
  ウィジェットテストで個別の行を確実に指定してタップできるようにするため）
- 行タップ＝編集の`GestureDetector`を、行全体を覆う形から「✕ボタンの48px幅の右端コーナーを
  除いた領域」に変更する（`Positioned(left:0, top:0, bottom:0, right:48)`）。Stackの
  ヒットテストは重なった全ての子を収集するため（最前面の子だけで止まらない）、
  行全体を覆う編集用GestureDetectorと✕ボタンが幾何学的に重なっていると、✕ボタンを
  タップしたときに編集用GestureDetectorの`onTap`も同時に発火してしまう。実際に
  ウィジェットテストで検証して確認した実バグ（詳細は下記「実装前調査結果」参照）

## 実装前調査結果（詳細）

- ソートは既存実装（`SessionPlanController._sorted`）で正しく動作していることを確認
- 削除ボタン自体の配線（`onPressed`・`removeSession`呼び出し）は元々正しかったが、行の
  高さ不足によりボタンの下側がはみ出し、`WidgetTester.tap()`でのヒットテストが外れる
  問題があった（`SizedBox(height: 48)`で解消）
- 高さ修正後、✕ボタンをタップすると削除自体は成功するが、行全体を覆う編集用
  `GestureDetector`の`onTap`も同時に発火し、`showTimePicker`（編集フロー）が開いてしまう
  実バグを発見した。原因は「Stackのヒットテストは最前面の子だけでなく重なった全ての子を
  収集する」というFlutterの挙動によるもので、祖先/兄弟の木構造を変えるだけでは解決せず、
  タップ領域を幾何学的に重複させないこと（✕ボタンの48px分を編集用領域から除外する）で
  解決した

## 実装しないこと

- `TimeTargetsSection`側の変更（既に十分な高さがあり問題が再現しないため対象外）
- ソートロジック自体の変更（既に正しく動作しているため）

## テスト（`test/features/session_plan/session_plan_screen_test.dart`、新規）

- 開始時刻順に描画されること（永続化・追加順に関わらず）
- ✕ボタンを実際に`WidgetTester.tap()`でタップして、そのセッションだけが削除されること
  （行タップ＝編集のジェスチャーが同時に発火しないことも、`ModalBarrier`が現れないことで確認）
- 複数セッションのうち特定の1件（先頭以外）を削除しても、残りが正しくソート順のまま
  表示されること

## 動作確認方法

`dart format` / `flutter analyze` / `flutter test` / `flutter build apk --debug`
