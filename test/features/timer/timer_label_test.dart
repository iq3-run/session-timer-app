import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/timer/timer_label.dart';
import 'package:session_timer/features/timer/timer_state.dart';

void main() {
  group('timerLabel', () {
    final now = DateTime(2026, 8, 8, 20);

    test('returns the plain label when unset', () {
      expect(timerLabel(null, now), 'タイマー');
      expect(timerLabel(const TimerState(), now), 'タイマー');
    });

    test('appends the end time while running (normal mode)', () {
      final target = now.add(const Duration(hours: 1, minutes: 45));
      final state = TimerState(targetEpochMs: target.millisecondsSinceEpoch);

      expect(timerLabel(state, now), 'タイマー(21:45まで)');
    });

    test('uses the linked-mode label while running (linked mode)', () {
      final target = now.add(const Duration(hours: 1, minutes: 45));
      final state = TimerState(
        targetEpochMs: target.millisecondsSinceEpoch,
        mode: TimerMode.linked,
      );

      expect(timerLabel(state, now), '連動タイマー(21:45まで)');
    });

    test('inserts （超過） before the end time once overdue', () {
      final target = now.subtract(const Duration(minutes: 5));
      final state = TimerState(targetEpochMs: target.millisecondsSinceEpoch);

      expect(timerLabel(state, now), 'タイマー（超過）(19:55まで)');
    });

    test('inserts （超過） for linked mode too', () {
      final target = now.subtract(const Duration(minutes: 5));
      final state = TimerState(
        targetEpochMs: target.millisecondsSinceEpoch,
        mode: TimerMode.linked,
      );

      expect(timerLabel(state, now), '連動タイマー（超過）(19:55まで)');
    });
  });
}
