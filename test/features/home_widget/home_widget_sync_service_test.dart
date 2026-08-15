import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/home_widget/home_widget_gateway.dart';
import 'package:session_timer/features/home_widget/home_widget_sync_service.dart';
import 'package:session_timer/features/stopwatch/stopwatch_state.dart';
import 'package:session_timer/features/targets/time_target.dart';

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

  Object? valueOf(String key) => saves.lastWhere((s) => s.key == key).value;
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
}
