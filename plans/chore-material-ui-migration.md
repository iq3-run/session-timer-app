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

`GlobalMaterialLocalizations` が `flutter_localizations`（deprecated のまま残存）と `material_ui` の
両方で定義され、名前が曖昧になる。`flutter_localizations` 側を `hide GlobalMaterialLocalizations`
して、`material_ui` 側を使う。

### `pubspec.yaml` / `pubspec.lock`

- `material_ui: ^1.11.1`、`cupertino_ui: ^1.1.7` を追加
- `environment.sdk` を `^3.12.2` → `^3.13.0` に引き上げ（`material_ui` が Dart ^3.13.0 /
  Flutter >=3.47.0 を要求するため。下限は Flutter 3.47.x に相当する）
- `pubspec.lock` は Flutter 3.50.1 で解決し直したもの。新規2パッケージのほか、SDK に連動する
  開発ツール（`analyzer` / `test` 系）が更新される

### `.github/workflows/flutter-ci.yml`

固定を完全には外さず、`flutter-version` を 3.47.2 → 3.50.1 に更新する（3か所）。

- 外さない理由: 未固定の `stable` は、無関係なPRのCIを突然赤くする（今回の再発防止）。
  固定したまま、更新は手元で format/analyze/test を通してから意図して行う運用にする
- コメントを、固定の理由・更新の手順・サポート下限（Flutter 3.47）に書き換える

## 実装しないこと

- 機能・見た目の変更（import とパッケージ追加のみ。挙動は変えない）
- `material_ui` 以外のパッケージの更新（ロックファイルの変動は SDK 連動分のみ）

## 確認（手元）

Flutter 3.50.1（CI の固定先）と 3.47.2（サポート下限）の両方で、次を確認する。

- `dart format --output=none --set-exit-if-changed .`
- `flutter analyze`（指摘0件）
- `flutter test`（393件）

## リスクと確認が必要な点

- Android / iOS のネイティブビルド: これまでの CI は analyze で止まって 3.50.1 でのビルドに
  到達していない。Gradle / AGP / Xcode 側が 3.50 に追従できているかは、CI の
  `Build Android (debug)` / `Build iOS (no codesign)` で確認する（環境に Android SDK がなく手元では不可）
- 実機・エミュレータでの見た目（`material_ui` に移っても `ThemeData` などの描画が変わらないか）
