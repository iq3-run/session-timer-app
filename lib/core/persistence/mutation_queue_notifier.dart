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
/// [build] is still loading waits for it. If that load failed, the mutation
/// retries the load first and reports an error without writing anything when
/// it fails again: persisting an update on top of [initialValue] would
/// overwrite whatever is actually stored.
///
/// The notifier assumes it is the only writer of its key. A rebuild keeps the
/// value in memory instead of re-reading storage, so anything that changes
/// the stored value from elsewhere must reload it explicitly.
///
/// Subclasses provide the persistence details ([initialValue],
/// [loadInitial], [persist], [persistenceFailureMessage]) and expose their
/// own operations on top of [mutate].
abstract class MutationQueueNotifier<T> extends AsyncNotifier<T> {
  final SerialQueue _queue = SerialQueue();
  final Completer<void> _initialLoad = Completer<void>();

  // Lazy so it is only read after the subclass is constructed.
  late T _lastGood = initialValue;

  // Whether [_lastGood] came from a successful load or persist, rather than
  // being the placeholder [initialValue].
  bool _loaded = false;

  // Counts successful persists, so [build] can tell that a mutation landed
  // while it was reading (see there).
  int _persistedCount = 0;

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
    final persistedBefore = _persistedCount;
    try {
      final prefs = await ref.watch(sharedPreferencesProvider.future);
      // A rebuild (e.g. `sharedPreferencesProvider` was invalidated) keeps the
      // value already in `state`: it is at least as new as what is on disk.
      if (state.hasValue) {
        _lastGood = state.value as T;
        _loaded = true;
        return _lastGood;
      }

      final loaded = await loadInitial(prefs);
      // A mutation can retry a failed load and persist while this one is
      // still reading (e.g. the framework's own retry of build()); what it
      // persisted is newer than what was just read. Counting persists rather
      // than looking at `state` also covers a later mutation that failed and
      // left `state` as an error.
      if (_persistedCount != persistedBefore) {
        _loaded = true;
        return _lastGood;
      }
      _lastGood = loaded;
      _loaded = true;
      return loaded;
    } finally {
      if (!_initialLoad.isCompleted) _initialLoad.complete();
    }
  }

  /// Applies [update] to the last good value, persists the result and
  /// publishes it as the new state. Loading or persisting failures are
  /// reported through `state` (and the returned future still completes
  /// normally for them). An error thrown by [update] itself is a bug in the
  /// caller: it goes to the caller's future and leaves `state` untouched.
  @protected
  Future<void> mutate(T Function(T) update) =>
      _queue.run(() => _mutateNow(update));

  Future<void> _mutateNow(T Function(T) update) async {
    if (!_initialLoad.isCompleted) await _initialLoad.future;

    final SharedPreferences prefs;
    try {
      prefs = await ref.read(sharedPreferencesProvider.future);
      // The initial load failed earlier: try again rather than building on
      // the placeholder (and overwriting what is stored). If it fails again
      // the error is reported and nothing is written.
      if (!_loaded) {
        _lastGood = await loadInitial(prefs);
        _loaded = true;
      }
    } on Object catch (e, st) {
      debugPrint('$runtimeType: loading failed: $e');
      _publish(AsyncError(e, st));
      return;
    }

    final updated = normalize(update(_lastGood));
    try {
      final persisted = await persist(prefs, updated);
      if (persisted) {
        _lastGood = updated;
        _persistedCount++;
        _publish(AsyncData(updated));
      } else {
        _publish(
          AsyncError(Exception(persistenceFailureMessage), StackTrace.current),
        );
      }
    } on Object catch (e, st) {
      debugPrint('$runtimeType: persisting failed: $e');
      _publish(AsyncError(e, st));
    }
  }

  // A write can finish after the notifier was disposed (e.g. a container
  // torn down mid-mutation); assigning `state` then would throw.
  void _publish(AsyncValue<T> value) {
    if (ref.mounted) state = value;
  }
}
