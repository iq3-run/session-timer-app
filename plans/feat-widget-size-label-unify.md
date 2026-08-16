# Feat: ホーム画面ウィジェット4種のサイズ統一・ピッカー名称改善

Issue: <https://github.com/iq3-run/session-timer-app/issues/61>

## Scope (confirmed with the user before starting)

- 既存4種のホーム画面ウィジェット（ストップウォッチ経過時間 / 次ターゲット
  残り時間 / 完了までのカウントダウン / 現在時刻）を、Androidの標準セル計算
  （API 31+）で**縦1×横2セル相当**として扱われるようにする。
- ウィジェットピッカー（長押しでウィジェット追加する画面）上で、4つとも
  「session_timer」としてしか区別できない現状を解消し、機能がひと目で
  わかる名称・説明文を表示する。

## 実機確認で得た前提（#54のクローズ時に判明）

- 実機（BlueStacks + Nova Launcher、`adb shell wm size 1080x1920` で
  ポートレート比率をエミュレート）で確認したところ、現状の
  `minWidth="110dp"` `minHeight="90dp"`（`minWidth`/`minHeight`のみの
  指定）では、**縦画面ホームでは各ウィジェットのセルが横幅に対して
  縦に約1.5倍間延びする**（本issueの技術方針で指摘されている通りの現象を
  実機で再現・確認済み）。文字の見切れやクラッシュは発生しない。
- 一方、横画面ホームでは現状の90dpで2行表示（ラベル+値）が問題なく収まる
  ことを確認済み。
- **重要**：この実機確認に使用したBlueStacksのゲストOSは Android 9
  （API 28、`adb shell getprop ro.build.version.sdk` で確認）であり、
  `targetCellWidth`/`targetCellHeight`（API 31+で追加）を解釈しない
  環境である。そのため上記の間延びは、Nova Launcherが本属性に
  対応していないかどうかとは無関係に、**`minWidth`/`minHeight`
  フォールバック経路そのものの挙動**である。API 31+ホストでの
  `targetCellWidth`/`targetCellHeight`経路（対応ホストではこちらが
  デフォルトサイズを決定する）は本PRでは実機未確認 —
  テスト・検証方針の節に追記する。

## 実装方針

1. **`*_widget_info.xml`（4ファイル）に `android:targetCellWidth="2"`
   `android:targetCellHeight="1"` を追加する（API 31+）。**
   - `minWidth`/`minHeight` は現行値（`110dp`/`90dp`）を**維持**する。
     issue本文の提案例（`minHeight=40dp`、1セル分の標準式
     `70dp*1-30dp`）は採用しない。公式ドキュメント通りの役割分担は
     次の通り：`targetCellWidth`/`targetCellHeight`対応ホスト
     （API 31+）ではこれらがデフォルトサイズを**決定**し、
     Android 11（API 30）以下または非対応ホストでは`minWidth`/
     `minHeight`が**そのままデフォルトサイズとして使われる**
     （フォールバックではなく、それが唯一の経路）。`90dp`は
     PR #55/#58 のレビューで見切れ問題を修正した結果の値であり、
     API30以下・非対応ホストでは`40dp`に下げると見切れが再発する
     リスクがあるため、`90dp`を維持する。API31+対応ホストでは
     `targetCellWidth`/`targetCellHeight`が優先されるため、
     `minHeight`の値自体は影響しない（`90dp`を維持しても1×2セル化の
     効果は損なわれない）。
   - `android:description` を追加し（API 31+、Android 12+ ピッカーで
     表示される説明文）、各ウィジェットの機能を簡潔に説明する文字列
     リソースを新設する。
2. **`AndroidManifest.xml` の4つの `<receiver>` に `android:label` を
   追加し**、ウィジェットピッカー上の表示名を機能別にする（現状は
   `android:label` 未指定でアプリ名「session_timer」にフォールバック
   している）。ラベルは「セッションタイマー：〇〇」形式とし、issue本文の
   例に合わせる。
3. **新規文字列リソース（`strings.xml`）** — ピッカー用のラベルと説明文。
   既存の `home_widget_label_*`（ウィジェット内表示用）はそのまま流用し、
   混同しないよう別名で追加する：
   - `widget_picker_label_stopwatch` / `_next_target` / `_completion` /
     `_current_time`
   - `widget_picker_description_stopwatch` / `_next_target` /
     `_completion` / `_current_time`

## Out of scope（将来検討）

- **横画面ホーム向けの `layout-land/` レイアウト分岐**
  （ラベルと値を横並び1行にして、横長で背の低いセルでも折り返し無しで
  収まるようにする案）。`RemoteViews`が参照するレイアウトリソースは
  ホスト（ランチャー）プロセスの現在の設定に応じて動的に解決されるため、
  `AppWidgetProviderInfo`側の属性（`minWidth`/`minHeight`など）を
  向き別に変えるより技術的に信頼できる。ただし今回の実機確認では横画面での
  見切れは未確認（仮説段階）であり、本issueのスコープ（セル統一・
  ピッカー名称）とは別の改修になるため、別issueとして提案可能な状態に
  しておく。
- **`res/xml-land/*_widget_info.xml` による横画面向け `minWidth`/
  `minHeight`/`targetCellWidth`/`targetCellHeight` の別定義**。
  リソース修飾子自体は技術的に可能だが、`AppWidgetProviderInfo`メタデータは
  ウィジェットの登録・再バインドのタイミングでしか読み直されない実装が
  多く、既に配置済みのウィジェットが端末回転にリアルタイム追従する保証が
  ない。上記の`layout-land/`案（RemoteViewsレイアウトの出し分け）の方が
  実用上信頼できるため、こちらを優先候補としつつ、`xml-land/`側も
  将来issueの選択肢として記録しておく。
- 縦画面ホームでの間延び自体の解消（API 30以下・`targetCellHeight`
  非対応ホストでの挙動改善を含む）。

## テスト・検証方針

- `dart format --set-exit-if-changed .` / `flutter analyze` / `flutter test`
  （Dartコード変更なしのため影響なし想定だが、既存テストの回帰がないことを
  確認）。
- `flutter build apk --debug`（`targetCellWidth`/`targetCellHeight`
  属性がAAPTでビルドエラーにならないことを確認。`compileSdk`の解決値は
  `targetSdk`からの逆算ではなく、ビルド済みAPKを
  `aapt dump badging app-debug.apk` で直接確認し、
  `compileSdkVersion='36'` であることを実測済み。API31+属性の解決可能性は
  この実測値で担保している）。
- 実機（BlueStacks + Nova Launcher、ゲストOS Android 9 / API 28）で
  以下を確認：
  - ウィジェットピッカー上で4つが機能別の名称・説明文で表示されること
  - 横画面ホームで4つを配置し、レイアウト崩れがないこと（既存動作の
    回帰確認）
  - 可能であれば縦画面（`adb shell wm size` オーバーライド）でも
    間延びの程度に変化がないか参考確認（「悪化していないこと」の
    確認に留める）
  - **このテスト環境はAPI 28のため、`minWidth`/`minHeight`
    フォールバック経路（Android 11/API 30以下・非対応ホストが使う経路）
    の確認に該当する。** `targetCellWidth`/`targetCellHeight`が実際に
    優先される API 31+ 対応ホストでの実機確認（例：Android 12+ の
    実機・エミュレータ）は本PRでは未実施 — 将来、API 31+ の実機/
    エミュレータ環境が確保できた際に確認する（テスト環境の制約による
    既知の未検証事項として記録）。
