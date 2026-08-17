# feat: リリース署名（release signing）設定を追加

- Issue: #76
- 作成日: 2026-08-18 JST

## 背景

Play Store（まずはクローズドテスト）への配布に向けた最初のステップとして、
Android release ビルドを正式な upload key で署名できるようにする。

現状 `android/app/build.gradle.kts` は Flutter プロジェクト生成時のテンプレートの
ままで、release ビルドでも debug 鍵を使っている:

```kotlin
buildTypes {
    release {
        // TODO: Add your own signing config for the release build.
        // Signing with the debug keys for now, so `flutter run --release` works.
        signingConfig = signingConfigs.getByName("debug")
        ...
    }
}
```

## スコープ

含む:

- upload keystore の生成（リポジトリにはコミットしない。ローカル環境にのみ保存）
- `android/key.properties`（gitignore済み・既存の `.gitignore` に元々エントリあり）
  に鍵情報を置く運用への変更
- `android/app/build.gradle.kts` に release 用 `signingConfig` を追加
- `android/key.properties.example`（実値を含まないテンプレート）をコミット
- README への「リリース署名のローカルセットアップ」手順の追記

含まない（スコープ外）:

- Play Console でのアプリ登録・クローズドテストのトラック設定（Googleアカウントでの
  手動作業のため対象外。ユーザー自身が実施）
- 課金による機能開放の実装（将来検討事項として別issue）

## 実装方針

Flutter公式の recommended パターン（<https://docs.flutter.dev/deployment/android#configure-signing-in-gradle>）に従う:

1. `android/app/build.gradle.kts` の先頭で `key.properties` を読み込む
   （存在しない場合は空の `Properties()` のまま進める）
2. `signingConfigs` に `release` を追加し、`key.properties` の値
   （`keyAlias` / `keyPassword` / `storeFile` / `storePassword`）を割り当てる
3. `buildTypes.release.signingConfig` を、`key.properties` が存在すれば
   `signingConfigs.getByName("release")`、存在しなければ従来通り
   `signingConfigs.getByName("debug")` にフォールバックする
   - 理由: CI（`.github/workflows/flutter-ci.yml`）は debug APK のみビルドしており
     release ビルドは実行しないが、keystore を持たない他の開発者が
     `flutter build apk --release` 等をローカルで叩いても壊れないようにするため
4. `android/key.properties.example` を新規作成し、必要なキーのみ記載（実値なし）
5. README にローカルでの release 署名セットアップ手順を追記
   （`key.properties` の作成方法、keystore生成コマンド例、Play App Signingとの関係）

## 生成物の扱い（重要・機密情報）

- upload keystore ファイル（`.jks`）と `key.properties` はこの PR には含めない
  （`.gitignore` に既存エントリ `key.properties` / `**/*.keystore` / `**/*.jks` あり）
- keystore のパスワードは、生成した値をユーザー自身のパスワードマネージャー等に
  保存してもらうため、この実装作業中に一度だけチャット上で提示する
  （他に安全に伝達する手段がないための一回限りの措置であり、継続的な運用として
  今後も繰り返す手順ではない）。提示後はユーザー側で直ちに保管すること
- keystore ファイル自体もリポジトリ外の安全な場所（ホームディレクトリ配下等）に
  保管する
- Play App Signing を利用する前提のため、upload key を万が一紛失しても
  Play Console 側でリセット申請が可能（Google側の署名鍵は別管理）

## テスト

- `dart format` / `flutter analyze` / `flutter test`
- `key.properties` を実際に作成した状態で `flutter build apk --release` が
  成功し、生成された APK が debug 署名ではなく新しい release 鍵で
  署名されていることを `apksigner` 等で確認
- `key.properties` を一時的に退避した状態（未生成のユーザーを想定）でも
  `flutter build apk --release` が成功し、フォールバック先の debug 署名で
  出力されることを確認（変更対象は `buildTypes.release` のため、
  `--debug` ビルドの成功確認だけでは検証できない）
