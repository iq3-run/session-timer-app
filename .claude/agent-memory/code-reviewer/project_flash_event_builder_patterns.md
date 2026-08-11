---
name: project-flash-event-builder-patterns
description: Findings from reviewing feat/46-timer-exact-completion-flash (flash_event.dart timerFlashEvents 0-minute entry) — completionFlashEvents/timerFlashEvents structural duplication
metadata:
  type: project
---

# flash_event.dart builder-function duplication (2026-08-12, issue #46)

`timerFlashEvents()` gained an exact-instant (`:0`) `FlashEvent` entry to match
`completionFlashEvents()`'s existing behavior (commit 437df7a). This made the two functions
structurally identical: null-check target, compute `targetEpochMs`, emit one exact `FlashEvent`
plus one per entry in a minutes list via the same `id`/`instant`/`label` shape — differing only in
id prefix (`timer:`/`completion:`), label text, and where the minutes list comes from (parameter
vs. the `timerFlashPointsMinutes` const). Flagged as **Warning** (DRY, MUST-level rule) —
**RESOLVED same PR**: extracted into a shared private `_exactPlusMinutesBefore` helper (commit
d4fef13), both public functions now just null-check and delegate. Verified the extraction is
behavior-preserving (all existing tests pass unchanged). If a third builder function
(`targetFlashEvents` doesn't count — different shape, no minutes-before loop) ever needs this same
exact-plus-minutes-list shape, it can reuse `_exactPlusMinutesBefore` directly.

Everything else in this PR was clean: id scheme has no collision risk (`timerFlashPointsMinutes =
[5, 3, 1]`, never `0`), `FlashQueueController`/`notification_event_source.dart` consume
`timerFlashEvents()` generically by id-prefix/instant so the new entry needed no changes there
(verified by reading both files), and the new test
(`timerFlashEvents returns the exact-completion event plus the 5/3/1-minute-before points`)
actually asserts `exact.instant == target` rather than just bumping the length assertion — real
coverage, not a rubber-stamp count update. `flutter test` on both affected test files passed
(11/11).

Related: [[project_stopwatch_pr_patterns]], [[project_session_schedule_patterns]]
