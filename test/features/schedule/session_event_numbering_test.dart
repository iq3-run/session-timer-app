import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/schedule/session_event.dart';
import 'package:session_timer/features/schedule/session_event_numbering.dart';

SessionEvent _event(String id, SessionEventType type, DateTime date) =>
    SessionEvent(id: id, type: type, date: date);

void main() {
  group('assignSequenceNumbers', () {
    test('numbers WE/WD/SS by date ascending, independently per type', () {
      final events = [
        _event('we2', SessionEventType.weekend, DateTime(2026, 9, 26)),
        _event('we1', SessionEventType.weekend, DateTime(2026, 8, 21)),
        _event('wd1', SessionEventType.workday, DateTime(2026, 9, 5)),
        _event('ss1', SessionEventType.specialSession, DateTime(2026, 10)),
      ];

      final numbers = assignSequenceNumbers(events);

      expect(numbers['we1'], 1);
      expect(numbers['we2'], 2);
      expect(numbers['wd1'], 1);
      expect(numbers['ss1'], 1);
    });

    test('OR/CR/CS never get a sequence number', () {
      final events = [
        _event('or', SessionEventType.orientation, DateTime(2026, 8, 7)),
        _event('cr', SessionEventType.classroom, DateTime(2026, 9, 11)),
        _event('cs', SessionEventType.completion, DateTime(2027, 6, 25)),
      ];

      final numbers = assignSequenceNumbers(events);

      expect(numbers.containsKey('or'), isFalse);
      expect(numbers.containsKey('cr'), isFalse);
      expect(numbers.containsKey('cs'), isFalse);
    });

    test('same-date entries of the same type break ties by list order', () {
      final sameDate = DateTime(2026, 9, 5);
      final events = [
        _event('later-added', SessionEventType.workday, sameDate),
        _event('earlier-added', SessionEventType.workday, sameDate),
      ];

      final numbers = assignSequenceNumbers(events);

      expect(numbers['later-added'], 1);
      expect(numbers['earlier-added'], 2);
    });
  });

  group('assignSequenceNumbers with A/B schedules', () {
    SessionEvent track(
      String id,
      SessionEventType type,
      DateTime date,
      SessionTrack track,
    ) => SessionEvent(id: id, type: type, date: date, track: track);

    test('A and B each count on their own, so both are 1WE', () {
      final events = [
        track(
          'a',
          SessionEventType.weekend,
          DateTime(2026, 8, 21),
          SessionTrack.a,
        ),
        track(
          'b',
          SessionEventType.weekend,
          DateTime(2026, 8, 28),
          SessionTrack.b,
        ),
      ];

      final numbers = assignSequenceNumbers(events);

      expect(numbers['a'], 1);
      expect(numbers['b'], 1); // not 2: it is B's own first weekend
    });

    test('the merged (common) event follows the A/B weekends', () {
      final events = [
        track(
          'a',
          SessionEventType.weekend,
          DateTime(2026, 8, 21),
          SessionTrack.a,
        ),
        track(
          'b',
          SessionEventType.weekend,
          DateTime(2026, 8, 28),
          SessionTrack.b,
        ),
        track(
          'merged',
          SessionEventType.weekend,
          DateTime(2026, 9, 26),
          SessionTrack.common,
        ),
        track(
          'after',
          SessionEventType.weekend,
          DateTime(2026, 10, 24),
          SessionTrack.common,
        ),
      ];

      final numbers = assignSequenceNumbers(events);

      expect(numbers['merged'], 2);
      expect(numbers['after'], 3);
    });

    test('WE and WD are numbered independently, each with its own A/B', () {
      final events = [
        track(
          'weA',
          SessionEventType.weekend,
          DateTime(2026, 8, 21),
          SessionTrack.a,
        ),
        track(
          'weB',
          SessionEventType.weekend,
          DateTime(2026, 8, 28),
          SessionTrack.b,
        ),
        track(
          'wdA',
          SessionEventType.workday,
          DateTime(2026, 9, 5),
          SessionTrack.a,
        ),
        track(
          'wdB',
          SessionEventType.workday,
          DateTime(2026, 9, 12),
          SessionTrack.b,
        ),
        track(
          'wd2',
          SessionEventType.workday,
          DateTime(2026, 11),
          SessionTrack.common,
        ),
      ];

      final numbers = assignSequenceNumbers(events);

      expect(numbers['wdA'], 1);
      expect(numbers['wdB'], 1);
      expect(numbers['wd2'], 2);
    });

    test('a common event continues from whichever schedule ran further', () {
      final events = [
        track(
          'a1',
          SessionEventType.weekend,
          DateTime(2026, 8, 21),
          SessionTrack.a,
        ),
        track(
          'a2',
          SessionEventType.weekend,
          DateTime(2026, 9, 5),
          SessionTrack.a,
        ),
        track(
          'b1',
          SessionEventType.weekend,
          DateTime(2026, 8, 28),
          SessionTrack.b,
        ),
        track(
          'merged',
          SessionEventType.weekend,
          DateTime(2026, 9, 26),
          SessionTrack.common,
        ),
      ];

      final numbers = assignSequenceNumbers(events);

      expect(numbers['a1'], 1);
      expect(numbers['a2'], 2);
      expect(numbers['b1'], 1);
      expect(numbers['merged'], 3);
    });

    test('a common event before the split counts toward both schedules', () {
      final events = [
        track(
          'first',
          SessionEventType.weekend,
          DateTime(2026, 8, 7),
          SessionTrack.common,
        ),
        track(
          'a',
          SessionEventType.weekend,
          DateTime(2026, 8, 21),
          SessionTrack.a,
        ),
        track(
          'b',
          SessionEventType.weekend,
          DateTime(2026, 8, 28),
          SessionTrack.b,
        ),
      ];

      final numbers = assignSequenceNumbers(events);

      expect(numbers['first'], 1);
      expect(numbers['a'], 2);
      expect(numbers['b'], 2);
    });

    test('an A/B event after a merge keeps counting without repeating', () {
      final events = [
        track(
          'a1',
          SessionEventType.weekend,
          DateTime(2026, 8, 21),
          SessionTrack.a,
        ),
        track(
          'merged',
          SessionEventType.weekend,
          DateTime(2026, 9, 26),
          SessionTrack.common,
        ),
        track(
          'a2',
          SessionEventType.weekend,
          DateTime(2026, 10, 24),
          SessionTrack.a,
        ),
      ];

      final numbers = assignSequenceNumbers(events);

      expect(numbers['a1'], 1);
      expect(numbers['merged'], 2);
      expect(numbers['a2'], 3);
    });

    test('B running ahead of A is handled the same as A ahead of B', () {
      final events = [
        track(
          'b1',
          SessionEventType.weekend,
          DateTime(2026, 8, 21),
          SessionTrack.b,
        ),
        track(
          'b2',
          SessionEventType.weekend,
          DateTime(2026, 9, 5),
          SessionTrack.b,
        ),
        track(
          'a1',
          SessionEventType.weekend,
          DateTime(2026, 8, 28),
          SessionTrack.a,
        ),
        track(
          'merged',
          SessionEventType.weekend,
          DateTime(2026, 9, 26),
          SessionTrack.common,
        ),
      ];

      final numbers = assignSequenceNumbers(events);

      expect(numbers['b2'], 2);
      expect(numbers['a1'], 1);
      expect(numbers['merged'], 3);
    });

    test('with no A/B events the numbering is unchanged', () {
      final events = [
        track(
          'w1',
          SessionEventType.weekend,
          DateTime(2026, 8, 21),
          SessionTrack.common,
        ),
        track(
          'w2',
          SessionEventType.weekend,
          DateTime(2026, 9, 26),
          SessionTrack.common,
        ),
      ];

      final numbers = assignSequenceNumbers(events);

      expect(numbers['w1'], 1);
      expect(numbers['w2'], 2);
    });
  });
}
