---
name: project-session-schedule-patterns
description: feat/44-session-schedule (SessionEvent/gap/chain/controller/screen) review findings — DataTable vertical-overflow bug confirmed empirically; recurring violations hit again
metadata:
  type: project
---

# Session-schedule feature (issue #44, branch `feat/44-session-schedule`) review notes

Reviewed 2026-08-11 at the staged diff (not yet pushed as a PR). `flutter analyze` /
`dart format --set-exit-if-changed` / `flutter test` all clean (47 tests pass) at review time.

**`session_schedule_screen.dart`'s `_ScheduleTable` has a confirmed, empirically-verified
vertical-overflow bug — Critical, not a theoretical concern.** The table is
`Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(...)))`
— horizontal scroll only, no vertical `SingleChildScrollView`/`ListView` wrapping it. Built a
throwaway widget-test probe (40 mocked WD events, 600px-tall surface, not committed) and
confirmed: no `FlutterError` is thrown (so `flutter analyze`/a normal widget test won't catch
this), but the last row's `Text` renders at `Offset(y: 2078)` while the surface is only 600px
tall and `find.byType(Scrollable)` returns exactly 1 (the horizontal one only) — rows past the
visible height are unreachable, no vertical scrollbar, no error. This directly conflicts with
the feature's own core design goal (`plans/feat-session-schedule.md`: "永続化は全件保持（過去
の項目も削除しない）") — since the table only grows, this will manifest in real usage within
months, not as an edge case. Fix: wrap in a second, outer vertical `SingleChildScrollView` (or
replace the horizontal-only wrapper with a widget that scrolls both axes), and add a widget test
that seeds >15 events and asserts the last row's `Finder` is actually within the viewport (or
that a vertical `Scrollable` exists) — a plain "does it build without throwing" test does not
catch this class of bug in this codebase's test style.
**If this pattern (`Expanded` → single-axis `SingleChildScrollView` → unbounded-growth list)
shows up again in a future PR, cite this finding — don't assume "no FlutterError thrown" means
the layout is safe; probe empirically (position of last item vs. surface size) rather than just
running `flutter test` and checking exit code.**

**Doc-comment content rule (plan-file self-references) — recurred again, now the single largest
occurrence in this repo's history: ~9 instances across one PR.** Same violation category as
[[project_stopwatch_pr_patterns]]'s "Doc-comment content rule" (previously flagged 4x, see
[[project_ntp_sync_patterns]]). This PR's new files almost all cite
`plans/feat-session-schedule.md` directly in doc comments: `session_gap_calculation.dart`
(class doc), `session_chain.dart` (`_chainTypes` doc), `session_event.dart` (`durationDays` doc),
`session_event_controller.dart` (class doc), `session_schedule_screen.dart` (class doc), plus
both `session_gap_calculation_test.dart` and `session_chain_test.dart` comments. Also
`session_schedule_entry_button.dart`'s class doc names its caller (`ClockScreen`) — same banned
category ("never reference the current task, fix, or callers"). The technical WHY in each
comment is fine and should stay; only the `plans/...`/caller-naming phrase needs to go. Given
this is now 5+ PRs deep with the same slip, the pattern is: an agent writing a large plan-driven
feature reflexively cites the plan file it just wrote from, in nearly every new file's doc
comment — flag it comprehensively (list every file) rather than picking one example, since it
recurs at the "whole feature" granularity, not the "one function" granularity.

**Mutation-queue skeleton — now a 5th+ instance, still not extracted.**
`SessionEventController` duplicates the same `_mutationQueue`/`_initialLoad`/`_lastGood`/
`_mutate`/`_mutateNow`/`_persistenceFailure` skeleton as `FlashPointsController`/
`TimeTargetsController`/`StopwatchController`/`TimerController` (see
[[project_stopwatch_pr_patterns]], where this was already raised as a Warning at 4 instances).
Flagged again here; extraction (`MutationQueueNotifier<T>` base/mixin) still hasn't happened
across any of these PRs. Continue flagging as Warning until it's actually extracted — this is a
standing, repeatedly-deferred recommendation, not a fresh discovery each time.

