import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/schedule/session_event.dart';
import 'package:session_timer/features/schedule/session_schedule_form_helpers.dart';

SessionEvent _event(SessionEventType type, {String id = 'e'}) =>
    SessionEvent(id: id, type: type, date: DateTime(2026, 11, 27));

void main() {
  group('isValidManualNumberText / parseManualNumberText', () {
    test('empty and blank text mean "auto" and are valid', () {
      expect(isValidManualNumberText(''), isTrue);
      expect(isValidManualNumberText('   '), isTrue);
      expect(parseManualNumberText(''), isNull);
      expect(parseManualNumberText('   '), isNull);
    });

    test('a positive integer is valid, ignoring surrounding spaces', () {
      expect(isValidManualNumberText('7'), isTrue);
      expect(isValidManualNumberText(' 7 '), isTrue);
      expect(parseManualNumberText(' 7 '), 7);
    });

    test('zero, negatives and non-numbers are invalid', () {
      for (final text in ['0', '-1', 'abc', '1.5']) {
        expect(isValidManualNumberText(text), isFalse, reason: text);
      }
    });
  });

  group('clampToScheduleRange', () {
    test('keeps a date inside the range', () {
      final date = DateTime(2026, 11, 27);
      expect(clampToScheduleRange(date), date);
    });

    test('keeps the boundary dates themselves', () {
      expect(clampToScheduleRange(earliestScheduleDate), earliestScheduleDate);
      expect(clampToScheduleRange(latestScheduleDate), latestScheduleDate);
    });

    test('pulls an out-of-range date to the nearest bound', () {
      expect(
        clampToScheduleRange(DateTime(1999, 12, 31)),
        earliestScheduleDate,
      );
      expect(clampToScheduleRange(DateTime(2100, 1, 2)), latestScheduleDate);
    });
  });

  group('hasVisibilityToggle', () {
    test('completion and classroom events never get one', () {
      expect(
        hasVisibilityToggle(_event(SessionEventType.completion), {}),
        isFalse,
      );
      expect(
        hasVisibilityToggle(_event(SessionEventType.classroom), {}),
        isFalse,
      );
    });

    test('only the first weekend is always shown', () {
      final first = _event(SessionEventType.weekend, id: 'w1');
      final second = _event(SessionEventType.weekend, id: 'w2');
      final numbers = {'w1': 1, 'w2': 2};

      expect(hasVisibilityToggle(first, numbers), isFalse);
      expect(hasVisibilityToggle(second, numbers), isTrue);
    });

    test('other types get one', () {
      for (final type in [
        SessionEventType.orientation,
        SessionEventType.workday,
        SessionEventType.specialSession,
      ]) {
        expect(hasVisibilityToggle(_event(type), {}), isTrue, reason: '$type');
      }
    });
  });
}
