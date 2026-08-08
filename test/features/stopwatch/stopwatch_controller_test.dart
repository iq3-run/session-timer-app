import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/core/persistence/shared_preferences_provider.dart';
import 'package:session_timer/features/stopwatch/stopwatch_controller.dart';
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
  });
}
