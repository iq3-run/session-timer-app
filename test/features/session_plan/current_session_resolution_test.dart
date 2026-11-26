import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/session_plan/current_session_resolution.dart';
import 'package:session_timer/features/session_plan/session_plan_entry.dart';

SessionPlanEntry _entry(
  String id, {
  required int startHour,
  required int durationMinutes,
  int startMinute = 0,
}) => SessionPlanEntry(
  id: id,
  startMinutes: startHour * 60 + startMinute,
  durationMinutes: durationMinutes,
);

void main() {
  group('resolveCurrentSession', () {
    final now = DateTime(2026, 8, 8, 10);

    test('returns null for an empty list', () {
      expect(resolveCurrentSession(const [], now), isNull);
    });

    test(
      'a not-yet-started session becomes current, with its own start as '
      'the auto target',
      () {
        final session = _entry('s1', startHour: 11, durationMinutes: 180);

        final resolution = resolveCurrentSession([session], now);

        expect(resolution?.session.id, 's1');
        expect(resolution?.completionTarget, DateTime(2026, 8, 8, 14));
        expect(resolution?.autoTargetStart, DateTime(2026, 8, 8, 11));
      },
    );

    test(
      "an in-progress session becomes current, with the next session's "
      'start as the auto target',
      () {
        final current = _entry('am', startHour: 9, durationMinutes: 210);
        final next = _entry('pm', startHour: 13, durationMinutes: 210);

        final resolution = resolveCurrentSession([current, next], now);

        expect(resolution?.session.id, 'am');
        expect(resolution?.completionTarget, DateTime(2026, 8, 8, 12, 30));
        expect(resolution?.autoTargetStart, DateTime(2026, 8, 8, 13));
      },
    );

    test(
      'an in-progress session with no next session clears the auto target',
      () {
        final current = _entry('am', startHour: 9, durationMinutes: 210);

        final resolution = resolveCurrentSession([current], now);

        expect(resolution?.session.id, 'am');
        expect(resolution?.autoTargetStart, isNull);
      },
    );

    test(
      'picks the session ending soonest, not the one listed first',
      () {
        final endsSoon = _entry(
          'soon',
          startHour: 9,
          startMinute: 30,
          durationMinutes: 40,
        );
        final endsLater = _entry('later', startHour: 9, durationMinutes: 240);

        final resolution = resolveCurrentSession([endsLater, endsSoon], now);

        expect(resolution?.session.id, 'soon');
      },
    );

    test(
      'a session whose time of day already passed today is still applied, '
      'targeting its next occurrence (tomorrow)',
      () {
        // Regression for #94: sessions used to carry the date they were
        // registered on, so one whose stored date had passed read as
        // "already ended" and could not be applied at all.
        final morning = _entry('am', startHour: 6, durationMinutes: 120);
        final lateNow = DateTime(2026, 8, 8, 20);

        final resolution = resolveCurrentSession([morning], lateNow);

        expect(resolution?.session.id, 'am');
        expect(resolution?.completionTarget, DateTime(2026, 8, 9, 8));
        expect(resolution?.autoTargetStart, DateTime(2026, 8, 9, 6));
      },
    );

    test(
      'after the last session of the day, the first one tomorrow is next',
      () {
        final am = _entry('am', startHour: 9, durationMinutes: 180);
        final pm = _entry('pm', startHour: 13, durationMinutes: 180);
        final evening = DateTime(2026, 8, 8, 20);

        final resolution = resolveCurrentSession([pm, am], evening);

        expect(resolution?.session.id, 'am');
        expect(resolution?.completionTarget, DateTime(2026, 8, 9, 12));
        expect(resolution?.autoTargetStart, DateTime(2026, 8, 9, 9));
      },
    );

    test(
      'a session running past midnight is current after midnight, ending '
      'later that same day',
      () {
        final night = _entry('night', startHour: 23, durationMinutes: 180);
        final afterMidnight = DateTime(2026, 8, 9, 1);

        final resolution = resolveCurrentSession([night], afterMidnight);

        expect(resolution?.session.id, 'night');
        expect(resolution?.completionTarget, DateTime(2026, 8, 9, 2));
        // Started yesterday, and it is the last session: nothing next.
        expect(resolution?.autoTargetStart, isNull);
      },
    );

    test(
      'a session running past midnight is upcoming before it starts, with '
      'its end on the following day',
      () {
        final night = _entry('night', startHour: 23, durationMinutes: 180);
        final evening = DateTime(2026, 8, 8, 21);

        final resolution = resolveCurrentSession([night], evening);

        expect(resolution?.completionTarget, DateTime(2026, 8, 9, 2));
        expect(resolution?.autoTargetStart, DateTime(2026, 8, 8, 23));
      },
    );

    test('a session ending exactly now is treated as ended', () {
      final ended = _entry('am', startHour: 8, durationMinutes: 120);
      final next = _entry('pm', startHour: 13, durationMinutes: 120);

      final resolution = resolveCurrentSession([ended, next], now);

      expect(resolution?.session.id, 'pm');
    });
  });

  group('resolveSessionOccurrence (manual apply, #94)', () {
    // 9:00〜12:00 on 2026-08-08.
    final morning = _entry('am', startHour: 9, durationMinutes: 180);

    test('before the start: applied as is, today', () {
      final occurrence = resolveSessionOccurrence(
        morning,
        DateTime(2026, 8, 8, 8),
      );

      expect(occurrence.start, DateTime(2026, 8, 8, 9));
      expect(occurrence.end, DateTime(2026, 8, 8, 12));
    });

    test('after the start but before the end: the start is in the past', () {
      final now = DateTime(2026, 8, 8, 10);

      final occurrence = resolveSessionOccurrence(morning, now);

      expect(occurrence.start, DateTime(2026, 8, 8, 9));
      expect(occurrence.start.isBefore(now), isTrue); // 残りがマイナス
      expect(occurrence.end, DateTime(2026, 8, 8, 12));
    });

    test('exactly at the start counts as started, still today', () {
      final occurrence = resolveSessionOccurrence(
        morning,
        DateTime(2026, 8, 8, 9),
      );

      expect(occurrence.start, DateTime(2026, 8, 8, 9));
      expect(occurrence.end, DateTime(2026, 8, 8, 12));
    });

    test('exactly at the end counts as ended: both move to tomorrow', () {
      final occurrence = resolveSessionOccurrence(
        morning,
        DateTime(2026, 8, 8, 12),
      );

      expect(occurrence.start, DateTime(2026, 8, 9, 9));
      expect(occurrence.end, DateTime(2026, 8, 9, 12));
    });

    test('after the end: both move to tomorrow', () {
      final occurrence = resolveSessionOccurrence(
        morning,
        DateTime(2026, 8, 8, 20),
      );

      expect(occurrence.start, DateTime(2026, 8, 9, 9));
      expect(occurrence.end, DateTime(2026, 8, 9, 12));
    });

    group('a session that runs past midnight (23:00〜2:00)', () {
      final night = _entry('night', startHour: 23, durationMinutes: 180);

      test(
        'in the evening, before it starts: today 23:00 to tomorrow 2:00',
        () {
          final occurrence = resolveSessionOccurrence(
            night,
            DateTime(2026, 8, 8, 21),
          );

          expect(occurrence.start, DateTime(2026, 8, 8, 23));
          expect(occurrence.end, DateTime(2026, 8, 9, 2));
        },
      );

      test('after midnight, in progress: it started yesterday', () {
        final occurrence = resolveSessionOccurrence(
          night,
          DateTime(2026, 8, 9, 1),
        );

        expect(occurrence.start, DateTime(2026, 8, 8, 23));
        expect(occurrence.end, DateTime(2026, 8, 9, 2));
      });

      test('once it ended (2:00), the next one is tonight', () {
        final occurrence = resolveSessionOccurrence(
          night,
          DateTime(2026, 8, 9, 2),
        );

        expect(occurrence.start, DateTime(2026, 8, 9, 23));
        expect(occurrence.end, DateTime(2026, 8, 10, 2));
      });
    });

    test('a full-day session in progress started yesterday', () {
      const allDay = SessionPlanEntry(
        id: 'all',
        startMinutes: 9 * 60,
        durationMinutes: 24 * 60,
      );

      final occurrence = resolveSessionOccurrence(
        allDay,
        DateTime(2026, 8, 8, 10),
      );

      expect(occurrence.start, DateTime(2026, 8, 8, 9));
      expect(occurrence.end, DateTime(2026, 8, 9, 9));
    });
  });
}
