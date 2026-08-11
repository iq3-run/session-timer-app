import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/schedule/session_chain.dart';
import 'package:session_timer/features/schedule/session_event.dart';
import 'package:session_timer/features/schedule/session_event_numbering.dart';

SessionEvent _event(
  String id,
  SessionEventType type,
  DateTime date, {
  bool visible = true,
  int? manualNumber,
}) => SessionEvent(
  id: id,
  type: type,
  date: date,
  visible: visible,
  manualNumber: manualNumber,
);

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

    test(
      "today falling on a WE's 2nd/3rd day still highlights that row, "
      "and doesn't count it as \"nearest past\" (which would produce a "
      'negative gap against its not-yet-reached end date)',
      () {
        // we1 spans 8/21 (Fri) through 8/23 (Sun); 8/22 is its middle day.
        final rows = buildScheduleRows(
          _confirmedChain(),
          DateTime(2026, 8, 22),
        );

        expect(_rowFor(rows, 'we1').isToday, isTrue);
        expect(_rowFor(rows, 'we1').todayGap, isNull);
        expect(rows.where((r) => r.event == null), isEmpty);
        // we1 being "ongoing" (not fully finished) must not block wd1
        // (9/5) from being picked up as the nearest *future* WE/WD/SS —
        // that pool is unaffected by this fix.
        expect(_rowFor(rows, 'wd1').todayGap, isNotNull);
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

    test('a hidden WD/SS-eligible event is dropped from the rows', () {
      final events = [
        ..._confirmedChain(), // wd1 is visible:true (the default)
      ];
      final hidden = [
        for (final e in events)
          e.id == 'wd1'
              ? _event('wd1', SessionEventType.workday, e.date, visible: false)
              : e,
      ];

      final rows = buildScheduleRows(hidden, DateTime(2026));

      expect(rows.where((r) => r.event?.id == 'wd1'), isEmpty);
    });

    test(
      "hiding an event does not change its neighbors' chain-gap values",
      () {
        final visibleRows = buildScheduleRows(
          _confirmedChain(),
          DateTime(2026),
        );
        final hidden = [
          for (final e in _confirmedChain())
            e.id == 'wd1'
                ? _event(
                    'wd1',
                    SessionEventType.workday,
                    e.date,
                    visible: false,
                  )
                : e,
        ];

        final hiddenRows = buildScheduleRows(hidden, DateTime(2026));

        // we2's gap is computed against wd1's end date regardless of
        // whether wd1's own row is drawn — hiding wd1 must not make we2's
        // gap silently jump to being measured against we1 instead.
        expect(
          _rowFor(hiddenRows, 'we2').chainGap?.days,
          _rowFor(visibleRows, 'we2').chainGap?.days,
        );
      },
    );

    test('the first WE stays visible even when explicitly hidden', () {
      final hidden = [
        for (final e in _confirmedChain())
          e.id == 'we1'
              ? _event('we1', SessionEventType.weekend, e.date, visible: false)
              : e,
      ];

      final rows = buildScheduleRows(hidden, DateTime(2026));

      expect(rows.where((r) => r.event?.id == 'we1'), isNotEmpty);
    });

    test('a later WE (not the first) is dropped when hidden', () {
      final hidden = [
        for (final e in _confirmedChain())
          e.id == 'we2'
              ? _event('we2', SessionEventType.weekend, e.date, visible: false)
              : e,
      ];

      final rows = buildScheduleRows(hidden, DateTime(2026));

      expect(rows.where((r) => r.event?.id == 'we2'), isEmpty);
    });

    test('CS stays visible even when explicitly hidden', () {
      final events = [
        ..._confirmedChain(),
        _event(
          'cs',
          SessionEventType.completion,
          DateTime(2027),
          visible: false,
        ),
      ];

      final rows = buildScheduleRows(events, DateTime(2026));

      expect(rows.where((r) => r.event?.id == 'cs'), isNotEmpty);
    });

    test('CR ignores visible:false — it is never subject to the toggle', () {
      final events = [
        ..._confirmedChain(),
        _event(
          'cr',
          SessionEventType.classroom,
          DateTime(2026, 9, 11),
          visible: false,
        ),
      ];

      final rows = buildScheduleRows(events, DateTime(2026, 9, 11));

      expect(_rowFor(rows, 'cr').isToday, isTrue);
    });
  });

  group('sessionEventLabel', () {
    test('uses the auto-assigned number when manualNumber is unset', () {
      final events = _confirmedChain();
      final numbers = assignSequenceNumbers(events);

      expect(sessionEventLabel(events[3], numbers), '2WE'); // we2, 2nd WE
    });

    test('prefers manualNumber over the auto-assigned number', () {
      final events = [
        for (final e in _confirmedChain())
          e.id == 'we2'
              ? _event(
                  'we2',
                  SessionEventType.weekend,
                  e.date,
                  manualNumber: 9,
                )
              : e,
      ];
      final numbers = assignSequenceNumbers(events);

      expect(sessionEventLabel(events[3], numbers), '9WE');
    });

    test(
      "a manualNumber on the first WE doesn't change its exemption from "
      'the visibility toggle or its 3-day duration — those still key off '
      'the real auto-assigned position, not the displayed label',
      () {
        final hidden = [
          for (final e in _confirmedChain())
            e.id == 'we1'
                ? _event(
                    'we1',
                    SessionEventType.weekend,
                    e.date,
                    visible: false,
                    manualNumber: 99,
                  )
                : e,
        ];

        final rows = buildScheduleRows(hidden, DateTime(2026));

        // Still shown (first-WE exemption unaffected by manualNumber) and
        // labeled with the override.
        expect(_rowFor(rows, 'we1').label, '99WE');
        // chainGap to we2 is unchanged from the un-overridden case (would
        // shift if isFirstWeekend's 3-day duration were affected).
        final baseline = buildScheduleRows(_confirmedChain(), DateTime(2026));
        expect(
          _rowFor(rows, 'we2').chainGap?.days,
          _rowFor(baseline, 'we2').chainGap?.days,
        );
      },
    );

    test(
      "a manualNumber doesn't change any other event's own auto-assigned "
      'number',
      () {
        final events = [
          for (final e in _confirmedChain())
            e.id == 'we1'
                ? _event(
                    'we1',
                    SessionEventType.weekend,
                    e.date,
                    manualNumber: 42,
                  )
                : e,
        ];
        final numbers = assignSequenceNumbers(events);

        expect(sessionEventLabel(events[3], numbers), '2WE'); // we2 unaffected
      },
    );
  });
}
