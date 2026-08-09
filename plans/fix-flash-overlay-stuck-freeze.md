# Fix: flash overlay gets stuck fully opaque after a stale-window promotion

Issue: <https://github.com/iq3-run/session-timer-app/issues/38>

## Problem

Confirmed on a real device (BlueStacks): backgrounding the app before one or
more flash-point windows fire, then resuming after they've all passed,
leaves the screen permanently solid amber — `FlashOverlay` never returns to
showing the normal UI, even though a flash animation is only supposed to
last 3 seconds (`flashAnimationDuration`).

Root cause (found via the `root-cause-debugger` subagent, confirmed with an
empirical widget test that reproduces the stuck state with zero device
backgrounding involved — just two `FlashQueueController.setActive()` calls):

`FlashOverlay._elapsedProgress()` (`lib/features/flash/flash_overlay.dart`)
computes how far into its 3s window a newly-promoted event already is, via
`DateTime.now()`, clamped to `[0.0, 1.0]`. When an event is promoted well
after its window has fully closed (e.g. `FlashQueueController` admitted
several candidates while the app was backgrounded, each becoming `active`
in turn as the previous one's window also turns out to be closed), this
clamps to exactly `1.0`, and the `ref.listen` callback calls
`_controller.forward(from: 1.0)`.

Flutter's `AnimationController` takes a synchronous zero-duration fast path
whenever `target == value` (both `1.0` here): it sets
`_status = AnimationStatus.completed` and calls `_checkStatusChanged()`,
but `_checkStatusChanged()` only notifies listeners when
`_lastReportedStatus != newStatus`. Since the *previous* event already
completed normally and left `_lastReportedStatus == completed`, this
synthetic completion is silently swallowed — `_onStatusChanged` never
fires, `FlashQueueController.advance()` is never called, and `_active` /
`_controller.value` stay pinned forever at the stale event / `1.0`, which
`_isVisibleSegment` maps to a permanently-visible (odd) segment.

- `lib/features/flash/flash_overlay.dart:42-47` (the `ref.listen` callback)

## Fix

In the `ref.listen` callback, check `_elapsedProgress(event) >= 1.0` before
animating. If the window has already fully closed by the time the event
was promoted, call `advance()` directly instead of `forward()` — mirroring
the "missed window" handling `FlashQueueController._admit` already does
for windows that close before even being admitted, just applied at the
point where a *queued* event's window can close between admission and
promotion.

## Out of scope

- The originally-reported trigger ("long-press on the timer's +30秒/+1分
  buttons while a flash is playing") was investigated but no concrete
  mechanical path from `TimerController.quickStart` into this exact stale-
  promotion state was found — those flash points are already in the past
  the instant they're computed for a short quick-start duration, so they
  get marked fired without ever being queued. This fix covers the general
  bug class (any event promoted after its window has fully elapsed); if
  the long-press trigger turns out to be a distinct path, it needs its own
  investigation with a concrete repro.

## Verification

- `dart format`
- `flutter analyze`
- `flutter test` (new widget test in `test/features/flash/flash_overlay_test.dart`
  covering: first event completes normally, then a second event promoted
  with an `instant` minutes in the past advances immediately instead of
  leaving the overlay stuck opaque)
- Manual: reproduce the original device repro (set completion time a few
  minutes out, background before any flash point fires, wait through all
  of them, resume) and confirm the overlay clears instead of freezing.
