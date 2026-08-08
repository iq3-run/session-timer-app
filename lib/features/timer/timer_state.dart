import 'package:session_timer/core/clock/epoch_bounds.dart';

/// Whether a running timer counts down from the moment it was set, or from
/// the stopwatch's effective start time (see docs/session-timer-spec.md
/// 3-1節).
enum TimerMode { normal, linked }

class TimerState {
  const TimerState({this.targetEpochMs, this.mode = TimerMode.normal});

  final int? targetEpochMs;

  /// Kept even while unset — it doubles as "last selected mode", which the
  /// +30s/+1min long-press quick-start reuses (spec: 直前に選んでいたモード
  /// を引き継ぐ).
  final TimerMode mode;

  bool get isRunning => targetEpochMs != null;

  DateTime? get targetTime => targetEpochMs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(targetEpochMs!);

  bool isOverdueAt(DateTime now) =>
      targetEpochMs != null && !now.isBefore(targetTime!);

  /// Positive while counting down, negative once overdue (counting up).
  /// Zero while unset.
  Duration remainingAt(DateTime now) =>
      targetTime == null ? Duration.zero : targetTime!.difference(now);

  Map<String, dynamic> toJson() => {
    if (targetEpochMs != null) 'targetEpochMs': targetEpochMs,
    'mode': mode.name,
  };

  /// Null if [json] doesn't match the expected shape — e.g. corrupted or
  /// from a future schema — rather than throwing, so a bad persisted value
  /// falls back to the unset state instead of crashing the app.
  static TimerState? tryFromJson(Map<String, dynamic> json) {
    final rawTargetEpochMs = json['targetEpochMs'];
    if (rawTargetEpochMs != null && rawTargetEpochMs is! int) return null;
    final targetEpochMs = rawTargetEpochMs as int?;
    if (targetEpochMs != null && targetEpochMs.abs() > maxEpochMs) {
      return null;
    }
    final mode = _modeFromName(json['mode']);
    if (mode == null) return null;
    return TimerState(targetEpochMs: targetEpochMs, mode: mode);
  }

  static TimerMode? _modeFromName(Object? name) {
    if (name is! String) return null;
    for (final mode in TimerMode.values) {
      if (mode.name == name) return mode;
    }
    return null;
  }
}
