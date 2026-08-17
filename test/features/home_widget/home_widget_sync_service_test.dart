import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/home_widget/home_widget_gateway.dart';
import 'package:session_timer/features/home_widget/home_widget_sync_service.dart';
import 'package:session_timer/features/schedule/session_chain.dart';
import 'package:session_timer/features/schedule/session_gap_calculation.dart';
import 'package:session_timer/features/stopwatch/stopwatch_state.dart';
import 'package:session_timer/features/targets/time_target.dart';
import 'package:session_timer/features/timer/timer_state.dart';

class _RecordedSave {
  _RecordedSave(this.key, this.value);
  final String key;
  final Object? value;
}

class _FakeHomeWidgetGateway implements HomeWidgetGateway {
  final saves = <_RecordedSave>[];
  final updatedAndroidNames = <String>[];

  @override
  Future<void> saveWidgetData(String key, Object? value) async {
    saves.add(_RecordedSave(key, value));
  }

  @override
  Future<void> updateWidget({required String androidName}) async {
    updatedAndroidNames.add(androidName);
  }

  @override
  Future<String?> getWidgetData(String key) async => valueOf(key) as String?;

  // Reverse-scan rather than `.lastWhere` so a key that was never saved
  // returns null (matching `getWidgetData`'s nullable contract) instead of
  // throwing `StateError`.
  Object? valueOf(String key) {
    for (final save in saves.reversed) {
      if (save.key == key) return save.value;
    }
    return null;
  }
}

