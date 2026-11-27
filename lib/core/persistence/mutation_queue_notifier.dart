import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/async/serial_queue.dart';
import 'package:session_timer/core/persistence/shared_preferences_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Base for notifiers whose whole state is one value persisted to
/// `SharedPreferences`, changed through serialized read-modify-write
/// mutations.
///
/// Mutations run one at a time through a [SerialQueue] and start from the
/// last value that was loaded or successfully persisted, rather than from
/// `state.value`: a failed persist sets `state` to `AsyncError` (which does
/// not retain the previous value), and reading `state` directly would strand
/// every later mutation with nothing to build on. A mutation queued while
/// [build] is still loading waits for it, even if the load failed — so a
/// single failure can't wedge the queue.
///
/// Subclasses provide the persistence details ([initialValue],
/// [loadInitial], [persist], [persistenceFailureMessage]) and expose their
/// own operations on top of [mutate].
abstract class MutationQueueNotifier<T> extends AsyncNotifier<T> {
  final SerialQueue _queue = SerialQueue();
  final Completer<void> _initialLoad = Completer<void>();

  // Lazy so it is only read after the subclass is constructed.
  late T _lastGood = initialValue;

  /// The value used until something has been loaded or persisted.
  @protected
  T get initialValue;

  /// Reads (and, if the subclass wants, cleans up) the persisted value. Runs
  /// once from [build].
  @protected
  Future<T> loadInitial(SharedPreferences prefs);

  /// Writes [value]; returns `false` when `SharedPreferences` reports that
  /// the write failed.
  @protected
  Future<bool> persist(SharedPreferences prefs, T value);

  /// Message of the error state set when [persist] returns `false`.
  @protected
  String get persistenceFailureMessage;

  /// Turns the result of a mutation into the value to persist (e.g. sorts
  /// it). Not applied to what [loadInitial] returns.
  @protected
  T normalize(T value) => value;

  @override
  Future<T> build() async {
    // If anything below throws, _initialLoad must still complete — otherwise
    // every mutation queued behind it would wait forever instead of failing
    // fast.
    try {
      final prefs = await ref.watch(sharedPreferencesProvider.future);
      // A mutation may have already landed on `state` while this build()
      // was awaiting the prefs future above — don't clobber it with a stale
      // read.
      if (state.hasValue) return state.value as T;

      final loaded = await loadInitial(prefs);
      _lastGood = loaded;
      return loaded;
    } finally {
      if (!_initialLoad.isCompleted) _initialLoad.complete();
    }
  }

  /// Applies [update] to the last good value, persists the result and
  /// publishes it as the new state. Failures are reported through `state`
  /// (and the returned future still completes normally for them).
  @protected
  Future<void> mutate(T Function(T) update) =>
      _queue.run(() => _mutateNow(update));

  Future<void> _mutateNow(T Function(T) update) async {
    if (!_initialLoad.isCompleted) await _initialLoad.future;
    final updated = normalize(update(_lastGood));
    try {
      final prefs = await ref.read(sharedPreferencesProvider.future);
      final persisted = await persist(prefs, updated);
      if (persisted) {
        _lastGood = updated;
        state = AsyncData(updated);
      } else {
        state = AsyncError(
          Exception(persistenceFailureMessage),
          StackTrace.current,
        );
      }
    } on Exception catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}
