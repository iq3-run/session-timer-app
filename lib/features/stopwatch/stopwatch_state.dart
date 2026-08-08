// A device clock or NTP-driven correction (see docs/session-timer-spec.md
// section 3-6) can move `now` backwards relative to a stored start epoch,
// which would otherwise produce a negative elapsed segment.
int clampToNonNegativeMs(int ms) => ms < 0 ? 0 : ms;

class StopwatchState {
  const StopwatchState({this.accumulatedMs = 0, this.runningSinceEpochMs});

  final int accumulatedMs;
  final int? runningSinceEpochMs;

  bool get isRunning => runningSinceEpochMs != null;

  Duration elapsedAt(DateTime now) {
    final rawRunningMs = runningSinceEpochMs == null
        ? 0
        : now.millisecondsSinceEpoch - runningSinceEpochMs!;
    return Duration(
      milliseconds: accumulatedMs + clampToNonNegativeMs(rawRunningMs),
    );
  }

  Map<String, dynamic> toJson() => {
    'accumulatedMs': accumulatedMs,
    if (runningSinceEpochMs != null) 'runningSinceEpochMs': runningSinceEpochMs,
  };

  static StopwatchState? tryFromJson(Map<String, dynamic> json) {
    final accumulatedMs = json['accumulatedMs'];
    if (accumulatedMs is! int || accumulatedMs < 0) return null;
    final runningSinceEpochMs = json['runningSinceEpochMs'];
    if (runningSinceEpochMs != null && runningSinceEpochMs is! int) {
      return null;
    }
    return StopwatchState(
      accumulatedMs: accumulatedMs,
      runningSinceEpochMs: runningSinceEpochMs as int?,
    );
  }
}
