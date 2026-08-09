import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:session_timer/features/flash/flash_event.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

// Android notification channels are immutable once created — changing
// importance/priority in code has no effect on a device that already has
// this channel ID from an earlier app version, since Android silently
// ignores re-creation with different settings for the same ID. Bumping to
// a new ID (rather than deleting/recreating the old one, which users may
// have customized) is the documented way to roll out new channel defaults:
// https://developer.android.com/develop/ui/compose/notifications/channels
const _androidChannelId = 'flash_points_v2';
const _androidChannelName = 'フラッシュポイント通知';
const _androidChannelDescription = '完了時刻・指定時刻・タイマーのフラッシュポイントの通知';
const _notificationTitle = 'セッションタイマー';

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(FlutterLocalNotificationsPlugin()),
);

/// Schedules a device notification for every future flash-point instant,
/// mirroring what `FlashOverlay` shows on screen. Unlike the flash overlay
/// (foreground-only), notifications are pre-scheduled via `zonedSchedule`
/// so they still arrive while the app is backgrounded or not running.
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
  /// it's been set. Reset to `null` on failure so a transient error (e.g. a
  /// platform channel not ready yet) doesn't permanently disable the
  /// feature for the rest of the app session.
  Future<void>? _initFuture;

  Future<void> init() =>
      _initFuture ??= _initNow().catchError((Object e, StackTrace st) {
        _initFuture = null;
        Error.throwWithStackTrace(e, st);
      });

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
    await _androidPlugin?.requestNotificationsPermission();
    // A decline (or the plugin already having the permission, in which
    // case this is a no-op — see `_scheduleMode`) doesn't stop notification
    // setup: any exception here still gets caught by the caller
    // (`NotificationScheduler._bootstrap`), and the iOS call below runs
    // regardless since it targets a different platform implementation.
    await _androidPlugin?.requestExactAlarmsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  AndroidFlutterLocalNotificationsPlugin? get _androidPlugin => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// Serializes [rescheduleAll] calls so an in-flight cancel-and-rebuild
  /// can't be interleaved with a newer one — e.g. two rapid state edits
  /// (add two time targets back-to-back) would otherwise race, letting the
  /// older call's later `zonedSchedule`s land after the newer call's
  /// `cancelAll()` and leave stale notifications behind. Mirrors
  /// `StopwatchController`/`TimeTargetsController`'s `_mutationQueue`
  /// pattern.
  Future<void> _rescheduleQueue = Future<void>.value();

  /// Cancels every pending scheduled notification and re-schedules one for
  /// each of [events] whose instant hasn't passed yet. Called whenever the
  /// candidate list changes (completion/target/timer state edited).
  Future<void> rescheduleAll(List<FlashEvent> events) {
    final previous = _rescheduleQueue;
    final result = previous.then((_) => _rescheduleNow(events));
    _rescheduleQueue = result.catchError((_) {});
    return result;
  }

  Future<void> _rescheduleNow(List<FlashEvent> events) async {
    await init();
    await _plugin.cancelAll();
    final now = DateTime.now();
    final upcoming = events.where((event) => event.instant.isAfter(now));
    final scheduleMode = await _scheduleMode();
    await Future.wait(
      upcoming.map(
        (event) => _plugin.zonedSchedule(
          id: _notificationId(event.id),
          title: _notificationTitle,
          body: event.label,
          scheduledDate: tz.TZDateTime.from(event.instant, tz.local),
          notificationDetails: _notificationDetails,
          androidScheduleMode: scheduleMode,
        ),
      ),
    );
  }

  /// Exact scheduling requires the user to have granted `SCHEDULE_EXACT_ALARM`
  /// (Android 12+); re-checked on every reschedule rather than cached, since
  /// the user can flip it in system settings at any time without the app
  /// knowing. Non-Android platforms (where `_androidPlugin` is null) fall
  /// back to inexact too — the value is only read on Android regardless, but
  /// keeps this method meaningful platform-agnostically.
  Future<AndroidScheduleMode> _scheduleMode() async {
    final exactAllowed =
        await _androidPlugin?.canScheduleExactNotifications() ?? false;
    return exactAllowed
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  static const _notificationDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      _androidChannelId,
      _androidChannelName,
      channelDescription: _androidChannelDescription,
      // Max importance so a flash-point notification appears as a
      // heads-up popup instead of only showing silently in the shade.
      importance: Importance.max,
      priority: Priority.high,
    ),
  );
}

/// Masks a hash down to a positive 32-bit int, as `zonedSchedule` requires.
const _int32SignMask = 0x7fffffff;

/// Collisions between two [FlashEvent.id]s are astronomically unlikely
/// given this app's event volume (well under a hundred at once) — accepted.
int _notificationId(String eventId) => eventId.hashCode & _int32SignMask;
