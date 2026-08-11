import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/schedule/session_chain.dart';
import 'package:session_timer/features/schedule/session_event.dart';

SessionEvent _event(String id, SessionEventType type, DateTime date) =>
    SessionEvent(id: id, type: type, date: date);

/// OR(8/7) -> 1WE(8/21, 3日間) -> 1WD(9/5) -> 2WE(9/26, 2日間) -> 2WD(11/1).
List<SessionEvent> _confirmedChain() => [
  _event('or', SessionEventType.orientation, DateTime(2026, 8, 7)),
  _event('we1', SessionEventType.weekend, DateTime(2026, 8, 21)),
  _event('wd1', SessionEventType.workday, DateTime(2026, 9, 5)),
  _event('we2', SessionEventType.weekend, DateTime(2026, 9, 26)),
  _event('wd2', SessionEventType.workday, DateTime(2026, 11)),
];

ScheduleRow _rowFor(List<ScheduleRow> rows, String id) =>
    rows.firstWhere((r) => r.event?.id == id);

void main() {
  group('buildScheduleRows', () {
    test('chain gaps follow the confirmed OR→1WE→1WD→2WE→2WD sequence', () {
      // Today is set far before everything so this test stays focused on
      // chainGap, without also triggering any today-gap.
      final rows = buildScheduleRows(_confirmedChain(), DateTime(2026));

      expect(_rowFor(rows, 'or').chainGap, isNull);
      expect(_rowFor(rows, 'we1').chainGap?.days, 13);
      expect(_rowFor(rows, 'we1').chainGap?.weeks, 2);
      expect(_rowFor(rows, 'wd1').chainGap?.days, 12);
      expect(_rowFor(rows, 'wd1').chainGap?.weeks, 2);
      expect(_rowFor(rows, 'we2').chainGap?.days, 20);
      expect(_rowFor(rows, 'we2').chainGap?.weeks, 3);
      expect(_rowFor(rows, 'wd2').chainGap?.days, 34);
      expect(_rowFor(rows, 'wd2').chainGap?.weeks, 5);
    });

    test('CS always gets a today-gap even though it is not WE/WD/SS', () {
      final events = [
        ..._confirmedChain(),
        _event('cs', SessionEventType.completion, DateTime(2027)),
      ];

      final rows = buildScheduleRows(events, DateTime(2026, 9, 14));

      expect(_rowFor(rows, 'cs').todayGap, isNotNull);
    });

    test(
      'only the nearest past and nearest future WE/WD/SS get a today-gap',
      () {
        final rows = buildScheduleRows(
          _confirmedChain(),
          DateTime(2026, 9, 14),
        );

        // 9/14 sits between wd1 (9/5, nearest past) and we2 (9/26, nearest
        // future) — we1 (further past) and wd2 (further future) must stay
        // blank.
        expect(_rowFor(rows, 'wd1').todayGap, isNotNull);
        expect(_rowFor(rows, 'we2').todayGap, isNotNull);
        expect(_rowFor(rows, 'we1').todayGap, isNull);
        expect(_rowFor(rows, 'wd2').todayGap, isNull);
      },
    );

    test('today not matching any event inserts a synthetic row in date '
        'order', () {
      final rows = buildScheduleRows(_confirmedChain(), DateTime(2026, 9, 14));

      final todayIndex = rows.indexWhere((r) => r.event == null);
      expect(todayIndex, isNot(-1));
      expect(rows[todayIndex].isToday, isTrue);
      expect(rows[todayIndex].date, DateTime(2026, 9, 14));
      // Sorted between wd1 (9/5) and we2 (9/26).
      expect(rows[todayIndex - 1].event?.id, 'wd1');
      expect(rows[todayIndex + 1].event?.id, 'we2');
    });

    test('today matching an event highlights that row instead of '
        'inserting a synthetic one', () {
      final rows = buildScheduleRows(_confirmedChain(), DateTime(2026, 9, 5));

      expect(rows.where((r) => r.event == null), isEmpty);
      expect(_rowFor(rows, 'wd1').isToday, isTrue);
    });

    test(
      'shows today-CR and next-CR rows only, excluding other CR entries',
      () {
        final events = [
          ..._confirmedChain(),
          _event('cr-past', SessionEventType.classroom, DateTime(2026, 8, 15)),
          _event('cr-today', SessionEventType.classroom, DateTime(2026, 9, 11)),
          _event('cr-next', SessionEventType.classroom, DateTime(2026, 9, 18)),
          _event('cr-later', SessionEventType.classroom, DateTime(2026, 10, 2)),
        ];

        final rows = buildScheduleRows(events, DateTime(2026, 9, 11));

        expect(rows.where((r) => r.event?.id == 'cr-past'), isEmpty);
        expect(rows.where((r) => r.event?.id == 'cr-later'), isEmpty);
        expect(_rowFor(rows, 'cr-today').isToday, isTrue);
        expect(_rowFor(rows, 'cr-today').label, 'CR');
        expect(_rowFor(rows, 'cr-next').label, '次回CR');
        expect(_rowFor(rows, 'cr-next').todayGap, isNotNull);
      },
    );

    test('CR events never receive a chain gap', () {
      final events = [
        ..._confirmedChain(),
        _event('cr', SessionEventType.classroom, DateTime(2026, 9, 18)),
      ];

      final rows = buildScheduleRows(events, DateTime(2026, 9));

      expect(_rowFor(rows, 'cr').chainGap, isNull);
    });
  });
}
