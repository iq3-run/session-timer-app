import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/core/clock/now_provider.dart';
import 'package:session_timer/features/completion/completion_time_controller.dart';
import 'package:session_timer/features/completion/completion_time_state.dart';
import 'package:session_timer/features/flash/flash_queue_controller.dart';
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

Future<ProviderContainer> _buildContainer({
  required StreamController<DateTime> clock,
  List<TimeTarget> targets = const [],
  CompletionTimeState completion = const CompletionTimeState(),
  TimerState timer = const TimerState(),
}) async {
  final container = ProviderContainer(
    overrides: [
      nowProvider.overrideWith((ref) => clock.stream),
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
  // Resolve the three (fake) async source controllers before the clock
  // starts ticking, so FlashQueueController's first real build sees the
  // test's data instead of racing its own loading state.
  await container.read(completionTimeControllerProvider.future);
  await container.read(timeTargetsControllerProvider.future);
  await container.read(timerControllerProvider.future);
  // Keep the queue controller (and therefore nowProvider) subscribed for the
  // whole test, matching the always-on widget tree in the real app.
  container.listen(flashQueueControllerProvider, (_, _) {});
  return container;
}

Future<void> _tick(StreamController<DateTime> clock, DateTime now) async {
  clock.add(now);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  group('FlashQueueController', () {
    test('does not fire before the window opens', () async {
      final clock = StreamController<DateTime>.broadcast();
      addTearDown(clock.close);
      final target = DateTime(2099, 1, 1, 12);
      final container = await _buildContainer(
        clock: clock,
        targets: [
          TimeTarget(id: 't1', epochMs: target.millisecondsSinceEpoch),
        ],
      );
      addTearDown(container.dispose);

      await _tick(clock, target.subtract(const Duration(seconds: 10)));

      final state = container.read(flashQueueControllerProvider);
      expect(state.active, isNull);
      expect(state.firedIds, isEmpty);
    });

    test(
      'activates once now enters the [instant - duration, instant] window',
      () async {
        final clock = StreamController<DateTime>.broadcast();
        addTearDown(clock.close);
        final target = DateTime(2099, 1, 1, 12);
        final container = await _buildContainer(
          clock: clock,
          targets: [
            TimeTarget(id: 't1', epochMs: target.millisecondsSinceEpoch),
          ],
        );
        addTearDown(container.dispose);

        await _tick(clock, target.subtract(const Duration(seconds: 2)));

        final state = container.read(flashQueueControllerProvider);
        expect(state.active?.id, 'target:t1:${target.millisecondsSinceEpoch}');
      },
    );

    test(
      'marks a missed window (long background gap) as fired without '
      'activating',
      () async {
        final clock = StreamController<DateTime>.broadcast();
        addTearDown(clock.close);
        final target = DateTime(2099, 1, 1, 12);
        final container = await _buildContainer(
          clock: clock,
          targets: [
            TimeTarget(id: 't1', epochMs: target.millisecondsSinceEpoch),
          ],
        );
        addTearDown(container.dispose);

        await _tick(clock, target.add(const Duration(minutes: 5)));

        final state = container.read(flashQueueControllerProvider);
        expect(state.active, isNull);
        expect(
          state.firedIds,
          contains('target:t1:${target.millisecondsSinceEpoch}'),
        );
      },
    );

    test('merges two events within 1s into a single active flash', () async {
      final clock = StreamController<DateTime>.broadcast();
      addTearDown(clock.close);
      final t0 = DateTime(2099, 1, 1, 12);
      final container = await _buildContainer(
        clock: clock,
        completion: CompletionTimeState(
          targetEpochMs: t0.millisecondsSinceEpoch,
        ),
        targets: [TimeTarget(id: 't1', epochMs: t0.millisecondsSinceEpoch)],
      );
      addTearDown(container.dispose);

      await _tick(clock, t0);

      // Both the exact-completion event and the coincident time target are
      // due at t0; they must collapse into one active flash, not two — if
      // they hadn't merged, a single advance() below would still leave the
      // second one active.
      expect(container.read(flashQueueControllerProvider).active, isNotNull);
      container.read(flashQueueControllerProvider.notifier).advance();
      expect(container.read(flashQueueControllerProvider).active, isNull);
    });

    test(
      'queues events more than 1s apart and plays them in order without '
      'dropping either',
      () async {
        final clock = StreamController<DateTime>.broadcast();
        addTearDown(clock.close);
        final t0 = DateTime(2099, 1, 1, 12);
        final t1Instant = t0.add(const Duration(seconds: 2));
        final container = await _buildContainer(
          clock: clock,
          targets: [
            TimeTarget(id: 't1', epochMs: t0.millisecondsSinceEpoch),
            TimeTarget(id: 't2', epochMs: t1Instant.millisecondsSinceEpoch),
          ],
        );
        addTearDown(container.dispose);

        await _tick(clock, t0);

        final first = container.read(flashQueueControllerProvider).active;
        expect(first?.id, 'target:t1:${t0.millisecondsSinceEpoch}');

        container.read(flashQueueControllerProvider.notifier).advance();
        final second = container.read(flashQueueControllerProvider).active;
        expect(second?.id, 'target:t2:${t1Instant.millisecondsSinceEpoch}');
      },
    );

    test(
      'plays events in chronological order even when they become due in a '
      'different order (e.g. resuming after a long background gap)',
      () async {
        final clock = StreamController<DateTime>.broadcast();
        addTearDown(clock.close);
        final early = DateTime(2099, 1, 1, 12);
        final mid = early.add(const Duration(milliseconds: 500));
        final late = early.add(const Duration(seconds: 3));
        // Listed out of chronological order — 'late' is due first in this
        // list — to prove admission sorts by instant instead of trusting
        // source order.
        final container = await _buildContainer(
          clock: clock,
          targets: [
            TimeTarget(id: 'late', epochMs: late.millisecondsSinceEpoch),
            TimeTarget(id: 'early', epochMs: early.millisecondsSinceEpoch),
            TimeTarget(id: 'mid', epochMs: mid.millisecondsSinceEpoch),
          ],
        );
        addTearDown(container.dispose);

        // All three windows are simultaneously open only exactly at `early`
        // (its window ends there, `late`'s window starts there, and `mid`'s
        // spans right through it).
        await _tick(clock, early);

        final first = container.read(flashQueueControllerProvider).active;
        expect(first?.id, 'target:early:${early.millisecondsSinceEpoch}');

        container.read(flashQueueControllerProvider.notifier).advance();
        final second = container.read(flashQueueControllerProvider).active;
        expect(second?.id, 'target:late:${late.millisecondsSinceEpoch}');
      },
    );
  });
}
