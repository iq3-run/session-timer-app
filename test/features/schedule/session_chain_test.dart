import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/schedule/session_chain.dart';
import 'package:session_timer/features/schedule/session_event.dart';
import 'package:session_timer/features/schedule/session_event_numbering.dart';
import 'package:session_timer/features/schedule/session_gap_calculation.dart';

SessionEvent _event(
  String id,
  SessionEventType type,
  DateTime date, {
  bool visible = true,
  int? manualNumber,
  SessionTrack track = SessionTrack.common,
}) => SessionEvent(
  id: id,
  type: type,
  date: date,
  visible: visible,
  manualNumber: manualNumber,
  track: track,
);

/// OR(8/7) -> 1WE(8/21, 3日間) -> 1WD(9/5) -> 2WE(9/26, 2日間) -> 2WD(11/1).
List<SessionEvent> _confirmedChain() => [
  _event('or', SessionEventType.orientation, DateTime(2026, 8, 7)),
  _event('we1', SessionEventType.weekend, DateTime(2026, 8, 21)),
  _event('wd1', SessionEventType.workday, DateTime(2026, 9, 5)),
  _event('we2', SessionEventType.weekend, DateTime(2026, 9, 26)),
  _event('wd2', SessionEventType.workday, DateTime(2026, 11)),
];

typedef GapResultView = ({int days, int weeks});

