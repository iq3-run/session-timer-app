import 'package:session_timer/features/schedule/session_event.dart';
import 'package:session_timer/features/schedule/session_event_numbering.dart';
import 'package:session_timer/features/schedule/session_gap_calculation.dart';

/// OR/WE/WD/SS/CS form the "週末間" chain; CR is tracked separately (see
/// [_crRows]) since it doesn't have a fixed cadence of its own.
const Set<SessionEventType> _chainTypes = {
  SessionEventType.orientation,
  SessionEventType.weekend,
  SessionEventType.workday,
  SessionEventType.specialSession,
  SessionEventType.completion,
};

/// The pool eligible for the single nearest-past/nearest-future "今日から"
/// gap — only WE/WD/SS, not OR (always in the past) or CS (handled
/// unconditionally, see [_todayGapFor]).
const Set<SessionEventType> _nearestTypes = {
  SessionEventType.weekend,
  SessionEventType.workday,
  SessionEventType.specialSession,
};

/// One row of the schedule table. [event] is null only for the synthetic
/// "今日" row inserted when today doesn't land on any event's date.
class ScheduleRow {
  const ScheduleRow({
    required this.label,
    required this.date,
    required this.isToday,
    this.event,
    this.chainGap,
    this.todayGap,
  });

  final SessionEvent? event;
  final String label;
  final DateTime date;
  final bool isToday;
  final GapResult? chainGap;
  final GapResult? todayGap;
}

/// Builds the full schedule table: chain rows (OR/WE/WD/SS/CS, chronological)
/// merged with the CR-specific rows (today's CR if any, plus the next
/// upcoming one), then a "今日" marker either on a matching row or inserted
/// as its own row.
List<ScheduleRow> buildScheduleRows(List<SessionEvent> events, DateTime today) {
  final numbers = assignSequenceNumbers(events);
  final chainEvents = events.where((e) => _chainTypes.contains(e.type)).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  final chainRows = _buildChainRows(chainEvents, numbers, today);

  final merged = [...chainRows, ..._crRows(events, today)]
    ..sort((a, b) => a.date.compareTo(b.date));
  return _withTodayMarker(merged, today);
}

List<ScheduleRow> _buildChainRows(
  List<SessionEvent> chainEvents,
  Map<String, int> numbers,
  DateTime today,
) {
  DateTime endOf(SessionEvent e) => e.endDate(
    isFirstWeekend: e.type == SessionEventType.weekend && numbers[e.id] == 1,
  );
  final nearestPast = _nearestPast(chainEvents, today, endOf);
  final nearestFuture = _nearestFuture(chainEvents, today);
  return [
    for (var i = 0; i < chainEvents.length; i++)
      _chainRow(
        chainEvents[i],
        previous: i == 0 ? null : chainEvents[i - 1],
        numbers: numbers,
        endOf: endOf,
        today: today,
        nearestPast: nearestPast,
        nearestFuture: nearestFuture,
      ),
  ];
}

ScheduleRow _chainRow(
  SessionEvent event, {
  required SessionEvent? previous,
  required Map<String, int> numbers,
  required DateTime Function(SessionEvent) endOf,
  required DateTime today,
  required SessionEvent? nearestPast,
  required SessionEvent? nearestFuture,
}) {
  final chainGap = previous == null
      ? null
      : calculateGap(fromEnd: endOf(previous), toStart: event.date);
  return ScheduleRow(
    event: event,
    label: _label(event, numbers),
    date: event.date,
    isToday: _isOngoing(event, endOf, today),
    chainGap: chainGap,
    todayGap: _todayGapFor(event, today, endOf, nearestPast, nearestFuture),
  );
}

/// True if [today] falls anywhere within [event]'s span (start through
/// end, inclusive) — a multi-day WE is still "today" on its 2nd/3rd day,
/// not just its start date.
bool _isOngoing(
  SessionEvent event,
  DateTime Function(SessionEvent) endOf,
  DateTime today,
) {
  return !today.isBefore(event.date) && !today.isAfter(endOf(event));
}

