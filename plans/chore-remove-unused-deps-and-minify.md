# Chore: 未使用ライブラリの除去とAndroidリリースビルドの縮小

Issue: <https://github.com/iq3-run/session-timer-app/issues/57>

## Scope (confirmed with the user before starting)

- `pubspec.yaml` から未使用の依存を削除する:
  - `cupertino_icons`（`lib/` 内で import 0件）
  - `wakelock_plus`（`lib/` 内で import 0件。bootstrap時に追加されたが未実装）
- `android/app/build.gradle.kts` の `release` buildType で R8 の
  `minifyEnabled` / `shrinkResources` を有効化する。

## Out of scope

- `--split-per-abi` でのビルド分割（別途検討、issueに明記済み）
- iOS向けの縮小設定（本プロジェクトはAndroidのみ対応）

## 調査結果

- 全依存について `grep -rl "import 'package:<name>" lib/` で使用箇所を確認。
  `cupertino_icons` と `wakelock_plus` のみ使用箇所0件。他は全て使用あり。
- `android/app/build.gradle.kts` の `release` buildType は現状
  `signingConfig` の指定のみで、`minifyEnabled` / `shrinkResources` は
  未設定（デフォルトで無効）。
- Dartコード自体はreleaseビルドで自動的にtree-shakingされるため、
  使用中の依存については追加対応不要。ネイティブプラグインのコードは
  Dartの使用有無に関わらず `GeneratedPluginRegistrant` 経由で
  バンドルされるため、未使用依存の削除がAPKサイズに直接効く。

## 実装方針

1. `flutter pub remove cupertino_icons wakelock_plus`
2. `android/app/build.gradle.kts` の `release` buildType に
   `isMinifyEnabled = true` / `isShrinkResources = true` を追加。
   本プロジェクトはFlutterプラグイン中心でカスタムReflectionは
   使っていないため、Flutter Gradle Pluginが提供するデフォルトの
   ProGuardルールで足りる見込み。ただし有効化後に
   `flutter build apk --release` が成功し、実機/エミュレータで
   通知・ホームウィジェット同期・NTP同期など主要機能が壊れていないことを
   確認する。
3. `flutter build apk --release` を実行し、ビルド成功とAPKサイズの
   変化を確認する。

## 確認事項（レビュー時に見てほしい点）

- R8有効化によって `flutter_local_notifications` や `home_widget` の
  プラットフォームチャンネル呼び出しが壊れていないか（reflectionベースの
  処理があると難読化で壊れることがあるため）。
- 実機ビルドでの動作確認は本セッションでは行っていない
  （既存の `Home-widget Android follow-ups` メモにある通り
  実機/エミュレータでの検証環境が未整備のため）。マージ前に手動確認を推奨。
