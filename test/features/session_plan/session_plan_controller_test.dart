import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/core/persistence/shared_preferences_provider.dart';
import 'package:session_timer/features/session_plan/session_plan_book.dart';
import 'package:session_timer/features/session_plan/session_plan_controller.dart';
import 'package:session_timer/features/session_plan/session_plan_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<List<SessionPlanEntry>> _sessions(ProviderContainer container) async =>
    (await container.read(sessionPlanControllerProvider.future))
        .active
        .sessions;

Future<SessionPlanBook> _book(ProviderContainer container) =>
    container.read(sessionPlanControllerProvider.future);

void main() {
  group('SessionPlanController', () {
    test('starts empty when nothing is persisted', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final sessions = await _sessions(container);

      expect(sessions, isEmpty);
    });

    test('addSession appends and sorts by time of day', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await _sessions(container);
      final notifier = container.read(sessionPlanControllerProvider.notifier);

      await notifier.addSession(startMinutes: 19 * 60, durationMinutes: 60);
      await notifier.addSession(startMinutes: 9 * 60, durationMinutes: 60);
      final sessions = await _sessions(container);

      expect(sessions.map((s) => s.startMinutes), [9 * 60, 19 * 60]);
    });

    test(
      'updateSession changes the start time and duration in place',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await _sessions(container);
        final notifier = container.read(sessionPlanControllerProvider.notifier);
        await notifier.addSession(startMinutes: 9 * 60, durationMinutes: 60);
        final id = (await _sessions(container)).single.id;

        await notifier.updateSession(
          id,
          startMinutes: 13 * 60,
          durationMinutes: 120,
        );
        final sessions = await _sessions(container);

        expect(sessions.single.startMinutes, 13 * 60);
        expect(sessions.single.durationMinutes, 120);
      },
    );

    test('persists the new date-less format', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await _sessions(container);

      await container
          .read(sessionPlanControllerProvider.notifier)
          .addSession(startMinutes: 540, durationMinutes: 210);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(sessionPlanBookJsonKey)!;
      expect(raw, contains('"startMinutes":540'));
      expect(raw, contains('"durationMinutes":210'));
      expect(raw, isNot(contains('Epoch')));
    });

    test('removeSession deletes the session', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await _sessions(container);
      final notifier = container.read(sessionPlanControllerProvider.notifier);
      await notifier.addSession(startMinutes: 9 * 60, durationMinutes: 60);
      final id = (await _sessions(container)).single.id;

      await notifier.removeSession(id);
      final sessions = await _sessions(container);

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

        final sessions = await _sessions(container);

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
        final sessions = await _sessions(container);

        expect(sessions.map((s) => s.id), contains('existing'));
        expect(sessions, hasLength(2));
      },
    );
  });

  group('SessionPlanController 組', () {
    ProviderContainer makeContainer() {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      return container;
    }

    test('starts with a single empty 組1', () async {
      SharedPreferences.setMockInitialValues({});
      final book = await _book(makeContainer());

      expect(book.sets.single.name, '組1');
      expect(book.active.sessions, isEmpty);
    });

    test(
      'a pre-組 list becomes 組1 and is not rewritten under the old key',
      () async {
        SharedPreferences.setMockInitialValues({
          sessionPlanJsonKey:
              '[{"id":"old","startMinutes":540,"durationMinutes":60}]',
        });
        final container = makeContainer();

        final book = await _book(container);
        expect(book.sets.single.name, '組1');
        expect(book.active.sessions.single.id, 'old');

        await container
            .read(sessionPlanControllerProvider.notifier)
            .addSession(startMinutes: 600, durationMinutes: 30);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(sessionPlanJsonKey), contains('"old"'));
        expect(prefs.getString(sessionPlanJsonKey), isNot(contains('600')));
        expect(prefs.getString(sessionPlanBookJsonKey), contains('"old"'));
      },
    );

    test(
      'addSet creates a named 組, makes it active and keeps the others',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = makeContainer();
        await _book(container);
        final notifier = container.read(sessionPlanControllerProvider.notifier);
        await notifier.addSession(startMinutes: 540, durationMinutes: 60);

        await notifier.addSet(name: '  平日  ');
        final book = await _book(container);

        expect(book.sets.map((s) => s.name), ['組1', '平日']);
        expect(book.active.name, '平日');
        expect(book.active.sessions, isEmpty);
        expect(book.sets.first.sessions, hasLength(1));
      },
    );

    test('addSet without a name picks the first unused 組N', () async {
      SharedPreferences.setMockInitialValues({});
      final container = makeContainer();
      await _book(container);
      final notifier = container.read(sessionPlanControllerProvider.notifier);

      await notifier.addSet(name: '組2');
      await notifier.addSet();
      await notifier.addSet(name: '   ');
      final book = await _book(container);

      expect(book.sets.map((s) => s.name), ['組1', '組2', '組3', '組4']);
    });

    test('sessions are added to, and read from, the active 組 only', () async {
      SharedPreferences.setMockInitialValues({});
      final container = makeContainer();
      final first = (await _book(container)).activeId;
      final notifier = container.read(sessionPlanControllerProvider.notifier);
      await notifier.addSession(startMinutes: 540, durationMinutes: 60);
      await notifier.addSet(name: 'B');
      await notifier.addSession(startMinutes: 900, durationMinutes: 60);

      var book = await _book(container);
      expect(book.active.sessions.map((s) => s.startMinutes), [900]);

      await notifier.selectSet(first);
      book = await _book(container);
      expect(book.active.sessions.map((s) => s.startMinutes), [540]);
    });

    test('the active 組 survives a reload', () async {
      SharedPreferences.setMockInitialValues({});
      final first = ProviderContainer();
      addTearDown(first.dispose);
      await _book(first);
      await first
          .read(sessionPlanControllerProvider.notifier)
          .addSet(name: 'B');

      final second = makeContainer();
      final book = await _book(second);

      expect(book.active.name, 'B');
      expect(book.sets, hasLength(2));
    });

    test('renameSet renames, trims and ignores a blank name', () async {
      SharedPreferences.setMockInitialValues({});
      final container = makeContainer();
      final id = (await _book(container)).activeId;
      final notifier = container.read(sessionPlanControllerProvider.notifier);

      await notifier.renameSet(id, ' 土日 ');
      expect((await _book(container)).active.name, '土日');

      await notifier.renameSet(id, '   ');
      expect((await _book(container)).active.name, '土日');
    });

    test('names are cut to the maximum length', () async {
      SharedPreferences.setMockInitialValues({});
      final container = makeContainer();
      final notifier = container.read(sessionPlanControllerProvider.notifier);

      await notifier.addSet(name: 'あ' * (maxSessionPlanSetNameLength + 5));

      expect(
        (await _book(container)).active.name,
        hasLength(maxSessionPlanSetNameLength),
      );
    });

    test(
      'removeSet activates the previous 組; the last one cannot go',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = makeContainer();
        final firstId = (await _book(container)).activeId;
        final notifier = container.read(sessionPlanControllerProvider.notifier);
        await notifier.addSet(name: 'B');
        await notifier.addSet(name: 'C');
        final cId = (await _book(container)).activeId;

        await notifier.removeSet(cId);
        var book = await _book(container);
        expect(book.sets.map((s) => s.name), ['組1', 'B']);
        expect(book.active.name, 'B');

        // Removing a non-active 組 leaves the active one alone.
        await notifier.removeSet(firstId);
        book = await _book(container);
        expect(book.sets.map((s) => s.name), ['B']);
        expect(book.active.name, 'B');

        await notifier.removeSet(book.activeId);
        expect((await _book(container)).sets, hasLength(1));
      },
    );

    test('selectSet ignores an unknown id', () async {
      SharedPreferences.setMockInitialValues({});
      final container = makeContainer();
      final id = (await _book(container)).activeId;

      await container
          .read(sessionPlanControllerProvider.notifier)
          .selectSet('nope');

      expect((await _book(container)).activeId, id);
    });

    test(
      'a corrupt book falls back to the legacy list, then to an empty 組1',
      () async {
        SharedPreferences.setMockInitialValues({
          sessionPlanBookJsonKey: '{not json',
          sessionPlanJsonKey:
              '[{"id":"old","startMinutes":540,"durationMinutes":60}]',
        });

        final book = await _book(makeContainer());

        expect(book.sets.single.name, '組1');
        expect(book.active.sessions.single.id, 'old');
      },
    );

    test('an unknown activeId falls back to the first 組 and one bad session '
        'only drops itself', () async {
      SharedPreferences.setMockInitialValues({
        sessionPlanBookJsonKey:
            '{"activeId":"gone","sets":['
            '{"id":"a","name":"A","sessions":['
            '{"id":"ok","startMinutes":540,"durationMinutes":60},'
            '{"id":"bad","startMinutes":-5,"durationMinutes":60}]},'
            '{"id":"b","name":"B","sessions":[]}]}',
      });

      final book = await _book(makeContainer());

      expect(book.active.id, 'a');
      expect(book.active.sessions.map((s) => s.id), ['ok']);
    });
  });
}
