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

**`SessionEvent` has no dedicated `_test.dart`, unlike its siblings — RESOLVED, was stale.**
Originally flagged 2026-08-11 against the staged (not-yet-pushed) diff. By the time PR #45
merged, `test/features/schedule/session_event_test.dart` existed (confirmed via
`git log --follow`: added in commit a10c206, the same PR). As of the 2026-08-12 `feat/48-
schedule-screen-split` review it has solid `tryFromJson`/`toJson` round-trip and malformed-field
coverage, extended further in that PR to cover the new `visible` field (defaults-to-true,
omitted-when-true serialization, round-trip, non-bool rejection). Don't re-raise this — the gap
this note originally described no longer exists.

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

**Follow-up (2026-08-12, issue #48/branch `feat/48-schedule-screen-split`, commit a741e85 —
`SessionScheduleScreen` split into read-only screen + new `SessionScheduleSettingsScreen`,
`SessionEvent` gained a persisted `visible` bool, `session_chain.dart`'s `buildScheduleRows`
gained a final `_isVisibleOnScheduleScreen` filter).**

- **Doc-comment self-reference rule recurred again (6th+ occurrence)**: `session_chain.dart`'s
  new filter comment cites `plans/feat-schedule-screen-split.md` directly (banned plan-file
  self-reference), and both `sessionEventLabel`'s doc comment (names its caller
  `SessionScheduleSettingsScreen` by name) and `SessionEvent.visible`'s doc comment (names the
  specific consumer function `session_chain.dart`'s `_isVisibleOnScheduleScreen`) hit the
  "never reference callers" ban. The technical WHY content in all three is fine and should stay
  — only the plan-file path / named-caller clauses need to go. This pattern has now recurred
  across effectively every PR in this feature area; treat it as expected-to-recur and check for
  it specifically rather than being surprised.
- **Visibility filter logic verified correct by hand-trace**: `_isVisibleOnScheduleScreen` is
  keyed off `numbers[event.id] == 1` (the WE's own assigned sequence number from
  `assignSequenceNumbers`, computed over the *unfiltered* full event list) rather than date
  order or list position — correct, and matches the same `numbers` map `_buildChainRows`/gap
  calc already use, so there's no risk of the "first WE" exemption disagreeing with the
  numbering shown in the label. Confirmed `buildScheduleRows` computes `numbers` and
  `_buildChainRows` (which runs gap calc) over the full unfiltered `chainEvents` list and only
  applies `.where(_isVisibleOnScheduleScreen)` as the very last step before merging with CR
  rows — hiding an event cannot change a neighbor's chain-gap value. `session_chain_test.dart`
  added a dedicated test for exactly this invariant ("hiding an event does not change its
  neighbors' chain-gap values") plus first-WE-stays-visible, later-WE-hidden, CS-stays-visible,
  and CR-ignores-visible cases — good coverage, no edge case found missing.
- **`_singletonTypes` (OR/CS) duplication is pre-existing, not new**: it was already duplicated
  between the old `session_schedule_screen.dart` and `session_event_controller.dart` before this
  PR; the split just relocated the copy from the old screen file into the new
  `session_schedule_settings_screen.dart` verbatim. Don't flag as newly introduced — it's a
  standing, not-yet-fixed opportunity to share a constant (e.g. from `session_event.dart`),
  worth a Suggestion each time a file touching it is reviewed, not a Warning.
- `SessionScheduleSettingsScreen.build` is 28 lines, over the 20-line mandate — but the old
  `SessionScheduleScreen.build` it was split from was already 27 lines pre-PR and was never
  flagged for length in the prior review. Top-level `Scaffold`/`AppBar`/`body` widget trees in
  this repo appear to get a de facto pass on the 20-line rule when the length is purely the
  declarative widget nesting (no extractable branching/looping logic inside). Keep noting as
  Suggestion only unless a future instance has real extractable logic mixed in, not just nesting.

**Follow-up (2026-08-12, issue #50/branch `feat/50-manual-event-numbering`, commit 7fadaf7 —
`SessionEvent` gained a persisted, display-only `manualNumber` int? override for WE/WD/SS
labels).**

- **Display-only invariant verified correct by direct read, not just by the commit message's
  claim**: grepped `_isVisibleOnScheduleScreen`, `isFirstWeekend` (both in `session_chain.dart`),
  and `_hasVisibilityToggle` (`session_schedule_settings_screen.dart`) — all three still key off
  `numbers[event.id]` from `assignSequenceNumbers`, never `event.manualNumber`. Only
  `sessionEventLabel` reads `event.manualNumber ?? numbers[event.id]`. `session_chain_test.dart`
  added dedicated tests asserting a manualNumber on the first WE doesn't change its visibility
  exemption, its 3-day duration (chainGap to the next WE unchanged), or any other event's own
  auto-assigned number — good, targeted coverage of exactly the invariant that mattered here.
- **DRY violation and `_EventRow.build` length — RESOLVED same PR (commit a30ed5f), before push.**
  `_ManualNumberDialogState`/`_AddEventFormState`'s duplicated validate/parse logic was extracted
  into top-level `_isValidManualNumberText`/`_parseManualNumberText`, and `_EventRow.build`'s
  number-label ternary was pulled into a `_numberLabel(...)` helper, bringing `build()` back under
  20 lines. CodeRabbit re-flagged both against a stale memory read before this note was updated —
  don't re-raise either.
- **Minor comment-policy hit — also resolved same PR**: `_editManualNumber`'s doc comment no
  longer names `_EventRow` by class name.
- **Follow-up (2026-08-12, CodeRabbit on PR #51): `GestureDetector` isn't keyboard-focusable —
  fixed by swapping to `InkWell`** (`editNumber_<id>`), which gets focus/Enter-Space activation for
  free. Added a widget test driving it via `Focus.of(...).requestFocus()` +
  `tester.sendKeyEvent(LogicalKeyboardKey.enter)` — note `Focus.of` must be called from a
  *descendant* of the InkWell (its Text child's context), not the InkWell's own context, since
  `Focus.of` searches upward and the InkWell's internal Focus wraps its child as an ancestor of
  the child, not of the InkWell widget itself. Worth remembering next time a tappable custom
  control needs a keyboard-activation test — this exact gotcha will recur.
- Everything else clean: JSON round-trip/validation (`tryFromJson` rejects non-int and <=0,
  tolerates explicit `null` unlike `visible`, with the asymmetry's WHY correctly stated in the
  comment), `SessionEventController.setManualNumber`/`_replaceEvent` reuse (good — extracted
  exactly the duplicated "find by id, replace" loop that `setVisible` used to inline, no new
  mutation-queue-skeleton instance since the controller wasn't touched at that level), 82 tests
  pass, `flutter analyze`/`dart format` clean.

Related: [[project_stopwatch_pr_patterns]], [[project_ntp_sync_patterns]]
