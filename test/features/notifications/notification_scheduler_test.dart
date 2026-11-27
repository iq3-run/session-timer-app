import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:session_timer/core/clock/ntp_sync_controller.dart';
import 'package:session_timer/features/flash/flash_event.dart';
import 'package:session_timer/features/notifications/notification_event_source.dart';
import 'package:session_timer/features/notifications/notification_scheduler.dart';
import 'package:session_timer/features/notifications/notification_service.dart';

class _TestOffset extends Notifier<int> {
  @override
  int build() => 0;

  // `Notifier.state` is protected, so changing it goes through here.
  // ignore: use_setters_to_change_properties
  void change(int value) => state = value;
}

final _testOffsetProvider = NotifierProvider<_TestOffset, int>(
  _TestOffset.new,
);

class _RecordingService extends NotificationService {
  _RecordingService() : super(FlutterLocalNotificationsPlugin());

  int clearSuppressedCalls = 0;
  final List<List<FlashEvent>> rescheduled = [];
  final List<int> offsets = [];

  @override
  Future<void> init() async {}

  @override
  Future<void> requestPermissions() async {}

  @override
  bool clearSuppressed() {
    clearSuppressedCalls++;
    // Like the real service: only the first call finds anything to forget.
    final hadAny = suppressed;
    suppressed = false;
    return hadAny;
  }

  bool suppressed = true;
  bool failReschedule = false;

  @override
  Future<void> rescheduleAll(
    List<FlashEvent> events, {
    int ntpOffsetMs = 0,
  }) async {
    rescheduled.add(events);
    offsets.add(ntpOffsetMs);
    if (failReschedule) throw Exception('plugin failed');
  }
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

  testWidgets('inactive alone does not restore (the app is still on screen)', (
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

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    expect(service.clearSuppressedCalls, 0);
    expect(service.rescheduled, isEmpty);
  });

  testWidgets(
    'nothing suppressed: leaving the foreground does not reschedule',
    (
      tester,
    ) async {
      final service = _RecordingService()..suppressed = false;
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

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      expect(service.rescheduled, isEmpty);
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

  testWidgets('a failed restore is retried on the next trip to the background '
      'even though the suppression record is already gone', (tester) async {
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
    service.failReschedule = true;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(service.rescheduled, hasLength(1)); // failed

    // The record is gone now; only the pending flag knows to retry.
    service
      ..suppressed = false
      ..failReschedule = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(service.rescheduled, hasLength(2)); // retried, and succeeded

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(service.rescheduled, hasLength(2)); // done: no more retries
  });

  testWidgets('hidden then paused reschedule only once', (tester) async {
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

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(service.rescheduled, hasLength(1));
  });

  group('NTP offset', () {
    testWidgets('is passed along when scheduling, and a change reschedules '
        'what is already registered', (tester) async {
      final service = _RecordingService();
      final event = FlashEvent(
        id: 'target:t1:1',
        instant: DateTime.now().add(const Duration(hours: 1)),
        label: '指定時刻',
      );
      final container = ProviderContainer(
        overrides: [
          notificationServiceProvider.overrideWithValue(service),
          notificationCandidateEventsProvider.overrideWithValue([event]),
          ntpOffsetMsProvider.overrideWith(
            (ref) => ref.watch(_testOffsetProvider),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: NotificationScheduler(child: SizedBox()),
          ),
        ),
      );
      await tester.pump();
      expect(service.offsets.last, 0);
      service.rescheduled.clear();
      service.offsets.clear();

      container.read(_testOffsetProvider.notifier).change(60000);
      await tester.pump();

      expect(service.rescheduled, [
        [event],
      ]);
      expect(service.offsets, [60000]);
    });
  });
}
