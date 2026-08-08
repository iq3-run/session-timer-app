# Feat: ⚙設定画面（設定シート）の土台

Issue: <https://github.com/iq3-run/session-timer-app/issues/24>

## Scope（2026-08-09、ユーザーとの事前確認事項）

- 表示形式：モーダルボトムシート（`showModalBottomSheet`）。プロトタイプ
  （`docs/session-timer.html` の `#sheet`/`#sheetBg`）と同じ、下からスライド
  インする構成。
- 導線：新規AppBarは追加しない。既存の`ClockScreen`のColumn内、
  `CurrentTimeDisplay`の上に歯車アイコン行を追加する。
- 中身：プロトタイプの4セクションを構造どおりに再現する。
  1. フラッシュポイント設定（追加/削除）
  2. 通知（ON/OFFトグル）
  3. おまけ：週末（マイルストーン）（追加/削除）
  4. おまけ：時刻同期（NTP風）
- **実装深度はUIのみ**。アプリの実状態（`FlashQueueController` の実際の
  フラッシュポイント、`NotificationService` の実際の通知有効/無効、永続化）
  には一切配線しない。#22（通知ON/OFF）・週末マイルストーン・NTP同期は
  それぞれ別issueでこの土台の上に実装する。

## Design decision: ephemeral local state, not a Riverpod controller

各セクションの「追加/削除/トグル」操作は、シートを開いている間だけ効く
`StatefulWidget`のローカルstateとして実装する（アプリ全体のprovider/
永続化は追加しない）。プロトタイプのJS変数もページリロードで消える
ephemeralな状態だったため、この振る舞いは元のプロトタイプに忠実。

理由：
- 本issueのスコープは「UIの土台」であり、実データへの配線は#22等の別issueが
  担当する。ここでRiverpod controllerを新設すると、後続issueが同じ責務の
  controllerを二重に作る/差し替えることになり手戻りが生じる。
- 一方で「タップしても何も起きない」完全な静的表示にすると、動作確認が
  しづらく実際のレイアウト崩れ（リストが伸びた時など）を目視できない。
  ローカルstateで足踏み用の`Text`用でよいので、シート内だけで
  追加/削除/トグルが「効いて見える」ようにする。

注意点（PRのItems to Confirmに記載）：これは見た目上インタラクティブだが、
アプリの実際の通知挙動やフラッシュポイントには一切影響しない。ユーザー
（開発者自身）は把握済みだが、将来このコードを読む人が誤解しないよう、
通知トグルの直下に「この設定は#22で有効になります」旨の小さいmutedテキスト
を添える。

NTP同期ボタンは実際のネットワークfetchを行わない（本issueのスコープ外か
つ、UIのみの土台でネットワーク処理を書くとエラーハンドリング等の実装が
中途半端になるため）。押すと固定文言のステータステキストに切り替わる
だけの静的挙動とする。

## File layout

```
lib/features/settings/
  settings_gear_button.dart       # ClockScreen内に置く導線。タップでシートをshowModalBottomSheetで開く
  settings_sheet.dart             # StatefulWidget。ephemeral stateを保持し、4セクションを合成
  flash_points_settings_section.dart
  notification_settings_section.dart
  weekend_milestones_settings_section.dart
  ntp_sync_settings_section.dart
```

- `settings_sheet.dart` が `List<int> _flashPointMinutes`,
  `bool _notifyEnabled`, `List<_Milestone> _milestones`,
  `String _ntpStatusText` を保持し、値とコールバックを各セクション
  StatelessWidgetに渡す（`ClockScreen`の`Stack`/`Column`構成や
  `CompletionCountdownSection`の親→子コールバック渡しパターンを踏襲）。
- `_Milestone`（id/label/date）は`weekend_milestones_settings_section.dart`
  内のプライベートクラスとして定義（アプリ全体のモデルではないため
  `features/targets/time_target.dart`のような共有モデル化はしない）。
- 色・スタイルは`SessionTimerColors`/`SessionTimerTextStyles`
  （`core/theme/session_timer_theme.dart`）を再利用。プロトタイプの
  amber/cyan/red/mutedの用途はそのまま踏襲（フラッシュポイント値=cyan、
  削除ボタン=red、キャプション=muted等）。

## UI詳細（プロトタイプ対応）

- **歯車ボタン**：`ClockScreen`のColumn先頭に`Align(alignment: Alignment
  .centerRight, child: SettingsGearButton())` を追加。`IconButton(icon:
  Icon(Icons.settings))` + `onPressed`で`showModalBottomSheet`。
- **シート外枠**：`showModalBottomSheet(backgroundColor:
  SessionTimerColors.panel, shape: RoundedRectangleBorder(borderRadius:
  BorderRadius.vertical(top: Radius.circular(16))), isScrollControlled:
  true, builder: ...)`。内容は`SingleChildScrollView`+`Column`で4セクション
  + 閉じるボタン。
- **フラッシュポイント設定**：見出し「完了◯分前フラッシュ」、現在値の
  一覧（`Chip`的な行、削除ボタン付き）、`TextField(keyboardType:
  TextInputType.number)` + 「追加」`FilledButton`。
- **通知**：見出し「通知」、`SwitchListTile`的な行（ラベル「フラッシュ/
  到達時に通知を送る」）＋ 直下に「この設定は#22で有効になります」の
  mutedキャプション。
- **週末（マイルストーン）**：見出し「おまけ：週末（マイルストーン）」、
  一覧（ラベル + 日付 + 削除ボタン）、ラベル用`TextField` + 日付は
  `showDatePicker`を開くボタン + 「追加」。
- **時刻同期（NTP風）**：見出し「おまけ：時刻同期（NTP風）」、「サーバー
  時刻に同期」ボタン、押すと固定文言「未同期（端末時刻を使用中）」→
  「同期は#1で実装予定です」に切り替わる静的ステータステキスト。
- 一番下に「閉じる」`FilledButton`（`Navigator.pop`相当、
  `showModalBottomSheet`のcontextで`Navigator.of(context).pop()`）。

## Tests

- `test/features/settings/settings_sheet_test.dart`
  - 歯車ボタンタップでシートが開き、4セクションの見出しが表示される。
  - フラッシュポイント追加：数値入力→「追加」で一覧に反映される。
  - フラッシュポイント削除：一覧の削除ボタンで一覧から消える。
  - 通知トグル：タップでON/OFFの見た目が切り替わる（実際の通知送出には
    触れない — このPRの範囲外であることをテストコメントで明示しない、
    テスト名で示す）。
  - マイルストーン追加/削除の同様のテスト。
  - NTP同期ボタン：タップでステータステキストが切り替わる。
  - 「閉じる」でシートが閉じる。

## Verification

- `dart format`
- `flutter analyze`
- `flutter test`
- debug build
- BlueStacks/実機で歯車ボタン→シート開閉、各セクションの追加/削除/トグル
  操作を目視確認。
