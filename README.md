# session-timer-app

セミナー／教育プログラムの運営者が、セッションを時間どおりに終わらせるために使うタイムマネジメント用スマホアプリ（Flutter製、Android / iOS対応）。

詳細な機能仕様は [docs/session-timer-spec.md](docs/session-timer-spec.md) を参照。UI設計の参考実装（HTMLプロトタイプ）は [docs/session-timer.html](docs/session-timer.html)。

## 技術スタック

- Flutter (Dart)
- 状態管理: Riverpod
- 永続化: shared_preferences
- ローカル通知: flutter_local_notifications
- ホーム画面ウィジェット（Android）: home_widget

採用理由は [plans/chore-bootstrap-project.md](plans/chore-bootstrap-project.md) を参照。

## セットアップ

```bash
flutter pub get
```

### 動作確認

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug
```

iOSビルドはmacOS環境（またはCI）でのみ確認可能。

### リリース署名（Android）

Play Storeへの配布に使う release ビルドは、専用の upload keystore で署名する。
`android/key.properties`（gitignore対象・リポジトリにはコミットしない）が
存在しない場合は自動的に debug 署名にフォールバックするため、keystoreを
持たない開発者も通常の開発・CIには影響しない。

セットアップ手順:

1. リポジトリ外の安全な場所に upload keystore を生成する

   ```bash
   keytool -genkeypair -v -keystore /path/to/upload-keystore.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

2. `android/key.properties.example` を参考に `android/key.properties` を作成し、
   `storePassword`・`keyPassword`・`keyAlias`・`storeFile`の4項目を記入する
   （いずれか不足・不一致があるとrelease buildが失敗する）
3. パスワードは直ちにパスワードマネージャー等の安全な場所に保管する
4. `flutter build apk --release` / `flutter build appbundle --release` で
   署名済みビルドを生成できる

Play App Signing を利用する前提のため、upload keyを紛失してもPlay Console側で
リセット申請が可能（実際の配布用署名鍵はGoogle側で別管理される）。

## ディレクトリ構成

機能ごとにIssue単位で段階的に構築する（`plans/`参照）。現時点で実装済みなのは`clock/`・`core/theme/`・`completion/`・`targets/`・`stopwatch/`・`timer/`・`flash/`・`notifications/`・`settings/`（フラッシュポイントの追加/削除・フラッシュ/通知トグル・NTP時刻同期）・`schedule/`（セッションスケジュール管理・週末間日数計算）・`home_widget/`（Androidホーム画面ウィジェットへのデータ同期、Android向けのみ）。

```text
lib/
  main.dart
  app.dart
  core/          # 時刻計算・永続化・通知・wakelockなどの横断的ユーティリティ
  features/
    clock/       # 現在時刻表示
    completion/  # 完了時刻カウントダウン
    targets/     # 指定時刻リスト
    stopwatch/   # ストップウォッチ
    timer/       # 単独カウントダウンタイマー
    flash/       # フラッシュ演出・キューイング
    notifications/ # フラッシュポイントの端末通知スケジューリング
    settings/    # 設定シート（フラッシュポイント・通知・NTP）
    schedule/    # セッションスケジュール管理（OR/WE/WD/CR/SS/CS・週末間日数計算）
    home_widget/ # Androidホーム画面ウィジェット（7種）へのデータ同期
test/            # libと同じfeature構成でミラーリング

android/app/src/main/kotlin/com/iq3run/session_timer/
  StopwatchWidgetProvider.kt              # 経過時間ウィジェット（開始/一時停止・リセットボタン付き）
  NextTargetWidgetProvider.kt             # 次の指定時刻までの残り時間ウィジェット
  CompletionCountdownWidgetProvider.kt    # 完了までのカウントダウンウィジェット
  CurrentTimeWidgetProvider.kt            # 現在時刻のみのウィジェット（Flutter同期不要）
  TimerWidgetProvider.kt                  # タイマー残り時間ウィジェット（終了間際に背景が単発点灯）
  TimerControlWidgetProvider.kt           # タイマー操作ウィジェット（開始/+30秒/+1分/リセットボタン付き）
  ScheduleWidgetProvider.kt               # セッションスケジュール一覧ウィジェット（RemoteViewsServiceのListView）
```

7種のAndroidホーム画面ウィジェットはユーザーが個別に追加できる独立したパネル。詳細は [plans/feat-home-widget-android.md](plans/feat-home-widget-android.md) を参照。ストップウォッチウィジェットは開始/一時停止・リセットボタンを持ち、アプリを開かずに操作できる（詳細は [plans/feat-stopwatch-widget-interactive-buttons.md](plans/feat-stopwatch-widget-interactive-buttons.md)）。タイマーウィジェット（表示専用）は残り5/3/1/0分のタイミングで背景を単発（3秒間）琥珀色に切り替える——本体アプリの`FlashOverlay`のストローブ演出をネイティブAlarmManagerで近似したもの（詳細は [plans/feat-timer-widget-display-android.md](plans/feat-timer-widget-display-android.md)）。タイマー操作ウィジェットは開始/+30秒/+1分/リセットの4ボタンでアプリを開かずにタイマーを操作できる（背景の点滅演出は持たない、詳細は [plans/feat-timer-widget-interactive-android.md](plans/feat-timer-widget-interactive-android.md)）。セッションスケジュールウィジェットは「セッションスケジュール」画面と同じ内容（種別・番号・日付、`visible`トグルの絞り込みも同一）を`ListView`でスクロール表示する——既存6種と異なり、可変長リストを扱うため`RemoteViewsService`/`RemoteViewsFactory`を使う唯一のウィジェット（詳細は [plans/feat-schedule-widget-android.md](plans/feat-schedule-widget-android.md)）。

## 開発フロー

機能ごとにIssueを作成し、`plans/`配下にplan fileを作成した上で実装する。実装後はサブエージェント + Gemini + CodeRabbitによるレビューを経てPRをマージする。
