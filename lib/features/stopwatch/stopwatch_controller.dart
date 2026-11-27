import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/persistence/mutation_queue_notifier.dart';
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

class StopwatchController extends MutationQueueNotifier<StopwatchState> {
  @override
  @protected
  StopwatchState get initialValue => const StopwatchState();

  @override
  @protected
  String get persistenceFailureMessage =>
      'SharedPreferences reported failure to persist stopwatch state';

  @override
  @protected
  Future<StopwatchState> loadInitial(SharedPreferences prefs) async =>
      _readPersisted(prefs);

  Future<void> toggle() {
    // Captured before queuing: if a prior persist is still in flight,
    // _mutateNow may run well after this call, and the operation should
    // still be timed from when the user actually tapped.
    final nowEpochMs = DateTime.now().millisecondsSinceEpoch;
    return mutate((s) {
      if (!s.isRunning) return _startedFrom(s, nowEpochMs);
      final elapsedThisRun = nowEpochMs - s.runningSinceEpochMs!;
      return StopwatchState(
        accumulatedMs: s.accumulatedMs + clampToNonNegativeMs(elapsedThisRun),
      );
    });
  }

  /// Starts the stopwatch only if it isn't already running. The not-running
  /// check runs inside the same mutation queue as the state change, so two
  /// concurrent callers can't both observe "not running" and race into a
  /// start-then-immediately-stop pair (unlike a naive
  /// read-current-state-then-toggle() sequence).
  Future<void> ensureRunning() {
    final nowEpochMs = DateTime.now().millisecondsSinceEpoch;
    return mutate((s) => s.isRunning ? s : _startedFrom(s, nowEpochMs));
  }

  /// Sets the elapsed time to [elapsed] (#80), e.g. correcting 2:30 to 3:00
  /// after starting a little late or early. Keeps the running/paused status:
  /// a running stopwatch carries on counting from the new value, a paused
  /// one stays paused at it. Negative values are clamped to zero.
  Future<void> setElapsed(Duration elapsed) {
    // Captured before queuing, as in [toggle]: the new value applies from
    // the moment the user confirmed, not from whenever the queue drains.
    final nowEpochMs = DateTime.now().millisecondsSinceEpoch;
    final elapsedMs = clampToNonNegativeMs(elapsed.inMilliseconds);
    return mutate(
      (s) => s.isRunning
          ? StopwatchState(runningSinceEpochMs: nowEpochMs - elapsedMs)
          : StopwatchState(accumulatedMs: elapsedMs),
    );
  }

  StopwatchState _startedFrom(StopwatchState s, int nowEpochMs) {
    return StopwatchState(
      accumulatedMs: s.accumulatedMs,
      runningSinceEpochMs: nowEpochMs,
    );
  }

  /// Long-press: full reset. Unconditionally resets the linked/independent
  /// timer too (spec 3-1節: ストップウォッチの長押しリセットはタイマーも
  /// リセットする).
  Future<void> reset() async {
    await mutate((_) => const StopwatchState());
    await ref.read(timerControllerProvider.notifier).reset();
  }

  /// Double-tap: reset + immediate restart. Only cascades to the timer if
  /// it's currently overdue/counting up — a timer still counting down is
  /// left alone (spec 3-1節: タイマーが完了（超過）していなければそのまま、
  /// すでに超過していればタイマーもリセットする).
  Future<void> resetAndRestart() async {
    final now = DateTime.now();
    await mutate(
      (_) => StopwatchState(runningSinceEpochMs: now.millisecondsSinceEpoch),
    );
    final timer = await ref.read(timerControllerProvider.future);
    if (timer.isOverdueAt(now)) {
      await ref.read(timerControllerProvider.notifier).reset();
    }
  }

  /// Resyncs from disk on app resume. A widget button tap (see
  /// `stopwatch_widget_callback.dart`) runs in a separate isolate with its
  /// own `SharedPreferences` cache — this app's own foreground instance
  /// doesn't see that write until it explicitly reloads. Queued behind
  /// running mutations so it can't race one; unconditionally overwrites the
  /// state since [StopwatchState] has no `==` to compare against cheaply.
  /// A failure is logged rather than turned into `AsyncError`, because
  /// `HomeWidgetScheduler` calls this via `unawaited(...)`.
  Future<void> reloadFromDisk() => reloadFromStorage();

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

  @override
  @protected
  Future<bool> persist(SharedPreferences prefs, StopwatchState value) {
    return prefs.setString(stopwatchStateJsonKey, jsonEncode(value.toJson()));
  }
}
