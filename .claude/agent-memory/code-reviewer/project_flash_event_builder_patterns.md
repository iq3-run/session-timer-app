---
name: project-flash-event-builder-patterns
description: Findings from reviewing feat/46-timer-exact-completion-flash (flash_event.dart timerFlashEvents 0-minute entry) — completionFlashEvents/timerFlashEvents structural duplication
metadata:
  type: project
---

# flash_event.dart builder-function duplication (2026-08-12, issue #46)

`timerFlashEvents()` gained an exact-instant (`:0`) `FlashEvent` entry to match
`completionFlashEvents()`'s existing behavior (commit 437df7a). After this change the two
functions are structurally identical: null-check target, compute `targetEpochMs`, emit one exact
`FlashEvent` plus one per entry in a minutes list via the same `id`/`instant`/`label` shape —
differing only in id prefix (`timer:`/`completion:`), label text, and where the minutes list comes
from (parameter vs. the `timerFlashPointsMinutes` const). Flagged as **Warning** (DRY, MUST-level
rule) — not yet fixed as of this review. Not previously flagged because `timerFlashEvents` didn't
have the exact-entry before this commit; this is the first instance of this specific duplication,
so it does not yet meet the "recurred N times" bar that upgrades other patterns in
[[project_stopwatch_pr_patterns]] / [[project_session_schedule_patterns]] from Suggestion to
Warning — it's called out directly here because the two functions sit ~30 lines apart in the same
file, making the copy obvious without even needing to grep. If a third builder function
(`targetFlashEvents` doesn't count — different shape, no minutes-before loop) ever needs this same
exact-plus-minutes-list shape, treat that as confirmation the extraction should have happened here
first.

Suggested extraction (not applied — this review is read-only):

```dart
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

Everything else in this PR was clean: id scheme has no collision risk (`timerFlashPointsMinutes =
[5, 3, 1]`, never `0`), `FlashQueueController`/`notification_event_source.dart` consume
`timerFlashEvents()` generically by id-prefix/instant so the new entry needed no changes there
(verified by reading both files), and the new test
(`timerFlashEvents returns the exact-completion event plus the 5/3/1-minute-before points`)
actually asserts `exact.instant == target` rather than just bumping the length assertion — real
coverage, not a rubber-stamp count update. `flutter test` on both affected test files passed
(11/11).

Related: [[project_stopwatch_pr_patterns]], [[project_session_schedule_patterns]]
