import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/persistence/shared_preferences_provider.dart';
import 'package:session_timer/features/stopwatch/stopwatch_state.dart';
import 'package:session_timer/features/timer/timer_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A single JSON key (rather than one key per field) so a partial
// SharedPreferences write can't leave a new accumulatedMs paired with a
// stale runningSinceEpochMs — that combination would double-count the
// previous running segment on the next restore.
const stopwatchStateJsonKey = 'stopwatch_state_json';

final stopwatchControllerProvider =
    AsyncNotifierProvider<StopwatchController, StopwatchState>(
      StopwatchController.new,
    );

class StopwatchController extends AsyncNotifier<StopwatchState> {
  // See TimeTargetsController (lib/features/targets/time_targets_controller.dart)
  // for why mutations are serialized through this queue instead of reading
  // `state.value` directly.
  Future<void> _mutationQueue = Future.value();
  final Completer<void> _initialLoad = Completer<void>();
  StopwatchState _lastGood = const StopwatchState();

  @override
  Future<StopwatchState> build() async {
    try {
      final prefs = await ref.watch(sharedPreferencesProvider.future);
      // A mutate() call may have already landed on `state` while this
      // build() was awaiting the prefs future above — don't clobber it with
      // a stale read.
      if (state.hasValue) return state.value!;

      final loaded = _readPersisted(prefs);
      _lastGood = loaded;
      return loaded;
    } finally {
      if (!_initialLoad.isCompleted) _initialLoad.complete();
    }
  }

  Future<void> toggle() {
    // Captured before queuing: if a prior persist is still in flight,
    // _mutateNow may run well after this call, and the operation should
    // still be timed from when the user actually tapped.
    final nowEpochMs = DateTime.now().millisecondsSinceEpoch;
    return _mutate((s) {
      if (!s.isRunning) {
        return StopwatchState(
          accumulatedMs: s.accumulatedMs,
          runningSinceEpochMs: nowEpochMs,
        );
      }
      final elapsedThisRun = nowEpochMs - s.runningSinceEpochMs!;
      return StopwatchState(
        accumulatedMs: s.accumulatedMs + clampToNonNegativeMs(elapsedThisRun),
      );
    });
  }

  /// Long-press: full reset. Unconditionally resets the linked/independent
  /// timer too (spec 3-1節: ストップウォッチの長押しリセットはタイマーも
  /// リセットする).
  Future<void> reset() async {
    await _mutate((_) => const StopwatchState());
    await ref.read(timerControllerProvider.notifier).reset();
  }

  /// Double-tap: reset + immediate restart. Only cascades to the timer if
  /// it's currently overdue/counting up — a timer still counting down is
  /// left alone (spec 3-1節: タイマーが完了（超過）していなければそのまま、
  /// すでに超過していればタイマーもリセットする).
  Future<void> resetAndRestart() async {
    final now = DateTime.now();
    await _mutate(
      (_) => StopwatchState(runningSinceEpochMs: now.millisecondsSinceEpoch),
    );
    final timer = await ref.read(timerControllerProvider.future);
    if (timer.isOverdueAt(now)) {
      await ref.read(timerControllerProvider.notifier).reset();
    }
  }

  Future<void> _mutate(StopwatchState Function(StopwatchState) update) {
    final previous = _mutationQueue;
    final result = previous.then((_) => _mutateNow(update));
    // Swallow the error here so it doesn't become an unhandled rejection on
    // the queue chain itself — _mutateNow already reports failures via
    // `state`, and each caller's own awaited `result` still sees it.
    _mutationQueue = result.catchError((_) {});
    return result;
  }

  Future<void> _mutateNow(
    StopwatchState Function(StopwatchState) update,
  ) async {
    if (!_initialLoad.isCompleted) await _initialLoad.future;
    final updated = update(_lastGood);
    try {
      final prefs = await ref.read(sharedPreferencesProvider.future);
      final persisted = await _persist(prefs, updated);
      if (persisted) {
        _lastGood = updated;
        state = AsyncData(updated);
      } else {
        state = _persistenceFailure();
      }
    } on Exception catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  StopwatchState _readPersisted(SharedPreferences prefs) {
    final raw = prefs.getString(stopwatchStateJsonKey);
    if (raw == null) return const StopwatchState();
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const StopwatchState();
    }
    if (decoded is! Map<String, dynamic>) return const StopwatchState();
    return StopwatchState.tryFromJson(decoded) ?? const StopwatchState();
  }

  Future<bool> _persist(SharedPreferences prefs, StopwatchState s) {
    return prefs.setString(stopwatchStateJsonKey, jsonEncode(s.toJson()));
  }

  AsyncValue<StopwatchState> _persistenceFailure() {
    return AsyncError(
      Exception(
        'SharedPreferences reported failure to persist stopwatch state',
      ),
      StackTrace.current,
    );
  }
}
