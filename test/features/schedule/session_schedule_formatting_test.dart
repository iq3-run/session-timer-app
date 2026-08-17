import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/schedule/session_gap_calculation.dart';
import 'package:session_timer/features/schedule/session_schedule_formatting.dart';

void main() {
  group('formatScheduleDate', () {
    test('formats as M/D(曜)', () {
      expect(formatScheduleDate(DateTime(2026, 8, 17)), '8/17(月)');
    });

    test('uses the correct weekday label for every day of the week', () {
      // 2026-08-17 is a Monday; each label below is one day further.
      const labels = ['月', '火', '水', '木', '金', '土', '日'];
      for (var i = 0; i < labels.length; i++) {
        final date = DateTime(2026, 8, 17 + i);
        expect(formatScheduleDate(date), endsWith('(${labels[i]})'));
      }
    });

    test('does not zero-pad single-digit month/day', () {
      expect(formatScheduleDate(DateTime(2026, 1, 2)), '1/2(金)');
    });
  });

  group('formatGap', () {
    test('returns an empty string for null', () {
      expect(formatGap(null), '');
    });

    test('formats as Nd(MW)', () {
      expect(formatGap(const GapResult(days: 3, weeks: 1)), '3日(1W)');
    });

    test('formats zero days and zero weeks (not treated as absent)', () {
      expect(formatGap(const GapResult(days: 0, weeks: 0)), '0日(0W)');
    });

    test('formats multi-digit days and weeks', () {
      expect(formatGap(const GapResult(days: 12, weeks: 2)), '12日(2W)');
    });
  });
}
