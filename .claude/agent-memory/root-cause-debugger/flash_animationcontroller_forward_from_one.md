---
name: flash-animationcontroller-forward-from-one
description: Flutter AnimationController.forward(from: 1.0) never fires the completed status listener when the controller's last reported status was already `completed` — silently freezes any code relying on that callback
metadata:
  type: project
---

## Mechanism (verified against Flutter 3.44.9 SDK source and Riverpod 3.4.2)

`AnimationController._animateToInternal` (`packages/flutter/lib/src/animation/animation_controller.dart`,
around line 640-690 in this SDK checkout) takes a **synchronous zero-duration
fast path** whenever `target == value` after `from:` is applied — it never
calls `_ticker.start()`. It still assigns `_status = AnimationStatus.completed`
and calls `_checkStatusChanged()`, but `_checkStatusChanged()`
(same file, ~line 933) only calls `notifyStatusListeners` when
`_lastReportedStatus != newStatus`. If the controller was already reported
`completed` (e.g. from the *previous* item finishing normally), re-arriving at
`completed` via the fast path is a no-op — the status listener never fires.

`AnimationController.stop()` does **not** reset `_lastReportedStatus` (it's
documented as sending no notifications), so `stop()` immediately before
`forward(from: 1.0)` does not clear the de-dup state either.

## Where this bit us

`lib/features/flash/flash_overlay.dart`'s `_elapsedProgress()` computes a
wall-clock catch-up starting point (`DateTime.now().difference(windowStart) /
duration`, clamped to `[0,1]`) and calls `_controller.forward(from:
progress)`. When a *second* (or later) queued flash event gets promoted well
after its own 3s window has already fully elapsed — the app-backgrounding
repro is the reliable trigger, since `FlashQueueController` keeps admitting/
queuing candidates every 1s tick regardless of foreground state, while
`FlashOverlay`'s ticker is frozen (no vsync frames delivered while
backgrounded) so `advance()` for the first event doesn't fire until resume —
`_elapsedProgress` clamps to exactly `1.0`. `forward(from: 1.0)` then hits the
fast path described above, and because the *first* event's natural completion
already set `_lastReportedStatus = completed`, the second event's synthetic
completion is swallowed. `_onStatusChanged` never calls
`FlashQueueController.advance()`, so `_active` is stuck on that event forever
and `_controller.value` is stuck at `1.0` (segment 11 of 12 in
`_isVisibleSegment`, which is odd → permanently visible amber).

Confirmed with a **pure widget test, no backgrounding simulation needed** —
just two consecutive `setActive()` calls where the second event's `instant`
is minutes in the past reproduces the stuck state deterministically. See PR
history / the diagnosis session for the throwaway probe test; it is not kept
in the repo.

## The fix shape (not yet applied as of this writing)

Don't rely on the AnimationController to synthesize a completion callback for
an already-expired catch-up. In the `ref.listen` callback, check whether
`_elapsedProgress(event) >= 1.0` *before* calling `forward()`; if so, treat it
like `FlashQueueController._admit`'s existing "missed window" case and call
`advance()` directly instead of animating.

## Generalization — check other call sites

Grep for `\.forward(from:` / `\.reverse(from:` anywhere a `from` value is
computed from a **fluctuating external clock or elapsed-time calculation**
(not a constant) and the code's correctness depends on the completion status
listener firing every time. Same defect class applies to `reverse(from:)`
hitting `dismissed` when already dismissed. As of this diagnosis, the only
occurrence in this repo is `flash_overlay.dart`.

## Ruled out during this investigation

- Ticker fully stalling and never resuming after backgrounding — false; Flutter's
  ticker does resume on the next frame after foreground resume and correctly
  drives the *first* queued animation to completion normally.
- Riverpod reentrant `state =` mutation being blocked/thrown (`element.dart`
  `_debugAssertNotificationAllowed`) — checked the assert; it only guards a
  provider mutating a *different* provider during that provider's own build,
  not a Notifier synchronously re-entering its own `state =` from a listener
  callback. No exception occurs; the recursion is legal and silent — the real
  culprit is purely the AnimationController status de-dup described above.
- The long-press `+30秒`/`+1分` freeze report sharing the *same* trigger via
  `TimerController.quickStart` — traced `quickStart` → `timerFlashEvents`:
  flash points 5/3/1 min before a freshly-started short timer are already
  fully in the past the instant they're computed, so
  `FlashQueueController._admit` marks them fired without ever queuing them
  (`now.isAfter(event.instant)` short-circuits before reaching `_queue.add`).
  No concrete mechanical path from `quickStart` into the stale-promotion bug
  was found — this remains unconfirmed/unreproduced as a distinct question,
  not folded into this root cause.
