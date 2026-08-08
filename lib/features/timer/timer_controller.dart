import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/persistence/shared_preferences_provider.dart';
import 'package:session_timer/features/stopwatch/stopwatch_controller.dart';
import 'package:session_timer/features/timer/timer_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A single JSON key (rather than one key per field) so a partial
// SharedPreferences write can't leave a new targetEpochMs paired with a
// stale mode, matching StopwatchController's rationale.
const timerStateJsonKey = 'timer_state_json';

final timerControllerProvider =
    AsyncNotifierProvider<TimerController, TimerState>(TimerController.new);

class TimerController extends AsyncNotifier<TimerState> {
  // See TimeTargetsController (lib/features/targets/time_targets_controller.dart)
  // for why mutations are serialized through this queue instead of reading
  // `state.value` directly.
  Future<void> _mutationQueue = Future.value();
  final Completer<void> _initialLoad = Completer<void>();
  TimerState _lastGood = const TimerState();

  @override
  Future<TimerState> build() async {
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

  /// Full (re)start with a freshly chosen mode/duration — the settings
  /// dialog's confirm action. Always replaces any timer already running.
  Future<void> start(TimerMode mode, Duration duration) async {
    final now = DateTime.now();
    final stopwatch = await ref.read(stopwatchControllerProvider.future);
    final alreadyElapsedMs = mode == TimerMode.linked
        ? stopwatch.elapsedAt(now).inMilliseconds
        : 0;
    final targetEpochMs =
        now.millisecondsSinceEpoch + duration.inMilliseconds - alreadyElapsedMs;
    await _mutate((_) => TimerState(targetEpochMs: targetEpochMs, mode: mode));
    await _autoStartStopwatchIfNeeded();
  }

  /// Long-press on the main timer area: full reset to unset. The mode is
  /// kept so it can be reused by [quickStart] afterward.
  Future<void> reset() => _mutate((s) => TimerState(mode: s.mode));

  /// Tap on the "+30秒"/"+1分" buttons: extends the remaining time if the
  /// timer is still counting down, otherwise starts a fresh countdown of
  /// exactly [amount] (spec 3-1節).
  Future<void> addTime(Duration amount) {
    final now = DateTime.now();
    var startedFresh = false;
    final result = _mutate((s) {
      if (s.isRunning && !s.isOverdueAt(now)) {
        return TimerState(
          targetEpochMs: s.targetEpochMs! + amount.inMilliseconds,
          mode: s.mode,
        );
      }
      startedFresh = true;
      return TimerState(
        targetEpochMs: now.millisecondsSinceEpoch + amount.inMilliseconds,
        mode: s.mode,
      );
    });
    return result.then((_) async {
      if (startedFresh) await _autoStartStopwatchIfNeeded();
    });
  }

  /// Long-press on the "+30秒"/"+1分" buttons: always starts a fresh
  /// countdown of exactly [amount], regardless of current state, reusing
  /// the most recently selected mode.
  Future<void> quickStart(Duration amount) async {
    final now = DateTime.now();
    await _mutate(
      (s) => TimerState(
        targetEpochMs: now.millisecondsSinceEpoch + amount.inMilliseconds,
        mode: s.mode,
      ),
    );
    await _autoStartStopwatchIfNeeded();
  }

  Future<void> _autoStartStopwatchIfNeeded() async {
    final stopwatch = await ref.read(stopwatchControllerProvider.future);
    if (!stopwatch.isRunning) {
      await ref.read(stopwatchControllerProvider.notifier).toggle();
    }
  }

  Future<void> _mutate(TimerState Function(TimerState) update) {
    final previous = _mutationQueue;
    final result = previous.then((_) => _mutateNow(update));
    // Swallow the error here so it doesn't become an unhandled rejection on
    // the queue chain itself — _mutateNow already reports failures via
    // `state`, and each caller's own awaited `result` still sees it.
    _mutationQueue = result.catchError((_) {});
    return result;
  }

  Future<void> _mutateNow(TimerState Function(TimerState) update) async {
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

  TimerState _readPersisted(SharedPreferences prefs) {
    final raw = prefs.getString(timerStateJsonKey);
    if (raw == null) return const TimerState();
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const TimerState();
    }
    if (decoded is! Map<String, dynamic>) return const TimerState();
    return TimerState.tryFromJson(decoded) ?? const TimerState();
  }

  Future<bool> _persist(SharedPreferences prefs, TimerState s) {
    return prefs.setString(timerStateJsonKey, jsonEncode(s.toJson()));
  }

  AsyncValue<TimerState> _persistenceFailure() {
    return AsyncError(
      Exception('SharedPreferences reported failure to persist timer state'),
      StackTrace.current,
    );
  }
}
