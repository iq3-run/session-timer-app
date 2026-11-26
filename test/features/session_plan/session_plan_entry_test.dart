import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/session_plan/session_plan_entry.dart';

void main() {
  group('SessionPlanEntry', () {
    test('toJson/tryFromJson round-trips a normal entry', () {
      const entry = SessionPlanEntry(
        id: 's1',
        startMinutes: 9 * 60 + 30,
        durationMinutes: 210,
      );

      final restored = SessionPlanEntry.tryFromJson(entry.toJson());

      expect(restored?.id, 's1');
      expect(restored?.startMinutes, 570);
      expect(restored?.durationMinutes, 210);
    });

    test('toJson holds no date information', () {
      const entry = SessionPlanEntry(
        id: 's1',
        startMinutes: 540,
        durationMinutes: 60,
      );

      expect(entry.toJson().keys, ['id', 'startMinutes', 'durationMinutes']);
    });

    test('labels show start and end as H:mm, wrapping past midnight', () {
      const entry = SessionPlanEntry(
        id: 's1',
        startMinutes: 23 * 60,
        durationMinutes: 3 * 60 + 5,
      );

      expect(entry.startLabel, '23:00');
      expect(entry.endLabel, '2:05');
    });

    test('startOn/endOn place the session on the given calendar day', () {
      const entry = SessionPlanEntry(
        id: 's1',
        startMinutes: 23 * 60,
        durationMinutes: 180,
      );
      final day = DateTime(2026, 8, 8, 15, 42);

      expect(entry.startOn(day), DateTime(2026, 8, 8, 23));
      expect(entry.endOn(day), DateTime(2026, 8, 9, 2));
    });

    group('legacy (epoch) format', () {
      test('is converted to a time of day and duration', () {
        final start = DateTime(2026, 1, 5, 9, 30);
        final end = DateTime(2026, 1, 5, 13);

        final restored = SessionPlanEntry.tryFromJson({
          'id': 's1',
          'startEpochMs': start.millisecondsSinceEpoch,
          'endEpochMs': end.millisecondsSinceEpoch,
        });

        expect(restored?.startMinutes, 9 * 60 + 30);
        expect(restored?.durationMinutes, 210);
      });

      test('keeps the time of day of a session that crossed midnight', () {
        final start = DateTime(2026, 1, 5, 23);
        final end = DateTime(2026, 1, 6, 2);

        final restored = SessionPlanEntry.tryFromJson({
          'id': 's1',
          'startEpochMs': start.millisecondsSinceEpoch,
          'endEpochMs': end.millisecondsSinceEpoch,
        });

        expect(restored?.startMinutes, 23 * 60);
        expect(restored?.endMinutes, 2 * 60);
      });

      test('rejects an end at or before the start', () {
        final same = SessionPlanEntry.tryFromJson({
          'id': 's1',
          'startEpochMs': 1000,
          'endEpochMs': 1000,
        });
        final before = SessionPlanEntry.tryFromJson({
          'id': 's1',
          'startEpochMs': 1000,
          'endEpochMs': 500,
        });

        expect(same, isNull);
        expect(before, isNull);
      });

      test('clamps a session longer than a day instead of dropping it', () {
        final restored = SessionPlanEntry.tryFromJson({
          'id': 's1',
          'startEpochMs': DateTime(2026, 1, 5, 9).millisecondsSinceEpoch,
          'endEpochMs': DateTime(2026, 1, 6, 10).millisecondsSinceEpoch,
        });

        expect(restored?.startMinutes, 9 * 60);
        expect(restored?.durationMinutes, 1440);
      });

      test('rejects an out-of-range epoch', () {
        const outOfRangeEpochMs = 9000000000000000;
        final restored = SessionPlanEntry.tryFromJson({
          'id': 's1',
          'startEpochMs': 0,
          'endEpochMs': outOfRangeEpochMs,
        });

        expect(restored, isNull);
      });

      test('rejects non-int epochs', () {
        expect(
          SessionPlanEntry.tryFromJson({
            'id': 's1',
            'startEpochMs': 'not-a-number',
            'endEpochMs': 1000,
          }),
          isNull,
        );
        expect(
          SessionPlanEntry.tryFromJson({
            'id': 's1',
            'startEpochMs': 0,
            'endEpochMs': 'not-a-number',
          }),
          isNull,
        );
      });
    });

    test('tryFromJson rejects a non-String id', () {
      final restored = SessionPlanEntry.tryFromJson({
        'id': 42,
        'startMinutes': 540,
        'durationMinutes': 60,
      });

      expect(restored, isNull);
    });

    test('tryFromJson rejects non-int minutes', () {
      expect(
        SessionPlanEntry.tryFromJson({
          'id': 's1',
          'startMinutes': '9:00',
          'durationMinutes': 60,
        }),
        isNull,
      );
      expect(
        SessionPlanEntry.tryFromJson({
          'id': 's1',
          'startMinutes': 540,
          'durationMinutes': '60',
        }),
        isNull,
      );
    });

    test('tryFromJson rejects out-of-range minutes', () {
      for (final (start, duration) in [
        (-1, 60),
        (1440, 60),
        (540, 0),
        (540, -5),
        (540, 1441),
      ]) {
        expect(
          SessionPlanEntry.tryFromJson({
            'id': 's1',
            'startMinutes': start,
            'durationMinutes': duration,
          }),
          isNull,
          reason: 'start=$start duration=$duration',
        );
      }
    });

    test('tryFromJson accepts a full-day duration', () {
      final restored = SessionPlanEntry.tryFromJson({
        'id': 's1',
        'startMinutes': 0,
        'durationMinutes': 1440,
      });

      expect(restored?.durationMinutes, 1440);
    });
  });
}
