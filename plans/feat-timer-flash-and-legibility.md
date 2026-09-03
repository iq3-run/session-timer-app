# 実装計画: タイマーのフラッシュタイミング追加とフラッシュ演出時の文字視認性向上

Issue: #83（親: #1）

## 対象

- タイマーのフラッシュに完了30秒前・15秒前・10秒前を追加する（既存の5分前・3分前・1分前は維持）
- `FlashOverlay`を画面最前面の全画面不透明レイヤーから背景レイヤーに変更し、フラッシュ点灯中も
  文字が読めるようにする
- フラッシュ色（アンバー）と同系色の文字（完了カウントダウン・タイマーカウントダウンの数値）に
  黒縁取りを付け、フラッシュ点灯時に背景色と同化して読めなくなるのを防ぐ

## 現状の確認（実装前の調査結果）

- `FlashOverlay`は`ClockScreen`のStackの**最後**（最前面）に置かれており、`Opacity`が1の
  瞬間は画面全体を不透明なアンバー色で覆う。HTMLプロトタイプ（`docs/session-timer.html`）の
  `#flashOverlay{position:fixed;...z-index:50}`も同じ「最前面を覆う」実装で、これは移植時の
  劣化ではなく元々の設計。今回の要件はこの挙動自体を「背景色のみ変更」に変更するもの
- アンバー色（`SessionTimerColors.amber`）を使っている文字は完了カウントダウン
  （`completion_countdown_section.dart`の非超過時）とタイマーカウントダウン
  （`timer_section.dart`の非超過時）の2箇所のみ（`grep`で確認済み）。超過時は赤色になり
  アンバー背景との区別は十分つくため対象外
- ホームウィジェット側には背景色フラッシュ演出自体がまだ存在しないため、今回の視認性改善は
  本体アプリのみが対象（issue #1のチェックリスト通り）

## 実装

### タイマーのフラッシュタイミング追加（`lib/features/flash/flash_event.dart`）

- `timerFlashPointsSeconds = [30, 15, 10]`を新設
- `timerFlashEvents`に、既存の`_exactPlusMinutesBefore`（5/3/1分前＋完了ちょうど）に加えて、
  秒単位のポイントを追加する。既存の`_exactPlusMinutesBefore`のid形式（`timer:{epoch}:{分}`）
  と衝突しないよう、秒指定のイベントのidは`timer:{epoch}:{秒}s`（末尾に`s`）とする
- `_exactPlusMinutesBefore`自体（completion/target/timerの3箇所で共用）は分単位のまま変更
  しない。秒単位の対応はタイマーだけの要件のため、既存のid形式・テストへの影響を避ける

### フラッシュ演出の背景レイヤー化（`lib/features/clock/clock_screen.dart`）

- `Stack`内で`FlashOverlay()`を`Padding`（画面コンテンツ）より**前**に置き、コンテンツの
  背後に描画されるようにする

### 文字視認性（黒縁取り、新規: `lib/features/flash/flash_legible_text.dart`）

- `FlashLegibleText`ウィジェットを新設: 渡された`TextStyle.color`が`SessionTimerColors.amber`
  の場合のみ、黒の縁取り（`Paint()..style=PaintingStyle.stroke`を`foreground`に指定した
  同一テキストを背後に重ねる）を追加する。それ以外の色ではそのまま`Text`と同じ見た目
  （黒背景時は縁取りが黒背景に同化して見えないため、通常時の見た目は変化しない）
- `completion_countdown_section.dart`・`timer_section.dart`の数値表示`Text`を
  `FlashLegibleText`に置き換える

## 実装しないこと

- ホームウィジェットの文字視認性対応（ホームウィジェットに背景色フラッシュ演出自体が無い）
- タイマー終了時刻の表示、ペア/トリオ交代タイミング通知、アナログ時計表示（別要件、issue #1
  のチェックリストに残す）
- 秒単位フラッシュポイントの通知（端末通知）を無効化すること — 既存のtimerFlashEventsは
  フラッシュと通知を同じイベント列で共用する設計（issue #79と同じ前提）のため、追加した
  秒単位ポイントも自動的に通知対象になる。これは既存アーキテクチャの自然な帰結であり、
  今回新たに何かを実装するものではない

## テスト

- `test/features/flash/flash_event_test.dart`: `timerFlashEvents`が30/15/10秒前を返すこと、
  既存の5/3/1分前・完了ちょうどと合わせて計7件になること
- `test/features/flash/flash_legible_text_test.dart`（新規）: アンバー色のときは縁取り用の
  `Text`が追加で存在すること、それ以外の色では単一の`Text`のみであること
- 既存の`flash_queue_controller_test.dart`・`notification_event_source_test.dart`は
  `_exactPlusMinutesBefore`のid形式を変更しないため影響なし（念のため実行して確認）

## 動作確認方法

`dart format` / `flutter analyze` / `flutter test` / `flutter build apk --debug`
