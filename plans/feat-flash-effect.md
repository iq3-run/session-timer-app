# Feat: screen flash effect (completion / time targets / timer)

Issue: <https://github.com/iq3-run/session-timer-app/issues/19>

## Scope

Per docs/session-timer-spec.md 3-3/3-4/3-5/3-5-1節, plus the timer's 5/3/1
分前 single-flash from 3-1節 that `plans/feat-countdown-timer.md` explicitly
deferred to "a later task building shared flash infrastructure". This is
that task.

Three flash sources feed one shared overlay + queue:

1. Completion countdown — fixed default 12 points (3-3節) + the exact
   completion instant itself (carried over from the HTML prototype's
   `completedFlashed`, section 2 "そのまま踏襲").
2. Time targets — one flash per target, ending exactly at its time.
3. Timer — single-shot flashes 5/3/1 minutes before its target.

Out of scope (separate issues, confirmed with the user before starting):

- Device notification + vibration.
- Flash-point add/remove customization UI — no ⚙ settings sheet exists yet
  anywhere in the app; building one is a separate future issue. This PR
  ships the 3-3節 defaults as a fixed, non-editable list.
- Weekend milestones, NTP sync (separate Issue #1 scope items).

## Design decision: bounded trigger window replaces persisted fired-flags

The HTML prototype fires a flash the instant `now >= triggerAt` and never
un-fires, so spec 3-7節 has it persist the fired-point set alongside the
completion time specifically to stop a restart from replaying every
already-passed point in one burst.

This implementation instead bounds each event to a window
`[instant - flashAnimationDuration, instant]` (this window *is* 3-5節's
"start early, end exactly at the instant" rule). Once `now` passes
`instant`, the window is permanently closed — a restart after that point
sees `now > instant` and skips it, with no persistence needed. This also
naturally satisfies 3-1's "already-past flash points at linked-timer-setup
time are skipped" bullet and "reset clears fired records" bullet for free
(see event identity below), so no separate reset/clear code path is
needed either.

This is a deliberate deviation from the letter of 3-7節 (which asks for
persistence) in favor of a simpler mechanism that meets the same stated
goal. Flagging this in the PR's Items to Confirm.

Consequence: if the app is backgrounded/killed for longer than
`flashAnimationDuration` (3s) across a flash's window, that flash is
silently skipped rather than replayed late. Acceptable given the app's
primary use case is a screen left on throughout the session.

## Event model

`lib/features/flash/flash_event.dart`

```dart
const flashAnimationDuration = Duration(milliseconds: 3000);
const flashBlinkCount = 6; // matches the HTML prototype's 6-blink strobe
const defaultCompletionFlashPointsMinutes = [
  120, 90, 60, 45, 30, 20, 15, 10, 5, 3, 2, 1,
];
const timerFlashPointsMinutes = [5, 3, 1];

class FlashEvent {
  const FlashEvent({required this.id, required this.instant, required this.label});
  final String id;       // composite key, see below
  final DateTime instant; // the moment the flash must END
  final String label;
}
```

Event id includes the source's current target epoch, so a changed target
(timer reset, target time edited) produces a brand-new id — old fired
entries for the previous target simply stop being referenced:

- Completion: `completion:<targetEpochMs>:<minutesBefore>` (`0` for the
  exact-completion event)
- Time target: `target:<targetId>:<epochMs>`
- Timer: `timer:<targetEpochMs>:<minutesBefore>`

Three pure functions build candidate lists from each controller's current
state (`completionFlashEvents`, `targetFlashEvents`, `timerFlashEvents`) —
no `now` dependency, so they're trivially unit-testable.

## Queue controller

`lib/features/flash/flash_queue_controller.dart` — plain `Notifier`
(no persistence; this is session-scoped, ephemeral state):

```dart
class FlashQueueState {
  const FlashQueueState({this.active, required this.firedIds});
  final FlashEvent? active;
  final Set<String> firedIds;
}
```

Instance fields `_firedIds` (Set) and `_queue` (List, not exposed in
state) live on the notifier itself, surviving `build()` re-invocations the
same way `TimerController._lastGood` survives rebuilds.

`build()` re-runs on every `nowProvider` tick (1s) and whenever
completion/targets/timer state changes:

1. Gather candidates from all three sources.
2. Skip any whose id is already in `_firedIds`.
3. Skip any not yet in their window (`now < instant - flashAnimationDuration`).
4. If `now > instant` (window already closed — missed), mark fired and
   skip silently (see design decision above).
5. Otherwise the window is open: mark fired, then merge-or-queue —
   3-5-1節's "within ~1s → merge" / "further apart → queue, don't
   interrupt":
   - if an event is currently `active` and `(event.instant - active.instant).abs() <= 1s` → merge, don't enqueue.
   - else if the queue's last entry is within 1s → merge, don't enqueue.
   - else append to `_queue`.
6. If nothing is `active` and the queue is non-empty, pop the first entry
   into `active`.

`void advance()` — called by the overlay when its local animation
finishes: pops the next queued event into `active` (or clears it),
chaining queued flashes back-to-back without a gap.

## Overlay widget

`lib/features/flash/flash_overlay.dart` — full-screen `IgnorePointer`
amber `ColoredBox`, driven by its own `AnimationController`
(`vsync`, `duration: flashAnimationDuration`) rather than the 1Hz
`nowProvider` tick, since the blink pattern needs sub-second granularity:

- Watches `flashQueueControllerProvider.active`. When the event's `id`
  changes (new flash, including a same-tick chain from `advance()`),
  restarts the controller from 0.
- Opacity per frame: split `[0,1]` into `flashBlinkCount * 2` equal
  segments, visible on odd segments — 6 visible blinks over 3s, matching
  the prototype's `steps(1) 6` CSS animation.
- On `AnimationStatus.completed`, calls
  `ref.read(flashQueueControllerProvider.notifier).advance()`.

Mounted in `clock_screen.dart` as the topmost layer of a `Stack` wrapping
the existing `Scaffold` body content.

## Chip carousel (3-4節)

`lib/features/flash/flash_points_chip_row.dart` — completion-countdown
points only (matches the HTML prototype's `chipRow`, which never included
target/timer flashes). Renders nothing when no completion target is set.

- Points shown descending by minutes-before (120 → 1), which is also
  ascending trigger-instant order — same order the prototype used.
- Window of 3 visible at a time (`_windowStart` int, clamped to
  `[0, points.length - 3]`).
- Default window: index of the first not-yet-fired point (via
  `FlashQueueState.firedIds`), clamped into range; if all fired, shows the
  last 3.
- Horizontal swipe shifts `_windowStart` by a full page (±3, clamped).
  Interpretation of "3つを切り替え" since the spec doesn't pin an exact
  shift amount — flagging in Items to Confirm.
- "…" indicator rendered when items exist before/after the current
  window.
- 5s idle `Timer`, reset on every swipe, that snaps `_windowStart` back to
  the computed default.
- Each chip shows the countdown to `instant` (unaffected by the
  animation-duration window shift — that shift only moves when the
  overlay animation *starts*, not the displayed target moment), or "済"
  once `firedIds` contains its id.

## Wiring

- `timeTargetFlashEvents` reads `timeTargetsControllerProvider`.
- `timerFlashEvents` reads `timerControllerProvider`.
- No changes needed to `CompletionTimeState`, `TimeTarget`, or
  `TimerState` — flash bookkeeping lives entirely in the new queue
  controller, keyed off data those already expose.

## Tests

- `test/features/flash/flash_event_test.dart` — candidate generation per
  source (window edges, exact-completion event, timer's already-past
  point at linked-setup time being naturally excluded).
- `test/features/flash/flash_queue_controller_test.dart` — window
  open/close boundaries, 1s merge threshold, sequential queueing without
  dropping events, id invalidation on target change (reset/edit).
- `test/features/flash/flash_overlay_test.dart` — widget test driving
  `AnimationController` via `WidgetTester.pump`, asserting the blink
  pattern and the `advance()` call on completion.
- `test/features/flash/flash_points_chip_row_test.dart` — default window
  selection, swipe paging, 5s idle revert (`WidgetTester.pump` with fake
  timers), "済" vs countdown rendering.

## Verification

- `dart format`
- `flutter analyze`
- `flutter test`
- debug build
- BlueStacks emulator: completion + a near-future time target + a short
  timer all flashing close together to see the merge/queue behavior live,
  chip carousel swipe + 5s auto-revert, exact-completion flash.
