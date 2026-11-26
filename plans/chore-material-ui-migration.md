# 実装計画: material_ui / cupertino_ui への import 移行と CI の Flutter 固定の更新

Issue: #101（親: #1）

## 背景

Flutter 3.47 以降、`package:flutter/material.dart` と `package:flutter/cupertino.dart` が
deprecated になり、実装は `material_ui` / `cupertino_ui` パッケージへ移った。stable が 3.50.1 に
なった時点で `flutter analyze` が34件の `deprecated_member_use` を報告して終了コード1になり、
CI が赤くなった（#98 で発覚）。#99 で CI を 3.47.2 に固定して回避していたが、暫定対応だった。

## 変更内容

### import の移行

- `package:flutter/material.dart` → `package:material_ui/material_ui.dart`（lib 23ファイル、test 8ファイル）
- `package:flutter/cupertino.dart` → `package:cupertino_ui/cupertino_ui.dart`（`timer_section.dart` の
  `CupertinoTimerPicker` / `CupertinoTheme`）
- import の並び順が崩れるため、`dart fix --apply --code=directives_ordering` で整える

### `lib/app.dart`

`GlobalMaterialLocalizations` は `flutter_localizations`（deprecated のまま残存）と `material_ui`
の両方で定義され、両方を import すると名前が曖昧になる。`app.dart` は `flutter_localizations` を
import せず、`material_ui` の `GlobalMaterialLocalizations` を使う。

挙動が変わらないことを、`material_ui` 1.11.1 のソースで確認した。

- `delegates` は旧版と同じ3つ（`GlobalCupertinoLocalizations` / `GlobalMaterialLocalizations` /
  `GlobalWidgetsLocalizations`）
- `isSupported` は `kMaterialSupportedLanguages`（対応言語リスト）で判定する点が同じ。
  `resolveDeviceLocale` のテスト（`test/app_test.dart`）が通る

`pubspec.yaml` の `flutter_localizations` は、直接 import する箇所がなくなったが、
`material_ui` が依存するため宣言はそのまま残す（外すかどうかは別途の整理）。

### `pubspec.yaml` / `pubspec.lock`

- `material_ui: ^1.11.1`、`cupertino_ui: ^1.1.7` を追加
- `environment.sdk` を `^3.12.2` → `^3.13.0` に引き上げ（`material_ui` が Dart ^3.13.0 /
  Flutter >=3.47.0 を要求するため。Flutter 3.47.x は Dart 3.13 を含む）
- `pubspec.lock` は Flutter 3.50.1 で解決し直したもの。新規2パッケージのほか、SDK 制約の変更で
  再解決された推移的な開発ツール類が更新される（`analyzer` 99→111、`_fe_analyzer_shared` 12→14、
  `test` / `test_api` / `test_core` / `matcher` など）。直接依存の更新は含まない

### `.github/workflows/flutter-ci.yml`

固定を完全には外さず、`flutter-version` を 3.47.2 → 3.50.1 に更新する（3か所）。

- 外さない理由: 未固定の `stable` は、無関係なPRのCIを突然赤くする（今回の再発防止）。
  固定したまま、更新は手元で format/analyze/test を通してから意図して行う運用にする
- コメントを、固定の理由・更新の手順・`material_ui` の要求（Flutter 3.47 以上）に書き換える。
  CI が検証するのは固定した 3.50.1 のみで、3.47 は手元での確認にとどまる

## 実装しないこと

- 機能・見た目の変更（import とパッケージ追加のみ。挙動は変えない）。ただし 3.50.1 の
  `dart format` が `lib/core/clock/ntp_sync_controller.dart` の typedef の整形を変えるため、
  CI の format チェックを通すためにその1箇所だけ整形差分が入る
- `material_ui` 以外のパッケージの更新（ロックファイルの変動は SDK 連動分のみ）

## 確認（手元）

Flutter 3.50.1（CI の固定先）と 3.47.2（`material_ui` が要求する最小の系列）の両方で、
次を確認する。

- `dart format --output=none --set-exit-if-changed .`
- `flutter analyze`（指摘0件）
- `flutter test`（393件）

## リスクと確認が必要な点

- Android / iOS のネイティブビルド: これまでの CI は analyze で止まって 3.50.1 でのビルドに
  到達していない。Gradle / AGP / Xcode 側が 3.50 に追従できているかは、CI の
  `Build Android (debug)` / `Build iOS (no codesign)` で確認する（環境に Android SDK がなく手元では不可）
- 実機・エミュレータでの見た目（`material_ui` に移っても `ThemeData` などの描画が変わらないか）