void main() {
  late _FakeHomeWidgetGateway gateway;
  late HomeWidgetSyncService service;

  setUp(() {
    gateway = _FakeHomeWidgetGateway();
    service = HomeWidgetSyncService(gateway);
  });

  group('HomeWidgetSyncService.syncStopwatch', () {
    test('sends accumulated/running/offset as strings and updates the '
        'stopwatch widget', () async {
      await service.syncStopwatch(
        const StopwatchState(accumulatedMs: 12345, runningSinceEpochMs: 999),
        7,
      );

      expect(gateway.valueOf(stopwatchAccumulatedMsKey), '12345');
      expect(gateway.valueOf(stopwatchRunningSinceEpochMsKey), '999');
      expect(gateway.valueOf(ntpOffsetMsKey), '7');
      expect(gateway.updatedAndroidNames, [stopwatchWidgetAndroidName]);
    });

    test('sends null (not the string "null") for runningSinceEpochMs when '
        'stopped', () async {
      await service.syncStopwatch(const StopwatchState(), 0);

      expect(gateway.valueOf(stopwatchRunningSinceEpochMsKey), isNull);
    });
  });

  group('HomeWidgetSyncService.syncNextTarget', () {
    test('sends the target epoch as a string and updates the next-target '
        'widget', () async {
      const target = TimeTarget(id: 't1', epochMs: 1700000000000);

      await service.syncNextTarget(target, 3);

      expect(gateway.valueOf(nextTargetEpochMsKey), '1700000000000');
      expect(gateway.valueOf(ntpOffsetMsKey), '3');
      expect(gateway.updatedAndroidNames, [nextTargetWidgetAndroidName]);
    });

    test('sends null when there is no next target', () async {
      await service.syncNextTarget(null, 0);

      expect(gateway.valueOf(nextTargetEpochMsKey), isNull);
    });
  });

  group('HomeWidgetSyncService.syncCompletion', () {
    test('sends the target epoch as a string and updates the completion '
        'widget', () async {
      final target = DateTime.fromMillisecondsSinceEpoch(1700000000000);

      await service.syncCompletion(target, 3);

      expect(gateway.valueOf(completionTargetEpochMsKey), '1700000000000');
      expect(gateway.valueOf(ntpOffsetMsKey), '3');
      expect(gateway.updatedAndroidNames, [completionWidgetAndroidName]);
    });

    test('sends null when the completion target is unset', () async {
      await service.syncCompletion(null, 0);

      expect(gateway.valueOf(completionTargetEpochMsKey), isNull);
    });
  });

  group('HomeWidgetSyncService.syncTimer', () {
    test(
      'sends the target epoch as a string and updates the timer widget',
      () async {
        const state = TimerState(targetEpochMs: 1700000000000);

        await service.syncTimer(state, 3);

        expect(gateway.valueOf(timerTargetEpochMsKey), '1700000000000');
        expect(gateway.valueOf(ntpOffsetMsKey), '3');
        expect(gateway.updatedAndroidNames, [
          timerWidgetAndroidName,
          timerControlWidgetAndroidName,
        ]);
      },
    );

    test('sends null when the timer is unset', () async {
      await service.syncTimer(const TimerState(), 0);

      expect(gateway.valueOf(timerTargetEpochMsKey), isNull);
    });

    test('sends null when there is no timer state at all', () async {
      await service.syncTimer(null, 0);

      expect(gateway.valueOf(timerTargetEpochMsKey), isNull);
    });
  });

  group('HomeWidgetSyncService.syncSchedule', () {
    /// Encodes a single row and decodes back the JSON object at index 0 —
    /// each test below only cares about one row's own field values, not the
    /// list-level plumbing (already covered by the "for each row"/"empty
    /// list" tests).
    Future<Map<String, dynamic>> encodedRow(ScheduleRow row) async {
      await service.syncSchedule([row]);
      final decoded =
          jsonDecode(gateway.valueOf(scheduleEventsJsonKey)! as String)
              as List<dynamic>;
      return decoded.single as Map<String, dynamic>;
    }

    test(
      'sends label/date/isToday for each row as JSON and updates the '
      'schedule widget',
      () async {
        final rows = [
          ScheduleRow(label: 'OR', date: DateTime(2026, 8, 10), isToday: false),
          ScheduleRow(label: '今日', date: DateTime(2026, 8, 17), isToday: true),
        ];

        await service.syncSchedule(rows);

        final decoded =
            (jsonDecode(gateway.valueOf(scheduleEventsJsonKey)! as String)
                    as List<dynamic>)
                .cast<Map<String, dynamic>>();
        expect(decoded.map((r) => r['label']), ['OR', '今日']);
        expect(decoded.map((r) => r['date']), ['8/10(月)', '8/17(月)']);
        expect(decoded.map((r) => r['isToday']), [false, true]);
        expect(gateway.updatedAndroidNames, [scheduleWidgetAndroidName]);
      },
    );

    test('sends empty chainGap/todayGap when a row has neither', () async {
      final row = ScheduleRow(
        label: 'CR',
        date: DateTime(2026, 8, 10),
        isToday: false,
      );

      final encoded = await encodedRow(row);

      expect(encoded['chainGap'], '');
      expect(encoded['todayGap'], '');
    });

    test(
      'sends chainGap and an empty todayGap when only chainGap is set',
      () async {
        final row = ScheduleRow(
          label: 'OR',
          date: DateTime(2026, 8, 10),
          isToday: false,
          chainGap: const GapResult(days: 3, weeks: 1),
        );

        final encoded = await encodedRow(row);

        expect(encoded['chainGap'], '3日(1W)');
        expect(encoded['todayGap'], '');
      },
    );

    test(
      'sends todayGap and an empty chainGap when only todayGap is set',
      () async {
        final row = ScheduleRow(
          label: '今日',
          date: DateTime(2026, 8, 17),
          isToday: true,
          todayGap: const GapResult(days: 0, weeks: 0),
        );

        final encoded = await encodedRow(row);

        expect(encoded['chainGap'], '');
        expect(encoded['todayGap'], '0日(0W)');
      },
    );

    test(
      'sends both chainGap and todayGap when a row is both a chain row and '
      'the nearest-past/nearest-future entry',
      () async {
        final row = ScheduleRow(
          label: '3WE',
          date: DateTime(2026, 8, 24),
          isToday: false,
          chainGap: const GapResult(days: 12, weeks: 2),
          todayGap: const GapResult(days: 5, weeks: 1),
        );

        final encoded = await encodedRow(row);

        expect(encoded['chainGap'], '12日(2W)');
        expect(encoded['todayGap'], '5日(1W)');
      },
    );

    test('sends an empty list as an empty JSON array', () async {
      await service.syncSchedule(const []);

      expect(gateway.valueOf(scheduleEventsJsonKey), '[]');
    });
  });
}
