import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/stopwatch/stopwatch_controller.dart';
import 'package:session_timer/features/timer/timer_controller.dart';
import 'package:session_timer/features/timer/timer_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('TimerController', () {
    test('starts unset with normal mode when nothing is persisted', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = await container.read(timerControllerProvider.future);

      expect(state.isRunning, isFalse);
      expect(state.mode, TimerMode.normal);
    });

    test(
      'start (normal mode) targets roughly now + duration and auto-starts '
      'the stopwatch',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(timerControllerProvider.future);
        await container.read(stopwatchControllerProvider.future);

        final beforeCallEpochMs = DateTime.now().millisecondsSinceEpoch;
        await container
            .read(timerControllerProvider.notifier)
            .start(TimerMode.normal, const Duration(minutes: 5));
        final state = await container.read(timerControllerProvider.future);
        final stopwatch = await container.read(
          stopwatchControllerProvider.future,
        );

        expect(
          state.targetEpochMs,
          closeTo(
            beforeCallEpochMs + const Duration(minutes: 5).inMilliseconds,
            200,
          ),
        );
        expect(stopwatch.isRunning, isTrue);
      },
    );

    test(
      'start (linked mode) subtracts the time already elapsed on the '
      'stopwatch from the duration',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(timerControllerProvider.future);
        await container.read(stopwatchControllerProvider.future);
        await container.read(stopwatchControllerProvider.notifier).toggle();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final beforeCallEpochMs = DateTime.now().millisecondsSinceEpoch;
        await container
            .read(timerControllerProvider.notifier)
            .start(TimerMode.linked, const Duration(minutes: 7));
        final state = await container.read(timerControllerProvider.future);

        // With ~50ms already elapsed on the stopwatch, the remaining time at
        // call time should be just under 7 minutes, not a full 7 minutes.
        final remainingMs = state.targetEpochMs! - beforeCallEpochMs;
        expect(
          remainingMs,
          lessThan(const Duration(minutes: 7).inMilliseconds),
        );
        expect(
          remainingMs,
          greaterThan(const Duration(minutes: 7).inMilliseconds - 500),
        );
      },
    );

    test(
      'start does not pause the stopwatch when it is already running',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(timerControllerProvider.future);
        await container.read(stopwatchControllerProvider.future);
        await container.read(stopwatchControllerProvider.notifier).toggle();

        await container
            .read(timerControllerProvider.notifier)
            .start(TimerMode.normal, const Duration(minutes: 1));
        final stopwatch = await container.read(
          stopwatchControllerProvider.future,
        );

        expect(stopwatch.isRunning, isTrue);
      },
    );

    test('reset clears the target but keeps the last selected mode', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(timerControllerProvider.future);
      await container.read(stopwatchControllerProvider.future);
      final notifier = container.read(timerControllerProvider.notifier);
      await notifier.start(TimerMode.linked, const Duration(minutes: 1));

      await notifier.reset();
      final state = await container.read(timerControllerProvider.future);

      expect(state.isRunning, isFalse);
      expect(state.mode, TimerMode.linked);
    });

    test(
      'addTime extends the remaining time while still counting down',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(timerControllerProvider.future);
        await container.read(stopwatchControllerProvider.future);
        final notifier = container.read(timerControllerProvider.notifier);
        await notifier.start(TimerMode.normal, const Duration(minutes: 5));
        final before = await container.read(timerControllerProvider.future);

        await notifier.addTime(const Duration(seconds: 30));
        final after = await container.read(timerControllerProvider.future);

        expect(
          after.targetEpochMs,
          before.targetEpochMs! + const Duration(seconds: 30).inMilliseconds,
        );
      },
    );

    test(
      'addTime restarts as a fresh short countdown once already overdue',
      () async {
        final pastEpochMs = DateTime.now()
            .subtract(const Duration(minutes: 1))
            .millisecondsSinceEpoch;
        SharedPreferences.setMockInitialValues({
          timerStateJsonKey: jsonEncode({
            'targetEpochMs': pastEpochMs,
            'mode': 'normal',
          }),
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(timerControllerProvider.future);
        await container.read(stopwatchControllerProvider.future);
        final notifier = container.read(timerControllerProvider.notifier);

        final beforeCallEpochMs = DateTime.now().millisecondsSinceEpoch;
        await notifier.addTime(const Duration(seconds: 30));
        final state = await container.read(timerControllerProvider.future);
        final stopwatch = await container.read(
          stopwatchControllerProvider.future,
        );

        expect(
          state.targetEpochMs,
          closeTo(
            beforeCallEpochMs + const Duration(seconds: 30).inMilliseconds,
            200,
          ),
        );
        expect(stopwatch.isRunning, isTrue);
      },
    );

    test(
      'quickStart always starts fresh, ignoring any in-progress countdown',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(timerControllerProvider.future);
        await container.read(stopwatchControllerProvider.future);
        final notifier = container.read(timerControllerProvider.notifier);
        await notifier.start(TimerMode.linked, const Duration(minutes: 5));

        final beforeCallEpochMs = DateTime.now().millisecondsSinceEpoch;
        await notifier.quickStart(const Duration(minutes: 1));
        final state = await container.read(timerControllerProvider.future);

        expect(
          state.targetEpochMs,
          closeTo(
            beforeCallEpochMs + const Duration(minutes: 1).inMilliseconds,
            200,
          ),
        );
        // Mode is inherited from the timer that was running before.
        expect(state.mode, TimerMode.linked);
      },
    );

    test(
      'an overdue (counting-up) state survives a cold restart as-is, '
      'unlike completion time it is not auto-reset',
      () async {
        final pastEpochMs = DateTime.now()
            .subtract(const Duration(minutes: 2))
            .millisecondsSinceEpoch;
        SharedPreferences.setMockInitialValues({
          timerStateJsonKey: jsonEncode({
            'targetEpochMs': pastEpochMs,
            'mode': 'normal',
          }),
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final state = await container.read(timerControllerProvider.future);

        expect(state.isRunning, isTrue);
        expect(state.targetEpochMs, pastEpochMs);
      },
    );
  });
}
