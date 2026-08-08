import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/core/persistence/shared_preferences_provider.dart';
import 'package:session_timer/features/stopwatch/stopwatch_controller.dart';
import 'package:session_timer/features/timer/timer_controller.dart';
import 'package:session_timer/features/timer/timer_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// Delegates to a real in-memory store, but fails the next write once
/// [failNextWrite] is armed — used to simulate a transient SharedPreferences
/// I/O failure without needing a full fake platform implementation.
class _FlakyStore extends InMemorySharedPreferencesStore {
  _FlakyStore.empty() : super.empty();

  bool failNextWrite = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (failNextWrite) {
      failNextWrite = false;
      return Future.value(false);
    }
    return super.setValue(valueType, key, value);
  }
}

/// Delegates to a real in-memory store, but every write waits on [unblock]
/// before completing — used to simulate backpressure on the mutation queue
/// (a slow prior persist) without needing a full fake platform
/// implementation.
class _DelayedStore extends InMemorySharedPreferencesStore {
  _DelayedStore(this.unblock) : super.empty();

  final Future<void> unblock;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    await unblock;
    return super.setValue(valueType, key, value);
  }
}

void main() {
  group('StopwatchController', () {
    test('starts stopped at zero when nothing is persisted', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = await container.read(stopwatchControllerProvider.future);

      expect(state.isRunning, isFalse);
      expect(state.accumulatedMs, 0);
    });

    test(
      'discards the whole persisted state when accumulatedMs is negative',
      () async {
        // runningSinceEpochMs is deliberately non-null here so this test
        // can't pass under a partial-fix regression that only clamps
        // accumulatedMs while leaving the rest of the invalid state intact.
        SharedPreferences.setMockInitialValues({
          stopwatchStateJsonKey: jsonEncode({
            'accumulatedMs': -1000,
            'runningSinceEpochMs': DateTime.now().millisecondsSinceEpoch,
          }),
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final state = await container.read(stopwatchControllerProvider.future);

        expect(state.isRunning, isFalse);
        expect(state.accumulatedMs, 0);
      },
    );

    test('toggle starts running, then pauses and accumulates', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(stopwatchControllerProvider.future);
      final notifier = container.read(stopwatchControllerProvider.notifier);

      await notifier.toggle();
      final running = await container.read(stopwatchControllerProvider.future);
      expect(running.isRunning, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await notifier.toggle();
      final paused = await container.read(stopwatchControllerProvider.future);

      expect(paused.isRunning, isFalse);
      expect(paused.accumulatedMs, greaterThan(0));
    });

    test('ensureRunning starts the stopwatch when it is stopped', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(stopwatchControllerProvider.future);
      final notifier = container.read(stopwatchControllerProvider.notifier);

      await notifier.ensureRunning();
      final state = await container.read(stopwatchControllerProvider.future);

      expect(state.isRunning, isTrue);
    });

    test(
      'ensureRunning is a no-op when the stopwatch is already running',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(stopwatchControllerProvider.future);
        final notifier = container.read(stopwatchControllerProvider.notifier);
        await notifier.toggle();
        final running = await container.read(
          stopwatchControllerProvider.future,
        );

        await notifier.ensureRunning();
        final state = await container.read(stopwatchControllerProvider.future);

        expect(state.isRunning, isTrue);
        expect(state.runningSinceEpochMs, running.runningSinceEpochMs);
      },
    );

    test(
      'two concurrent ensureRunning calls leave the stopwatch running, '
      'not started-then-immediately-stopped',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(stopwatchControllerProvider.future);
        final notifier = container.read(stopwatchControllerProvider.notifier);

        final first = notifier.ensureRunning();
        final second = notifier.ensureRunning();
        await Future.wait([first, second]);
        final state = await container.read(stopwatchControllerProvider.future);

        expect(state.isRunning, isTrue);
      },
    );

    test('reset returns to stopped and zero', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(stopwatchControllerProvider.future);
      final notifier = container.read(stopwatchControllerProvider.notifier);
      await notifier.toggle();

      await notifier.reset();
      final state = await container.read(stopwatchControllerProvider.future);

      expect(state.isRunning, isFalse);
      expect(state.accumulatedMs, 0);
    });

    test(
      'resetAndRestart zeroes the accumulated time and starts running',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(stopwatchControllerProvider.future);
        final notifier = container.read(stopwatchControllerProvider.notifier);
        await notifier.toggle();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await notifier.toggle();

        await notifier.resetAndRestart();
        final state = await container.read(stopwatchControllerProvider.future);

        expect(state.isRunning, isTrue);
        expect(state.accumulatedMs, 0);
      },
    );

    test(
      'a paused state survives a cold restart with the same accumulated time',
      () async {
        SharedPreferences.setMockInitialValues({});
        final firstContainer = ProviderContainer();
        await firstContainer.read(stopwatchControllerProvider.future);
        final notifier = firstContainer.read(
          stopwatchControllerProvider.notifier,
        );
        await notifier.toggle();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await notifier.toggle();
        final beforeRestart = await firstContainer.read(
          stopwatchControllerProvider.future,
        );
        final persistedPrefs = await firstContainer.read(
          sharedPreferencesProvider.future,
        );
        final persistedJson = persistedPrefs.getString(stopwatchStateJsonKey);
        firstContainer.dispose();

        // SharedPreferences.getInstance() caches its result process-wide, so
        // disposing the container alone doesn't simulate a cold restart —
        // re-seed the mock backing store from what was actually persisted.
        SharedPreferences.setMockInitialValues({
          stopwatchStateJsonKey: ?persistedJson,
        });
        final secondContainer = ProviderContainer();
        addTearDown(secondContainer.dispose);
        final restored = await secondContainer.read(
          stopwatchControllerProvider.future,
        );

        expect(restored.isRunning, isFalse);
        expect(restored.accumulatedMs, beforeRestart.accumulatedMs);
      },
    );

    test(
      'a running state survives a cold restart and keeps counting through '
      'the downtime',
      () async {
        SharedPreferences.setMockInitialValues({});
        final firstContainer = ProviderContainer();
        await firstContainer.read(stopwatchControllerProvider.future);
        final notifier = firstContainer.read(
          stopwatchControllerProvider.notifier,
        );
        await notifier.toggle();
        final persistedPrefs = await firstContainer.read(
          sharedPreferencesProvider.future,
        );
        final persistedJson = persistedPrefs.getString(stopwatchStateJsonKey);
        final persistedRunningSinceEpochMs =
            (jsonDecode(persistedJson!)
                    as Map<String, dynamic>)['runningSinceEpochMs']
                as int;
        firstContainer.dispose();

        await Future<void>.delayed(const Duration(milliseconds: 20));
        // A lower bound on what the app was stopped for, computed from the
        // saved start epoch — guards against a regression that re-bases
        // runningSinceEpochMs to the restore time and silently drops the
        // downtime instead of continuing to count through it.
        final minimumElapsedMs =
            DateTime.now().millisecondsSinceEpoch -
            persistedRunningSinceEpochMs;
        SharedPreferences.setMockInitialValues({
          stopwatchStateJsonKey: persistedJson,
        });
        final secondContainer = ProviderContainer();
        addTearDown(secondContainer.dispose);
        final restored = await secondContainer.read(
          stopwatchControllerProvider.future,
        );

        expect(restored.isRunning, isTrue);
        expect(
          restored.elapsedAt(DateTime.now()).inMilliseconds,
          greaterThanOrEqualTo(minimumElapsedMs),
        );
      },
    );

    test(
      'concurrent mutations without awaiting each other both land',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(stopwatchControllerProvider.future);
        final notifier = container.read(stopwatchControllerProvider.notifier);

        final first = notifier.toggle();
        final second = notifier.reset();
        await Future.wait([first, second]);
        final state = await container.read(stopwatchControllerProvider.future);

        expect(state.isRunning, isFalse);
        expect(state.accumulatedMs, 0);
      },
    );

    test(
      'toggle succeeds again after a prior persistence failure',
      () async {
        final previousStore = SharedPreferencesStorePlatform.instance;
        addTearDown(
          () => SharedPreferencesStorePlatform.instance = previousStore,
        );
        SharedPreferences.setMockInitialValues({});
        final flakyStore = _FlakyStore.empty();
        SharedPreferencesStorePlatform.instance = flakyStore;
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(stopwatchControllerProvider.future);
        final notifier = container.read(stopwatchControllerProvider.notifier);

        flakyStore.failNextWrite = true;
        await notifier.toggle();
        expect(container.read(stopwatchControllerProvider).hasError, isTrue);

        await notifier.toggle();
        final state = await container.read(stopwatchControllerProvider.future);

        expect(state.isRunning, isTrue);
      },
    );

    test(
      'toggle times the running segment from call time, not from when '
      'a slow prior persist lets the queued mutation run',
      () async {
        final previousStore = SharedPreferencesStorePlatform.instance;
        addTearDown(
          () => SharedPreferencesStorePlatform.instance = previousStore,
        );
        SharedPreferences.setMockInitialValues({});
        final unblock = Completer<void>();
        SharedPreferencesStorePlatform.instance = _DelayedStore(
          unblock.future,
        );
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(stopwatchControllerProvider.future);
        final notifier = container.read(stopwatchControllerProvider.notifier);

        final startCallEpochMs = DateTime.now().millisecondsSinceEpoch;
        final startFuture = notifier.toggle();

        // The start mutation is now queued behind a persist blocked on
        // `unblock`. Pause is called well before that persist is released,
        // so a regression that captures the running epoch at queue-drain
        // time (instead of at the toggle() call itself) would inflate
        // accumulatedMs by roughly the full delay below.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final pauseCallEpochMs = DateTime.now().millisecondsSinceEpoch;
        final pauseFuture = notifier.toggle();

        await Future<void>.delayed(const Duration(milliseconds: 80));
        unblock.complete();
        await Future.wait([startFuture, pauseFuture]);
        final state = await container.read(stopwatchControllerProvider.future);

        final actualCallGapMs = pauseCallEpochMs - startCallEpochMs;
        expect(state.accumulatedMs, closeTo(actualCallGapMs, 40));
      },
    );

    test('reset() also resets an active (still counting down) timer', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(stopwatchControllerProvider.future);
      await container.read(timerControllerProvider.future);
      await container
          .read(timerControllerProvider.notifier)
          .start(TimerMode.normal, const Duration(minutes: 5));

      await container.read(stopwatchControllerProvider.notifier).reset();
      final timer = await container.read(timerControllerProvider.future);

      expect(timer.isRunning, isFalse);
    });

    test(
      'resetAndRestart() resets the timer when it is already overdue',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(stopwatchControllerProvider.future);
        await container.read(timerControllerProvider.future);
        await container
            .read(timerControllerProvider.notifier)
            .start(TimerMode.normal, const Duration(milliseconds: 10));
        await Future<void>.delayed(const Duration(milliseconds: 30));

        await container
            .read(stopwatchControllerProvider.notifier)
            .resetAndRestart();
        final timer = await container.read(timerControllerProvider.future);

        expect(timer.isRunning, isFalse);
      },
    );

    test(
      'resetAndRestart() leaves a still-counting-down timer alone',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(stopwatchControllerProvider.future);
        await container.read(timerControllerProvider.future);
        await container
            .read(timerControllerProvider.notifier)
            .start(TimerMode.normal, const Duration(minutes: 5));
        final before = await container.read(timerControllerProvider.future);

        await container
            .read(stopwatchControllerProvider.notifier)
            .resetAndRestart();
        final after = await container.read(timerControllerProvider.future);

        expect(after.isRunning, isTrue);
        expect(after.targetEpochMs, before.targetEpochMs);
      },
    );
  });
}
