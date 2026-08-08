import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/core/persistence/shared_preferences_provider.dart';
import 'package:session_timer/features/completion/completion_time_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('CompletionTimeController', () {
    test('starts unset when nothing is persisted', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = await container.read(
        completionTimeControllerProvider.future,
      );

      expect(state.targetEpochMs, isNull);
    });

    test('setTarget persists and restores across a fresh container', () async {
      SharedPreferences.setMockInitialValues({});
      final target = DateTime.now().add(const Duration(hours: 1));

      final firstContainer = ProviderContainer();
      await firstContainer.read(completionTimeControllerProvider.future);
      await firstContainer
          .read(completionTimeControllerProvider.notifier)
          .setTarget(target);
      final persistedPrefs = await firstContainer.read(
        sharedPreferencesProvider.future,
      );
      final persistedEpochMs = persistedPrefs.getInt(completionTimeEpochMsKey);
      firstContainer.dispose();

      // SharedPreferences.getInstance() caches its result process-wide, so
      // disposing the container alone doesn't simulate a cold restart —
      // re-seed the mock backing store from what was actually persisted,
      // which forces a genuinely fresh instance for the next getInstance().
      final restartedMockValues = <String, Object>{};
      if (persistedEpochMs != null) {
        restartedMockValues[completionTimeEpochMsKey] = persistedEpochMs;
      }
      SharedPreferences.setMockInitialValues(restartedMockValues);
      final secondContainer = ProviderContainer();
      addTearDown(secondContainer.dispose);
      final restored = await secondContainer.read(
        completionTimeControllerProvider.future,
      );

      expect(restored.targetEpochMs, target.millisecondsSinceEpoch);
    });

    test(
      'resets to unset on startup if the stored time already passed',
      () async {
        final pastEpochMs = DateTime.now()
            .subtract(const Duration(minutes: 1))
            .millisecondsSinceEpoch;
        SharedPreferences.setMockInitialValues({
          completionTimeEpochMsKey: pastEpochMs,
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final state = await container.read(
          completionTimeControllerProvider.future,
        );

        expect(state.targetEpochMs, isNull);
      },
    );

    test('clear removes the persisted target', () async {
      final futureEpochMs = DateTime.now()
          .add(const Duration(hours: 1))
          .millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        completionTimeEpochMsKey: futureEpochMs,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(completionTimeControllerProvider.future);

      await container.read(completionTimeControllerProvider.notifier).clear();
      final state = await container.read(
        completionTimeControllerProvider.future,
      );

      expect(state.targetEpochMs, isNull);
    });
  });
}
