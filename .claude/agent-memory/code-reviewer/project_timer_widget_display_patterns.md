---
name: project-timer-widget-display-patterns
description: Issue #63 (feat/63-timer-widget-display-android) — TimerState.targetEpochMs is raw-device-clock, not NTP-corrected, unlike Completion/NextTarget; matters for any future clock-offset math
metadata:
  type: project
---

# Timer widget display (issue #63, branch `feat/63-timer-widget-display-android`) review notes

Reviewed 2026-08-17, uncommitted working tree (not yet pushed as a PR). `flutter analyze`/
`flutter test`/`dart format --set-exit-if-changed` all clean.

## RESOLVED (same PR, before merge): `TimerState.targetEpochMs` is raw-device-clock, not
NTP-corrected — unlike the 3 pre-existing synced widgets' targets

This is a genuinely subtle distinction worth remembering for **any future feature that does
clock-offset math against `TimerController`**, not just this widget:

- `CompletionTimeController`/`TimeTargetsController`'s target epochs represent an absolute
  real-world wall-clock instant (a user-picked time-of-day via `resolveNextOccurrence`), and their
  **in-app display** (`completion_countdown_section.dart`, `time_targets_section.dart`) computes
  remaining time against `watchNow(ref)` (`nowProvider`, NTP-corrected). So `HomeWidgetTimeMath`'s
  `System.currentTimeMillis() + ntpOffsetMs` correction is *correct* for those two — it's what
  makes the widget's displayed countdown match the in-app one.
- `TimerController.start()`/`addTime()`/`quickStart()` compute `targetEpochMs` from raw
  `DateTime.now()` (not `watchNow`/`nowProvider`), and `timer_section.dart`'s in-app countdown
  display (`_TimerBody.build()`) also compares against raw `DateTime.now()` — both ends are
  self-consistent on the *uncorrected* device clock, by design (a countdown timer is a duration
  from press, not an absolute future instant).
- `TimerWidgetSync.apply` originally called `HomeWidgetTimeMath.countDownBase(targetEpochMs,
  ntpOffsetMs)` — same call shape as `CompletionCountdownWidgetProvider`/`NextTargetWidgetProvider`
  — which **applied the NTP correction to a value that was never NTP-corrected in the first
  place**. Net effect would have been: the widget's displayed remaining time differs from
  `timer_section.dart`'s displayed remaining time by exactly `ntpOffsetMs`, for the entire lifetime
  of every timer session whenever the device clock is non-trivially off true time — precisely the
  scenario the whole NTP-sync feature exists to correct for. **Fixed**: `TimerWidgetSync.apply` now
  calls `HomeWidgetTimeMath.countDownBase(it, ntpOffsetMs = 0L)`, with a comment explaining why
  Timer's `targetEpochMs` doesn't get the same treatment as Completion/NextTarget's.

**Important nuance, don't over-correct on a second read**: the **flash-window scheduling**
(`TimerWidgetFlashPoints.deviceWindows`/`TimerWidgetFlashScheduler`) applying the same
`instant - ntpOffsetMs` correction is *actually right* — verified by deriving both sides by hand.
`FlashQueueController.build()` (the in-app flash trigger) admits a `timerFlashEvents` event using
`now = ref.watch(nowProvider).value` (NTP-corrected) compared against `event.windowStart`, where
`event.instant` is built from the same raw `targetEpochMs`. Working the arithmetic through, the
device-clock instant at which the in-app flash actually starts is
`instant - flashWindowMs - ntpOffsetMs` — exactly what `TimerWidgetFlashScheduler` schedules via
`AlarmManager`. So the *flash timing* correctly mirrors the app's real behavior; only the
*Chronometer countdown number* needed the fix above. `TimerWidgetFlashPoints`'s correction was left
as-is, correctly.

If a future PR touches `TimerController`/`timer_section.dart` to make timer targets NTP-corrected
(closing the underlying inconsistency at the source, which also exists between
`timer_section.dart`'s raw `DateTime.now()` display and `FlashQueueController`'s NTP-corrected
admission check for the *same* timer state — a second, separate pre-existing inconsistency, out of
scope for this PR), re-check whether the widget-side correction should then be re-added.

## RESOLVED: recurring comment-policy violation, again

`TimerWidgetFlashPoints.kt`'s doc comment originally cited `plans/feat-timer-widget-display-android.md`
directly ("see the ... note in plans/feat-timer-widget-display-android.md"). Same banned
self-reference category tracked extensively in [[project_ntp_sync_patterns]] (4+ occurrences) and
[[project_notification_scheduler_patterns]] (plan-file citations specifically). **Fixed** (before
CodeRabbit even ran) by replacing the citation with the plain technical WHY inline. Keep flagging
this immediately in future PRs — it keeps slipping past the agent that writes the code.

