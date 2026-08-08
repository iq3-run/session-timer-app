import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/completion/completion_time_state.dart';
import 'package:session_timer/features/flash/flash_event.dart';
import 'package:session_timer/features/targets/time_target.dart';
import 'package:session_timer/features/timer/timer_state.dart';

void main() {
  group('completionFlashEvents', () {
    test('returns nothing when no completion time is set', () {
      expect(completionFlashEvents(null), isEmpty);
      expect(completionFlashEvents(const CompletionTimeState()), isEmpty);
    });

    test('includes the exact-completion event plus every default point', () {
      final target = DateTime(2026, 8, 8, 15);
      final events = completionFlashEvents(
        CompletionTimeState(targetEpochMs: target.millisecondsSinceEpoch),
      );

      expect(events, hasLength(defaultCompletionFlashPointsMinutes.length + 1));
      final exact = events.firstWhere((e) => e.id.endsWith(':0'));
      expect(exact.instant, target);

      final tenMinBefore = events.firstWhere((e) => e.id.endsWith(':10'));
      expect(
        tenMinBefore.instant,
        target.subtract(const Duration(minutes: 10)),
      );
    });

    test('ids embed the target epoch so a new target produces new ids', () {
      final targetA = DateTime(2026, 8, 8, 15);
      final targetB = DateTime(2026, 8, 8, 16);
      final idsA = completionFlashEvents(
        CompletionTimeState(targetEpochMs: targetA.millisecondsSinceEpoch),
      ).map((e) => e.id).toSet();
      final idsB = completionFlashEvents(
        CompletionTimeState(targetEpochMs: targetB.millisecondsSinceEpoch),
      ).map((e) => e.id).toSet();

      expect(idsA.intersection(idsB), isEmpty);
    });
  });

  group('targetFlashEvents', () {
    test('returns one event per target ending exactly at its time', () {
      final t = DateTime(2026, 8, 8, 12, 30);
      final events = targetFlashEvents([
        TimeTarget(id: 'abc', epochMs: t.millisecondsSinceEpoch),
      ]);

      expect(events, hasLength(1));
      expect(events.single.id, 'target:abc:${t.millisecondsSinceEpoch}');
      expect(events.single.instant, t);
    });

    test('returns nothing for an empty list', () {
      expect(targetFlashEvents(const []), isEmpty);
    });
  });

  group('timerFlashEvents', () {
    test('returns nothing when the timer is unset', () {
      expect(timerFlashEvents(null), isEmpty);
      expect(timerFlashEvents(const TimerState()), isEmpty);
    });

    test('returns the 5/3/1-minute-before points', () {
      final target = DateTime(2026, 8, 8, 15);
      final events = timerFlashEvents(
        TimerState(targetEpochMs: target.millisecondsSinceEpoch),
      );

      expect(events, hasLength(timerFlashPointsMinutes.length));
      for (final m in timerFlashPointsMinutes) {
        final event = events.firstWhere((e) => e.id.endsWith(':$m'));
        expect(event.instant, target.subtract(Duration(minutes: m)));
      }
    });
  });
}
