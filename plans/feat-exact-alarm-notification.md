# Feat: exact-alarm scheduling + heads-up popup for flash-point notifications

Issue: <https://github.com/iq3-run/session-timer-app/issues/39>

## Problem

Flash-point notifications (completion time / time targets / timer) arrive,
but with two gaps confirmed by the user during manual device testing:

1. **Precision** — `NotificationService._rescheduleNow` always used
   `AndroidScheduleMode.inexactAllowWhileIdle`, so Android's battery
   optimization can delay actual delivery by several minutes.
2. **No popup** — the `flash_points` notification channel didn't set an
   explicit `Importance`, defaulting to `Importance.defaultImportance`,
   which never shows as a heads-up (popup) notification.

## Fix

- Add `<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>`
  to `AndroidManifest.xml` (required on Android 12+ for exact alarms; the
  user must still grant it explicitly on Android 13+).
- `NotificationService.requestPermissions()` now also calls the plugin's
  `requestExactAlarmsPermission()` (best-effort — a decline doesn't block
  the rest of notification setup).
- `NotificationService._rescheduleNow` checks
  `canScheduleExactNotifications()` on every reschedule (not cached, since
  the user can flip the permission in system settings at any time) and
  picks `AndroidScheduleMode.exactAllowWhileIdle` when granted, falling
  back to `AndroidScheduleMode.inexactAllowWhileIdle` otherwise — the app's
  notification feature never breaks outright just because the permission
  was declined.
- `_notificationDetails`'s `AndroidNotificationDetails` now sets
  `importance: Importance.max, priority: Priority.high` so a delivered
  notification shows as a heads-up popup.

## Out of scope

- `USE_EXACT_ALARM` (the no-prompt alternative permission for genuine
  alarm-clock apps) — Play Store policy restricts it to apps whose primary
  function is alarms/timers, and using it incorrectly risks a policy
  rejection; `SCHEDULE_EXACT_ALARM` with a graceful inexact fallback is the
  safer default for this app.
- `USE_FULL_SCREEN_INTENT` / full-screen heads-up over the lock screen —
  not requested by the user; `Importance.max` heads-up while the device is
  unlocked/in-use is the scope agreed on.

## Verification

- `dart format`
- `flutter analyze`
- `flutter test` (new/updated tests in
  `test/features/notifications/notification_service_test.dart`: requests
  exact-alarm permission, schedules exactly when granted, falls back to
  inexact when not, schedules at `Importance.max`, and the existing
  overlapping-calls test updated for the new `canScheduleExactNotifications`
  call in the sequence)
- Manual on-device: confirm the exact-alarm permission prompt appears on
  first launch, granting it results in notifications arriving at their
  exact scheduled time, and delivered notifications appear as a heads-up
  popup.
