---
name: project-timer-widget-display-patterns
description: Issue #63 (feat/63-timer-widget-display-android) — TimerState.targetEpochMs is raw-device-clock, not NTP-corrected, unlike Completion/NextTarget; matters for any future clock-offset math
metadata:
  type: project
---

# Timer widget display (issue #63, branch `feat/63-timer-widget-display-android`) review notes

Reviewed 2026-08-17, uncommitted working tree (not yet pushed as a PR). `flutter analyze`/
`flutter test`/`dart format --set-exit-if-changed` all clean.

## Critical, real finding: `TimerState.targetEpochMs` is raw-device-clock, not NTP-corrected —
unlike the 3 pre-existing synced widgets' targets

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
- `TimerWidgetSync.apply` calls `HomeWidgetTimeMath.countDownBase(targetEpochMs, ntpOffsetMs)` —
  same call shape as `CompletionCountdownWidgetProvider`/`NextTargetWidgetProvider` — which
  **applies the NTP correction to a value that was never NTP-corrected in the first place**. Net
  effect: the widget's displayed remaining time differs from `timer_section.dart`'s displayed
  remaining time by exactly `ntpOffsetMs`, for the entire lifetime of every timer session whenever
  the device clock is non-trivially off true time — precisely the scenario the whole NTP-sync
  feature exists to correct for. The plan file (`plans/feat-timer-widget-display-android.md`,
  "時刻計算：NTPオフセットの扱い" section) explicitly reasons "matches what the other 3 widgets
  already do" — that reasoning doesn't hold here because it assumes `targetEpochMs` means the same
  thing across all 4 widgets, and it doesn't.

**Important nuance, don't over-correct on a second read**: the **flash-window scheduling**
(`TimerWidgetFlashPoints.deviceWindows`/`TimerWidgetFlashScheduler`) applying the same
`instant - ntpOffsetMs` correction is *actually right* — verified by deriving both sides by hand.
`FlashQueueController.build()` (the in-app flash trigger) admits a `timerFlashEvents` event using
`now = ref.watch(nowProvider).value` (NTP-corrected) compared against `event.windowStart`, where
`event.instant` is built from the same raw `targetEpochMs`. Working the arithmetic through, the
device-clock instant at which the in-app flash actually starts is
`instant - flashWindowMs - ntpOffsetMs` — exactly what `TimerWidgetFlashScheduler` schedules via
`AlarmManager`. So the *flash timing* correctly mirrors the app's real behavior; only the
*Chronometer countdown number* is wrong. Minimal fix: stop passing `ntpOffsetMs` to
`HomeWidgetTimeMath.countDownBase` for the Timer widget specifically (pass `0L`, with a comment
explaining why — Timer's `targetEpochMs` is raw-device, unlike Completion/NextTarget's), while
leaving `TimerWidgetFlashPoints`'s correction as-is.

If a future PR touches `TimerController`/`timer_section.dart` to make timer targets NTP-corrected
(closing the underlying inconsistency at the source, which also exists between
`timer_section.dart`'s raw `DateTime.now()` display and `FlashQueueController`'s NTP-corrected
admission check for the *same* timer state — a second, separate pre-existing inconsistency, out of
scope for this PR), re-check whether the widget-side correction should then be re-added.

## Recurring comment-policy violation, again

`TimerWidgetFlashPoints.kt`'s doc comment cites
`plans/feat-timer-widget-display-android.md` directly ("see the ... note in
plans/feat-timer-widget-display-android.md"). Same banned self-reference category tracked
extensively in [[project_ntp_sync_patterns]] (4+ occurrences) and
[[project_notification_scheduler_patterns]] (plan-file citations specifically). Keep flagging this
immediately — it keeps slipping past the agent that writes the code.

## Plan-promised test not delivered

`plans/feat-timer-widget-display-android.md`'s テスト section explicitly commits to adding a test
in `test/features/home_widget/home_widget_scheduler_test.dart` proving a `timerControllerProvider`
state change triggers a `syncTimer`-equivalent call ("なければ新規追加" — add new if no sibling
test exists). No such test exists for *any* of the 4 synced widgets in that file (it only has one
pre-existing app-resume test) — so the plan's own "add new if none exist" branch should have fired
and didn't. The new `ref.listen(timerControllerProvider, ...)` wiring in
`home_widget_scheduler.dart` is therefore untested at the scheduler level; only the underlying
`HomeWidgetSyncService.syncTimer` unit is covered. Watch whether this recurs — if a future PR's
plan file promises a test and the diff doesn't deliver it, that's worth escalating as a process gap
independent of whether the missing test would have caught a real bug.

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
