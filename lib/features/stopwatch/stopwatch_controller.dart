import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/persistence/shared_preferences_provider.dart';
import 'package:session_timer/features/stopwatch/stopwatch_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

const stopwatchAccumulatedMsKey = 'stopwatch_accumulated_ms';
const stopwatchRunningSinceEpochMsKey = 'stopwatch_running_since_epoch_ms';

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

      final loaded = StopwatchState(
        accumulatedMs: prefs.getInt(stopwatchAccumulatedMsKey) ?? 0,
        runningSinceEpochMs: prefs.getInt(stopwatchRunningSinceEpochMsKey),
      );
      _lastGood = loaded;
      return loaded;
    } finally {
      if (!_initialLoad.isCompleted) _initialLoad.complete();
    }
  }

  Future<void> toggle() => _mutate((s) {
    if (!s.isRunning) {
      return StopwatchState(
        accumulatedMs: s.accumulatedMs,
        runningSinceEpochMs: DateTime.now().millisecondsSinceEpoch,
      );
    }
    final elapsedThisRun =
        DateTime.now().millisecondsSinceEpoch - s.runningSinceEpochMs!;
    return StopwatchState(accumulatedMs: s.accumulatedMs + elapsedThisRun);
  });

  Future<void> reset() => _mutate((_) => const StopwatchState());

  Future<void> resetAndRestart() => _mutate(
    (_) => StopwatchState(
      runningSinceEpochMs: DateTime.now().millisecondsSinceEpoch,
    ),
  );

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

  Future<bool> _persist(SharedPreferences prefs, StopwatchState s) async {
    final accumulatedOk = await prefs.setInt(
      stopwatchAccumulatedMsKey,
      s.accumulatedMs,
    );
    final runningOk = s.runningSinceEpochMs == null
        ? await prefs.remove(stopwatchRunningSinceEpochMsKey)
        : await prefs.setInt(
            stopwatchRunningSinceEpochMsKey,
            s.runningSinceEpochMs!,
          );
    return accumulatedOk && runningOk;
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
