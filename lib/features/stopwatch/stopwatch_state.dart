class StopwatchState {
  const StopwatchState({this.accumulatedMs = 0, this.runningSinceEpochMs});

  final int accumulatedMs;
  final int? runningSinceEpochMs;

  bool get isRunning => runningSinceEpochMs != null;

  // Clamped to zero: a device clock or NTP-driven correction (see
  // docs/session-timer-spec.md section 3-6) can move `now` backwards
  // relative to `runningSinceEpochMs`, which would otherwise show a
  // negative elapsed time.
  Duration elapsedAt(DateTime now) {
    final rawRunningMs = runningSinceEpochMs == null
        ? 0
        : now.millisecondsSinceEpoch - runningSinceEpochMs!;
    return Duration(
      milliseconds: accumulatedMs + (rawRunningMs < 0 ? 0 : rawRunningMs),
    );
  }

  Map<String, dynamic> toJson() => {
    'accumulatedMs': accumulatedMs,
    if (runningSinceEpochMs != null) 'runningSinceEpochMs': runningSinceEpochMs,
  };

  static StopwatchState? tryFromJson(Map<String, dynamic> json) {
    final accumulatedMs = json['accumulatedMs'];
    if (accumulatedMs is! int) return null;
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
