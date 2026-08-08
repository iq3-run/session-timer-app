# 実装計画: 起動時ロード完了前のミューテーションによるデータ損失の修正

Issue: #8（親: #1）

## 対象

PR #7（指定時刻リスト、マージ済み）で追加した`_mutate`直列化キューについて、ユーザー依頼によりマージ後にGeminiで再レビューを実施した結果発見したバグの修正。

## 原因

`TimeTargetsController._mutateNow`が`state.value ?? const []`を読んでいた。`build()`が`SharedPreferences.getInstance()`の完了待ちの間（`state`がまだ`AsyncLoading`）に`addTarget`等が呼ばれると、`state.value`は`null`となり空リストにフォールバックする。その空リストに新規1件を足しただけの結果を`_persist`でディスクへ書き込むため、既存の永続化データが失われる。`build()`側の`if (state.hasValue) return state.value!;`ガードにより、この損失は`build()`完了後も気づかれない。

## 修正内容

`_mutateNow`で`state.value`の代わりに`AsyncNotifier`が提供する`future`ゲッター（`state`が最初にAsyncLoadingでなくなった値を待つ）を使う。`_mutate`によるミューテーションは既に直列化されているため、`await future`は実質的にbuild()の完了（またはそれ以前に直列化された別のミューテーションの結果）を正しく待つことになり、空リストへのフォールバックが起こらない。

## 実装しないこと

- `_mutateNow`の`on Exception catch`を`on Object catch`に広げる件（Gemini再レビューで別途指摘）は、既存の`CompletionTimeController`と一貫した方針を優先し見送り。実害の可能性が低い（このメソッド内でExceptionでないErrorが投げられる現実的な経路がない）ため、今回はスコープ外とする

## テスト

`test/features/targets/time_targets_controller_test.dart`に、`sharedPreferencesProvider`を`Completer`で制御可能なFutureに差し替え、初期ロード未完了の間に`addTarget`を呼んでも既存データが失われないことを検証するテストを追加する。

## 動作確認方法

`flutter analyze` / `dart format --set-exit-if-changed` / `flutter test`
