import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/core/clock/now_provider.dart';
import 'package:session_timer/features/completion/completion_time_controller.dart';
import 'package:session_timer/features/completion/completion_time_state.dart';
import 'package:session_timer/features/flash/flash_point_config.dart';
import 'package:session_timer/features/flash/flash_points_controller.dart';
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

class _MutableCompletionController extends CompletionTimeController {
  @override
  Future<CompletionTimeState> build() async => const CompletionTimeState();

  void setEpoch(int? epochMs) {
    state = AsyncData(CompletionTimeState(targetEpochMs: epochMs));
  }
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

class _FixedFlashPointsController extends FlashPointsController {
  _FixedFlashPointsController(this._value);
  final List<FlashPointConfig> _value;
  @override
  Future<List<FlashPointConfig>> build() async => _value;
}

class _MutableFlashPointsController extends FlashPointsController {
  _MutableFlashPointsController(this._initial);
  final List<FlashPointConfig> _initial;
  @override
  Future<List<FlashPointConfig>> build() async => _initial;

  void setPoints(List<FlashPointConfig> points) => state = AsyncData(points);
}

Future<ProviderContainer> _buildContainer({
  required StreamController<DateTime> clock,
  List<TimeTarget> targets = const [],
  CompletionTimeState completion = const CompletionTimeState(),
  TimerState timer = const TimerState(),
  // Empty by default so tests aren't crowded with the 12 default
  // completion-countdown points unless a test opts in.
  List<FlashPointConfig> flashPoints = const [],
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
      flashPointsControllerProvider.overrideWith(
        () => _FixedFlashPointsController(flashPoints),
      ),
    ],
  );
  // Resolve the four (fake) async source controllers before the clock
  // starts ticking, so FlashQueueController's first real build sees the
  // test's data instead of racing its own loading state.
  await container.read(completionTimeControllerProvider.future);
  await container.read(timeTargetsControllerProvider.future);
  await container.read(timerControllerProvider.future);
  await container.read(flashPointsControllerProvider.future);
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

    test(
      'reselecting the same completion time after clearing it fires again, '
      'instead of being silently suppressed by stale fired state',
      () async {
        final clock = StreamController<DateTime>.broadcast();
        addTearDown(clock.close);
        final target = DateTime(2099, 1, 1, 12);
        final completionController = _MutableCompletionController();
        final container = ProviderContainer(
          overrides: [
            nowProvider.overrideWith((ref) => clock.stream),
            completionTimeControllerProvider.overrideWith(
              () => completionController,
            ),
            timeTargetsControllerProvider.overrideWith(
              () => _FixedTargetsController(const []),
            ),
            timerControllerProvider.overrideWith(
              () => _FixedTimerController(const TimerState()),
            ),
            flashPointsControllerProvider.overrideWith(
              () => _FixedFlashPointsController(const []),
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(completionTimeControllerProvider.future);
        await container.read(timeTargetsControllerProvider.future);
        await container.read(timerControllerProvider.future);
        await container.read(flashPointsControllerProvider.future);
        container.listen(flashQueueControllerProvider, (_, _) {});
        final id = 'completion:${target.millisecondsSinceEpoch}:0';

        completionController.setEpoch(target.millisecondsSinceEpoch);
        await _tick(clock, target);
        expect(container.read(flashQueueControllerProvider).active?.id, id);
        container.read(flashQueueControllerProvider.notifier).advance();

        completionController.setEpoch(null);
        await Future<void>.delayed(Duration.zero);
        completionController.setEpoch(target.millisecondsSinceEpoch);
        await _tick(clock, target);

        expect(container.read(flashQueueControllerProvider).active?.id, id);
      },
    );

    test(
      'a flash-disabled completion point never activates, even once its '
      'window is due',
      () async {
        final clock = StreamController<DateTime>.broadcast();
        addTearDown(clock.close);
        final target = DateTime(2099, 1, 1, 12);
        final container = await _buildContainer(
          clock: clock,
          completion: CompletionTimeState(
            targetEpochMs: target.millisecondsSinceEpoch,
          ),
          flashPoints: const [
            FlashPointConfig(minutes: 5, flashEnabled: false),
          ],
        );
        addTearDown(container.dispose);

        await _tick(clock, target.subtract(const Duration(minutes: 5)));

        final state = container.read(flashQueueControllerProvider);
        expect(state.active, isNull);
        expect(state.firedIds, isEmpty);
      },
    );

    test(
      'a queued (not yet active) completion point is dropped once its flash '
      'is disabled, instead of firing anyway when promoted',
      () async {
        final clock = StreamController<DateTime>.broadcast();
        addTearDown(clock.close);
        final target = DateTime(2099, 1, 1, 12);
        final completionEpoch = target.millisecondsSinceEpoch;
        // The '5' point's window opens 2s after the target's, so a single
        // tick at the target's instant admits both — more than the 1s merge
        // threshold apart, so the target is promoted to active and the
        // completion point is left queued behind it.
        final targetInstant = target
            .subtract(const Duration(minutes: 5))
            .subtract(const Duration(seconds: 2));
        final flashPointsController = _MutableFlashPointsController(const [
          FlashPointConfig(minutes: 5),
        ]);
        final container = ProviderContainer(
          overrides: [
            nowProvider.overrideWith((ref) => clock.stream),
            completionTimeControllerProvider.overrideWith(
              () => _FixedCompletionController(
                CompletionTimeState(targetEpochMs: completionEpoch),
              ),
            ),
            timeTargetsControllerProvider.overrideWith(
              () => _FixedTargetsController([
                TimeTarget(
                  id: 't1',
                  epochMs: targetInstant.millisecondsSinceEpoch,
                ),
              ]),
            ),
            timerControllerProvider.overrideWith(
              () => _FixedTimerController(const TimerState()),
            ),
            flashPointsControllerProvider.overrideWith(
              () => flashPointsController,
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(completionTimeControllerProvider.future);
        await container.read(timeTargetsControllerProvider.future);
        await container.read(timerControllerProvider.future);
        await container.read(flashPointsControllerProvider.future);
        container.listen(flashQueueControllerProvider, (_, _) {});

        await _tick(clock, targetInstant);
        expect(
          container.read(flashQueueControllerProvider).active?.id,
          'target:t1:${targetInstant.millisecondsSinceEpoch}',
        );

        flashPointsController.setPoints(const [
          FlashPointConfig(minutes: 5, flashEnabled: false),
        ]);
        await Future<void>.delayed(Duration.zero);
        // Reading the provider (not just `.notifier`) forces any pending
        // rebuild from the setPoints mutation above to flush before
        // advance() inspects `_queue` — otherwise advance() could act on a
        // stale, not-yet-purged queue.
        container.read(flashQueueControllerProvider);

        container.read(flashQueueControllerProvider.notifier).advance();
        final afterAdvance = container.read(flashQueueControllerProvider);
        expect(afterAdvance.active, isNull);

        // Past the disabled point's own original instant (target - 5min),
        // but well short of the always-on exact-completion event at
        // `target` itself — isolates "the disabled point specifically never
        // resurfaces" from that unrelated always-fires event.
        await _tick(
          clock,
          target
              .subtract(const Duration(minutes: 5))
              .add(
                const Duration(seconds: 1),
              ),
        );
        // The disabled point was already marked "window entered" back when
        // it was first admitted into `_queue` during the initial tick —
        // `_admit` records that unconditionally before the merge/queue
        // decision, so its id staying in `firedIds` here is expected, not a
        // sign the purge failed. `active` staying null is the real check.
        expect(container.read(flashQueueControllerProvider).active, isNull);
      },
    );
  });
}
