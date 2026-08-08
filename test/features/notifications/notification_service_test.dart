import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/features/flash/flash_event.dart';
import 'package:session_timer/features/notifications/notification_service.dart';

// flutter_local_notifications dispatches to a platform-specific
// implementation based on `defaultTargetPlatform`, all of which funnel
// through this single method channel — mocking it here (forced to Android,
// since that's this project's primary target) is the only way to observe
// what NotificationService actually asks the plugin to do, since the
// plugin's own public class can't be subclassed for a fake (its generative
// constructor is private).
const _channel = MethodChannel('dexterous.com/flutter/local_notifications');

class _RecordedCall {
  _RecordedCall(this.method, this.arguments);
  final String method;
  final Object? arguments;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<_RecordedCall> calls;

  setUp(() {
    calls = [];
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    // Normally done by the generated plugin registrant at native app
    // startup — `flutter test` never runs that, so
    // `FlutterLocalNotificationsPlatform.instance` is otherwise left
    // uninitialized.
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(_RecordedCall(call.method, call.arguments));
          return switch (call.method) {
            'initialize' => true,
            _ => null,
          };
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  NotificationService buildService() => NotificationService(
    FlutterLocalNotificationsPlugin(),
    localTimezoneIdentifier: () async => 'Etc/UTC',
  );

  group('NotificationService.rescheduleAll', () {
    test('cancels all pending notifications before rescheduling', () async {
      final service = buildService();

      await service.rescheduleAll(const []);

      expect(calls.map((c) => c.method), contains('cancelAll'));
    });

    test('skips events whose instant has already passed', () async {
      final service = buildService();
      final past = FlashEvent(
        id: 'target:t1:1',
        instant: DateTime.now().subtract(const Duration(minutes: 1)),
        label: '過去',
      );

      await service.rescheduleAll([past]);

      expect(calls.where((c) => c.method == 'zonedSchedule'), isEmpty);
    });

    test('schedules future events with their label as the body', () async {
      final service = buildService();
      final future = FlashEvent(
        id: 'target:t1:1',
        instant: DateTime.now().add(const Duration(hours: 1)),
        label: '指定時刻になりました',
      );

      await service.rescheduleAll([future]);

      final scheduled = calls.where((c) => c.method == 'zonedSchedule');
      expect(scheduled, hasLength(1));
      final arguments = scheduled.single.arguments! as Map<dynamic, dynamic>;
      expect(arguments['body'], '指定時刻になりました');
    });

    test('derives a stable, deterministic id from the event id', () async {
      final service = buildService();
      final event = FlashEvent(
        id: 'completion:123456:10',
        instant: DateTime.now().add(const Duration(hours: 1)),
        label: '残り10分',
      );

      await service.rescheduleAll([event]);
      final firstArgs =
          calls.singleWhere((c) => c.method == 'zonedSchedule').arguments!
              as Map<dynamic, dynamic>;
      calls.clear();
      await service.rescheduleAll([event]);
      final secondArgs =
          calls.singleWhere((c) => c.method == 'zonedSchedule').arguments!
              as Map<dynamic, dynamic>;

      expect(secondArgs['id'], firstArgs['id']);
      expect(firstArgs['id'] as int, greaterThanOrEqualTo(0));
    });

    test(
      'serializes overlapping calls instead of interleaving their '
      'cancelAll/zonedSchedule steps',
      () async {
        // Gate 'zonedSchedule' so the first call can't finish until the
        // test releases it — if the two calls below weren't serialized,
        // the second call's (ungated) cancelAll() would run while the
        // first call is still stuck waiting, landing before the first
        // call's zonedSchedule instead of after it.
        final zonedScheduleGate = Completer<void>();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_channel, (call) async {
              calls.add(_RecordedCall(call.method, call.arguments));
              if (call.method == 'zonedSchedule') {
                await zonedScheduleGate.future;
              }
              return switch (call.method) {
                'initialize' => true,
                _ => null,
              };
            });
        final service = buildService();
        final eventA = FlashEvent(
          id: 'a',
          instant: DateTime.now().add(const Duration(hours: 1)),
          label: 'A',
        );
        final eventB = FlashEvent(
          id: 'b',
          instant: DateTime.now().add(const Duration(hours: 2)),
          label: 'B',
        );

        final first = service.rescheduleAll([eventA]);
        final second = service.rescheduleAll([eventB]);
        zonedScheduleGate.complete();
        await Future.wait([first, second]);

        expect(calls.map((c) => c.method).toList(), [
          'initialize',
          'cancelAll',
          'zonedSchedule',
          'cancelAll',
          'zonedSchedule',
        ]);
        final scheduledBodies = calls
            .where((c) => c.method == 'zonedSchedule')
            .map((c) => (c.arguments! as Map<dynamic, dynamic>)['body'])
            .toList();
        expect(scheduledBodies, ['A', 'B']);
      },
    );
  });
}
