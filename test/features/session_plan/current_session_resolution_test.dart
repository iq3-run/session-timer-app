import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/session_plan/current_session_resolution.dart';
import 'package:session_timer/features/session_plan/session_plan_entry.dart';

SessionPlanEntry _entry(String id, DateTime start, DateTime end) =>
    SessionPlanEntry(
      id: id,
      startEpochMs: start.millisecondsSinceEpoch,
      endEpochMs: end.millisecondsSinceEpoch,
    );

void main() {
  group('resolveCurrentSession', () {
    final now = DateTime(2026, 8, 8, 10);

    test('returns null for an empty list', () {
      expect(resolveCurrentSession(const [], now), isNull);
    });

    test('returns null when every session has already ended', () {
      final sessions = [
        _entry(
          's1',
          now.subtract(const Duration(hours: 2)),
          now.subtract(const Duration(hours: 1)),
        ),
      ];

      expect(resolveCurrentSession(sessions, now), isNull);
    });

    test(
      'a not-yet-started session becomes current, with its own start as '
      'the auto target',
      () {
        final session = _entry(
          's1',
          now.add(const Duration(hours: 1)),
          now.add(const Duration(hours: 4)),
        );

        final resolution = resolveCurrentSession([session], now);

        expect(resolution?.session.id, 's1');
        expect(resolution?.completionTarget, session.endTime);
        expect(resolution?.autoTargetStart, session.startTime);
      },
    );

    test(
      "an in-progress session becomes current, with the next session's "
      'start as the auto target',
      () {
        final current = _entry(
          'am',
          now.subtract(const Duration(hours: 1)),
          now.add(const Duration(hours: 2, minutes: 30)),
        );
        final next = _entry(
          'pm',
          now.add(const Duration(hours: 3, minutes: 30)),
          now.add(const Duration(hours: 7)),
        );

        final resolution = resolveCurrentSession([current, next], now);

        expect(resolution?.session.id, 'am');
        expect(resolution?.completionTarget, current.endTime);
        expect(resolution?.autoTargetStart, next.startTime);
      },
    );

    test(
      'an in-progress session with no next session clears the auto target',
      () {
        final current = _entry(
          'am',
          now.subtract(const Duration(hours: 1)),
          now.add(const Duration(hours: 2, minutes: 30)),
        );

        final resolution = resolveCurrentSession([current], now);

        expect(resolution?.session.id, 'am');
        expect(resolution?.autoTargetStart, isNull);
      },
    );

    test(
      'picks the session ending soonest among not-yet-ended ones, not the '
      'one listed first',
      () {
        final endsSoon = _entry(
          'soon',
          now.subtract(const Duration(minutes: 30)),
          now.add(const Duration(minutes: 10)),
        );
        final endsLater = _entry(
          'later',
          now.subtract(const Duration(hours: 1)),
          now.add(const Duration(hours: 3)),
        );

        final resolution = resolveCurrentSession([endsLater, endsSoon], now);

        expect(resolution?.session.id, 'soon');
      },
    );
  });
}
