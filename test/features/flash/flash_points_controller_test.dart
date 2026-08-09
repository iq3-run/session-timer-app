import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/completion/completion_time_controller.dart';
import 'package:session_timer/features/completion/completion_time_state.dart';
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

class _FixedCompletionController extends CompletionTimeController {
  _FixedCompletionController(this._value);
  final CompletionTimeState _value;
  @override
  Future<CompletionTimeState> build() async => _value;
}

Future<List<int>> _buildWithCompletion(
  List<int>? persisted,
  DateTime? completionTarget,
) async {
  SharedPreferences.setMockInitialValues({
    if (persisted != null) flashPointsMinutesJsonKey: jsonEncode(persisted),
  });
  final container = ProviderContainer(
    overrides: [
      completionTimeControllerProvider.overrideWith(
        () => _FixedCompletionController(
          CompletionTimeState(
            targetEpochMs: completionTarget?.millisecondsSinceEpoch,
          ),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container.read(flashPointsControllerProvider.future);
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

    test(
      'a persisted empty custom list still gets all 12 defaults back',
      () async {
        SharedPreferences.setMockInitialValues({
          flashPointsMinutesJsonKey: jsonEncode(<int>[]),
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final points = await container.read(
          flashPointsControllerProvider.future,
        );

        expect(points, defaultCompletionFlashPointsMinutes);
      },
    );

    // 11/13/17/19 are deliberately non-default minute values, so these
    // mutation tests aren't affected by defaults always being present.

    test('addPoint appends a new point', () async {
      SharedPreferences.setMockInitialValues({
        flashPointsMinutesJsonKey: jsonEncode([11, 13]),
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(flashPointsControllerProvider.future);

      await container.read(flashPointsControllerProvider.notifier).addPoint(7);
      final points = await container.read(
        flashPointsControllerProvider.future,
      );

      expect(points, containsAll([11, 13, 7]));
    });

    test('addPoint ignores a duplicate value', () async {
      SharedPreferences.setMockInitialValues({
        flashPointsMinutesJsonKey: jsonEncode([11, 13]),
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(flashPointsControllerProvider.future);

      await container.read(flashPointsControllerProvider.notifier).addPoint(13);
      final points = await container.read(
        flashPointsControllerProvider.future,
      );

      expect(points.where((m) => m == 13), hasLength(1));
    });

    test('addPoint ignores zero and negative values', () async {
      SharedPreferences.setMockInitialValues({
        flashPointsMinutesJsonKey: jsonEncode([11, 13]),
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

      expect(points, isNot(anyOf(contains(0), contains(-3))));
    });

    test('removePoint drops the matching value', () async {
      SharedPreferences.setMockInitialValues({
        flashPointsMinutesJsonKey: jsonEncode([11, 13, 17]),
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(flashPointsControllerProvider.future);

      await container
          .read(flashPointsControllerProvider.notifier)
          .removePoint(13);
      final points = await container.read(
        flashPointsControllerProvider.future,
      );

      expect(points, containsAll([11, 17]));
      expect(points, isNot(contains(13)));
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

    group('startup rules against the current completion time', () {
      // 99 and 7 are deliberately non-default minute values (the defaults
      // are 120/90/60/45/30/20/15/10/5/3/2/1) so these tests exercise the
      // "custom point" branch of the rule, not the "default point" branch.

      test(
        'a removed default is always revived, regardless of whether a '
        'completion time is set',
        () async {
          final withoutOne = [
            ...defaultCompletionFlashPointsMinutes,
          ]..remove(120);

          for (final completionTarget in [
            null,
            DateTime.now().add(const Duration(minutes: 200)),
            DateTime.now().subtract(const Duration(hours: 1)),
          ]) {
            final points = await _buildWithCompletion(
              withoutOne,
              completionTarget,
            );
            expect(points, contains(120));
          }
        },
      );

      test(
        'leaves custom points untouched when no completion time is set',
        () async {
          final points = await _buildWithCompletion([99, 7], null);

          expect(points, containsAll([99, 7]));
        },
      );

      test(
        'leaves custom points untouched when nothing has passed yet',
        () async {
          final farFuture = DateTime.now().add(const Duration(days: 1));
          final points = await _buildWithCompletion([99, 7], farFuture);

          expect(points, containsAll([99, 7]));
        },
      );

      test(
        'an overdue completion time drops every custom point but keeps all '
        '12 defaults',
        () async {
          final overdue = DateTime.now().subtract(const Duration(hours: 1));
          final points = await _buildWithCompletion([99, 7], overdue);

          expect(points.toSet(), defaultCompletionFlashPointsMinutes.toSet());
        },
      );

      test(
        'drops only the custom point whose own moment has already passed, '
        'keeping ones still ahead',
        () async {
          // Completion is 10 minutes out: a 99-minutes-before custom
          // point's moment (completion - 99min) is long past, but a
          // 7-minutes-before custom point's moment is still 3 minutes
          // ahead.
          final soon = DateTime.now().add(const Duration(minutes: 10));
          final points = await _buildWithCompletion([99, 7], soon);

          expect(points, isNot(contains(99)));
          expect(points, contains(7));
        },
      );
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
        'flutter.$flashPointsMinutesJsonKey': jsonEncode([11, 13]),
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
      await container.read(flashPointsControllerProvider.notifier).addPoint(19);
      final points = await container.read(
        flashPointsControllerProvider.future,
      );
      expect(points, containsAll([11, 13, 19]));
      expect(points, isNot(contains(7)));
    });
  });
}
