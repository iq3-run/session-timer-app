import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/home_widget/next_time_target.dart';
import 'package:session_timer/features/targets/time_target.dart';

void main() {
  final now = DateTime(2099, 1, 1, 12);

  group('nextTimeTarget', () {
    test('returns null for an empty list', () {
      expect(nextTimeTarget(const [], now), isNull);
    });

    test('returns null when every target has already passed', () {
      final targets = [
        TimeTarget(
          id: 'a',
          epochMs: now
              .subtract(const Duration(minutes: 5))
              .millisecondsSinceEpoch,
        ),
        TimeTarget(
          id: 'b',
          epochMs: now
              .subtract(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
        ),
      ];

      expect(nextTimeTarget(targets, now), isNull);
    });

    test(
      'returns the earliest not-yet-passed target from an already-sorted '
      'list',
      () {
        final past = TimeTarget(
          id: 'past',
          epochMs: now
              .subtract(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
        );
        final soon = TimeTarget(
          id: 'soon',
          epochMs: now.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
        );
        final later = TimeTarget(
          id: 'later',
          epochMs: now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
        );

        expect(nextTimeTarget([past, soon, later], now)?.id, 'soon');
      },
    );

    test('treats a target exactly at now as already passed', () {
      final target = TimeTarget(id: 'a', epochMs: now.millisecondsSinceEpoch);

      expect(nextTimeTarget([target], now), isNull);
    });
  });
}
