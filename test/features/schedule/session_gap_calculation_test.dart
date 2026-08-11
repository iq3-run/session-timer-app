import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/schedule/session_gap_calculation.dart';

void main() {
  group('calculateGap', () {
    // 2026-08-07/21 and 2026-09-05 are real Fri/Fri/Sat dates — verified
    // against the actual calendar, not assumed.
    test('1WE (ends 8/23) to 1WD (starts 9/5): 12 days, 2 weeks', () {
      final result = calculateGap(
        fromEnd: DateTime(2026, 8, 23),
        toStart: DateTime(2026, 9, 5),
      );

      expect(result.days, 12);
      expect(result.weeks, 2);
    });

    test('OR (8/7) to 1WE (starts 8/21): 13 days, 2 weeks '
        '(landing on Friday adds the extra week)', () {
      final result = calculateGap(
        fromEnd: DateTime(2026, 8, 7),
        toStart: DateTime(2026, 8, 21),
      );

      expect(result.days, 13);
      expect(result.weeks, 2);
    });

    test('today (8/11) to 1WE (starts 8/21): 9 days, 2 weeks', () {
      final result = calculateGap(
        fromEnd: DateTime(2026, 8, 11),
        toStart: DateTime(2026, 8, 21),
      );

      expect(result.days, 9);
      expect(result.weeks, 2);
    });

    test('adjacent days (no gap): 0 days, 0 weeks', () {
      final result = calculateGap(
        fromEnd: DateTime(2026, 8, 10),
        toStart: DateTime(2026, 8, 11),
      );

      expect(result.days, 0);
      expect(result.weeks, 0);
    });

    test('landing on a non-Friday with no Friday in between: 0 weeks', () {
      // 8/10 (Mon) -> 8/12 (Wed): the single day in between (8/11, Tue)
      // isn't a Friday, and the landing day isn't either.
      final result = calculateGap(
        fromEnd: DateTime(2026, 8, 10),
        toStart: DateTime(2026, 8, 12),
      );

      expect(result.days, 1);
      expect(result.weeks, 0);
    });

    test('landing exactly on a Friday with nothing else in between adds '
        'the bonus week', () {
      // 8/13 (Thu) -> 8/14 (Fri): 0 days between, but the landing day
      // itself is a Friday.
      final result = calculateGap(
        fromEnd: DateTime(2026, 8, 13),
        toStart: DateTime(2026, 8, 14),
      );

      expect(result.days, 0);
      expect(result.weeks, 1);
    });
  });
}
