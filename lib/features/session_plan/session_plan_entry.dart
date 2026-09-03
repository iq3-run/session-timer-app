import 'package:session_timer/core/clock/epoch_bounds.dart';

/// A single pre-registered session in the day's plan: a start time plus an
/// end time (either typed in directly or derived from a duration at input
/// time — this class only ever stores the resolved end).
class SessionPlanEntry {
  const SessionPlanEntry({
    required this.id,
    required this.startEpochMs,
    required this.endEpochMs,
  });

  /// Null if [json] doesn't match the expected shape, or [endEpochMs] isn't
  /// after [startEpochMs] — mirrors `TimeTarget.tryFromJson`: one bad entry
  /// doesn't take down the whole persisted list.
  static SessionPlanEntry? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final startEpochMs = json['startEpochMs'];
    final endEpochMs = json['endEpochMs'];
    if (id is! String || startEpochMs is! int || endEpochMs is! int) {
      return null;
    }
    if (startEpochMs.abs() > maxEpochMs || endEpochMs.abs() > maxEpochMs) {
      return null;
    }
    if (endEpochMs <= startEpochMs) return null;
    return SessionPlanEntry(
      id: id,
      startEpochMs: startEpochMs,
      endEpochMs: endEpochMs,
    );
  }

  final String id;
  final int startEpochMs;
  final int endEpochMs;

  DateTime get startTime => DateTime.fromMillisecondsSinceEpoch(startEpochMs);
  DateTime get endTime => DateTime.fromMillisecondsSinceEpoch(endEpochMs);

  Map<String, dynamic> toJson() => {
    'id': id,
    'startEpochMs': startEpochMs,
    'endEpochMs': endEpochMs,
  };
}
