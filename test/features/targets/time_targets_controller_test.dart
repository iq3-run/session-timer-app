import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/core/persistence/shared_preferences_provider.dart';
import 'package:session_timer/features/targets/time_targets_controller.dart';
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
  group('TimeTargetsController', () {
    test('starts empty when nothing is persisted', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final targets = await container.read(
        timeTargetsControllerProvider.future,
      );

      expect(targets, isEmpty);
    });

    test('addTarget appends and sorts by time', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(timeTargetsControllerProvider.future);
      final later = DateTime.now().add(const Duration(hours: 2));
      final sooner = DateTime.now().add(const Duration(hours: 1));

      final notifier = container.read(timeTargetsControllerProvider.notifier);
      await notifier.addTarget(later);
      await notifier.addTarget(sooner);
      final targets = await container.read(
        timeTargetsControllerProvider.future,
      );

      expect(targets.map((t) => t.epochMs), [
        sooner.millisecondsSinceEpoch,
        later.millisecondsSinceEpoch,
      ]);
    });

    test('updateTarget changes the target time in place', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(timeTargetsControllerProvider.future);
      final notifier = container.read(timeTargetsControllerProvider.notifier);
      await notifier.addTarget(DateTime.now().add(const Duration(hours: 1)));
      final id = (await container.read(
        timeTargetsControllerProvider.future,
      )).single.id;

      final newTime = DateTime.now().add(const Duration(hours: 3));
      await notifier.updateTarget(id, newTime);
      final targets = await container.read(
        timeTargetsControllerProvider.future,
      );

      expect(targets.single.id, id);
      expect(targets.single.epochMs, newTime.millisecondsSinceEpoch);
    });

    test(
      'updateTarget/removeTarget match by id, not by shared epochMs',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(timeTargetsControllerProvider.future);
        final notifier = container.read(timeTargetsControllerProvider.notifier);
        final sharedTime = DateTime.now().add(const Duration(hours: 1));
        await notifier.addTarget(sharedTime);
        await notifier.addTarget(sharedTime);
        final ids = (await container.read(
          timeTargetsControllerProvider.future,
        )).map((t) => t.id).toList();
        expect(ids.toSet(), hasLength(2));

        final newTime = DateTime.now().add(const Duration(hours: 3));
        await notifier.updateTarget(ids.first, newTime);
        final afterUpdate = await container.read(
          timeTargetsControllerProvider.future,
        );

        expect(
          afterUpdate.firstWhere((t) => t.id == ids.first).epochMs,
          newTime.millisecondsSinceEpoch,
        );
        expect(
          afterUpdate.firstWhere((t) => t.id == ids.last).epochMs,
          sharedTime.millisecondsSinceEpoch,
        );

        await notifier.removeTarget(ids.first);
        final afterRemove = await container.read(
          timeTargetsControllerProvider.future,
        );

        expect(afterRemove.single.id, ids.last);
      },
    );

    test('removeTarget deletes the target', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(timeTargetsControllerProvider.future);
      final notifier = container.read(timeTargetsControllerProvider.notifier);
      await notifier.addTarget(DateTime.now().add(const Duration(hours: 1)));
      final id = (await container.read(
        timeTargetsControllerProvider.future,
      )).single.id;

      await notifier.removeTarget(id);
      final targets = await container.read(
        timeTargetsControllerProvider.future,
      );

      expect(targets, isEmpty);
    });

    test(
      'drops already-expired targets on a cold restart, keeps future ones',
      () async {
        SharedPreferences.setMockInitialValues({});
        final firstContainer = ProviderContainer();
        final notifier = firstContainer.read(
          timeTargetsControllerProvider.notifier,
        );
        await firstContainer.read(timeTargetsControllerProvider.future);
        await notifier.addTarget(
          DateTime.now().subtract(const Duration(minutes: 1)),
        );
        final futureTarget = DateTime.now().add(const Duration(hours: 1));
        await notifier.addTarget(futureTarget);
        final persistedPrefs = await firstContainer.read(
          sharedPreferencesProvider.future,
        );
        final persistedJson = persistedPrefs.getString(timeTargetsJsonKey);
        firstContainer.dispose();

        // Simulate a cold restart: re-seed the mock backing store from what
        // was actually persisted (see completion_time_controller_test.dart
        // for why disposing alone isn't enough).
        final restartedMockValues = <String, Object>{};
        if (persistedJson != null) {
          restartedMockValues[timeTargetsJsonKey] = persistedJson;
        }
        SharedPreferences.setMockInitialValues(restartedMockValues);
        final secondContainer = ProviderContainer();
        addTearDown(secondContainer.dispose);
        final targets = await secondContainer.read(
          timeTargetsControllerProvider.future,
        );

        expect(targets.single.epochMs, futureTarget.millisecondsSinceEpoch);
      },
    );

    test(
      'drops a persisted entry with an out-of-range epochMs, keeps the rest',
      () async {
        final validEpochMs = DateTime.now()
            .add(const Duration(hours: 1))
            .millisecondsSinceEpoch;
        // Beyond DateTime.fromMillisecondsSinceEpoch's documented max range.
        const outOfRangeEpochMs = 9000000000000000;
        SharedPreferences.setMockInitialValues({
          timeTargetsJsonKey:
              '[{"id":"valid","epochMs":$validEpochMs},'
              '{"id":"bad","epochMs":$outOfRangeEpochMs}]',
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final targets = await container.read(
          timeTargetsControllerProvider.future,
        );

        expect(targets.single.id, 'valid');
      },
    );

    test(
      'concurrent mutations without awaiting each other both land',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(timeTargetsControllerProvider.future);
        final notifier = container.read(timeTargetsControllerProvider.notifier);

        final first = notifier.addTarget(
          DateTime.now().add(const Duration(hours: 1)),
        );
        final second = notifier.addTarget(
          DateTime.now().add(const Duration(hours: 2)),
        );
        await Future.wait([first, second]);
        final targets = await container.read(
          timeTargetsControllerProvider.future,
        );

        expect(targets, hasLength(2));
      },
    );

    test(
      'a mutation queued before the initial load resolves does not wipe '
      'already-persisted targets',
      () async {
        final existingEpochMs = DateTime.now()
            .add(const Duration(hours: 1))
            .millisecondsSinceEpoch;
        SharedPreferences.setMockInitialValues({
          timeTargetsJsonKey: '[{"id":"existing","epochMs":$existingEpochMs}]',
        });
        final prefsCompleter = Completer<SharedPreferences>();
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWith(
              (ref) => prefsCompleter.future,
            ),
          ],
        );
        addTearDown(container.dispose);

        // build() is now blocked awaiting sharedPreferencesProvider. Queue a
        // mutation before it resolves.
        final newTargetTime = DateTime.now().add(const Duration(hours: 2));
        final addFuture = container
            .read(timeTargetsControllerProvider.notifier)
            .addTarget(newTargetTime);

        prefsCompleter.complete(await SharedPreferences.getInstance());
        await addFuture;
        final targets = await container.read(
          timeTargetsControllerProvider.future,
        );

        expect(targets.map((t) => t.id), contains('existing'));
        expect(targets, hasLength(2));
      },
    );

    test(
      'addTarget succeeds again after a prior persistence failure',
      () async {
        SharedPreferences.setMockInitialValues({});
        final flakyStore = _FlakyStore.empty();
        SharedPreferencesStorePlatform.instance = flakyStore;
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(timeTargetsControllerProvider.future);
        final notifier = container.read(timeTargetsControllerProvider.notifier);

        flakyStore.failNextWrite = true;
        await notifier.addTarget(DateTime.now().add(const Duration(hours: 1)));
        expect(
          container.read(timeTargetsControllerProvider).hasError,
          isTrue,
        );

        final retryTime = DateTime.now().add(const Duration(hours: 2));
        await notifier.addTarget(retryTime);
        final targets = await container.read(
          timeTargetsControllerProvider.future,
        );

        expect(targets.single.epochMs, retryTime.millisecondsSinceEpoch);
      },
    );
  });
}
