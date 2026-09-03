import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/session_plan/session_plan_entry.dart';

void main() {
  group('SessionPlanEntry', () {
    test('toJson/tryFromJson round-trips a normal entry', () {
      const entry = SessionPlanEntry(
        id: 's1',
        startEpochMs: 1700000000000,
        endEpochMs: 1700010000000,
      );

      final restored = SessionPlanEntry.tryFromJson(entry.toJson());

      expect(restored?.id, 's1');
      expect(restored?.startEpochMs, 1700000000000);
      expect(restored?.endEpochMs, 1700010000000);
    });

    test('tryFromJson rejects a non-String id', () {
      final restored = SessionPlanEntry.tryFromJson({
        'id': 42,
        'startEpochMs': 0,
        'endEpochMs': 1000,
      });

      expect(restored, isNull);
    });

    test('tryFromJson rejects a non-int startEpochMs', () {
      final restored = SessionPlanEntry.tryFromJson({
        'id': 's1',
        'startEpochMs': 'not-a-number',
        'endEpochMs': 1000,
      });

      expect(restored, isNull);
    });

    test('tryFromJson rejects a non-int endEpochMs', () {
      final restored = SessionPlanEntry.tryFromJson({
        'id': 's1',
        'startEpochMs': 0,
        'endEpochMs': 'not-a-number',
      });

      expect(restored, isNull);
    });

    test('tryFromJson rejects an endEpochMs at or before startEpochMs', () {
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

    test('tryFromJson rejects an out-of-range epoch', () {
      const outOfRangeEpochMs = 9000000000000000;
      final restored = SessionPlanEntry.tryFromJson({
        'id': 's1',
        'startEpochMs': 0,
        'endEpochMs': outOfRangeEpochMs,
      });

      expect(restored, isNull);
    });
  });
}
