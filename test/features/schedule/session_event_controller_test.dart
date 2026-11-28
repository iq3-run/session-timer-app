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

    test(
      'removeEvents drops only the given ids and persists the rest',
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
        await notifier.addEvent(
          SessionEventType.orientation,
          DateTime(2026, 8, 7),
        );
        final all = await container.read(sessionEventControllerProvider.future);
        final keep = all.firstWhere((e) => e.type == SessionEventType.workday);

        await notifier.removeEvents({
          for (final e in all)
            if (e.id != keep.id) e.id,
        });
        final events = await container.read(
          sessionEventControllerProvider.future,
        );

        expect(events.map((e) => e.id), [keep.id]);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(sessionEventsJsonKey), contains(keep.id));
      },
    );

    test(
      'removeEvents can clear everything, persisting the empty list',
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
        final all = await container.read(sessionEventControllerProvider.future);

        await notifier.removeEvents({for (final e in all) e.id});
        final events = await container.read(
          sessionEventControllerProvider.future,
        );

        expect(events, isEmpty);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(sessionEventsJsonKey), '[]');
      },
    );

    test(
      'removeEvents leaves an event added after the ids were chosen',
      () async {
        // The confirmation dialog counts the events on screen; one added
        // before the delete runs must survive it.
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
        final confirmed = await container.read(
          sessionEventControllerProvider.future,
        );
        await notifier.addEvent(SessionEventType.workday, DateTime(2026, 9, 5));

        await notifier.removeEvents({for (final e in confirmed) e.id});
        final events = await container.read(
          sessionEventControllerProvider.future,
        );

        expect(events.map((e) => e.type), [SessionEventType.workday]);
      },
    );

    test('removeEvents with unknown ids is a harmless no-op', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionEventControllerProvider.notifier);
      await notifier.addEvent(SessionEventType.weekend, DateTime(2026, 8, 21));

      await notifier.removeEvents({'no-such-id'});
      final events = await container.read(
        sessionEventControllerProvider.future,
      );

      expect(events, hasLength(1));
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

  group('SessionEventController addEvents', () {
    Future<(ProviderContainer, SessionEventController)>
    setUpController() async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionEventControllerProvider.future);
      return (
        container,
        container.read(sessionEventControllerProvider.notifier),
      );
    }

    test(
      'adds one event per day, normalizing times and collapsing repeats',
      () async {
        final (container, notifier) = await setUpController();

        await notifier.addEvents(SessionEventType.classroom, [
          DateTime(2026, 8, 21, 9),
          DateTime(2026, 8, 21, 18),
          DateTime(2026, 8, 7),
        ]);
        final events = await container.read(
          sessionEventControllerProvider.future,
        );

        expect(events.map((e) => e.date).toList()..sort(), [
          DateTime(2026, 8, 7),
          DateTime(2026, 8, 21),
        ]);
        expect({for (final e in events) e.id}, hasLength(2));
      },
    );

    test('persists the whole batch in one write', () async {
      final (container, notifier) = await setUpController();

      await notifier.addEvents(SessionEventType.workday, [
        DateTime(2026, 9, 5),
        DateTime(2026, 9, 6),
        DateTime(2026, 9, 7),
      ], track: SessionTrack.b);

      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString(sessionEventsJsonKey)!) as List;
      expect(saved, hasLength(3));
      expect(
        (await container.read(sessionEventControllerProvider.future)).every(
          (e) => e.track == SessionTrack.b,
        ),
        isTrue,
      );
    });

    test('a singleton type only takes the earliest day', () async {
      final (container, notifier) = await setUpController();

      await notifier.addEvents(SessionEventType.orientation, [
        DateTime(2026, 8, 9),
        DateTime(2026, 8, 2),
      ]);
      final events = await container.read(
        sessionEventControllerProvider.future,
      );

      expect(events.single.date, DateTime(2026, 8, 2));
    });

    test('a singleton type is not added again once one exists', () async {
      final (container, notifier) = await setUpController();
      await notifier.addEvents(SessionEventType.completion, [
        DateTime(2026, 12),
      ]);

      await notifier.addEvents(SessionEventType.completion, [
        DateTime(2026, 12, 8),
      ]);

      expect(
        await container.read(sessionEventControllerProvider.future),
        hasLength(1),
      );
    });

    test('an empty list changes nothing', () async {
      final (container, notifier) = await setUpController();

      await notifier.addEvents(SessionEventType.weekend, const []);

      expect(
        await container.read(sessionEventControllerProvider.future),
        isEmpty,
      );
    });
  });

  group('SessionEventController A/B schedules', () {
    Future<ProviderContainer> container() async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(sessionEventControllerProvider.future);
      return c;
    }

    test('addEvent stores the track on a WE and persists it', () async {
      final c = await container();
      final notifier = c.read(sessionEventControllerProvider.notifier);

      await notifier.addEvent(
        SessionEventType.weekend,
        DateTime(2026, 8, 21),
        track: SessionTrack.a,
      );
      final events = await c.read(sessionEventControllerProvider.future);

      expect(events.single.track, SessionTrack.a);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(sessionEventsJsonKey), contains('"track":"a"'));
    });

    test('addEvent stores the track on a WD', () async {
      final c = await container();

      await c
          .read(sessionEventControllerProvider.notifier)
          .addEvent(
            SessionEventType.workday,
            DateTime(2026, 9, 5),
            track: SessionTrack.b,
          );
      final events = await c.read(sessionEventControllerProvider.future);

      expect(events.single.track, SessionTrack.b);
    });

    test('a track on a type that cannot have one is ignored', () async {
      final c = await container();
      final notifier = c.read(sessionEventControllerProvider.notifier);

      for (final type in [
        SessionEventType.orientation,
        SessionEventType.classroom,
        SessionEventType.specialSession,
        SessionEventType.completion,
      ]) {
        await notifier.addEvent(
          type,
          DateTime(2026, 8, 7),
          track: SessionTrack.a,
        );
      }
      final events = await c.read(sessionEventControllerProvider.future);

      expect(events, hasLength(4));
      expect(events.every((e) => e.track == SessionTrack.common), isTrue);
    });

    test('editing visibility, number, or date keeps the track', () async {
      final c = await container();
      final notifier = c.read(sessionEventControllerProvider.notifier);
      await notifier.addEvent(
        SessionEventType.weekend,
        DateTime(2026, 8, 21),
        track: SessionTrack.b,
      );
      final id = (await c.read(sessionEventControllerProvider.future))
          .single
          .id;

      await notifier.setVisible(id, visible: false);
      await notifier.setManualNumber(id, 3);
      await notifier.setDate(id, DateTime(2026, 8, 28));
      final event = (await c.read(sessionEventControllerProvider.future))
          .single;

      expect(event.track, SessionTrack.b);
      expect(event.visible, isFalse);
      expect(event.manualNumber, 3);
      expect(event.date, DateTime(2026, 8, 28));
    });

    test('a schedule saved before A/B existed loads as common', () async {
      SharedPreferences.setMockInitialValues({
        sessionEventsJsonKey: jsonEncode([
          {
            'id': 'we1',
            'type': 'weekend',
            'epochMs': DateTime.utc(2026, 8, 21).millisecondsSinceEpoch,
          },
        ]),
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);

      final events = await c.read(sessionEventControllerProvider.future);

      expect(events.single.track, SessionTrack.common);
    });
  });
}
