import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/timer/timer_state.dart';

void main() {
  group('TimerState', () {
    test('is not running when unset', () {
      const state = TimerState();

      expect(state.isRunning, isFalse);
      expect(state.targetTime, isNull);
    });

    test('isOverdueAt is false before the target and true at/after it', () {
      final target = DateTime(2026, 1, 1, 12);
      final state = TimerState(targetEpochMs: target.millisecondsSinceEpoch);

      expect(
        state.isOverdueAt(target.subtract(const Duration(seconds: 1))),
        isFalse,
      );
      expect(state.isOverdueAt(target), isTrue);
      expect(state.isOverdueAt(target.add(const Duration(seconds: 1))), isTrue);
    });

    test('remainingAt is positive before the target, negative after', () {
      final target = DateTime(2026, 1, 1, 12);
      final state = TimerState(targetEpochMs: target.millisecondsSinceEpoch);

      expect(
        state.remainingAt(target.subtract(const Duration(seconds: 30))),
        const Duration(seconds: 30),
      );
      expect(
        state.remainingAt(target.add(const Duration(seconds: 30))),
        const Duration(seconds: -30),
      );
    });

    test('toJson/tryFromJson round-trips an unset state', () {
      const state = TimerState(mode: TimerMode.linked);

      final restored = TimerState.tryFromJson(state.toJson());

      expect(restored?.targetEpochMs, isNull);
      expect(restored?.mode, TimerMode.linked);
    });

    test('toJson/tryFromJson round-trips a running state', () {
      const state = TimerState(targetEpochMs: 123456789);

      final restored = TimerState.tryFromJson(state.toJson());

      expect(restored?.targetEpochMs, 123456789);
      expect(restored?.mode, TimerMode.normal);
    });

    test('tryFromJson rejects a non-int targetEpochMs', () {
      final restored = TimerState.tryFromJson({
        'targetEpochMs': 'not-a-number',
        'mode': 'normal',
      });

      expect(restored, isNull);
    });

    test('tryFromJson rejects an unrecognized mode', () {
      final restored = TimerState.tryFromJson({'mode': 'turbo'});

      expect(restored, isNull);
    });

    test('tryFromJson rejects a missing mode', () {
      final restored = TimerState.tryFromJson({});

      expect(restored, isNull);
    });
  });
}
