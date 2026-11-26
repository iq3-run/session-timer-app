import 'dart:math' as math;

/// Minutes in a day — also the longest a session can last.
const int minutesPerDay = 24 * 60;

/// A single pre-registered session in the day's plan: a time of day to
/// start at plus how long it lasts.
///
/// Deliberately holds no calendar date. The plan is a repeating daily
/// rhythm (e.g. AM/PM/evening blocks), so a stored date would only be an
/// accident of which day the session happened to be registered on — and
/// once that day passed, the session would wrongly read as "already
/// ended". Dates are derived from the wall clock when needed instead
/// (see [startOn] / [endOn]).
class SessionPlanEntry {
  const SessionPlanEntry({
    required this.id,
    required this.startMinutes,
    required this.durationMinutes,
  }) : assert(
         startMinutes >= 0 && startMinutes < minutesPerDay,
         'startMinutes must be within a day',
       ),
       assert(
         durationMinutes > 0 && durationMinutes <= minutesPerDay,
         'durationMinutes must be 1..1440',
       );

  /// Null if [json] doesn't match the expected shape or holds an
  /// out-of-range value — mirrors `TimeTarget.tryFromJson`: one bad entry
  /// doesn't take down the whole persisted list.
  ///
  /// Also reads the legacy format (absolute `startEpochMs`/`endEpochMs`,
  /// written before sessions became date-less), keeping only the local
  /// time of day, so sessions registered earlier are not lost.
  static SessionPlanEntry? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String) return null;

    final startMinutes = json['startMinutes'];
    final durationMinutes = json['durationMinutes'];
    if (startMinutes is int && durationMinutes is int) {
      return _validated(id, startMinutes, durationMinutes);
    }
    return _tryFromLegacyJson(id, json);
  }

  static SessionPlanEntry? _tryFromLegacyJson(
    String id,
    Map<String, dynamic> json,
  ) {
    final startEpochMs = json['startEpochMs'];
    final endEpochMs = json['endEpochMs'];
    if (startEpochMs is! int || endEpochMs is! int) return null;
    if (endEpochMs <= startEpochMs) return null;
    final DateTime start;
    final DateTime end;
    try {
      start = DateTime.fromMillisecondsSinceEpoch(startEpochMs);
      end = DateTime.fromMillisecondsSinceEpoch(endEpochMs);
    } on Object {
      // Out-of-range epoch (beyond DateTime's representable range).
      return null;
    }
    // Clamp rather than reject: a legacy session longer than a day can't be
    // represented, but dropping it would silently lose the user's entry.
    return _validated(
      id,
      start.hour * 60 + start.minute,
      math.min(end.difference(start).inMinutes, minutesPerDay),
    );
  }

  static SessionPlanEntry? _validated(
    String id,
    int startMinutes,
    int durationMinutes,
  ) {
    if (startMinutes < 0 || startMinutes >= minutesPerDay) return null;
    if (durationMinutes <= 0 || durationMinutes > minutesPerDay) return null;
    return SessionPlanEntry(
      id: id,
      startMinutes: startMinutes,
      durationMinutes: durationMinutes,
    );
  }

  final String id;

  /// Minutes since midnight, 0–1439.
  final int startMinutes;

  /// 1–1440. A session that runs past midnight is just one whose
  /// `startMinutes + durationMinutes` exceeds a day.
  final int durationMinutes;

  /// Minutes since midnight of the end time, 0–1439 (wraps past midnight).
  int get endMinutes => (startMinutes + durationMinutes) % minutesPerDay;

  String get startLabel => _formatMinutes(startMinutes);
  String get endLabel => _formatMinutes(endMinutes);

  /// This session's start on the calendar day of [day] (local time).
  DateTime startOn(DateTime day) => DateTime(
    day.year,
    day.month,
    day.day,
    startMinutes ~/ 60,
    startMinutes % 60,
  );

  /// The end of the occurrence that starts on the calendar day of [day].
  /// Built from wall-clock fields rather than `Duration` arithmetic so a
  /// DST transition can't shift the end's hour.
  DateTime endOn(DateTime day) => DateTime(
    day.year,
    day.month,
    day.day,
    startMinutes ~/ 60,
    startMinutes % 60 + durationMinutes,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'startMinutes': startMinutes,
    'durationMinutes': durationMinutes,
  };
}

String _formatMinutes(int minutes) =>
    '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';
