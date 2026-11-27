import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/persistence/mutation_queue_notifier.dart';
import 'package:session_timer/features/stopwatch/stopwatch_controller.dart';
import 'package:session_timer/features/timer/timer_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A single JSON key (rather than one key per field) so a partial
// SharedPreferences write can't leave a new targetEpochMs paired with a
// stale mode, matching StopwatchController's rationale.
const timerStateJsonKey = 'timer_state_json';

final timerControllerProvider =
    AsyncNotifierProvider<TimerController, TimerState>(TimerController.new);

class TimerController extends MutationQueueNotifier<TimerState> {
  @override
  @protected
  TimerState get initialValue => const TimerState();

  @override
  @protected
  String get persistenceFailureMessage =>
      'SharedPreferences reported failure to persist timer state';

  @override
  @protected
  Future<TimerState> loadInitial(SharedPreferences prefs) async =>
      _readPersisted(prefs);

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
    await mutate((_) => TimerState(targetEpochMs: targetEpochMs, mode: mode));
    await _autoStartStopwatchIfNeeded();
  }

  /// Long-press on the main timer area: full reset to unset. The mode is
  /// kept so it can be reused by [quickStart] afterward.
  Future<void> reset() => mutate((s) => TimerState(mode: s.mode));

  /// Tap on the "+30秒"/"+1分" buttons: extends the remaining time if the
  /// timer is still counting down, otherwise starts a fresh countdown of
  /// exactly [amount] (spec 3-1節).
  Future<void> addTime(Duration amount) {
    final now = DateTime.now();
    var startedFresh = false;
    final result = mutate((s) {
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
    await mutate(
      (s) => TimerState(
        targetEpochMs: now.millisecondsSinceEpoch + amount.inMilliseconds,
        mode: s.mode,
      ),
    );
    await _autoStartStopwatchIfNeeded();
  }

  Future<void> _autoStartStopwatchIfNeeded() {
    return ref.read(stopwatchControllerProvider.notifier).ensureRunning();
  }

  /// See `StopwatchController.reloadFromDisk` — same rationale (a
  /// widget-driven `reset()` cascades into this controller too, from a
  /// separate isolate this app's foreground instance can't observe until it
  /// reloads).
  Future<void> reloadFromDisk() => reloadFromStorage();

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

  @override
  @protected
  Future<bool> persist(SharedPreferences prefs, TimerState value) {
    return prefs.setString(timerStateJsonKey, jsonEncode(value.toJson()));
  }
}
