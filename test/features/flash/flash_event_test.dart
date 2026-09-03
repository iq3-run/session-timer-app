import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/completion/completion_time_state.dart';
import 'package:session_timer/features/flash/flash_event.dart';
import 'package:session_timer/features/targets/time_target.dart';
import 'package:session_timer/features/timer/timer_state.dart';

void main() {
  group('completionFlashEvents', () {
    test('returns nothing when no completion time is set', () {
      expect(
        completionFlashEvents(null, defaultCompletionFlashPointsMinutes),
        isEmpty,
      );
      expect(
        completionFlashEvents(
          const CompletionTimeState(),
          defaultCompletionFlashPointsMinutes,
        ),
        isEmpty,
      );
    });

    test('includes the exact-completion event plus every point passed in', () {
      final target = DateTime(2026, 8, 8, 15);
      final events = completionFlashEvents(
        CompletionTimeState(targetEpochMs: target.millisecondsSinceEpoch),
        defaultCompletionFlashPointsMinutes,
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

    test('returns only the exact-completion event when the point list is '
        'empty (user removed every point)', () {
      final target = DateTime(2026, 8, 8, 15);
      final events = completionFlashEvents(
        CompletionTimeState(targetEpochMs: target.millisecondsSinceEpoch),
        const [],
      );

      expect(events, hasLength(1));
      expect(events.single.id, endsWith(':0'));
    });

    test('ids embed the target epoch so a new target produces new ids', () {
      final targetA = DateTime(2026, 8, 8, 15);
      final targetB = DateTime(2026, 8, 8, 16);
      final idsA = completionFlashEvents(
        CompletionTimeState(targetEpochMs: targetA.millisecondsSinceEpoch),
        defaultCompletionFlashPointsMinutes,
      ).map((e) => e.id).toSet();
      final idsB = completionFlashEvents(
        CompletionTimeState(targetEpochMs: targetB.millisecondsSinceEpoch),
        defaultCompletionFlashPointsMinutes,
      ).map((e) => e.id).toSet();

      expect(idsA.intersection(idsB), isEmpty);
    });
  });

  group('targetFlashEvents', () {
    test(
      'returns the exact-instant event plus the 15/10/5/3/2/1-minute-before '
      'points, untitled wording',
      () {
        final t = DateTime(2026, 8, 8, 12, 30);
        final events = targetFlashEvents([
          TimeTarget(id: 'abc', epochMs: t.millisecondsSinceEpoch),
        ]);

        expect(events, hasLength(targetFlashPointsMinutes.length + 1));
        final exact = events.singleWhere(
          (e) => e.id == 'target:abc:${t.millisecondsSinceEpoch}:0',
        );
        expect(exact.instant, t);
        expect(exact.label, '指定時刻になりました');

        for (final m in targetFlashPointsMinutes) {
          final event = events.firstWhere((e) => e.id.endsWith(':$m'));
          expect(event.instant, t.subtract(Duration(minutes: m)));
          expect(event.label, '残り$m分');
        }
      },
    );

    test('uses the target title in the exact and pre-notify wording', () {
      final t = DateTime(2026, 8, 8, 12, 30);
      final events = targetFlashEvents([
        TimeTarget(id: 'abc', epochMs: t.millisecondsSinceEpoch, title: '朝礼'),
      ]);

      final exact = events.singleWhere(
        (e) => e.id == 'target:abc:${t.millisecondsSinceEpoch}:0',
      );
      expect(exact.label, '朝礼になりました');

      final fiveMinBefore = events.firstWhere((e) => e.id.endsWith(':5'));
      expect(fiveMinBefore.label, '朝礼まで残り5分');
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

    test('returns the exact-completion event plus the 5/3/1-minute-before '
        'points', () {
      final target = DateTime(2026, 8, 8, 15);
      final events = timerFlashEvents(
        TimerState(targetEpochMs: target.millisecondsSinceEpoch),
      );

      expect(
        events,
        hasLength(
          timerFlashPointsMinutes.length + timerFlashPointsSeconds.length + 1,
        ),
      );
      final exact = events.singleWhere(
        (e) => e.id == 'timer:${target.millisecondsSinceEpoch}:0',
      );
      expect(exact.instant, target);
      expect(exact.label, 'タイマー終了です');

      for (final m in timerFlashPointsMinutes) {
        final event = events.firstWhere((e) => e.id.endsWith(':$m'));
        expect(event.instant, target.subtract(Duration(minutes: m)));
      }
    });

    test('returns the 30/15/10-second-before points too', () {
      final target = DateTime(2026, 8, 8, 15);
      final events = timerFlashEvents(
        TimerState(targetEpochMs: target.millisecondsSinceEpoch),
      );

      for (final s in timerFlashPointsSeconds) {
        final event = events.singleWhere(
          (e) => e.id == 'timer:${target.millisecondsSinceEpoch}:${s}s',
        );
        expect(event.instant, target.subtract(Duration(seconds: s)));
        expect(event.label, 'タイマー残り$s秒');
      }
    });
  });
}
