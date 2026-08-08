import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/completion/completion_time_controller.dart';
import 'package:session_timer/features/completion/completion_time_state.dart';
import 'package:session_timer/features/flash/flash_event.dart';
import 'package:session_timer/features/notifications/notification_event_source.dart';
import 'package:session_timer/features/targets/time_target.dart';
import 'package:session_timer/features/targets/time_targets_controller.dart';
import 'package:session_timer/features/timer/timer_controller.dart';
import 'package:session_timer/features/timer/timer_state.dart';

class _FixedCompletionController extends CompletionTimeController {
  _FixedCompletionController(this._value);
  final CompletionTimeState _value;
  @override
  Future<CompletionTimeState> build() async => _value;
}

class _FixedTargetsController extends TimeTargetsController {
  _FixedTargetsController(this._value);
  final List<TimeTarget> _value;
  @override
  Future<List<TimeTarget>> build() async => _value;
}

class _FixedTimerController extends TimerController {
  _FixedTimerController(this._value);
  final TimerState _value;
  @override
  Future<TimerState> build() async => _value;
}

void main() {
  test(
    'combines completion, target, and timer candidates from all three '
    'sources, matching their own pure event-builder functions',
    () async {
      final completionTarget = DateTime(2099, 1, 1, 12);
      final timeTarget = DateTime(2099, 1, 1, 13);
      final timerTarget = DateTime(2099, 1, 1, 14);

      final completion = CompletionTimeState(
        targetEpochMs: completionTarget.millisecondsSinceEpoch,
      );
      final targets = [
        TimeTarget(id: 't1', epochMs: timeTarget.millisecondsSinceEpoch),
      ];
      final timer = TimerState(
        targetEpochMs: timerTarget.millisecondsSinceEpoch,
      );

      final container = ProviderContainer(
        overrides: [
          completionTimeControllerProvider.overrideWith(
            () => _FixedCompletionController(completion),
          ),
          timeTargetsControllerProvider.overrideWith(
            () => _FixedTargetsController(targets),
          ),
          timerControllerProvider.overrideWith(
            () => _FixedTimerController(timer),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(completionTimeControllerProvider.future);
      await container.read(timeTargetsControllerProvider.future);
      await container.read(timerControllerProvider.future);

      final actual = container
          .read(notificationCandidateEventsProvider)
          .map((e) => e.id)
          .toSet();
      final expected = [
        ...completionFlashEvents(completion),
        ...targetFlashEvents(targets),
        ...timerFlashEvents(timer),
      ].map((e) => e.id).toSet();

      expect(actual, expected);
    },
  );

  test('is empty when no source has a target set', () async {
    final container = ProviderContainer(
      overrides: [
        completionTimeControllerProvider.overrideWith(
          () => _FixedCompletionController(const CompletionTimeState()),
        ),
        timeTargetsControllerProvider.overrideWith(
          () => _FixedTargetsController(const []),
        ),
        timerControllerProvider.overrideWith(
          () => _FixedTimerController(const TimerState()),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(completionTimeControllerProvider.future);
    await container.read(timeTargetsControllerProvider.future);
    await container.read(timerControllerProvider.future);

    expect(container.read(notificationCandidateEventsProvider), isEmpty);
  });
}
