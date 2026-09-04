import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/core/persistence/shared_preferences_provider.dart';
import 'package:session_timer/features/session_plan/session_plan_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SessionPlanController', () {
    test('starts empty when nothing is persisted', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final sessions = await container.read(
        sessionPlanControllerProvider.future,
      );

      expect(sessions, isEmpty);
    });

    test('addSession appends and sorts by time of day', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionPlanControllerProvider.future);
      final notifier = container.read(sessionPlanControllerProvider.notifier);
      // Fixed same-day times, not DateTime.now() — the sort is now by
      // time-of-day only, so a now()-relative fixture would flip order
      // (and fail) whenever "later" wraps past midnight, e.g. any run
      // between 19:00 and 23:00 local time.
      final laterStart = DateTime(2026, 8, 8, 19);
      final soonerStart = DateTime(2026, 8, 8, 9);

      await notifier.addSession(
        laterStart,
        laterStart.add(const Duration(hours: 1)),
      );
      await notifier.addSession(
        soonerStart,
        soonerStart.add(const Duration(hours: 1)),
      );
      final sessions = await container.read(
        sessionPlanControllerProvider.future,
      );

      expect(sessions.map((s) => s.startEpochMs), [
        soonerStart.millisecondsSinceEpoch,
        laterStart.millisecondsSinceEpoch,
      ]);
    });

    test(
      'sorts by time-of-day even when entries land on different calendar '
      'dates',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(sessionPlanControllerProvider.future);
        final notifier = container.read(
          sessionPlanControllerProvider.notifier,
        );
        // 19:00 today has an earlier epoch than 9:00 tomorrow, but 9:00 is
        // earlier in the day — this is the exact scenario
        // resolveNextOccurrence produces when a user registers "9:00"
        // after 9am has already passed today, landing it on tomorrow's
        // date while an evening session registered earlier that same day
        // still resolves to today.
        final today = DateTime(2026, 8, 8);
        final eveningToday = DateTime(2026, 8, 8, 19);
        final morningTomorrow = DateTime(2026, 8, 9, 9);

        await notifier.addSession(
          eveningToday,
          eveningToday.add(const Duration(hours: 2)),
        );
        await notifier.addSession(
          morningTomorrow,
          morningTomorrow.add(const Duration(hours: 2)),
        );
        final sessions = await container.read(
          sessionPlanControllerProvider.future,
        );

        expect(sessions.map((s) => s.startTime.hour), [9, 19]);
        // Sanity check the fixture actually crosses midnight (today's
        // guard against the two DateTimes above drifting to the same day
        // if this test is ever edited).
        expect(morningTomorrow.day, isNot(today.day));
      },
    );

    test('updateSession changes the start/end time in place', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionPlanControllerProvider.future);
      final notifier = container.read(sessionPlanControllerProvider.notifier);
      final start = DateTime.now().add(const Duration(hours: 1));
      await notifier.addSession(start, start.add(const Duration(hours: 1)));
      final id = (await container.read(
        sessionPlanControllerProvider.future,
      )).single.id;

      final newStart = DateTime.now().add(const Duration(hours: 3));
      final newEnd = newStart.add(const Duration(hours: 2));
      await notifier.updateSession(id, newStart, newEnd);
      final sessions = await container.read(
        sessionPlanControllerProvider.future,
      );

      expect(sessions.single.startEpochMs, newStart.millisecondsSinceEpoch);
      expect(sessions.single.endEpochMs, newEnd.millisecondsSinceEpoch);
    });

    test('removeSession deletes the session', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionPlanControllerProvider.future);
      final notifier = container.read(sessionPlanControllerProvider.notifier);
      final start = DateTime.now().add(const Duration(hours: 1));
      await notifier.addSession(start, start.add(const Duration(hours: 1)));
      final id = (await container.read(
        sessionPlanControllerProvider.future,
      )).single.id;

      await notifier.removeSession(id);
      final sessions = await container.read(
        sessionPlanControllerProvider.future,
      );

      expect(sessions, isEmpty);
    });

    test(
      'keeps an already-ended session across a cold restart, unlike '
      'TimeTargetsController — the plan is only cleared by hand',
      () async {
        final pastStart = DateTime.now().subtract(const Duration(days: 1));
        final pastEnd = pastStart.add(const Duration(hours: 1));
        final pastStartMs = pastStart.millisecondsSinceEpoch;
        final pastEndMs = pastEnd.millisecondsSinceEpoch;
        SharedPreferences.setMockInitialValues({
          sessionPlanJsonKey:
              '[{"id":"past","startEpochMs":$pastStartMs,'
              '"endEpochMs":$pastEndMs}]',
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final sessions = await container.read(
          sessionPlanControllerProvider.future,
        );

        expect(sessions.single.id, 'past');
      },
    );

    test(
      'a mutation queued before the initial load resolves does not wipe '
      'already-persisted sessions',
      () async {
        final existingStart = DateTime.now().add(const Duration(hours: 1));
        final existingEnd = existingStart.add(const Duration(hours: 1));
        final existingStartMs = existingStart.millisecondsSinceEpoch;
        final existingEndMs = existingEnd.millisecondsSinceEpoch;
        SharedPreferences.setMockInitialValues({
          sessionPlanJsonKey:
              '[{"id":"existing","startEpochMs":$existingStartMs,'
              '"endEpochMs":$existingEndMs}]',
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
        final newStart = DateTime.now().add(const Duration(hours: 3));
        final addFuture = container
            .read(sessionPlanControllerProvider.notifier)
            .addSession(newStart, newStart.add(const Duration(hours: 1)));

        prefsCompleter.complete(await SharedPreferences.getInstance());
        await addFuture;
        final sessions = await container.read(
          sessionPlanControllerProvider.future,
        );

        expect(sessions.map((s) => s.id), contains('existing'));
        expect(sessions, hasLength(2));
      },
    );
  });
}