/// 今日から column: only the single nearest-past WE/WD/SS, the single
/// nearest-future WE/WD/SS, and CS (always) get a value — every other chain
/// row leaves this blank.
GapResult? _todayGapFor(
  SessionEvent event,
  DateTime today,
  DateTime Function(SessionEvent) endOf,
  SessionEvent? nearestPast,
  SessionEvent? nearestFuture,
) {
  if (identical(event, nearestPast)) {
    return calculateGap(fromEnd: endOf(event), toStart: today);
  }
  final isNextOrCompletion =
      identical(event, nearestFuture) ||
      event.type == SessionEventType.completion;
  return isNextOrCompletion
      ? calculateGap(fromEnd: today, toStart: event.date)
      : null;
}

/// "Nearest past" means fully finished — an ongoing multi-day WE (today
/// falls within its span but hasn't reached its end date yet) doesn't
/// count, or [_todayGapFor] would compute a gap against a not-yet-reached
/// end date and produce a nonsensical negative result.
SessionEvent? _nearestPast(
  List<SessionEvent> chainEvents,
  DateTime today,
  DateTime Function(SessionEvent) endOf,
) {
  final past = chainEvents.where(
    (e) => _nearestTypes.contains(e.type) && endOf(e).isBefore(today),
  );
  return past.isEmpty
      ? null
      : past.reduce((a, b) => a.date.isAfter(b.date) ? a : b);
}

SessionEvent? _nearestFuture(List<SessionEvent> chainEvents, DateTime today) {
  final future = chainEvents.where(
    (e) => _nearestTypes.contains(e.type) && e.date.isAfter(today),
  );
  return future.isEmpty
      ? null
      : future.reduce((a, b) => a.date.isBefore(b.date) ? a : b);
}

/// At most two rows: today's CR (if one lands exactly on today) and the
/// next upcoming CR after today. Other CR entries never appear in the
/// table — only "now" and "next" matter during a live session.
List<ScheduleRow> _crRows(List<SessionEvent> events, DateTime today) {
  final crEvents = events.where((e) => e.type == SessionEventType.classroom);
  final todayMatches = crEvents.where((e) => e.date.isAtSameMomentAs(today));
  final futureMatches = crEvents.where((e) => e.date.isAfter(today));
  final todayCr = todayMatches.isEmpty ? null : todayMatches.first;
  final nextCr = futureMatches.isEmpty
      ? null
      : futureMatches.reduce((a, b) => a.date.isBefore(b.date) ? a : b);
  return [
    if (todayCr != null)
      ScheduleRow(
        event: todayCr,
        label: 'CR',
        date: todayCr.date,
        isToday: true,
      ),
    if (nextCr != null)
      ScheduleRow(
        event: nextCr,
        label: '次回CR',
        date: nextCr.date,
        isToday: false,
        todayGap: calculateGap(fromEnd: today, toStart: nextCr.date),
      ),
  ];
}

List<ScheduleRow> _withTodayMarker(List<ScheduleRow> rows, DateTime today) {
  if (rows.any((r) => r.isToday)) return rows;
  final insertIndex = rows.indexWhere((r) => r.date.isAfter(today));
  final todayRow = ScheduleRow(label: '今日', date: today, isToday: true);
  if (insertIndex == -1) return [...rows, todayRow];
  return [
    ...rows.sublist(0, insertIndex),
    todayRow,
    ...rows.sublist(insertIndex),
  ];
}

String _label(SessionEvent event, Map<String, int> numbers) {
  final number = numbers[event.id];
  return switch (event.type) {
    SessionEventType.orientation => 'OR',
    SessionEventType.weekend => '${number}WE',
    SessionEventType.workday => '${number}WD',
    SessionEventType.classroom => 'CR',
    SessionEventType.specialSession => '${number}SS',
    SessionEventType.completion => 'CS',
  };
}