## RESOLVED: plan-promised test not delivered

`plans/feat-timer-widget-display-android.md`'s テスト section explicitly commits to adding a test
in `test/features/home_widget/home_widget_scheduler_test.dart` proving a `timerControllerProvider`
state change triggers a `syncTimer`-equivalent call ("なければ新規追加" — add new if no sibling
test exists). No such test existed for *any* of the 4 synced widgets in that file (it only had one
pre-existing app-resume test) — so the plan's own "add new if none exist" branch should have fired
and initially didn't. **Fixed** (before CodeRabbit ran) by adding
`'a timer state change syncs the timer widget'` to `home_widget_scheduler_test.dart`, overriding
`homeWidgetGatewayProvider` with a recording fake. Watch whether the "plan promises a test, diff
doesn't deliver it" pattern recurs in a future PR — that's worth escalating as a process gap
independent of whether the missing test would have caught a real bug.

## CodeRabbit follow-up (post-push)

- **Valid, applied**: `TimerWidgetFlashPoints.isFlashing`'s `nowDeviceMs in start..end` was a
  closed interval at both ends; made half-open (`>= start && < end`) so the exact millisecond a
  window's end alarm fires doesn't still read as flashing. Low-risk, easy correctness improvement,
  independent of the window-direction question below.
- **False positive, rejected**: CodeRabbit's "Major/Functional Correctness" comment argued the
  window should run `[instant, instant + FLASH_WINDOW_MS)` (flash starts at the 5/3/1/0-minute
  mark and lasts 3s *after* it) instead of `[instant - FLASH_WINDOW_MS, instant)` (flash ends *at*
  the mark, starting 3s before). Verified against `lib/features/flash/flash_event.dart`'s explicit
  contract: `FlashEvent.instant` is documented as "the wall-clock moment the flash animation must
  *end*", and `windowStart => instant.subtract(flashAnimationDuration)`. CodeRabbit's suggested
  direction directly contradicts this — the in-app `FlashOverlay` already ends its strobe exactly
  at `instant`, and this widget deliberately mirrors that. Rejected with the citation above rather
  than applying the suggested diff. Another instance of "don't blindly apply — verify against the
  actual codebase" (CLAUDE.md, PR Bot Review Handling) paying off on a *Major*-severity, seemingly
  concrete/confident finding with a ready-made diff — severity and confidence aren't a substitute
  for checking.
- **Valid, applied**: this memory file and `MEMORY.md#L11` themselves were stale — written by the
  first-pass review before the fixes above were applied, then committed describing resolved issues
  as still-open Critical findings. CodeRabbit caught it correctly. Lesson: when a review's fixes
  get applied *after* its memory write-up, go back and update the memory write-up too before
  committing — don't let "the finding is now fixed" and "the memory file describing the finding"
  drift out of sync.

## Verified clean, no findings

- `TimerWidgetSync` not sharing `HomeWidgetChronometerPanel` — confirmed justified: the panel has
  no notion of a flash-state background/visibility toggle, same reasoning `StopwatchWidgetProvider`
  already established for its own independence.
- `HomeWidgetPlugin.getData(context): SharedPreferences` (used by `TimerWidgetFlashReceiver`, first
  use of this specific API in the repo) verified against the real installed plugin source
  (`home_widget-0.9.3`) — it's the exact call `HomeWidgetProvider`'s own base `onUpdate` uses
  internally.
- PendingIntent request-code scheme (`REQUEST_CODE_BASE = 9100`, `pointIndex*2+edge`) — verified no
  real collision risk with any other PendingIntent in the app regardless of numeric range, because
  Android's PendingIntent identity keys on `(requestCode, target component, action, data, type,
  categories)` — a different target component (`TimerWidgetFlashReceiver`) is already sufficient
  for uniqueness. The code comment overstates why the range is needed (implies the reservation
  itself prevents collision) but isn't wrong to have; not worth blocking on.
- `cancelAll`/`reschedule` leak avoidance across `onDisabled`/repeated `onUpdate` — correct:
  `reschedule` always cancels-then-rebuilds (same shape as `NotificationService.rescheduleAll`),
  `onDisabled` (last instance removed) cancels everything, no per-`onDeleted` action needed since
  scheduling is app-wide, not per-widget-id.
- Magic number: `minutes * 60_000L` in `TimerWidgetFlashPoints.deviceWindows` has no named constant
  (unlike the adjacent `FLASH_WINDOW_MS`) — flagged as a minor Warning (MUST-level "no magic
  numbers" rule), low severity.

Related: [[project_home_widget_android_patterns]], [[project_ntp_sync_patterns]],
[[project_notification_scheduler_patterns]]
