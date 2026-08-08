class StopwatchState {
  const StopwatchState({this.accumulatedMs = 0, this.runningSinceEpochMs});

  final int accumulatedMs;
  final int? runningSinceEpochMs;

  bool get isRunning => runningSinceEpochMs != null;

  Duration elapsedAt(DateTime now) {
    final runningMs = runningSinceEpochMs == null
        ? 0
        : now.millisecondsSinceEpoch - runningSinceEpochMs!;
    return Duration(milliseconds: accumulatedMs + runningMs);
  }
}
