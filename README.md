# session-timer-app

セミナー／教育プログラムの運営者が、セッションを時間どおりに終わらせるために使うタイムマネジメント用スマホアプリ（Flutter製、Android / iOS対応）。

詳細な機能仕様は [docs/session-timer-spec.md](docs/session-timer-spec.md) を参照。UI設計の参考実装（HTMLプロトタイプ）は [docs/session-timer.html](docs/session-timer.html)。

## 技術スタック

- Flutter (Dart)
- 状態管理: Riverpod
- 永続化: shared_preferences
- ローカル通知: flutter_local_notifications
- 画面常時点灯: wakelock_plus

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

## ディレクトリ構成

機能ごとにIssue単位で段階的に構築する（`plans/`参照）。現時点で実装済みなのは`clock/`・`core/theme/`・`completion/`・`targets/`・`stopwatch/`・`timer/`・`flash/`・`notifications/`で、`settings/`は今後のPRで追加される想定の構成。

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
    settings/    # 設定シート（マイルストーン・通知・NTP）
test/            # libと同じfeature構成でミラーリング
```

## 開発フロー

機能ごとにIssueを作成し、`plans/`配下にplan fileを作成した上で実装する。実装後はサブエージェント + Gemini + CodeRabbitによるレビューを経てPRをマージする。
