import 'package:session_timer/core/clock/epoch_bounds.dart';

enum SessionEventType {
  orientation,
  weekend,
  workday,
  classroom,
  specialSession,
  completion,
}

/// A single scheduled session (OR/WE/WD/CR/SS/CS). [date] only ever carries
/// a calendar date — normalized to midnight in the constructor itself so
/// that comparisons like `isAtSameMomentAs` between two events can't be
/// broken by a stray time-of-day component slipping in from a caller.
class SessionEvent {
  SessionEvent({
    required this.id,
    required this.type,
    required DateTime date,
    this.visible = true,
  }) : date = DateTime(date.year, date.month, date.day);

  final String id;
  final SessionEventType type;
  final DateTime date;

  /// Whether this event's row shows on the read-only "セッションスケジュー
  /// ル" screen. Only meaningful for OR / non-first WE / WD / SS — CS, the
  /// first WE, and CR always show regardless of this field (see
  /// `session_chain.dart`'s `_isVisibleOnScheduleScreen`). Toggling this
  /// never affects the 週末間/今日から day-count chain, which always runs
  /// over every event — it only controls whether a row is drawn.
  final bool visible;

  /// Every type is a single day except WE, whose first occurrence
  /// ([isFirstWeekend]) runs 3 days and later ones run 2. Whether a given
  /// WE is "first" isn't decidable from this event alone; it depends on
  /// the full list's chronological order, so it's supplied by the caller.
  int durationDays({required bool isFirstWeekend}) {
    if (type != SessionEventType.weekend) return 1;
    return isFirstWeekend ? 3 : 2;
  }

  /// Adds via the calendar (year/month/day), not `Duration` — a
  /// `Duration`-based add is a fixed number of hours, which can land on
  /// the wrong calendar day across a daylight-saving transition in
  /// non-Japan timezones (this app's timezone follows the device, not a
  /// hardcoded JST).
  DateTime endDate({required bool isFirstWeekend}) {
    final extraDays = durationDays(isFirstWeekend: isFirstWeekend) - 1;
    return DateTime(date.year, date.month, date.day + extraDays);
  }

  /// Null if [json] doesn't match the expected shape — one bad entry
  /// doesn't take down the whole persisted list (mirrors
  /// `TimeTarget.tryFromJson`).
  static SessionEvent? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final typeName = json['type'];
    final epochMs = json['epochMs'];
    if (id is! String || typeName is! String || epochMs is! int) return null;
    if (epochMs.abs() > maxEpochMs) return null;
    final matches = SessionEventType.values.where((t) => t.name == typeName);
    if (matches.isEmpty) return null;
    // Absent (older persisted entries, from before `visible` existed)
    // defaults to true — everything used to always show.
    final rawVisible = json['visible'];
    if (rawVisible != null && rawVisible is! bool) return null;
    final utc = DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true);
    return SessionEvent(
      id: id,
      type: matches.first,
      date: utc,
      visible: (rawVisible as bool?) ?? true,
    );
  }

  /// Serialized via a UTC-anchored epoch rather than [date]'s own local
  /// one — [date] only ever carries a calendar date, and anchoring to UTC
  /// keeps that date stable in storage even if the device's timezone
  /// changes between saving and loading.
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'epochMs': DateTime.utc(
      date.year,
      date.month,
      date.day,
    ).millisecondsSinceEpoch,
    // Omitted when true (the default) — keeps the common case's JSON as
    // compact as before this field existed.
    if (!visible) 'visible': false,
  };
}
