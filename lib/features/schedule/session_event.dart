import 'package:session_timer/core/clock/epoch_bounds.dart';

enum SessionEventType {
  orientation,
  weekend,
  workday,
  classroom,
  specialSession,
  completion,
}

/// Types of which at most one event can exist (OR and CS).
const Set<SessionEventType> singletonEventTypes = {
  SessionEventType.orientation,
  SessionEventType.completion,
};

/// Types that carry a sequence number (and so can take a manual override) —
/// OR/CR/CS never have one regardless of `manualNumber`.
const Set<SessionEventType> numberedEventTypes = {
  SessionEventType.weekend,
  SessionEventType.workday,
  SessionEventType.specialSession,
};

/// Which schedule an event belongs to. Some programs run two parallel
/// schedules for their early sessions (A and B) that merge into one from a
/// later session on; [common] is every event outside that split — and the
/// default, so a program with no A/B split never sees this.
enum SessionTrack { common, a, b }

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
    this.manualNumber,
    this.track = SessionTrack.common,
  }) : date = DateTime(date.year, date.month, date.day);

  /// Only WE and WD can be split into A/B schedules; every other type is
  /// always [SessionTrack.common].
  static bool supportsTrack(SessionEventType type) =>
      type == SessionEventType.weekend || type == SessionEventType.workday;

  final String id;
  final SessionEventType type;
  final DateTime date;

  /// Whether this event's row shows on the read-only "セッションスケジュー
  /// ル" screen. Only meaningful for OR / non-first WE / WD / SS — CS, the
  /// first WE, and CR always show regardless of this field. Toggling this
  /// never affects the 週末間/今日から day-count chain, which always runs
  /// over every event — it only controls whether a row is drawn.
  final bool visible;

  /// Overrides the auto-assigned sequence number (`assignSequenceNumbers`)
  /// shown in this event's label (e.g. "2WE") — `null` keeps the automatic
  /// date-order number. Only meaningful for WE/WD/SS; OR/CR/CS never carry
  /// a number regardless of this field. Purely a display override for this
  /// one event — it doesn't affect any other event's own auto-assigned
  /// number, and duplicate/skipped numbers across events aren't checked.
  final int? manualNumber;

  /// The A or B schedule this event belongs to, or [SessionTrack.common] for
  /// an event shared by both. Only meaningful for WE/WD (see
  /// [supportsTrack]). Events on different tracks don't count toward each
  /// other's sequence numbers or 週末間 gaps.
  final SessionTrack track;

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
    // defaults to true — everything used to always show. An explicit
    // `null` is rejected like any other wrong-typed value, unlike a
    // missing key — `visible` has no meaningful null state to tolerate.
    final rawVisible = json['visible'];
    if (json.containsKey('visible') && rawVisible is! bool) return null;
    // manualNumber is genuinely nullable (absent = auto), so unlike
    // `visible` an explicit `null` here is accepted, not rejected.
    final rawManualNumber = json['manualNumber'];
    if (rawManualNumber != null && rawManualNumber is! int) return null;
    if (rawManualNumber is int && rawManualNumber <= 0) return null;
    // Absent (every entry saved before A/B schedules existed) is `common`.
    // A present-but-unknown value, or a track on a type that can't have
    // one, rejects the entry like any other malformed field.
    final rawTrack = json['track'];
    if (json.containsKey('track') && rawTrack is! String) return null;
    final tracks = SessionTrack.values.where((t) => t.name == rawTrack);
    if (rawTrack != null && tracks.isEmpty) return null;
    final track = rawTrack == null ? SessionTrack.common : tracks.first;
    if (track != SessionTrack.common && !supportsTrack(matches.first)) {
      return null;
    }
    final utc = DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true);
    return SessionEvent(
      id: id,
      type: matches.first,
      date: utc,
      visible: (rawVisible as bool?) ?? true,
      manualNumber: rawManualNumber as int?,
      track: track,
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
    if (manualNumber != null) 'manualNumber': manualNumber,
    // Omitted for `common`, like `visible`, so an un-split schedule's JSON
    // is unchanged.
    if (track != SessionTrack.common) 'track': track.name,
  };
}
