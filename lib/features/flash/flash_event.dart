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

/// Default 完了◯分前 flash points (docs/session-timer-spec.md 3-3節), used
/// to seed `FlashPointsController` on first launch.
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

  /// The moment this flash's animation must *start* so it ends at [instant].
  DateTime get windowStart => instant.subtract(flashAnimationDuration);
}

/// The exact-completion flash plus one flash per entry in [minutesBefore],
/// or `[]` if no completion time is set.
List<FlashEvent> completionFlashEvents(
  CompletionTimeState? completion,
  List<int> minutesBefore,
) {
  final target = completion?.targetTime;
  if (target == null) return const [];
  return _exactPlusMinutesBefore(
    idPrefix: 'completion',
    target: target,
    minutesBefore: minutesBefore,
    exactLabel: '完了時刻です',
    labelFor: (m) => '残り$m分',
  );
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

/// Timer完了 5/3/1分前 flashes plus the exact-completion (0分) flash, or `[]`
/// while the timer is unset. A point already passed at the moment the timer
/// was (re)started is naturally excluded by the queue controller's window
/// check — no special-casing needed here (spec 3-1節: "すでに過ぎているフラッ
/// シュポイントは発火させない").
List<FlashEvent> timerFlashEvents(TimerState? timer) {
  final target = timer?.targetTime;
  if (target == null) return const [];
  return _exactPlusMinutesBefore(
    idPrefix: 'timer',
    target: target,
    minutesBefore: timerFlashPointsMinutes,
    exactLabel: 'タイマー終了です',
    labelFor: (m) => 'タイマー残り$m分',
  );
}

/// Shared shape behind [completionFlashEvents] and [timerFlashEvents]: one
/// exact-instant flash at [target] plus one per entry in [minutesBefore].
List<FlashEvent> _exactPlusMinutesBefore({
  required String idPrefix,
  required DateTime target,
  required List<int> minutesBefore,
  required String exactLabel,
  required String Function(int minutes) labelFor,
}) {
  final targetEpochMs = target.millisecondsSinceEpoch;
  return [
    FlashEvent(
      id: '$idPrefix:$targetEpochMs:0',
      instant: target,
      label: exactLabel,
    ),
    for (final m in minutesBefore)
      FlashEvent(
        id: '$idPrefix:$targetEpochMs:$m',
        instant: target.subtract(Duration(minutes: m)),
        label: labelFor(m),
      ),
  ];
}
