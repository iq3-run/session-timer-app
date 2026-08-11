# Feat: タイマー完了ジャストのフラッシュ・通知

Issue: <https://github.com/iq3-run/session-timer-app/issues/46>

## Scope

完了時刻 (`completionFlashEvents`) は既にジャスト0分のエントリ (`id`
`completion:$targetEpochMs:0`, ラベル「完了時刻です」) を常に生成しているが、
タイマー (`timerFlashEvents`) は `timerFlashPointsMinutes = [5, 3, 1]` の分前
のみで、0分（ジャスト完了の瞬間）のエントリが無い。これを追加する。

- 対象は `lib/features/flash/flash_event.dart` の `timerFlashEvents()`、および
  `completionFlashEvents()` と共有する `_exactPlusMinutesBefore` ヘルパーの
  導入（ローカルレビューでの重複指摘を受けて追加。詳細は下記コード参照）。
- `completionFlashEvents` のジャスト0分エントリと同じ形（`instant: target`）
  で、タイマー用の id 体系 (`timer:$targetEpochMs:...`) に合わせたエントリを
  1件追加する。id のサフィックスは既存の分前エントリ (`timer:$targetEpochMs:5`
  等) と衝突しないよう `0` を使う（`completionFlashEvents` と同じ規約）。
- ラベルは既存の分前エントリが `'タイマー残り$m分'` なので、ジャストは
  `'タイマー終了です'` とする。
- 通知 (`notification_event_source.dart`) は `timerFlashEvents()` をそのまま
  使っているため、この変更だけで自動的に通知にも反映される（コード変更不要）。
- フラッシュのマージ・キュー処理 (`FlashQueueController`) は id/instant ベース
  で汎用的に動くため変更不要。

## 変更箇所

### `lib/features/flash/flash_event.dart`

`timerFlashEvents`/`completionFlashEvents` が構造的に同一になったため、共通
処理を private ヘルパーに抽出する（両関数とも `target == null` の早期returnの
みを残し、本体はヘルパーに委譲する）:

```dart
List<FlashEvent> timerFlashEvents(TimerState? timer) {
  final target = timer?.targetTime;
  if (target == null) return const [];
  return _exactPlusMinutesBefore(
    idPrefix: 'timer',
    target: target,
    minutesBefore: timerFlashPointsMinutes,
    exactLabel: 'タイマー終了です',
    labelFor: (m) => 'タイマー残り$m分',
  );
}

List<FlashEvent> _exactPlusMinutesBefore({
  required String idPrefix,
  required DateTime target,
  required List<int> minutesBefore,
  required String exactLabel,
  required String Function(int minutes) labelFor,
}) {
  final targetEpochMs = target.millisecondsSinceEpoch;
  return [
    FlashEvent(id: '$idPrefix:$targetEpochMs:0', instant: target, label: exactLabel),
    for (final m in minutesBefore)
      FlashEvent(
        id: '$idPrefix:$targetEpochMs:$m',
        instant: target.subtract(Duration(minutes: m)),
        label: labelFor(m),
      ),
  ];
}
```

## テストへの影響

`test/features/flash/flash_event_test.dart` の `timerFlashEvents` グループ:

- 既存の `'returns the 5/3/1-minute-before points'` テストの件数アサーション
  (`hasLength(timerFlashPointsMinutes.length)`) を `+ 1` に更新。
- 新規: ジャスト0分エントリが `instant == target` で含まれることを検証する
  テストを追加（`completionFlashEvents` の同種テストに倣う）。

## Verification

- `dart format` / `flutter analyze` / `flutter test` / debug build
- `code-reviewer` サブエージェント + Gemini CLI ローカルレビュー（両方、push
  前に完了させる）
- BlueStacks/実機でタイマーを短時間（1分等）で設定し、0になった瞬間にフラッ
  シュ・通知が発火することを目視確認