GapResultView? _gapView(GapResult? gap) =>
    gap == null ? null : (days: gap.days, weeks: gap.weeks);

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

    test('CS gets a today-gap like every other row', () {
      final events = [
        ..._confirmedChain(),
        _event('cs', SessionEventType.completion, DateTime(2027)),
      ];

      final rows = buildScheduleRows(events, DateTime(2026, 9, 14));

      expect(_rowFor(rows, 'cs').todayGap, isNotNull);
    });

    test('every chain row gets a today-gap, past and future alike', () {
      // 2026-09-14 is a Monday, between wd1 (9/5) and we2 (9/26): every
      // row — not just the nearest on each side — has a value.
      final rows = buildScheduleRows(_confirmedChain(), DateTime(2026, 9, 14));

      // Past rows count from the event's last day to today.
      expect(_rowFor(rows, 'or').todayGap?.days, 37); // 8/8..9/13
      expect(_rowFor(rows, 'or').todayGap?.weeks, 5);
      expect(_rowFor(rows, 'we1').todayGap?.days, 21); // ends 8/23
      expect(_rowFor(rows, 'we1').todayGap?.weeks, 3);
      expect(_rowFor(rows, 'wd1').todayGap?.days, 8);
      expect(_rowFor(rows, 'wd1').todayGap?.weeks, 1);
      // Future rows count from today to the event's first day.
      expect(_rowFor(rows, 'we2').todayGap?.days, 11);
      expect(_rowFor(rows, 'we2').todayGap?.weeks, 2);
      expect(_rowFor(rows, 'wd2').todayGap?.days, 47);
      expect(_rowFor(rows, 'wd2').todayGap?.weeks, 7);
    });

    test('a finished CS counts days since it, not a negative gap', () {
      final events = [
        ..._confirmedChain(),
        _event('cs', SessionEventType.completion, DateTime(2026, 9)),
      ];

      final rows = buildScheduleRows(events, DateTime(2026, 9, 14));

      expect(_rowFor(rows, 'cs').todayGap?.days, 12); // 9/2..9/13
      expect(_rowFor(rows, 'cs').todayGap?.weeks, 2);
    });

    test('the synthetic 今日 row has no today-gap', () {
      final rows = buildScheduleRows(_confirmedChain(), DateTime(2026, 9, 14));

      expect(rows.singleWhere((r) => r.event == null).todayGap, isNull);
    });

    group('today-gap at the day boundaries (today = Mon 2026-09-14)', () {
      final today = DateTime(2026, 9, 14);

      GapResultView? gapOf(SessionEvent event) => _gapView(
        _rowFor(buildScheduleRows([event], today), event.id).todayGap,
      );

      test('an event that ended yesterday is 0 days away', () {
        final event = _event(
          'e',
          SessionEventType.workday,
          DateTime(2026, 9, 13),
        );

        expect(gapOf(event), (days: 0, weeks: 0));
      });

      test('an event starting tomorrow is 0 days away', () {
        final event = _event(
          'e',
          SessionEventType.workday,
          DateTime(2026, 9, 15),
        );

        expect(gapOf(event), (days: 0, weeks: 0));
      });

      test('a single-day event on today has no gap (it is today)', () {
        final event = _event('e', SessionEventType.workday, today);

        expect(gapOf(event), isNull);
      });

      test('a CS on today has no gap, rather than the old -1 days', () {
        final event = _event('e', SessionEventType.completion, today);

        expect(gapOf(event), isNull);
      });

      test('a multi-day event on its last day has no gap', () {
        // 1WE runs 3 days: 9/12 (Sat) through 9/14.
        final event = _event(
          'e',
          SessionEventType.weekend,
          DateTime(2026, 9, 12),
        );

        expect(gapOf(event), isNull);
      });

      test('a multi-day event that ended yesterday is 0 days away', () {
        // 1WE runs 3 days: 9/11 (Fri) through 9/13.
        final event = _event(
          'e',
          SessionEventType.weekend,
          DateTime(2026, 9, 11),
        );

        expect(gapOf(event), (days: 0, weeks: 0));
      });
    });

    test('every row shown has a today-gap except the ongoing/今日 ones', () {
      final events = [
        ..._confirmedChain(),
        _event('cr-next', SessionEventType.classroom, DateTime(2026, 9, 18)),
        _event('cs', SessionEventType.completion, DateTime(2027)),
      ];

      final rows = buildScheduleRows(events, DateTime(2026, 9, 14));

      expect(
        rows.where((r) => r.todayGap == null).map((r) => r.label),
        ['今日'],
      );
    });

    test('hidden rows do not change the today-gap of the rows still shown', () {
      final hidden = [
        for (final e in _confirmedChain())
          if (e.id == 'we2' || e.id == 'wd2')
            _event(e.id, e.type, e.date, visible: false)
          else
            e,
      ];

      final rows = buildScheduleRows(hidden, DateTime(2026, 9, 14));
      final baseline = buildScheduleRows(
        _confirmedChain(),
        DateTime(2026, 9, 14),
      );

      expect(rows.where((r) => r.event?.id == 'we2'), isEmpty);
      expect(
        _rowFor(rows, 'wd1').todayGap?.days,
        _rowFor(baseline, 'wd1').todayGap?.days,
      );
    });

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
      'and leaves its today-gap blank (measuring against its '
      'not-yet-reached end date would produce a negative gap)',
      () {
        // we1 spans 8/21 (Fri) through 8/23 (Sun); 8/22 is its middle day.
        final rows = buildScheduleRows(
          _confirmedChain(),
          DateTime(2026, 8, 22),
        );

        expect(_rowFor(rows, 'we1').isToday, isTrue);
        expect(_rowFor(rows, 'we1').todayGap, isNull);
        expect(rows.where((r) => r.event == null), isEmpty);
        // we1 being "ongoing" only blanks its own cell: the rows before and
        // after it still get theirs.
        expect(_rowFor(rows, 'or').todayGap, isNotNull);
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
          if (e.id == 'wd1')
            _event('wd1', SessionEventType.workday, e.date, visible: false)
          else
            e,
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
            if (e.id == 'wd1')
              _event(
                'wd1',
                SessionEventType.workday,
                e.date,
                visible: false,
              )
            else
              e,
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
          if (e.id == 'we1')
            _event('we1', SessionEventType.weekend, e.date, visible: false)
          else
            e,
      ];

      final rows = buildScheduleRows(hidden, DateTime(2026));

      expect(rows.where((r) => r.event?.id == 'we1'), isNotEmpty);
    });

    test('a later WE (not the first) is dropped when hidden', () {
      final hidden = [
        for (final e in _confirmedChain())
          if (e.id == 'we2')
            _event('we2', SessionEventType.weekend, e.date, visible: false)
          else
            e,
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
          if (e.id == 'we2')
            _event(
              'we2',
              SessionEventType.weekend,
              e.date,
              manualNumber: 9,
            )
          else
            e,
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
            if (e.id == 'we1')
              _event(
                'we1',
                SessionEventType.weekend,
                e.date,
                visible: false,
                manualNumber: 99,
              )
            else
              e,
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
            if (e.id == 'we1')
              _event(
                'we1',
                SessionEventType.weekend,
                e.date,
                manualNumber: 42,
              )
            else
              e,
        ];
        final numbers = assignSequenceNumbers(events);

        expect(sessionEventLabel(events[3], numbers), '2WE'); // we2 unaffected
      },
    );
  });

  group('buildScheduleRows with A/B schedules', () {
    /// OR(8/7) -> 1WE(A, 8/21) / 1WE(B, 8/28) -> 1WD(A, 9/5) / 1WD(B, 9/12)
    /// -> 2WE (9/26, merged).
    List<SessionEvent> branched() => [
      _event('or', SessionEventType.orientation, DateTime(2026, 8, 7)),
      _event(
        'weA',
        SessionEventType.weekend,
        DateTime(2026, 8, 21),
        track: SessionTrack.a,
      ),
      _event(
        'weB',
        SessionEventType.weekend,
        DateTime(2026, 8, 28),
        track: SessionTrack.b,
      ),
      _event(
        'wdA',
        SessionEventType.workday,
        DateTime(2026, 9, 5),
        track: SessionTrack.a,
      ),
      _event(
        'wdB',
        SessionEventType.workday,
        DateTime(2026, 9, 12),
        track: SessionTrack.b,
      ),
      _event('we2', SessionEventType.weekend, DateTime(2026, 9, 26)),
    ];

    // Far before everything, so the 今日から column stays out of the way.
    final farBefore = DateTime(2026);

    test('labels carry the schedule and both 1WE are numbered 1', () {
      final rows = buildScheduleRows(branched(), farBefore);

      expect(_rowFor(rows, 'weA').label, '1WE(A)');
      expect(_rowFor(rows, 'weB').label, '1WE(B)');
      expect(_rowFor(rows, 'wdA').label, '1WD(A)');
      expect(_rowFor(rows, 'wdB').label, '1WD(B)');
      expect(_rowFor(rows, 'we2').label, '2WE');
    });

    test('rows stay in date order, A and B interleaved', () {
      final rows = buildScheduleRows(branched(), farBefore);

      expect(
        rows.map((r) => r.event?.id).whereType<String>().toList(),
        ['or', 'weA', 'weB', 'wdA', 'wdB', 'we2'],
      );
    });

    test('each schedule measures 週末間 from its own previous event', () {
      final rows = buildScheduleRows(branched(), farBefore);

      // Both 1WE follow the OR, not each other.
      expect(_rowFor(rows, 'weA').chainGap?.days, 13);
      expect(_rowFor(rows, 'weB').chainGap?.days, 20);
      expect(_rowFor(rows, 'weB').chainGap?.weeks, 3);
      // 1WD(A) follows 1WE(A) (ends 8/23), 1WD(B) follows 1WE(B) (ends 8/30)
      // — not whichever event happens to sit before it in date order.
      expect(_rowFor(rows, 'wdA').chainGap?.days, 12);
      expect(_rowFor(rows, 'wdB').chainGap?.days, 12);
    });

    test(
      'both 1WE last 3 days, the first-weekend rule applying per schedule',
      () {
        final rows = buildScheduleRows(branched(), DateTime(2026, 8, 30));

        // 8/30 is the third day of 1WE(B) (8/28-8/30), so that row is today.
        expect(_rowFor(rows, 'weB').isToday, isTrue);
        expect(_rowFor(rows, 'weA').isToday, isFalse);
      },
    );

    test('the merge row shows one 週末間 per schedule', () {
      final rows = buildScheduleRows(branched(), farBefore);
      final merged = _rowFor(rows, 'we2');

      expect(merged.chainGap, isNull);
      expect(merged.trackChainGaps.map((g) => g.track), [
        SessionTrack.a,
        SessionTrack.b,
      ]);
      expect(merged.trackChainGaps[0].gap.days, 20); // from 1WD(A), 9/5
      expect(merged.trackChainGaps[0].gap.weeks, 3);
      expect(merged.trackChainGaps[1].gap.days, 13); // from 1WD(B), 9/12
      expect(merged.trackChainGaps[1].gap.weeks, 2);
    });

    test('only the merge row has per-schedule gaps', () {
      final rows = buildScheduleRows(branched(), farBefore);

      for (final id in ['or', 'weA', 'weB', 'wdA', 'wdB']) {
        expect(_rowFor(rows, id).trackChainGaps, isEmpty, reason: id);
      }
    });

    test('events after the merge are a single chain again', () {
      final events = [
        ...branched(),
        _event('wd2', SessionEventType.workday, DateTime(2026, 11)),
      ];

      final rows = buildScheduleRows(events, farBefore);

      expect(_rowFor(rows, 'wd2').trackChainGaps, isEmpty);
      expect(_rowFor(rows, 'wd2').chainGap?.days, 34); // from 2WE (ends 9/27)
    });

    test('with only one schedule in use the chain is a single sequence', () {
      final onlyA = [
        _event('or', SessionEventType.orientation, DateTime(2026, 8, 7)),
        _event(
          'weA',
          SessionEventType.weekend,
          DateTime(2026, 8, 21),
          track: SessionTrack.a,
        ),
        _event(
          'wdA',
          SessionEventType.workday,
          DateTime(2026, 9, 5),
          track: SessionTrack.a,
        ),
        _event('we2', SessionEventType.weekend, DateTime(2026, 9, 26)),
      ];

      final rows = buildScheduleRows(onlyA, farBefore);

      expect(_rowFor(rows, 'we2').trackChainGaps, isEmpty);
      expect(_rowFor(rows, 'we2').chainGap?.days, 20); // from 1WD(A)
    });

    test('without any A/B events nothing changes', () {
      final rows = buildScheduleRows(_confirmedChain(), farBefore);

      for (final row in rows) {
        expect(row.trackChainGaps, isEmpty);
      }
      expect(_rowFor(rows, 'we2').chainGap?.days, 20);
    });

    test(
      'a merge row whose schedules share a previous event shows one value',
      () {
        // A and B events exist, but both schedules' last event before the
        // common one is the same common event.
        final events = [
          _event('or', SessionEventType.orientation, DateTime(2026, 8, 7)),
          _event('common', SessionEventType.weekend, DateTime(2026, 8, 14)),
          _event(
            'weA',
            SessionEventType.weekend,
            DateTime(2026, 9, 5),
            track: SessionTrack.a,
          ),
          _event(
            'weB',
            SessionEventType.weekend,
            DateTime(2026, 9, 12),
            track: SessionTrack.b,
          ),
        ];

        final rows = buildScheduleRows(events, farBefore);

        expect(_rowFor(rows, 'weA').chainGap?.days, isNotNull);
        expect(_rowFor(rows, 'weB').chainGap?.days, isNotNull);
        expect(_rowFor(rows, 'common').trackChainGaps, isEmpty);
      },
    );

    test('the 今日から value does not depend on the schedule', () {
      final rows = buildScheduleRows(branched(), DateTime(2026, 9, 14));

      // Every row has its own today-gap, A and B alike.
      expect(_rowFor(rows, 'weA').todayGap, isNotNull);
      expect(_rowFor(rows, 'weB').todayGap, isNotNull);
      expect(_rowFor(rows, 'we2').todayGap, isNotNull);
    });
  });
}
