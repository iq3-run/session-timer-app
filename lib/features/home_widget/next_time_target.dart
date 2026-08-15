import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/features/targets/time_target.dart';
import 'package:session_timer/features/targets/time_targets_controller.dart';

/// The earliest target that hasn't passed yet, for the "next target"
/// widget's single-value display. `targets` is expected pre-sorted
/// ascending by `epochMs` (as `TimeTargetsController` always returns it), so
/// the first entry past `now` is the answer.
TimeTarget? nextTimeTarget(List<TimeTarget> targets, DateTime now) {
  final nowEpochMs = now.millisecondsSinceEpoch;
  for (final target in targets) {
    if (target.epochMs > nowEpochMs) return target;
  }
  return null;
}

/// Deliberately doesn't watch a ticking `now` provider — like
/// `notificationCandidateEventsProvider`, this only needs to recompute when
/// the target list itself changes, not on every second's tick.
final nextTimeTargetProvider = Provider<TimeTarget?>((ref) {
  final targets = ref.watch(timeTargetsControllerProvider).value ?? const [];
  return nextTimeTarget(targets, DateTime.now());
});
