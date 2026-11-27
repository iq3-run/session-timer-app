import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/core/persistence/mutation_queue_notifier.dart';
import 'package:session_timer/core/persistence/shared_preferences_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'counter';

/// Persist outcome the next write should have.
enum _Write { ok, reportsFailure, throws }

_Write _nextWrite = _Write.ok;
int _loadCalls = 0;
bool _loadThrows = false;

class _Counter extends MutationQueueNotifier<int> {
  @override
  int get initialValue => 0;

  @override
  String get persistenceFailureMessage => 'could not persist $_key';

  @override
  Future<int> loadInitial(SharedPreferences prefs) async {
    _loadCalls++;
    if (_loadThrows) throw StateError('load failed');
    return prefs.getInt(_key) ?? 0;
  }

  @override
  Future<bool> persist(SharedPreferences prefs, int value) async {
    switch (_nextWrite) {
      case _Write.ok:
        return prefs.setInt(_key, value);
      case _Write.reportsFailure:
        return false;
      case _Write.throws:
        throw StateError('write failed');
    }
  }

  @override
  int normalize(int value) => value < 0 ? 0 : value;

  Future<void> add(int n) => mutate((v) => v + n);

  @visibleForTesting
  Future<void> mutateForTest(int Function(int) update) => mutate(update);
}

// No automatic retry: the failed-load tests count `loadInitial` calls and
// must not depend on Riverpod's retry timing.
final _counterProvider = AsyncNotifierProvider<_Counter, int>(
  _Counter.new,
  retry: (_, _) => null,
);

void main() {
  void resetKnobs() {
    _nextWrite = _Write.ok;
    _loadCalls = 0;
    _loadThrows = false;
  }

  setUp(() {
    resetKnobs();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(resetKnobs);

  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  test('loads the persisted value once', () async {
    SharedPreferences.setMockInitialValues({_key: 5});
    final container = makeContainer();

    expect(await container.read(_counterProvider.future), 5);
    expect(_loadCalls, 1);
  });

  test(
    'queued mutations apply in order, each on the previous result',
    () async {
      final container = makeContainer();
      final notifier = container.read(_counterProvider.notifier);

      await Future.wait([notifier.add(1), notifier.add(2), notifier.add(3)]);

      expect(container.read(_counterProvider).value, 6);
      expect((await SharedPreferences.getInstance()).getInt(_key), 6);
    },
  );

  test('normalize applies to mutation results', () async {
    final container = makeContainer();
    final notifier = container.read(_counterProvider.notifier);

    await notifier.add(-5);

    expect(container.read(_counterProvider).value, 0);
  });

  test(
    'a mutation queued before the load resolves keeps the stored value',
    () async {
      SharedPreferences.setMockInitialValues({_key: 10});
      final prefsCompleter = Completer<SharedPreferences>();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith(
            (ref) => prefsCompleter.future,
          ),
        ],
      );
      addTearDown(container.dispose);

      final added = container.read(_counterProvider.notifier).add(1);
      prefsCompleter.complete(await SharedPreferences.getInstance());
      await added;

      expect(container.read(_counterProvider).value, 11);
    },
  );

  test('a persist that reports failure sets the error state', () async {
    final container = makeContainer();
    final notifier = container.read(_counterProvider.notifier);
    await notifier.add(1);

    _nextWrite = _Write.reportsFailure;
    await notifier.add(1);

    final state = container.read(_counterProvider);
    expect(state.hasError, isTrue);
    expect(state.error.toString(), contains('could not persist $_key'));
  });

  test(
    'an error thrown by the update goes to the caller, not to state',
    () async {
      final container = makeContainer();
      final notifier = container.read(_counterProvider.notifier);
      await notifier.add(2);

      await expectLater(
        notifier.mutateForTest((_) => throw StateError('bad update')),
        throwsStateError,
      );

      expect(container.read(_counterProvider).value, 2);
      await notifier.add(1);
      expect(container.read(_counterProvider).value, 3);
    },
  );

  test('a write finishing after dispose does not throw', () async {
    final container = ProviderContainer();
    final notifier = container.read(_counterProvider.notifier);
    await container.read(_counterProvider.future);

    final pending = notifier.add(1);
    container.dispose();

    await expectLater(pending, completes);
  });

  test('a persist that throws sets the error state', () async {
    final container = makeContainer();
    final notifier = container.read(_counterProvider.notifier);

    _nextWrite = _Write.throws;
    await notifier.add(1);

    expect(container.read(_counterProvider).hasError, isTrue);
  });

  test('after a failed persist, the next mutation builds on the last good '
      'value', () async {
    final container = makeContainer();
    final notifier = container.read(_counterProvider.notifier);
    await notifier.add(2);

    _nextWrite = _Write.reportsFailure;
    await notifier.add(100);
    expect(container.read(_counterProvider).hasError, isTrue);

    _nextWrite = _Write.ok;
    await notifier.add(1);

    expect(container.read(_counterProvider).value, 3);
  });

  test('a failed initial load does not overwrite what is stored', () async {
    SharedPreferences.setMockInitialValues({_key: 10});
    _loadThrows = true;
    final container = makeContainer();
    final notifier = container.read(_counterProvider.notifier);
    await expectLater(
      container.read(_counterProvider.future),
      throwsStateError,
    );

    await notifier.add(4);

    expect(container.read(_counterProvider).hasError, isTrue);
    expect((await SharedPreferences.getInstance()).getInt(_key), 10);
  });

  test('a mutation after a failed initial load retries the load', () async {
    SharedPreferences.setMockInitialValues({_key: 10});
    _loadThrows = true;
    final container = makeContainer();
    final notifier = container.read(_counterProvider.notifier);
    await expectLater(
      container.read(_counterProvider.future),
      throwsStateError,
    );

    _loadThrows = false;
    await notifier.add(4);

    expect(container.read(_counterProvider).value, 14);
    expect((await SharedPreferences.getInstance()).getInt(_key), 14);
  });

  test('a mutation queued behind a failed one still runs', () async {
    final container = makeContainer();
    final notifier = container.read(_counterProvider.notifier);
    await notifier.add(1);

    _nextWrite = _Write.reportsFailure;
    final failing = notifier.add(100);
    final after = notifier.add(2);
    // The write outcome is read when each mutation persists, so flip it once
    // the first has run.
    await failing;
    _nextWrite = _Write.ok;
    await after;

    expect(container.read(_counterProvider).value, 3);
  });

  test(
    'a rebuild keeps the current value and mutations continue from it',
    () async {
      final container = makeContainer();
      final notifier = container.read(_counterProvider.notifier);
      await notifier.add(2);

      container.invalidate(sharedPreferencesProvider);
      expect(await container.read(_counterProvider.future), 2);

      await notifier.add(1);
      expect(container.read(_counterProvider).value, 3);
    },
  );
}
