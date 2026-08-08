# Feat: device notification + vibration

Issue: <https://github.com/iq3-run/session-timer-app/issues/21>

## Scope (confirmed with the user before starting)

- **Firing mechanism: pre-scheduled.** Unlike the flash overlay (which only
  fires while the app is in the foreground, per `plans/feat-flash-effect.md`'s
  deliberate window-based design), notifications must reach the user while
  the app is backgrounded or not running. Every time a source's state
  changes, the full list of future flash-point instants for that source is
  (re)scheduled up front via `flutter_local_notifications`'
  `zonedSchedule` — the OS delivers them even if the app process is gone.
- **Event coverage: all flash events** — completion countdown's 12 default
  points + the exact-completion instant, every time target, and the timer's
  5/3/1-minutes-before points. Same event set the flash overlay already
  animates.
- **Vibration: Android notification-channel default pattern only.** No new
  vibration package. iOS gets whatever vibration/sound accompanies a local
  notification by default — not controlled per-notification from the app.

## Out of scope

- ⚙ settings sheet / per-notification-type toggle — ships as an always-on
  behavior tied to existing completion/target/timer state, same reasoning
  as the flash effect shipping without a settings sheet.
- Weekend milestones, NTP sync (separate Issue #1 items).
- Surviving a device **reboot**: pending Android alarms are cleared on
  reboot, and this plan does not add a boot receiver
  (`RECEIVE_BOOT_COMPLETED` + native rebroadcast) to re-arm them. Notified
  schedules are naturally rebuilt the next time the app is opened before
  the reboot-cleared events' instants, same as `flash_queue_controller.dart`
  already tolerates missed windows silently. Flagging as an accepted gap in
  Items to Confirm.

## Design decisions requiring implementation-time judgment (flag in PR)

These weren't put back to the user mid-plan because they're standard
engineering trade-offs with a clear best default, same as
`feat-flash-effect.md`'s own "Items to Confirm" entries — but they should
be called out explicitly for review:

1. **Android exact-alarm permission: NOT requested.** Android 12+ gates
   `AndroidScheduleMode.exactAllowWhileIdle` behind the special "Alarms &
   reminders" grant (`SCHEDULE_EXACT_ALARM`), which needs the user to leave
   the app to a system settings screen. Since these are reminder
   notifications (not an alarm-clock use case), this plan uses
   `AndroidScheduleMode.inexactAllowWhileIdle` instead — no special
   permission, but the OS may batch/delay delivery by several minutes under
   Doze, especially for far-future points (e.g. the 120-minutes-before
   completion notification). Acceptable for a reminder; flagging the
   precision trade-off.
2. **Notification id derivation**: `FlashEvent.id` (a String) is hashed to
   a positive 32-bit int (`id.hashCode & 0x7fffffff`) for
   `flutter_local_notifications`' required int id. Collisions are
   astronomically unlikely given the event volume here, but it's a
   non-cryptographic hash, not a guaranteed-unique id.
3. **New dependency: `flutter_timezone`** (or equivalent) is needed to feed
   `timezone`'s `tz.setLocalLocation` with the device's actual IANA zone
   name — `timezone` (already a pubspec dependency, currently unused)
   defaults to UTC otherwise, which would fire every notification at the
   wrong wall-clock time outside UTC. Add via `flutter pub add
   flutter_timezone`.
4. **Reschedule strategy: cancel-all-and-rebuild**, not diffed. The
   candidate-event provider only recomputes when completion/targets/timer
   state actually changes (not on every 1s clock tick — same as
   `flash_event.dart`'s pure, `now`-independent candidate functions), so
   this is infrequent enough that `cancelAll()` + reschedule-everything-
   future is simpler and safer than diffing old vs. new schedules, at the
   cost of a brief window where a notification due in the next instant
   could theoretically be cancelled and not re-added if its instant has
   just passed `now` (filtered out as "past" on rebuild). Same accepted-
   edge-case tolerance as the flash queue's own missed-window handling.

## New module: `lib/features/notifications/`

### `notification_event_source.dart`

```dart
final notificationCandidateEventsProvider = Provider<List<FlashEvent>>((ref) {
  final completion = ref.watch(completionTimeControllerProvider).value;
  final targets = ref.watch(timeTargetsControllerProvider).value ?? const [];
  final timer = ref.watch(timerControllerProvider).value;
  return [
    ...completionFlashEvents(completion),
    ...targetFlashEvents(targets),
    ...timerFlashEvents(timer),
  ];
});
```

Reuses the same pure functions from `lib/features/flash/flash_event.dart`
that `FlashQueueController` already uses — no duplicated event-building
logic. This provider deliberately does *not* watch `nowProvider`; it only
changes when a source's state does.

### `notification_service.dart`

```dart
class NotificationService {
  NotificationService(this._plugin);
  final FlutterLocalNotificationsPlugin _plugin;

  Future<void> init() { ... } // platform init settings, Android channel
                               // with vibration pattern, iOS category
  Future<bool> requestPermissions() { ... } // Android 13+ POST_NOTIFICATIONS,
                                             // iOS alert/sound/badge
  Future<void> rescheduleAll(List<FlashEvent> events) async {
    await _plugin.cancelAll();
    final now = DateTime.now();
    for (final event in events) {
      if (!event.instant.isAfter(now)) continue;
      await _plugin.zonedSchedule(
        _notificationId(event.id),
        'セッションタイマー',
        event.label,
        tz.TZDateTime.from(event.instant, tz.local),
        _notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}

int _notificationId(String eventId) => eventId.hashCode & 0x7fffffff;
```

`_plugin` is injected (constructor param) so tests can pass a fake instead
of the real platform-channel-backed plugin.

### `notification_scheduler.dart`

A thin widget, not a Riverpod `Notifier`, since the side effect
(scheduling via a platform channel) is async and shouldn't run inside a
provider's synchronous `build()`:

```dart
class NotificationScheduler extends ConsumerStatefulWidget {
  const NotificationScheduler({required this.child, super.key});
  final Widget child;
  ...
}

class _NotificationSchedulerState extends ConsumerState<NotificationScheduler> {
  @override
  void initState() {
    super.initState();
    final service = ref.read(notificationServiceProvider);
    unawaited(service.init().then((_) => service.requestPermissions()));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(notificationCandidateEventsProvider, (previous, next) {
      unawaited(ref.read(notificationServiceProvider).rescheduleAll(next));
    });
    return widget.child;
  }
}
```

Mounted once in `lib/app.dart`, wrapping `ClockScreen`:

```dart
home: const NotificationScheduler(child: ClockScreen()),
```

`ClockScreen` itself is unchanged — this keeps the notification concern
entirely out of the screen tree, mirroring how `FlashOverlay` keeps flash
concerns self-contained.

## Platform config

### Android (`android/app/src/main/AndroidManifest.xml`)

- `<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>`
  (Android 13+ runtime-requested, but still needs the manifest entry)
- `<uses-permission android:name="android.permission.VIBRATE"/>`
- No `SCHEDULE_EXACT_ALARM`/`USE_EXACT_ALARM` (see Item 1 above) and no
  boot receiver (see Out of scope).
- Verify against `flutter_local_notifications` v22 setup docs at
  implementation time for any other required manifest entries (e.g.
  default notification icon `meta-data`).

### iOS (`ios/Runner/AppDelegate.swift`)

- Add `UNUserNotificationCenter.current().delegate = self` (with the
  `UNUserNotificationCenterDelegate` conformance the plugin needs for
  foreground presentation) per `flutter_local_notifications` iOS setup —
  confirm exact snippet against the installed package version.

### `pubspec.yaml`

- Add `flutter_timezone` (see Item 3 above) via `flutter pub add
  flutter_timezone`.
- `flutter_local_notifications` is already present, currently unused.
- `timezone` is already present, currently unused.

## Tests

- `test/features/notifications/notification_event_source_test.dart` —
  thin: confirms the provider's output matches the concatenation of the
  three existing (already-tested) event-source functions for a given
  fixture state.
- `test/features/notifications/notification_service_test.dart` — inject a
  fake `FlutterLocalNotificationsPlugin`-shaped test double (or use the
  package's own testing utilities if it ships one for v22) and assert:
  - past events are skipped, future events are scheduled
  - `cancelAll()` is called before rescheduling
  - notification ids are derived deterministically from event ids

No widget test is planned for `NotificationScheduler` itself — its only
logic is wiring (`ref.listen` + delegate calls), covered indirectly by the
service-level tests plus manual verification.

## Verification

- `dart format`
- `flutter analyze`
- `flutter test`
- debug build
- BlueStacks emulator: grant notification permission, set a near-future
  time target and a short timer, background the app, confirm a
  notification arrives with the expected label at roughly the right time
  (allow for `inexactAllowWhileIdle` drift per Item 1).
