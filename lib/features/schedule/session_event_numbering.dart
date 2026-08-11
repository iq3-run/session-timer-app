import 'package:session_timer/features/schedule/session_event.dart';

const Set<SessionEventType> _numberedTypes = {
  SessionEventType.weekend,
  SessionEventType.workday,
  SessionEventType.specialSession,
};

/// Assigns 1-based, per-type sequence numbers (1WE, 2WE, ...) to WE/WD/SS
/// events, ordered by date. OR/CR/CS never get a number, so they're absent
/// from the returned map. Same-date events within a type are ordered by
/// their position in [events] (the order they were added), since
/// `List.sort` isn't stable and date alone can't break the tie.
Map<String, int> assignSequenceNumbers(List<SessionEvent> events) {
  final result = <String, int>{};
  for (final type in _numberedTypes) {
    final indexed =
        [
          for (var i = 0; i < events.length; i++)
            if (events[i].type == type) (index: i, event: events[i]),
        ]..sort((a, b) {
          final byDate = a.event.date.compareTo(b.event.date);
          return byDate != 0 ? byDate : a.index.compareTo(b.index);
        });
    for (var i = 0; i < indexed.length; i++) {
      result[indexed[i].event.id] = i + 1;
    }
  }
  return result;
}
