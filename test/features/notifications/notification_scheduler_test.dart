import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:session_timer/features/flash/flash_event.dart';
import 'package:session_timer/features/notifications/notification_event_source.dart';
import 'package:session_timer/features/notifications/notification_scheduler.dart';
import 'package:session_timer/features/notifications/notification_service.dart';

class _RecordingService extends NotificationService {
  _RecordingService() : super(FlutterLocalNotificationsPlugin());

  int clearSuppressedCalls = 0;
  final List<List<FlashEvent>> rescheduled = [];

  @override
  Future<void> init() async {}

  @override
  Future<void> requestPermissions() async {}

  @override
  void clearSuppressed() => clearSuppressedCalls++;

  @override
  Future<void> rescheduleAll(List<FlashEvent> events) async =>
      rescheduled.add(events);
}

void main() {
  testWidgets(
    'leaving the foreground restores notifications cancelled for a flash '
    '(#95)',
    (tester) async {
      final service = _RecordingService();
      final event = FlashEvent(
        id: 'target:t1:1',
        instant: DateTime.now().add(const Duration(hours: 1)),
        label: '指定時刻',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notificationServiceProvider.overrideWithValue(service),
            notificationCandidateEventsProvider.overrideWithValue([event]),
          ],
          child: const MaterialApp(
            home: NotificationScheduler(child: SizedBox()),
          ),
        ),
      );
      await tester.pump();
      service.rescheduled.clear();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      expect(service.clearSuppressedCalls, 1);
      expect(service.rescheduled, [
        [event],
      ]);
    },
  );

  testWidgets('returning to the foreground does not reschedule', (
    tester,
  ) async {
    final service = _RecordingService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationServiceProvider.overrideWithValue(service),
          notificationCandidateEventsProvider.overrideWithValue(const []),
        ],
        child: const MaterialApp(
          home: NotificationScheduler(child: SizedBox()),
        ),
      ),
    );
    await tester.pump();
    service.rescheduled.clear();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(service.clearSuppressedCalls, 0);
    expect(service.rescheduled, isEmpty);
  });
}
