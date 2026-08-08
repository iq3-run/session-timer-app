# Feat: countdown timer (normal / stopwatch-linked)

Issue: <https://github.com/iq3-run/session-timer-app/issues/17>

## Scope

Timer core only, per docs/session-timer-spec.md 3-1節. Flash effects (5/3/1
minute single-flash before completion) are explicitly out of scope — no
common flash infrastructure (3-4/3-5/3-5-1節) exists yet for any feature
(completion countdown, time targets, stopwatch either), so it will be built
once as a shared piece across all of them in a later task. Confirmed with
the user before starting this plan.

## Model

`lib/features/timer/timer_state.dart`

```dart
enum TimerMode { normal, linked }

class TimerState {
  const TimerState({this.targetEpochMs, this.mode = TimerMode.normal});
  final int? targetEpochMs;
  final TimerMode mode;
  ...
}
```

- `targetEpochMs == null` means unset (never configured, or fully reset).
- `mode` is kept even while unset — it doubles as "last selected mode",
  which the +30s/+1min long-press quick-start needs (spec: 直前に選んでいた
  モードを引き継ぐ).
- No `isOverdueResetArmed`/fired-flash bookkeeping — out of scope per above.
- Unlike `CompletionTimeState` (3-7節), the timer has no time-based
  auto-reset-on-restart: 3-9節 is explicit that a running/overdue timer is
  restored as-is on restart, because it's tracked as "remaining duration"
  logic (an absolute target epoch that a normal clock comparison naturally
  keeps counting past zero), not a wall-clock deadline that becomes
  meaningless once passed.

## Target-epoch computation

Both modes reduce to a single absolute `targetEpochMs`:

- Normal: `target = now + duration`.
- Linked: `target = now + (duration - stopwatch.elapsedAt(now))`. This
  matches the spec example directly (3 min already elapsed on the
  stopwatch, 7 min duration → target is 4 min out) and correctly lets the
  timer keep counting down independently afterward, since stopwatch
  pause/resume must not affect it (spec: 独立してカウントを続ける).

So `TimerController.start(mode, duration)` computes the target once at
call time and stores it — no continuous re-sync to the stopwatch is
needed or wanted.

## Controller

`lib/features/timer/timer_controller.dart`, following the
`StopwatchController` pattern (mutation queue + `_lastGood` +
`_initialLoad` + single JSON key, `timer_state_json`):

- `start(TimerMode mode, Duration duration)` — full (re)start, used by the
  settings-dialog confirm action. Always replaces any in-progress timer.
- `reset()` — long-press: clears to `TimerState(mode: <kept>)`.
- `addTime(Duration amount)` — the tap on +30s/+1min:
  - if not overdue: `target += amount`.
  - if overdue (or unset): starts a fresh countdown of exactly `amount`
    (mode unchanged).
- `quickStart(Duration amount)` — the long-press on +30s/+1min: always
  starts a fresh countdown of exactly `amount`, regardless of current
  state, keeping `mode` from the last configured timer.
- `start`/`addTime`(when it starts fresh)/`quickStart` all auto-start the
  stopwatch if it isn't already running (spec: タイマー開始時の自動連動),
  via `ref.read(stopwatchControllerProvider.notifier)`.

## Cross-controller wiring (stopwatch ↔ timer)

`StopwatchController` gains calls into `TimerController`:

- `reset()` (long-press) — unconditionally also resets the timer.
- `resetAndRestart()` (double-tap) — resets the timer only if it is
  currently overdue (counting up past zero); leaves it alone otherwise.

Implemented via `ref.read(timerControllerProvider.notifier)` inside the
stopwatch controller's mutate methods, after the stopwatch's own state has
committed.

## UI

`lib/features/timer/timer_section.dart`, added to `clock_screen.dart`
after `StopwatchSection`:

- Main tappable area (`HitTestBehavior.opaque`, matching the existing
  sections): shows remaining/overdue time, mode label, subtitle.
  - Tap → opens a bottom sheet with a mode selector (通常/連動) and a
    `CupertinoTimerPicker` (mode: `ms`) for duration, confirmed by a
    start button → `TimerController.start`.
  - Long-press → `TimerController.reset()`.
- Two buttons, "+30秒" / "+1分":
  - `onTap` → `TimerController.addTime(...)`.
  - `onLongPress` → `TimerController.quickStart(...)`.
- Overdue state renders in red (matching `CompletionCountdownSection`'s
  overdue styling), reusing `formatCountdown`'s existing negative-duration
  (`-MM:SS`) convention, and keeps counting up.

## Verification

- `dart format`
- `flutter analyze`
- `flutter test` (new `timer_controller_test.dart`, `timer_state_test.dart`,
  plus stopwatch-controller tests extended for the new cross-reset
  behavior)
- debug build
- manual check in the run skill / emulator: mode picker, tap-to-restart
  while running, long-press full reset, +30s/+1min tap vs. long-press in
  both counting-down and overdue states, stopwatch auto-start on timer
  start, stopwatch pause/resume not affecting timer, stopwatch long-press
  reset cascading to timer, stopwatch double-tap only resetting an overdue
  timer
