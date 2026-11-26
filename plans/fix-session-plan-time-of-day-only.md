# 実装計画: セッションの流れを「日付なしの時刻のみ」で保持し、常に適用できるようにする

Issue: #94（親: #1）

## 症状と原因

「現在のセッションを設定」を押しても、適用できるはずの時間帯のセッションが適用されず
「該当するセッションがありません」になることがある。

`SessionPlanEntry`が登録時に`resolveNextOccurrence`で解決された絶対時刻
（`startEpochMs`/`endEpochMs`）を保存しており、`resolveCurrentSession`が
`endTime.isAfter(now)`で「終了済み」を除外している。そのため、登録した日が過ぎた
セッション（例: 昨日の9:00〜12:30として保存されたもの）は、今日の9:30に押しても
「過去の時刻」と判断されて対象外になる。

セッションの流れは「毎日繰り返す一日のリズム」であり、保存された日付はユーザーが
選んだ値ではなく登録時の偶然の産物（#92の整理と同じ前提）。

## 方針

日付情報を持たせず、時刻（開始時刻＋所要時間）だけを保持する。適用時に「今」を基準に
該当する日付を毎回導出する。

### `lib/features/session_plan/session_plan_entry.dart`

- フィールドを`startEpochMs`/`endEpochMs`から`startMinutes`（0時からの分、0〜1439）と
  `durationMinutes`（1〜1440）に変更する。終了が開始より前の時刻（日跨ぎ）は
  `durationMinutes`で自然に表現できる
- `toJson`は新形式（`startMinutes`/`durationMinutes`）のみ出力する
- `tryFromJson`は新形式に加え、**旧形式（`startEpochMs`/`endEpochMs`）も読み込んで
  時刻のみに変換**する（過去に登録したセッションも消えずに適用対象になる）。
  旧形式の変換は端末のローカル時刻での時分を使う
- 不正な値（範囲外、型違い、旧形式で終了が開始以前、24時間超）は従来どおりその1件のみ破棄する
- 表示用に`startLabel`/`endLabel`（`H:mm`）を提供する

### `lib/features/session_plan/current_session_resolution.dart`

- 各セッションについて「終了が`now`より後になる最も早い発生（昨日・今日・明日のうち）」
  を求める。所要時間が24時間以内なので昨日〜明日の3日分で必ず見つかる
- その中で終了が最も早いものを現在のセッションとする（従来と同じ選び方）。
  これにより、セッションが1件でもあれば常に適用できる（`null`は空リストのときだけ）
- `autoTargetStart`の規則は従来どおり:
  - 未開始なら、そのセッション自身の開始時刻
  - 進行中なら、開始時刻順で次のセッションの次回開始時刻（なければ`null`）

### `lib/features/session_plan/session_plan_controller.dart`

- `addSession`/`updateSession`は`startMinutes`/`durationMinutes`を受け取る
- 並び替えは`startMinutes`順（#92の挙動を維持）

### `lib/features/session_plan/session_plan_screen.dart`

- 開始時刻はピッカーの時分をそのまま`startMinutes`にする（`resolveNextOccurrence`を使わない）
- 終了は「所要時間（1〜24時間）」または「終了時刻」。終了時刻指定は
  `(終了 − 開始) mod 24h`を所要時間とする（同時刻なら24時間）
- 一覧の表示は`startLabel〜endLabel`

## 実装しないこと

- 今日/明日などの日付表示、曜日ごとの設定（要望になし）
- 進行中セッションが最後の1件のとき、翌日の最初のセッションを`autoTargetStart`にすること
  （従来どおり`null`。仕様変更は別issue）

## テスト

- `session_plan_entry_test.dart`: 新形式のラウンドトリップ、旧形式の変換（日跨ぎ時刻でも
  時分が保たれる）、不正値の破棄
- `current_session_resolution_test.dart`: 「過去の日付で保存されていた」時代の再現ケース
  （今日の進行中時間帯が適用できる）、日跨ぎセッション（23:00〜2:00、深夜1:00に適用）、
  全セッションの時間帯外でも次のセッションが選ばれること
- `session_plan_controller_test.dart` / `session_plan_screen_test.dart`: 新APIへ追従。
  旧形式で保存済みのデータが読み込まれ表示されること

## 動作確認方法

`dart format` / `flutter analyze` / `flutter test`、デバッグビルド。
実機/エミュレータでは縦・横の両方で一覧と「現在のセッションを設定」を確認する。
