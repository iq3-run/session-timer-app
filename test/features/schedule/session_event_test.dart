import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/core/clock/epoch_bounds.dart';
import 'package:session_timer/features/schedule/session_event.dart';

void main() {
  group('SessionEvent', () {
    test('toJson/tryFromJson round-trips a normal event', () {
      final event = SessionEvent(
        id: 'we1',
        type: SessionEventType.weekend,
        date: DateTime(2026, 8, 21),
      );

      final restored = SessionEvent.tryFromJson(event.toJson());

      expect(restored?.id, 'we1');
      expect(restored?.type, SessionEventType.weekend);
      expect(restored?.date, DateTime(2026, 8, 21));
    });

    test('tryFromJson rejects a non-String id', () {
      final restored = SessionEvent.tryFromJson({
        'id': 42,
        'type': 'weekend',
        'epochMs': 0,
      });

      expect(restored, isNull);
    });

    test('tryFromJson rejects a non-String type', () {
      final restored = SessionEvent.tryFromJson({
        'id': 'we1',
        'type': 3,
        'epochMs': 0,
      });

      expect(restored, isNull);
    });

    test('tryFromJson rejects an unrecognized type name', () {
      final restored = SessionEvent.tryFromJson({
        'id': 'we1',
        'type': 'holiday',
        'epochMs': 0,
      });

      expect(restored, isNull);
    });

    test('tryFromJson rejects a non-int epochMs', () {
      final restored = SessionEvent.tryFromJson({
        'id': 'we1',
        'type': 'weekend',
        'epochMs': 'not-a-number',
      });

      expect(restored, isNull);
    });

    test("tryFromJson rejects an epochMs beyond DateTime's valid range", () {
      final restored = SessionEvent.tryFromJson({
        'id': 'we1',
        'type': 'weekend',
        'epochMs': maxEpochMs + 1,
      });

      expect(restored, isNull);
    });

    test('durationDays is 1 for every type except WE', () {
      for (final type in SessionEventType.values) {
        if (type == SessionEventType.weekend) continue;
        final event = SessionEvent(
          id: 'x',
          type: type,
          date: DateTime(2026),
        );

        expect(event.durationDays(isFirstWeekend: false), 1);
      }
    });

    test('durationDays is 3 for the first WE, 2 for later ones', () {
      final event = SessionEvent(
        id: 'we',
        type: SessionEventType.weekend,
        date: DateTime(2026, 8, 21),
      );

      expect(event.durationDays(isFirstWeekend: true), 3);
      expect(event.durationDays(isFirstWeekend: false), 2);
    });

    test('endDate adds durationDays - 1, staying on the calendar date', () {
      final event = SessionEvent(
        id: 'we',
        type: SessionEventType.weekend,
        date: DateTime(2026, 8, 21),
      );

      expect(event.endDate(isFirstWeekend: true), DateTime(2026, 8, 23));
      expect(event.endDate(isFirstWeekend: false), DateTime(2026, 8, 22));
    });

    test('endDate rolls over a month boundary correctly', () {
      final event = SessionEvent(
        id: 'we',
        type: SessionEventType.weekend,
        date: DateTime(2026, 8, 30),
      );

      expect(event.endDate(isFirstWeekend: true), DateTime(2026, 9));
    });

    test('visible defaults to true', () {
      final event = SessionEvent(
        id: 'we',
        type: SessionEventType.weekend,
        date: DateTime(2026, 8, 21),
      );

      expect(event.visible, isTrue);
    });

    test('toJson omits visible when true, includes it when false', () {
      final visible = SessionEvent(
        id: 'we',
        type: SessionEventType.weekend,
        date: DateTime(2026, 8, 21),
      );
      final hidden = SessionEvent(
        id: 'wd',
        type: SessionEventType.workday,
        date: DateTime(2026, 8, 21),
        visible: false,
      );

      expect(visible.toJson().containsKey('visible'), isFalse);
      expect(hidden.toJson()['visible'], false);
    });

    test('tryFromJson round-trips visible:false', () {
      final event = SessionEvent(
        id: 'wd',
        type: SessionEventType.workday,
        date: DateTime(2026, 8, 21),
        visible: false,
      );

      final restored = SessionEvent.tryFromJson(event.toJson());

      expect(restored?.visible, isFalse);
    });

    test(
      'tryFromJson defaults visible to true for older data without the '
      'field',
      () {
        final restored = SessionEvent.tryFromJson({
          'id': 'we1',
          'type': 'weekend',
          'epochMs': 0,
        });

        expect(restored?.visible, isTrue);
      },
    );

    test('tryFromJson rejects a non-bool visible', () {
      final restored = SessionEvent.tryFromJson({
        'id': 'we1',
        'type': 'weekend',
        'epochMs': 0,
        'visible': 'nope',
      });

      expect(restored, isNull);
    });

    test('tryFromJson rejects an explicit null visible, unlike a missing '
        'key', () {
      final restored = SessionEvent.tryFromJson({
        'id': 'we1',
        'type': 'weekend',
        'epochMs': 0,
        'visible': null,
      });

      expect(restored, isNull);
    });

    test('manualNumber defaults to null', () {
      final event = SessionEvent(
        id: 'we',
        type: SessionEventType.weekend,
        date: DateTime(2026, 8, 21),
      );

      expect(event.manualNumber, isNull);
    });

    test('toJson omits manualNumber when null, includes it when set', () {
      final auto = SessionEvent(
        id: 'we',
        type: SessionEventType.weekend,
        date: DateTime(2026, 8, 21),
      );
      final overridden = SessionEvent(
        id: 'we2',
        type: SessionEventType.weekend,
        date: DateTime(2026, 8, 21),
        manualNumber: 5,
      );

      expect(auto.toJson().containsKey('manualNumber'), isFalse);
      expect(overridden.toJson()['manualNumber'], 5);
    });

    test('tryFromJson round-trips a manualNumber', () {
      final event = SessionEvent(
        id: 'we',
        type: SessionEventType.weekend,
        date: DateTime(2026, 8, 21),
        manualNumber: 3,
      );

      final restored = SessionEvent.tryFromJson(event.toJson());

      expect(restored?.manualNumber, 3);
    });

    test(
      'tryFromJson defaults manualNumber to null for data without the '
      'field, and tolerates an explicit null (unlike visible)',
      () {
        final missing = SessionEvent.tryFromJson({
          'id': 'we1',
          'type': 'weekend',
          'epochMs': 0,
        });
        final explicitNull = SessionEvent.tryFromJson({
          'id': 'we1',
          'type': 'weekend',
          'epochMs': 0,
          'manualNumber': null,
        });

        expect(missing?.manualNumber, isNull);
        expect(explicitNull?.manualNumber, isNull);
      },
    );

    test('tryFromJson rejects a non-int manualNumber', () {
      final restored = SessionEvent.tryFromJson({
        'id': 'we1',
        'type': 'weekend',
        'epochMs': 0,
        'manualNumber': 'nope',
      });

      expect(restored, isNull);
    });

    test('tryFromJson rejects a manualNumber <= 0', () {
      final restored = SessionEvent.tryFromJson({
        'id': 'we1',
        'type': 'weekend',
        'epochMs': 0,
        'manualNumber': 0,
      });

      expect(restored, isNull);
    });
  });
}
