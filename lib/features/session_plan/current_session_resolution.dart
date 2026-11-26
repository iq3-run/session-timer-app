import 'package:session_timer/features/session_plan/session_plan_entry.dart';

/// The derived 完了時刻/指定時刻 pair for whichever session is current right
/// now, computed fresh from the wall clock rather than a stored "current
/// index" — calling this again at any time re-derives the right answer
/// without needing sequential calls.
typedef CurrentSessionResolution = ({
  SessionPlanEntry session,
  DateTime completionTarget,
  DateTime? autoTargetStart,
});

typedef _Occurrence = ({DateTime start, DateTime end});

/// Picks the session that is in progress right now or, failing that, the
/// next one to begin — whichever ends soonest. Sessions hold only a time of
/// day, so each one is placed on the calendar relative to [now]; any
/// non-empty plan therefore always has a current session. Returns `null`
/// only when [sessions] is empty.
///
/// `autoTargetStart` is the resolved session's own start time if it hasn't
/// started yet (a countdown to "when this session begins"), or — once it
/// has started — the next start of whichever session follows it in
/// time-of-day order, or `null` if it is the last one.
CurrentSessionResolution? resolveCurrentSession(
  List<SessionPlanEntry> sessions,
  DateTime now,
) {
  if (sessions.isEmpty) return null;

  SessionPlanEntry? selected;
  _Occurrence? selectedOccurrence;
  for (final session in sessions) {
    final occurrence = _currentOrNextOccurrence(session, now);
    if (selectedOccurrence == null ||
        occurrence.end.isBefore(selectedOccurrence.end)) {
      selected = session;
      selectedOccurrence = occurrence;
    }
  }
  // Non-empty list: both were assigned on the first iteration.
  if (selected == null || selectedOccurrence == null) return null;

  if (selectedOccurrence.start.isAfter(now)) {
    return (
      session: selected,
      completionTarget: selectedOccurrence.end,
      autoTargetStart: selectedOccurrence.start,
    );
  }

  final byStart = [...sessions]
    ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
  final selectedIndex = byStart.indexWhere((s) => s.id == selected!.id);
  final next = selectedIndex + 1 < byStart.length
      ? byStart[selectedIndex + 1]
      : null;
  return (
    session: selected,
    completionTarget: selectedOccurrence.end,
    autoTargetStart: next == null ? null : _nextStartAfter(next, now),
  );
}

/// The earliest occurrence of [session] that hasn't ended yet at [now]:
/// the one in progress, or the next to begin. Durations are at most 24h,
/// so looking from yesterday (a session that ran past midnight) through
/// tomorrow is always enough to find one.
_Occurrence _currentOrNextOccurrence(SessionPlanEntry session, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  for (var dayOffset = -1; dayOffset <= 0; dayOffset++) {
    final day = DateTime(today.year, today.month, today.day + dayOffset);
    final end = session.endOn(day);
    if (end.isAfter(now)) return (start: session.startOn(day), end: end);
  }
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  return (start: session.startOn(tomorrow), end: session.endOn(tomorrow));
}

/// The next moment [session] starts strictly after [now].
DateTime _nextStartAfter(SessionPlanEntry session, DateTime now) {
  final today = session.startOn(now);
  if (today.isAfter(now)) return today;
  return session.startOn(DateTime(now.year, now.month, now.day + 1));
}
