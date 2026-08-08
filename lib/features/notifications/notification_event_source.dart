import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/features/completion/completion_time_controller.dart';
import 'package:session_timer/features/flash/flash_event.dart';
import 'package:session_timer/features/targets/time_targets_controller.dart';
import 'package:session_timer/features/timer/timer_controller.dart';

/// The full set of flash-point instants that should get a scheduled device
/// notification — the same three sources `FlashQueueController` animates,
/// but without any window/firing logic: this only changes when a source's
/// state does, not on every clock tick, since scheduling is done up front
/// rather than at fire time.
final notificationCandidateEventsProvider = Provider<List<FlashEvent>>((ref) {
  final completion = ref.watch(completionTimeControllerProvider).value;
  final targets = ref.watch(timeTargetsControllerProvider).value ?? const [];
  final timer = ref.watch(timerControllerProvider).value;
  return [
    ...completionFlashEvents(completion),
    ...targetFlashEvents(targets),
    ...timerFlashEvents(timer),
  ];
});
