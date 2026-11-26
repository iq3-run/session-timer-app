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

      await notifier.addSession(startMinutes: 19 * 60, durationMinutes: 60);
      await notifier.addSession(startMinutes: 9 * 60, durationMinutes: 60);
      final sessions = await container.read(
        sessionPlanControllerProvider.future,
      );

      expect(sessions.map((s) => s.startMinutes), [9 * 60, 19 * 60]);
    });

    test(
      'updateSession changes the start time and duration in place',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(sessionPlanControllerProvider.future);
        final notifier = container.read(sessionPlanControllerProvider.notifier);
        await notifier.addSession(startMinutes: 9 * 60, durationMinutes: 60);
        final id = (await container.read(
          sessionPlanControllerProvider.future,
        )).single.id;

        await notifier.updateSession(
          id,
          startMinutes: 13 * 60,
          durationMinutes: 120,
        );
        final sessions = await container.read(
          sessionPlanControllerProvider.future,
        );

        expect(sessions.single.startMinutes, 13 * 60);
        expect(sessions.single.durationMinutes, 120);
      },
    );

    test('persists the new date-less format', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionPlanControllerProvider.future);

      await container
          .read(sessionPlanControllerProvider.notifier)
          .addSession(startMinutes: 540, durationMinutes: 210);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(sessionPlanJsonKey)!;
      expect(raw, contains('"startMinutes":540'));
      expect(raw, contains('"durationMinutes":210'));
      expect(raw, isNot(contains('Epoch')));
    });

    test('removeSession deletes the session', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sessionPlanControllerProvider.future);
      final notifier = container.read(sessionPlanControllerProvider.notifier);
      await notifier.addSession(startMinutes: 9 * 60, durationMinutes: 60);
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
      'loads sessions persisted in the legacy epoch format as time-of-day '
      'only, however long ago they were registered',
      () async {
        // Regression for #94: a session registered days ago must remain
        // appliable today, so only its time of day may survive loading.
        final pastStart = DateTime(2020, 3, 4, 9, 30);
        final pastEnd = DateTime(2020, 3, 4, 13);
        SharedPreferences.setMockInitialValues({
          sessionPlanJsonKey:
              '[{"id":"past","startEpochMs":'
              '${pastStart.millisecondsSinceEpoch},'
              '"endEpochMs":${pastEnd.millisecondsSinceEpoch}}]',
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final sessions = await container.read(
          sessionPlanControllerProvider.future,
        );

        expect(sessions.single.id, 'past');
        expect(sessions.single.startMinutes, 9 * 60 + 30);
        expect(sessions.single.durationMinutes, 210);
      },
    );

    test(
      'a mutation queued before the initial load resolves does not wipe '
      'already-persisted sessions',
      () async {
        SharedPreferences.setMockInitialValues({
          sessionPlanJsonKey:
              '[{"id":"existing","startMinutes":540,"durationMinutes":60}]',
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
        final addFuture = container
            .read(sessionPlanControllerProvider.notifier)
            .addSession(startMinutes: 13 * 60, durationMinutes: 60);

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
