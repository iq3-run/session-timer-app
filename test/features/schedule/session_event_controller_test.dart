import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/schedule/session_event.dart';
import 'package:session_timer/features/schedule/session_event_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// Delegates to a real in-memory store, but fails the next write once
/// [failNextWrite] is armed — mirrors `flash_points_controller_test.dart`'s
/// own `_FlakyStore`.
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
  group('SessionEventController', () {
    test('starts empty when nothing is persisted', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final events = await container.read(
        sessionEventControllerProvider.future,
      );

      expect(events, isEmpty);
    });

    test('addEvent appends a new event', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionEventControllerProvider.future);

      await container
          .read(sessionEventControllerProvider.notifier)
          .addEvent(SessionEventType.weekend, DateTime(2026, 8, 21));
      final events = await container.read(
        sessionEventControllerProvider.future,
      );

      expect(events, hasLength(1));
      expect(events.single.type, SessionEventType.weekend);
      expect(events.single.date, DateTime(2026, 8, 21));
    });

    test('addEvent normalizes the date to midnight', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionEventControllerProvider.future);

      await container
          .read(sessionEventControllerProvider.notifier)
          .addEvent(
            SessionEventType.workday,
            DateTime(2026, 9, 5, 14, 30),
          );
      final events = await container.read(
        sessionEventControllerProvider.future,
      );

      expect(events.single.date, DateTime(2026, 9, 5));
    });

    test('a second OR is rejected once one already exists', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionEventControllerProvider.notifier);
      await notifier.addEvent(
        SessionEventType.orientation,
        DateTime(2026, 8, 7),
      );

      await notifier.addEvent(
        SessionEventType.orientation,
        DateTime(2026, 8, 8),
      );
      final events = await container.read(
        sessionEventControllerProvider.future,
      );

      expect(events, hasLength(1));
      expect(events.single.date, DateTime(2026, 8, 7));
    });

    test('a second CS is rejected once one already exists', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionEventControllerProvider.notifier);
      await notifier.addEvent(
        SessionEventType.completion,
        DateTime(2027, 6, 25),
      );

      await notifier.addEvent(
        SessionEventType.completion,
        DateTime(2027, 7),
      );
      final events = await container.read(
        sessionEventControllerProvider.future,
      );

      expect(events, hasLength(1));
      expect(events.single.date, DateTime(2027, 6, 25));
    });

    test('WE can have multiple entries, unlike OR/CS', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionEventControllerProvider.notifier);

      await notifier.addEvent(SessionEventType.weekend, DateTime(2026, 8, 21));
      await notifier.addEvent(SessionEventType.weekend, DateTime(2026, 9, 26));
      final events = await container.read(
        sessionEventControllerProvider.future,
      );

      expect(events, hasLength(2));
    });

    test('removeEvent drops the matching event', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionEventControllerProvider.notifier);
      await notifier.addEvent(SessionEventType.weekend, DateTime(2026, 8, 21));
      final added = (await container.read(
        sessionEventControllerProvider.future,
      )).single;

      await notifier.removeEvent(added.id);
      final events = await container.read(
        sessionEventControllerProvider.future,
      );

      expect(events, isEmpty);
    });

    test('past events are not dropped on a fresh build (unlike '
        'TimeTargetsController)', () async {
      final pastEvent = SessionEvent(
        id: 'past',
        type: SessionEventType.workday,
        date: DateTime(2000),
      );
      SharedPreferences.setMockInitialValues({
        sessionEventsJsonKey: jsonEncode([pastEvent.toJson()]),
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final events = await container.read(
        sessionEventControllerProvider.future,
      );

      expect(events, hasLength(1));
      expect(events.single.id, 'past');
    });

    test('a mutation survives across a fresh container (persisted)', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      await container.read(sessionEventControllerProvider.future);
      await container
          .read(sessionEventControllerProvider.notifier)
          .addEvent(SessionEventType.weekend, DateTime(2026, 8, 21));
      container.dispose();

      final reloaded = ProviderContainer();
      addTearDown(reloaded.dispose);
      final events = await reloaded.read(sessionEventControllerProvider.future);

      expect(events, hasLength(1));
    });

    test(
      'setVisible flips only the matching event, leaving others alone',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(
          sessionEventControllerProvider.notifier,
        );
        await notifier.addEvent(
          SessionEventType.weekend,
          DateTime(2026, 8, 21),
        );
        await notifier.addEvent(SessionEventType.workday, DateTime(2026, 9, 5));
        final before = await container.read(
          sessionEventControllerProvider.future,
        );
        final workday = before.firstWhere(
          (e) => e.type == SessionEventType.workday,
        );

        await notifier.setVisible(workday.id, visible: false);
        final after = await container.read(
          sessionEventControllerProvider.future,
        );

        final updatedWorkday = after.firstWhere((e) => e.id == workday.id);
        final untouchedWeekend = after.firstWhere(
          (e) => e.type == SessionEventType.weekend,
        );
        expect(updatedWorkday.visible, isFalse);
        expect(untouchedWeekend.visible, isTrue);
      },
    );

    test('setVisible is a no-op for an id that does not exist', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionEventControllerProvider.notifier);
      await notifier.addEvent(SessionEventType.weekend, DateTime(2026, 8, 21));

      await notifier.setVisible('does-not-exist', visible: false);
      final events = await container.read(
        sessionEventControllerProvider.future,
      );

      expect(events.single.visible, isTrue);
    });

    test('addEvent accepts a manualNumber override', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionEventControllerProvider.notifier);

      await notifier.addEvent(
        SessionEventType.weekend,
        DateTime(2026, 8, 21),
        manualNumber: 5,
      );
      final events = await container.read(
        sessionEventControllerProvider.future,
      );

      expect(events.single.manualNumber, 5);
    });

    test('setManualNumber sets and clears only the matching event', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionEventControllerProvider.notifier);
      await notifier.addEvent(SessionEventType.weekend, DateTime(2026, 8, 21));
      await notifier.addEvent(SessionEventType.workday, DateTime(2026, 9, 5));
      final before = await container.read(
        sessionEventControllerProvider.future,
      );
      final weekend = before.firstWhere(
        (e) => e.type == SessionEventType.weekend,
      );
      final workday = before.firstWhere(
        (e) => e.type == SessionEventType.workday,
      );

      await notifier.setManualNumber(weekend.id, 7);
      final afterSet = await container.read(
        sessionEventControllerProvider.future,
      );
      expect(
        afterSet.firstWhere((e) => e.id == weekend.id).manualNumber,
        7,
      );
      expect(
        afterSet.firstWhere((e) => e.id == workday.id).manualNumber,
        isNull,
      );

      await notifier.setManualNumber(weekend.id, null);
      final afterClear = await container.read(
        sessionEventControllerProvider.future,
      );
      expect(
        afterClear.firstWhere((e) => e.id == weekend.id).manualNumber,
        isNull,
      );
    });

    test('setManualNumber is a no-op for an id that does not exist', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionEventControllerProvider.notifier);
      await notifier.addEvent(SessionEventType.weekend, DateTime(2026, 8, 21));

      await notifier.setManualNumber('does-not-exist', 9);
      final events = await container.read(
        sessionEventControllerProvider.future,
      );

      expect(events.single.manualNumber, isNull);
    });

    test('setDate changes only the matching event, leaving other fields '
        'untouched', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionEventControllerProvider.notifier);
      await notifier.addEvent(
        SessionEventType.weekend,
        DateTime(2026, 8, 21),
        manualNumber: 3,
      );
      await notifier.addEvent(SessionEventType.workday, DateTime(2026, 9, 5));
      final before = await container.read(
        sessionEventControllerProvider.future,
      );
      final weekend = before.firstWhere(
        (e) => e.type == SessionEventType.weekend,
      );
      final workday = before.firstWhere(
        (e) => e.type == SessionEventType.workday,
      );

      await notifier.setDate(weekend.id, DateTime(2026, 8, 28));
      final after = await container.read(sessionEventControllerProvider.future);

      final updatedWeekend = after.firstWhere((e) => e.id == weekend.id);
      expect(updatedWeekend.date, DateTime(2026, 8, 28));
      expect(updatedWeekend.manualNumber, 3);
      expect(after.firstWhere((e) => e.id == workday.id).date, workday.date);
    });

    test('setDate is a no-op for an id that does not exist', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionEventControllerProvider.notifier);
      await notifier.addEvent(SessionEventType.weekend, DateTime(2026, 8, 21));

      await notifier.setDate('does-not-exist', DateTime(2026, 9));
      final events = await container.read(
        sessionEventControllerProvider.future,
      );

      expect(events.single.date, DateTime(2026, 8, 21));
    });

    test('a failed persist surfaces as AsyncError without corrupting the '
        'in-memory list', () async {
      final previousStore = SharedPreferencesStorePlatform.instance;
      addTearDown(
        () => SharedPreferencesStorePlatform.instance = previousStore,
      );
      SharedPreferences.setMockInitialValues({});
      final store = _FlakyStore.empty();
      SharedPreferencesStorePlatform.instance = store;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionEventControllerProvider.future);

      store.failNextWrite = true;
      await container
          .read(sessionEventControllerProvider.notifier)
          .addEvent(SessionEventType.weekend, DateTime(2026, 8, 21));

      expect(
        container.read(sessionEventControllerProvider),
        isA<AsyncError<List<SessionEvent>>>(),
      );
    });
  });
}
