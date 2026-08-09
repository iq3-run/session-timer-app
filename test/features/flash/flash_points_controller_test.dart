import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/flash/flash_event.dart';
import 'package:session_timer/features/flash/flash_points_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// Delegates to a real in-memory store, but fails the next write once
/// [failNextWrite] is armed — used to simulate a transient SharedPreferences
/// I/O failure without needing a full fake platform implementation.
class _FlakyStore extends InMemorySharedPreferencesStore {
  _FlakyStore.withData(super.data) : super.withData();

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
  group('FlashPointsController', () {
    test('seeds the default 12 points on first launch', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final points = await container.read(
        flashPointsControllerProvider.future,
      );

      expect(points, defaultCompletionFlashPointsMinutes);
    });

    test('an empty persisted list stays empty (not re-seeded)', () async {
      SharedPreferences.setMockInitialValues({
        flashPointsMinutesJsonKey: jsonEncode(<int>[]),
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final points = await container.read(
        flashPointsControllerProvider.future,
      );

      expect(points, isEmpty);
    });

    test('addPoint appends a new point', () async {
      SharedPreferences.setMockInitialValues({
        flashPointsMinutesJsonKey: jsonEncode([10, 5]),
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(flashPointsControllerProvider.future);

      await container.read(flashPointsControllerProvider.notifier).addPoint(7);
      final points = await container.read(
        flashPointsControllerProvider.future,
      );

      expect(points, [10, 5, 7]);
    });

    test('addPoint ignores a duplicate value', () async {
      SharedPreferences.setMockInitialValues({
        flashPointsMinutesJsonKey: jsonEncode([10, 5]),
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(flashPointsControllerProvider.future);

      await container.read(flashPointsControllerProvider.notifier).addPoint(5);
      final points = await container.read(
        flashPointsControllerProvider.future,
      );

      expect(points, [10, 5]);
    });

    test('addPoint ignores zero and negative values', () async {
      SharedPreferences.setMockInitialValues({
        flashPointsMinutesJsonKey: jsonEncode([10, 5]),
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(flashPointsControllerProvider.future);
      final notifier = container.read(flashPointsControllerProvider.notifier);

      await notifier.addPoint(0);
      await notifier.addPoint(-3);
      final points = await container.read(
        flashPointsControllerProvider.future,
      );

      expect(points, [10, 5]);
    });

    test('removePoint drops the matching value', () async {
      SharedPreferences.setMockInitialValues({
        flashPointsMinutesJsonKey: jsonEncode([10, 5, 1]),
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(flashPointsControllerProvider.future);

      await container
          .read(flashPointsControllerProvider.notifier)
          .removePoint(5);
      final points = await container.read(
        flashPointsControllerProvider.future,
      );

      expect(points, [10, 1]);
    });

    test('a mutation survives across a fresh container (persisted)', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      await container.read(flashPointsControllerProvider.future);
      await container.read(flashPointsControllerProvider.notifier).addPoint(7);
      container.dispose();

      final reloaded = ProviderContainer();
      addTearDown(reloaded.dispose);
      final points = await reloaded.read(
        flashPointsControllerProvider.future,
      );

      expect(points, contains(7));
    });

    test('a failed persist surfaces as AsyncError without corrupting the '
        'in-memory list', () async {
      final previousStore = SharedPreferencesStorePlatform.instance;
      addTearDown(
        () => SharedPreferencesStorePlatform.instance = previousStore,
      );
      // Resets SharedPreferences' own internal instance cache, which
      // otherwise survives across tests in this file and would make the
      // next getInstance() call below ignore the flaky store entirely.
      SharedPreferences.setMockInitialValues({});
      final store = _FlakyStore.withData({
        'flutter.$flashPointsMinutesJsonKey': jsonEncode([10, 5]),
      });
      SharedPreferencesStorePlatform.instance = store;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(flashPointsControllerProvider.future);

      store.failNextWrite = true;
      await container.read(flashPointsControllerProvider.notifier).addPoint(7);

      expect(
        container.read(flashPointsControllerProvider),
        isA<AsyncError<List<int>>>(),
      );

      // A subsequent successful mutation recovers from the last-good list
      // (not the failed one) — the failed `7` must not have snuck in.
      await container.read(flashPointsControllerProvider.notifier).addPoint(3);
      final points = await container.read(
        flashPointsControllerProvider.future,
      );
      expect(points, [10, 5, 3]);
    });
  });
}
