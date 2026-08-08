# 実装計画: プロジェクト基盤構築

Issue: #2 (親: #1)

## 対象

Flutterプロジェクトの雛形作成、CI、markdownlint、CodeRabbit設定、README整備。

## 技術選定

- フレームワーク: Flutter（Dart）。理由はチャットでの検討ログの通り、本仕様書（3-1節等）の状態遷移が精密で、単一コードベースでAndroid/iOSの挙動を一致させやすいことを優先。
- パッケージ名: `com.iq3run.session_timer`（`flutter create --org com.iq3run --project-name session_timer`の既定に従う）
- 状態管理: Riverpod（テスト容易性・DIのしやすさを優先。Providerのみのシンプル構成から開始し、機能追加に応じて必要な分だけ足す）
- 永続化: `shared_preferences`（キーバリューで十分。仕様上必要なのはepochミリ秒やJSON化した小さなリストのみで、SQLite等は過剰）
- 通知: `flutter_local_notifications`（ローカル通知スケジューリング、3-7節のバックグラウンド通知要件に対応）
- 画面常時点灯: `wakelock_plus`
- lint: `flutter create` 既定の `flutter_lints` に加え、CLAUDE.mdのコーディング規約（関数20行以内、DRY等）に近い厳格ルールを持つ `very_good_analysis` を採用

## ディレクトリ構成

```text
lib/
  main.dart
  app.dart
  core/          # 時刻計算・永続化・通知・wakelockなどの横断的ユーティリティ
  features/
    clock/           # 現在時刻表示
    completion/       # 完了時刻カウントダウン
    targets/          # 指定時刻リスト
    stopwatch/
    timer/
    flash/            # フラッシュ演出・キューイング
    settings/         # 設定シート（マイルストーン・通知・NTP）
test/
  （libと同じfeature構成でミラーリング）
```

機能ごとにディレクトリを切るのは、#2以降のIssueが機能単位でPRを分割する前提のため。

## CI

- `.github/workflows/flutter-ci.yml`
  - `dart format --output=none --set-exit-if-changed .`
  - `flutter analyze`
  - `flutter test --coverage`
  - Android: `flutter build apk --debug`（ubuntu-latest、subosito/flutter-action使用）
  - iOS: `flutter build ios --no-codesign`（macos-latest。本機はWindowsのためローカルでiOSビルド確認ができず、CIが唯一の検証手段）
- `.github/workflows/markdown-lint.yml`: GRIMOIRE-CODEリポジトリの設定を踏襲（DavidAnson/markdownlint-cli2-action）

## markdownlint

GRIMOIRE-CODEの `.markdownlint.yaml`（MD013, MD029無効化）をベースに、このリポジトリの実態に合わせて調整する。

## CodeRabbit

`.coderabbit.yaml` を追加。GitHub App自体のインストールはOAuthフローが必要なためユーザーに依頼する（PRコメントで案内）。パブリックリポジトリのため無料プランで利用可能。

## 実装しないこと

- 実際のセッションタイマー機能（#3以降で対応）
- CIでのAndroid実機/エミュレータテスト、iOSシミュレータテスト（現時点ではビルド確認のみ。widget testはローカル/CIのユニットレベルで行う）
- Fastlane等のリリース自動化（将来必要になれば別Issueで検討）

## テスト

雛形段階のため機能テストはなし。`flutter test` がプレースホルダのwidgetテスト（`flutter create`既定生成分は仕様に合わないため差し替え、アプリ起動がクラッシュしないことを確認する最小限のsmoke testに置換）で通ることを確認する。

## 動作確認方法

- `flutter analyze`
- `dart format --output=none --set-exit-if-changed .`
- `flutter test`
- `flutter build apk --debug`（ローカルのAndroid SDKで確認）
- CI（GitHub Actions）が緑になることを確認
