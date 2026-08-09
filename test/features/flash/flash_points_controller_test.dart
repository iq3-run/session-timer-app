import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/completion/completion_time_controller.dart';
import 'package:session_timer/features/completion/completion_time_state.dart';
import 'package:session_timer/features/flash/flash_event.dart';
import 'package:session_timer/features/flash/flash_point_config.dart';
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

/// Encodes a plain list of minute values as the persisted JSON shape
/// (each entry both toggles ON), matching what a real `_persist` call
/// would have written for an all-enabled list.
String _persistedJson(List<int> minutes) => jsonEncode([
  for (final m in minutes) FlashPointConfig(minutes: m).toJson(),
]);

List<int> _minutes(List<FlashPointConfig> points) =>
    points.map((p) => p.minutes).toList();

Future<List<FlashPointConfig>> _buildWithCompletion(
  List<int>? persistedMinutes,
  DateTime? completionTarget,
) async {
  SharedPreferences.setMockInitialValues({
    if (persistedMinutes != null)
      flashPointsMinutesJsonKey: _persistedJson(persistedMinutes),
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

      expect(_minutes(points), defaultCompletionFlashPointsMinutes);
      expect(points, everyElement(isA<FlashPointConfig>()));
      expect(points.every((p) => p.flashEnabled && p.notifyEnabled), isTrue);
    });

    test(
      'a persisted empty custom list still gets all 12 defaults back',
      () async {
        SharedPreferences.setMockInitialValues({
          flashPointsMinutesJsonKey: jsonEncode(<Object>[]),
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final points = await container.read(
          flashPointsControllerProvider.future,
        );

        expect(_minutes(points), defaultCompletionFlashPointsMinutes);
      },
    );

    test(
      'data in the pre-toggle List<int> format degrades to the default '
      'baseline instead of crashing',
      () async {
        SharedPreferences.setMockInitialValues({
          flashPointsMinutesJsonKey: jsonEncode([11, 13]),
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final points = await container.read(
          flashPointsControllerProvider.future,
        );

        expect(_minutes(points), defaultCompletionFlashPointsMinutes);
      },
    );

    // 11/13/17/19 are deliberately non-default minute values, so these
    // mutation tests aren't affected by defaults always being present.

    test('addPoint appends a new point with both toggles on', () async {
      SharedPreferences.setMockInitialValues({
        flashPointsMinutesJsonKey: _persistedJson([11, 13]),
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(flashPointsControllerProvider.future);

      await container.read(flashPointsControllerProvider.notifier).addPoint(7);
      final points = await container.read(
        flashPointsControllerProvider.future,
      );

      expect(_minutes(points), containsAll([11, 13, 7]));
      final added = points.firstWhere((p) => p.minutes == 7);
      expect(added.flashEnabled, isTrue);
      expect(added.notifyEnabled, isTrue);
    });

    test('addPoint ignores a duplicate value', () async {
      SharedPreferences.setMockInitialValues({
        flashPointsMinutesJsonKey: _persistedJson([11, 13]),
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(flashPointsControllerProvider.future);

      await container.read(flashPointsControllerProvider.notifier).addPoint(13);
      final points = await container.read(
        flashPointsControllerProvider.future,
      );

      expect(points.where((p) => p.minutes == 13), hasLength(1));
    });

    test('addPoint ignores zero and negative values', () async {
      SharedPreferences.setMockInitialValues({
        flashPointsMinutesJsonKey: _persistedJson([11, 13]),
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

      expect(_minutes(points), isNot(anyOf(contains(0), contains(-3))));
    });

    test('removePoint drops the matching value', () async {
      SharedPreferences.setMockInitialValues({
        flashPointsMinutesJsonKey: _persistedJson([11, 13, 17]),
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

      expect(_minutes(points), containsAll([11, 17]));
      expect(_minutes(points), isNot(contains(13)));
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

      expect(_minutes(points), contains(7));
    });

    group('setFlashEnabled / setNotifyEnabled', () {
      test('setFlashEnabled(false) also forces notify off', () async {
        SharedPreferences.setMockInitialValues({
          flashPointsMinutesJsonKey: _persistedJson([11]),
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(flashPointsControllerProvider.future);

        await container
            .read(flashPointsControllerProvider.notifier)
            .setFlashEnabled(11, enabled: false);
        final points = await container.read(
          flashPointsControllerProvider.future,
        );

        final point = points.firstWhere((p) => p.minutes == 11);
        expect(point.flashEnabled, isFalse);
        expect(point.notifyEnabled, isFalse);
      });

      test(
        'setNotifyEnabled is a no-op while the point is flash-disabled',
        () async {
          SharedPreferences.setMockInitialValues({
            flashPointsMinutesJsonKey: _persistedJson([11]),
          });
          final container = ProviderContainer();
          addTearDown(container.dispose);
          await container.read(flashPointsControllerProvider.future);
          final notifier = container.read(
            flashPointsControllerProvider.notifier,
          );

          await notifier.setFlashEnabled(11, enabled: false);
          await notifier.setNotifyEnabled(11, enabled: true);
          final points = await container.read(
            flashPointsControllerProvider.future,
          );

          final point = points.firstWhere((p) => p.minutes == 11);
          expect(point.notifyEnabled, isFalse);
        },
      );

      test(
        're-enabling flash does not automatically restore notify',
        () async {
          SharedPreferences.setMockInitialValues({
            flashPointsMinutesJsonKey: _persistedJson([11]),
          });
          final container = ProviderContainer();
          addTearDown(container.dispose);
          await container.read(flashPointsControllerProvider.future);
          final notifier = container.read(
            flashPointsControllerProvider.notifier,
          );

          await notifier.setFlashEnabled(11, enabled: false);
          await notifier.setFlashEnabled(11, enabled: true);
          final points = await container.read(
            flashPointsControllerProvider.future,
          );

          final point = points.firstWhere((p) => p.minutes == 11);
          expect(point.flashEnabled, isTrue);
          expect(point.notifyEnabled, isFalse);
        },
      );

      test('setNotifyEnabled(false) leaves flash untouched', () async {
        SharedPreferences.setMockInitialValues({
          flashPointsMinutesJsonKey: _persistedJson([11]),
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(flashPointsControllerProvider.future);

        await container
            .read(flashPointsControllerProvider.notifier)
            .setNotifyEnabled(11, enabled: false);
        final points = await container.read(
          flashPointsControllerProvider.future,
        );

        final point = points.firstWhere((p) => p.minutes == 11);
        expect(point.flashEnabled, isTrue);
        expect(point.notifyEnabled, isFalse);
      });
    });

    group('startup rules against the current completion time', () {
      // 99 and 7 are deliberately non-default minute values (the defaults
      // are 120/90/60/45/30/20/15/10/5/3/2/1) so these tests exercise the
      // "custom point" branch of the rule, not the "default point" branch.

      // The four "missing default" scenarios from the rule table: revived
      // unless completion is set, still ahead, AND this point's own moment
      // hasn't arrived yet either — that's the one case it stays gone.

      test(
        'a removed default is revived when no completion time is set',
        () async {
          final withoutOne = [...defaultCompletionFlashPointsMinutes]
            ..remove(120);
          final points = await _buildWithCompletion(withoutOne, null);

          expect(_minutes(points), contains(120));
        },
      );

      test(
        'a removed default is revived when the completion time is overdue',
        () async {
          final withoutOne = [
            ...defaultCompletionFlashPointsMinutes,
          ]..remove(120);
          final overdue = DateTime.now().subtract(const Duration(hours: 1));
          final points = await _buildWithCompletion(withoutOne, overdue);

          expect(_minutes(points), contains(120));
        },
      );

      test(
        'a removed default is revived once its own moment has passed, '
        'even while the completion time itself is still ahead',
        () async {
          // Completion is 30 seconds out: the "1分前" default's own moment
          // (completion - 1min) is already 30 seconds in the past.
          final withoutOne = [
            ...defaultCompletionFlashPointsMinutes,
          ]..remove(1);
          final soon = DateTime.now().add(const Duration(seconds: 30));
          final points = await _buildWithCompletion(withoutOne, soon);

          expect(_minutes(points), contains(1));
        },
      );

      test(
        'a removed default stays gone while both the completion time and '
        'its own moment are still ahead',
        () async {
          // Completion is 200 minutes out: the "120分前" default's own
          // moment (completion - 120min) is still 80 minutes ahead.
          final withoutOne = [
            ...defaultCompletionFlashPointsMinutes,
          ]..remove(120);
          final stillAhead = DateTime.now().add(const Duration(minutes: 200));
          final points = await _buildWithCompletion(withoutOne, stillAhead);

          expect(_minutes(points), isNot(contains(120)));
        },
      );

      test(
        'leaves custom points untouched when no completion time is set',
        () async {
          final points = await _buildWithCompletion([99, 7], null);

          expect(_minutes(points), containsAll([99, 7]));
        },
      );

      test(
        'leaves custom points untouched when nothing has passed yet',
        () async {
          final farFuture = DateTime.now().add(const Duration(days: 1));
          final points = await _buildWithCompletion([99, 7], farFuture);

          expect(_minutes(points), containsAll([99, 7]));
        },
      );

      test(
        'an overdue completion time drops every custom point but keeps all '
        '12 defaults',
        () async {
          // The real CompletionTimeController self-heals an overdue target
          // to null before FlashPointsController ever reads it, so this
          // exact input is unreachable in the running app — this exercises
          // _applyStartupRules' arithmetic in isolation via the fixed
          // fixture, as a belt-and-suspenders check.
          final overdue = DateTime.now().subtract(const Duration(hours: 1));
          final points = await _buildWithCompletion([99, 7], overdue);

          expect(
            _minutes(points).toSet(),
            defaultCompletionFlashPointsMinutes.toSet(),
          );
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

          expect(_minutes(points), isNot(contains(99)));
          expect(_minutes(points), contains(7));
        },
      );

      test(
        'a revived default comes back with both toggles on, even if it had '
        'been toggled off before it went missing',
        () async {
          // The persisted entry for 120 is flash/notify OFF, but it's
          // *missing* from the same list, i.e. this simulates a default
          // whose off-state was never re-persisted after being dropped —
          // the revived entry must not inherit that state.
          SharedPreferences.setMockInitialValues({
            flashPointsMinutesJsonKey: jsonEncode([
              for (final m in defaultCompletionFlashPointsMinutes)
                if (m != 120) FlashPointConfig(minutes: m).toJson(),
            ]),
          });
          final container = ProviderContainer(
            overrides: [
              completionTimeControllerProvider.overrideWith(
                () => _FixedCompletionController(const CompletionTimeState()),
              ),
            ],
          );
          addTearDown(container.dispose);

          final points = await container.read(
            flashPointsControllerProvider.future,
          );

          final revived = points.firstWhere((p) => p.minutes == 120);
          expect(revived.flashEnabled, isTrue);
          expect(revived.notifyEnabled, isTrue);
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
        'flutter.$flashPointsMinutesJsonKey': _persistedJson([11, 13]),
      });
      SharedPreferencesStorePlatform.instance = store;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(flashPointsControllerProvider.future);

      store.failNextWrite = true;
      await container.read(flashPointsControllerProvider.notifier).addPoint(7);

      expect(
        container.read(flashPointsControllerProvider),
        isA<AsyncError<List<FlashPointConfig>>>(),
      );

      // A subsequent successful mutation recovers from the last-good list
      // (not the failed one) — the failed `7` must not have snuck in.
      await container.read(flashPointsControllerProvider.notifier).addPoint(19);
      final points = await container.read(
        flashPointsControllerProvider.future,
      );
      expect(_minutes(points), containsAll([11, 13, 19]));
      expect(_minutes(points), isNot(contains(7)));
    });
  });
}
