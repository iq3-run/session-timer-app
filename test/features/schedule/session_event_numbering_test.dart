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
}
