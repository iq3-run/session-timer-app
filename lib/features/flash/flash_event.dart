import 'package:session_timer/features/completion/completion_time_state.dart';
import 'package:session_timer/features/targets/time_target.dart';
import 'package:session_timer/features/timer/timer_state.dart';

/// Length of the strobe animation played by `FlashOverlay`. Each flash event
/// is scheduled to *end* exactly at [FlashEvent.instant], so the overlay
/// starts this long before it (docs/session-timer-spec.md 3-5節).
const flashAnimationDuration = Duration(milliseconds: 3000);

/// Number of visible on/off blinks within [flashAnimationDuration], matching
/// the HTML prototype's `steps(1) 6` strobe animation.
const flashBlinkCount = 6;

/// Default 完了◯分前 flash points (docs/session-timer-spec.md 3-3節). Fixed
/// for now — no settings-sheet customization UI exists yet.
const defaultCompletionFlashPointsMinutes = [
  120,
  90,
  60,
  45,
  30,
  20,
  15,
  10,
  5,
  3,
  2,
  1,
];

/// Timer完了 5/3/1分前 single-shot flash points (spec 3-1節).
const timerFlashPointsMinutes = [5, 3, 1];

/// A single scheduled flash. [instant] is the wall-clock moment the flash
/// animation must *end* — see [flashAnimationDuration].
class FlashEvent {
  const FlashEvent({
    required this.id,
    required this.instant,
    required this.label,
  });

  /// Composite key that embeds the source's current target epoch, so a
  /// changed target (timer reset, edited time target, new completion time)
  /// naturally produces a fresh id — old fired-state for the previous
  /// target is simply never referenced again.
  final String id;

  final DateTime instant;
  final String label;
}

/// The exact-completion flash plus the 完了◯分前 points, or `[]` if no
/// completion time is set.
List<FlashEvent> completionFlashEvents(CompletionTimeState? completion) {
  final target = completion?.targetTime;
  if (target == null) return const [];
  final targetEpochMs = target.millisecondsSinceEpoch;
  return [
    FlashEvent(
      id: 'completion:$targetEpochMs:0',
      instant: target,
      label: '完了時刻です',
    ),
    for (final m in defaultCompletionFlashPointsMinutes)
      FlashEvent(
        id: 'completion:$targetEpochMs:$m',
        instant: target.subtract(Duration(minutes: m)),
        label: '残り$m分',
      ),
  ];
}

/// One flash per time target, ending exactly at its time.
List<FlashEvent> targetFlashEvents(List<TimeTarget> targets) => [
  for (final t in targets)
    FlashEvent(
      id: 'target:${t.id}:${t.epochMs}',
      instant: t.targetTime,
      label: '指定時刻になりました',
    ),
];

/// Timer完了 5/3/1分前 flashes, or `[]` while the timer is unset. A point
/// already passed at the moment the timer was (re)started is naturally
/// excluded by the queue controller's window check — no special-casing
/// needed here (spec 3-1節: "すでに過ぎているフラッシュポイントは発火させ
/// ない").
List<FlashEvent> timerFlashEvents(TimerState? timer) {
  final target = timer?.targetTime;
  if (target == null) return const [];
  final targetEpochMs = target.millisecondsSinceEpoch;
  return [
    for (final m in timerFlashPointsMinutes)
      FlashEvent(
        id: 'timer:$targetEpochMs:$m',
        instant: target.subtract(Duration(minutes: m)),
        label: 'タイマー残り$m分',
      ),
  ];
}