**`SessionEvent` has no dedicated `_test.dart`, unlike its siblings.** `FlashPointConfig`
(`test/features/flash/flash_point_config_test.dart`) and `TimerState`
(`test/features/timer/timer_state_test.dart`) both have direct unit tests for
`tryFromJson`/`toJson` round-trip and malformed-field rejection (wrong type, missing field,
out-of-range epoch). `SessionEvent.tryFromJson` has 5 rejection branches (wrong-typed
id/type/epochMs, out-of-range epochMs via `maxEpochMs`, unknown enum name) and none are
exercised anywhere — `session_event_controller_test.dart` only tests the happy path plus a
persistence-failure (`AsyncError`) case, never a corrupt/malformed persisted JSON string. This
is a real, concrete gap against this repo's own established convention for persisted-model
files, not a nitpick.

**Verified correct on close reading (no findings)**: `calculateGap`/`_countFridaysInRange`'s
Friday-counting closed-form (hand-traced against all 3 of the plan's confirmed worked examples
plus the test suite's 3 additional boundary cases — adjacent days, non-Friday landing, exact-Friday
landing with 0 days between); `assignSequenceNumbers`'s stable-sort-workaround (`List.sort` is
genuinely not guaranteed stable in Dart, so the index tiebreak comment is accurate, not
defensive-for-no-reason); `buildScheduleRows`'s `identical()`-based nearest-past/future matching
(safe because `chainEvents` and the objects passed into `_nearestPast`/`_nearestFuture` are the
literal same `SessionEvent` instances, never copies); the CR today/next split logic; the
singleton-type (OR/CS) no-op-add guard in the controller, matching the existing
`UniqueKey().toString()` id-generation precedent already used by `TimeTargetsController`.

**Minor, Suggestion-only**: `clock_screen.dart`'s new `Row` wraps both `SessionScheduleEntryButton`
and `SettingsGearButton` each in `SizedBox(width: 48, ...)` — a new, unnamed magic-number `48`
(no existing constant reused; Flutter's own `kMinInteractiveDimension == 48.0` would be the
natural fit but isn't referenced). Low severity since it's a well-known Material tap-target size,
not an arbitrary number — didn't escalate past Suggestion.

**Follow-up (2026-08-11, CodeRabbit-driven fix on PR #45, working tree not yet pushed).**
CodeRabbit caught a real correctness bug the initial review missed: `_nearestPast` filtered
by `e.date.isBefore(today)` (event *start* before today) instead of `endOf(e).isBefore(today)`
(event *fully finished*) — for a multi-day WE, `today` landing mid-span (e.g. WE starts Fri,
today is Sat) got wrongly treated as "nearest past", producing a negative-day gap. Fixed by
threading `endOf` into `_nearestPast` and adding `_spans`/`isToday` so a mid-span day still
highlights as "today" without being counted as past. Traced by hand (start day / middle day /
exact end day / day-after-end for both a 2-day and 3-day WE): semantics are `isToday` = today
∈ [start, end] inclusive, `isPast` = today > end (strictly) — the two never overlap, and on the
event's own last day it's still "ongoing" (isToday=true, not yet nearestPast), which is correct
and intentional. No missed edge case. Same commit also fixed the `durationDays` doc comment's
caller-naming (`the caller (\`assignSequenceNumbers\`)` → `the caller`) — good, this is the
`[[project_stopwatch_pr_patterns]]`/`[[project_ntp_sync_patterns]]` doc-comment self-reference
class being *self-corrected* proactively rather than needing to be flagged again.

`SessionEvent`'s constructor dropped `const` and normalizes `date` to midnight itself now
(previously callers normalized before passing in). Verified via grep: zero `const SessionEvent(`
call sites remain anywhere in the repo (lib or test) — clean, no compile break.

Confirmed independently (this repo's `_ScheduleTable`, not touched in this diff) that the
DataTable vertical-overflow bug flagged earlier in this file's history is now fixed —
`SingleChildScrollView` is nested (outer vertical, inner horizontal) — and the new widget test
(`session_schedule_screen_test.dart`, 30 seeded rows, asserts `tester.getTopLeft(...).dy` moves
after a drag) is exactly the empirically-grounded test style this memory file previously asked
for. Close the loop: that Critical finding is resolved, no need to re-raise it.

Related: [[project_stopwatch_pr_patterns]], [[project_ntp_sync_patterns]]
