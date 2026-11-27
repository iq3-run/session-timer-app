import 'package:session_timer/features/schedule/session_event.dart';

/// Assigns 1-based, per-type sequence numbers (1WE, 2WE, ...) to WE/WD/SS
/// events, ordered by date. OR/CR/CS never get a number, so they're absent
/// from the returned map. Same-date events within a type are ordered by
/// their position in [events] (the order they were added), since
/// `List.sort` isn't stable and date alone can't break the tie.
///
/// When the schedule is split into A and B ([SessionTrack]), each track
/// counts on its own, so 1WE(A) and 1WE(B) are both 1WE rather than 1WE and
/// 2WE. A track's number counts the common events before it plus its own
/// earlier ones. A common event — where the two schedules merge — continues
/// from whichever track has run further, so the merged 2WE follows
/// 1WE(A)/1WE(B) — and if A has run to 2WE while B stopped at 1WE, the
/// merged one is 3WE. The schedules are expected to end at the merge, but if
/// an A/B event is dated after a common one it counts on from it — from the
/// furthest schedule, whichever one it is on — so a number is never repeated
/// within one schedule. With no A/B events this is the plain date-order count.
Map<String, int> assignSequenceNumbers(List<SessionEvent> events) {
  final result = <String, int>{};
  for (final type in numberedEventTypes) {
    final indexed =
        [
          for (var i = 0; i < events.length; i++)
            if (events[i].type == type) (index: i, event: events[i]),
        ]..sort((a, b) {
          final byDate = a.event.date.compareTo(b.event.date);
          return byDate != 0 ? byDate : a.index.compareTo(b.index);
        });
    // Running counts of the events seen so far, in date order.
    var common = 0;
    final onTrack = {SessionTrack.a: 0, SessionTrack.b: 0};
    for (final entry in indexed) {
      final event = entry.event;
      if (event.track == SessionTrack.common) {
        final furthest = onTrack.values.reduce((a, b) => a > b ? a : b);
        result[event.id] = common + furthest + 1;
        // Both schedules pass through a merge, so the one that was behind
        // catches up to the one that was ahead. Otherwise a later event on
        // the lagging schedule would be given this event's number again.
        for (final track in onTrack.keys) {
          onTrack[track] = furthest;
        }
        common++;
      } else {
        final count = onTrack[event.track]!;
        result[event.id] = common + count + 1;
        onTrack[event.track] = count + 1;
      }
    }
  }
  return result;
}
