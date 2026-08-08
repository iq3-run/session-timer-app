# 実装計画: 指定時刻リスト（複数登録・永続化）

Issue: #6（親: #1）

## 対象

- 「＋指定時刻を追加」タップ→ネイティブ時刻ピッカーを直接開き、選択した時刻をそのまま「指定時刻 H:MM」として登録
- 複数登録・タップで再編集・✕で削除
- 永続化（spec 3-8節）: 起動時に既に超過した指定時刻をリストから除去。稼働中に超過した場合はcompletion時刻と同様、次回起動まで表示を維持（赤字・負数カウント）

## 実装しないこと

- フラッシュ演出・通知（指定時刻到達時のフラッシュは別Issue）
- 週末マイルストーン、設定シート（別Issue）

## データモデル・永続化

- `TimeTarget`（`lib/features/targets/time_target.dart`）: `{id: String, epochMs: int}`のイミュータブルクラス
- `id`は`UniqueKey().toString()`で生成（追加のパッケージ依存を増やさず、Flutter標準機能で一意性を確保）
- 永続化はJSON文字列としてSharedPreferencesの1キー（`time_targets_json`）にまとめて保存する。`shared_preferences`の`getStringList`ではなく`getString`+`jsonEncode`/`jsonDecode`を使う理由は、各要素が`id`と`epochMs`の2フィールドを持つため
- `timeTargetsControllerProvider`（`AsyncNotifierProvider<TimeTargetsController, List<TimeTarget>>`）:
  - `build()`: 永続化されたJSONを読み込み、`epochMs <= now`のものを除去して保存し直し、epochMs昇順でソートして返す（completion_time_controllerと同じ「build()とのレース回避」ガードも踏襲）
  - `addTarget(DateTime)` / `updateTarget(id, DateTime)` / `removeTarget(id)`: 更新後にJSONへ保存

## UI

- `lib/features/targets/time_targets_section.dart`: 登録済みリスト（各行タップで編集、✕で削除）+ 末尾に「＋ 指定時刻を追加」行
- 各行の残り時間表示は`core/clock/duration_format.dart`の`formatCountdown`を再利用（負数＝超過をそのまま赤字表示）
- 電池消費を抑えるため、`nowProvider`の秒間隔watchは各行の残り時間テキスト部分（末端widget）にのみ限定する（completion機能と同じ設計判断）

## テスト

- `test/features/targets/time_targets_controller_test.dart`: 追加・更新・削除・起動時の期限切れ除去（"restores across a fresh container"は完了時刻のテストと同様、`SharedPreferences.setMockInitialValues`で永続化データを読み直して再シードすることで真のコールドリスタートを検証する）

## 動作確認方法

`flutter analyze` / `dart format --set-exit-if-changed` / `flutter test` / `flutter build apk --debug`
