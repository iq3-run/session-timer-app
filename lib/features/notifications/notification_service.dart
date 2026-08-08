import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:session_timer/features/flash/flash_event.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

const _androidChannelId = 'flash_points';
const _androidChannelName = 'フラッシュポイント通知';
const _androidChannelDescription = '完了時刻・指定時刻・タイマーのフラッシュポイントの通知';
const _notificationTitle = 'セッションタイマー';

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(FlutterLocalNotificationsPlugin()),
);

/// Schedules a device notification for every future flash-point instant,
/// mirroring what `FlashOverlay` shows on screen. Notifications are
/// pre-scheduled via `zonedSchedule` rather than fired at the moment a
/// flash actually plays, so they still arrive while the app is backgrounded
/// or not running — see plans/feat-device-notifications.md for why this
/// differs from the flash overlay's foreground-only design.
class NotificationService {
  NotificationService(
    this._plugin, {
    Future<String> Function()? localTimezoneIdentifier,
  }) : _localTimezoneIdentifier =
           localTimezoneIdentifier ??
           (() async => (await FlutterTimezone.getLocalTimezone()).identifier);

  final FlutterLocalNotificationsPlugin _plugin;

  /// Injectable so tests can supply a fixed zone instead of hitting the
  /// `flutter_timezone` platform channel.
  final Future<String> Function() _localTimezoneIdentifier;

  /// Memoized so concurrent callers (e.g. `NotificationScheduler.initState`
  /// racing an early `rescheduleAll`) share one in-flight initialization
  /// instead of double-initializing the plugin or reading `tz.local` before
  /// it's been set.
  Future<void>? _initFuture;

  Future<void> init() => _initFuture ??= _initNow();

  Future<void> _initNow() async {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(await _localTimezoneIdentifier()));

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const darwinSettings = DarwinInitializationSettings();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
      ),
    );
  }

  Future<void> requestPermissions() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// Cancels every pending scheduled notification and re-schedules one for
  /// each of [events] whose instant hasn't passed yet. Called whenever the
  /// candidate list changes (completion/target/timer state edited), which
  /// is infrequent enough that a full rebuild is simpler than diffing the
  /// old and new schedules. Awaits [init] itself so callers can't race it.
  Future<void> rescheduleAll(List<FlashEvent> events) async {
    await init();
    await _plugin.cancelAll();
    final now = DateTime.now();
    for (final event in events) {
      if (!event.instant.isAfter(now)) continue;
      await _plugin.zonedSchedule(
        id: _notificationId(event.id),
        title: _notificationTitle,
        body: event.label,
        scheduledDate: tz.TZDateTime.from(event.instant, tz.local),
        notificationDetails: _notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  static const _notificationDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      _androidChannelId,
      _androidChannelName,
      channelDescription: _androidChannelDescription,
    ),
  );
}

/// `zonedSchedule` requires a positive 32-bit int id. Collisions between
/// two [FlashEvent.id]s are astronomically unlikely given this app's event
/// volume (well under a hundred at once) — accepted, see Items to Confirm
/// in plans/feat-device-notifications.md.
int _notificationId(String eventId) => eventId.hashCode & 0x7fffffff;
