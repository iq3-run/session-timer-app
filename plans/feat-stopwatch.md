# 実装計画: ストップウォッチ

Issue: #10（親: #1）

## 対象範囲

`docs/session-timer-spec.md` 2章・3-2節・3-9節に基づくストップウォッチの実装。

- タップで開始／一時停止
- 長押しで0にリセットして停止
- ダブルタップで0にリセットして即再スタート（3-2節の新規要件）
- 経過時間は1/10秒まで表示（他の画面表示は1秒間隔のまま。ストップウォッチ表示のみ滑らかに更新し、電池消費とのバランスを取る）
- 計測中／一時停止中いずれの状態もアプリ終了・再起動をまたいで継続する（3-9節）

スコープ外：カウントダウンタイマー（3-1節）、フラッシュ演出・通知・バイブレーション、週末マイルストーン、NTP同期、Wake Lock。

## 状態管理・永続化

`TimeTargetsController`（`lib/features/targets/time_targets_controller.dart`）と同じ、ミューテーション直列化キュー＋`_lastGood`フィールド＋`_initialLoad`Completerのパターンを踏襲する。

`StopwatchState`（`lib/features/stopwatch/stopwatch_state.dart`）:

- `accumulatedMs: int`（一時停止中に確定した累積時間）
- `runningSinceEpochMs: int?`（計測中の場合のみ、その計測区間の開始epoch）
- `isRunning`・`elapsedAt(DateTime now)`（累積＋計測中区間の差分）を算出するgetter

`StopwatchController`（`lib/features/stopwatch/stopwatch_controller.dart`）:

- `toggle()`：計測中なら経過分を`accumulatedMs`に確定して停止、停止中なら`runningSinceEpochMs`を現在epochにセットして開始
- `reset()`：`accumulatedMs=0`・`runningSinceEpochMs=null`（長押し）
- `resetAndRestart()`：`accumulatedMs=0`・`runningSinceEpochMs=現在epoch`（ダブルタップ）

永続化キーは`stopwatch_state_json`（`TimeTargetsController`と同じくJSON文字列を1キーへ保存する方式）。`accumulatedMs`・`runningSinceEpochMs`をそれぞれ独立したキーで書き込むと、片方だけ書き込み成功した場合に新しい累積時間と古い計測開始epochが組み合わさり、次回復元時に同じ区間を二重計上してしまう（PRレビューで指摘・修正）。3-9節の「開始基準epoch＋その時点での累積時間」方式そのもの。再起動時、`runningSinceEpochMs`が保存されていれば計測中状態のまま復元し、経過時間はダウンタイム分も含めて自動的に加算される（実際のストップウォッチと同じ挙動なので、超過リセットのような特別処理は不要）。

## UI

`lib/features/stopwatch/stopwatch_section.dart`：HTMLプロトタイプの`#swWrap`相当。`ClockScreen`（`lib/features/clock/clock_screen.dart`）の`TimeTargetsSection`の下に配置。

- `GestureDetector`の`onTap`/`onDoubleTap`/`onLongPress`をそのまま使う（仕様書3-2節が推奨する「プラットフォーム標準のジェスチャー認識を優先」に従い、自前のpointerdown/upタイマー実装は行わない）
- `onDoubleTap`を併用するとFlutterの標準挙動として`onTap`の発火が約300ms遅延する。これは仕様書3-2節末尾の自前実装フォールバックで言及されている遅延と同種のトレードオフであり許容する
- 経過時間の1/10秒更新は、専用の`StatefulWidget`が計測中のみ`Timer.periodic(100ms)`で`setState`する形にする（Riverpodのグローバルな高頻度ティッカーは使わない＝非計測時や画面外で余計な再描画をしない）
- ラベル表示・ヒントテキストはHTML版を踏襲しつつ、ダブルタップの説明を追加する

`lib/core/clock/duration_format.dart`に`formatElapsedTenths(Duration)`を追加（`fmtHMSTenths`相当。ストップウォッチの経過時間は負値を取らないため符号処理はしない）。

## テスト

`test/features/stopwatch/stopwatch_controller_test.dart`（`time_targets_controller_test.dart`と同構成）:

- 未永続化時はゼロ・停止状態で始まる
- `toggle`で開始→再度`toggle`で一時停止し、`accumulatedMs`に反映される
- `reset`でゼロ・停止状態に戻る
- `resetAndRestart`でゼロから即計測中になる
- 一時停止状態での永続化→再起動後も同じ`accumulatedMs`で復元される
- 計測中状態での永続化→再起動後も計測中のまま復元され、ダウンタイム分を含めて経過時間が増えている
- `await`せずに連続呼び出しても直列化キューにより両方反映される（既存パターンに合わせた回帰防止）
- 永続化失敗時は`AsyncError`になり、次回のミューテーションは成功する

## 動作確認方法

`dart format --set-exit-if-changed .` / `flutter analyze` / `flutter test` / `flutter build apk --debug`。

ジェスチャー操作（タップ/長押し/ダブルタップの実際の反応）は既存のCodeRabbit申し送り事項のとおり自動チェックの対象外のため、実機・エミュレータでの確認が別途必要。
