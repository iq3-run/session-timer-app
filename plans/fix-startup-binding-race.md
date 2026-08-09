# Fix: startup NTP auto-sync races WidgetsFlutterBinding init, poisoning SharedPreferences

Issue: <https://github.com/iq3-run/session-timer-app/issues/36>

## Problem

`main()` calls `unawaited(_autoSyncNtpAtStartup(container))` *before*
`runApp()`:

```dart
void main() {
  final container = ProviderContainer();
  unawaited(_autoSyncNtpAtStartup(container));
  runApp(
    UncontrolledProviderScope(container: container, child: const SessionTimerApp()),
  );
}
```

`_autoSyncNtpAtStartup` synchronously drives
`container.read(ntpSyncControllerProvider.future)` →
`NtpSyncController.build()` → `ref.watch(sharedPreferencesProvider.future)` →
`SharedPreferences.getInstance()`, which needs a working platform channel
(`ServicesBinding.instance`). `WidgetsFlutterBinding.ensureInitialized()` is
normally called inside `runApp()`, but `runApp()` hasn't executed yet at
this point in `main()`, so the channel call throws:

```text
Unhandled Exception: Binding has not yet been initialized.
#11 sharedPreferencesProvider (shared_preferences_provider.dart:5)
#25 NtpSyncController.build (ntp_sync_controller.dart:80)
```

The thrown error is a `FlutterError` (extends `Error`, not `Exception`), so
`_autoSyncNtpAtStartup`'s `on Exception catch` doesn't catch it — it
escapes as an unhandled async error. Worse, Riverpod caches the failed
`sharedPreferencesProvider.future` as a permanent error, so every later
read of it (from `CompletionTimeController`, `StopwatchController`,
`TimerController`, etc.) rethrows the same cached error instead of
retrying. Since nearly every feature persists through
`sharedPreferencesProvider`, this silently breaks completion-time setting,
the stopwatch, and the timer for the rest of the app's life — confirmed by
manual testing on a real device (BlueStacks): completion time picker,
stopwatch tap-to-start, and timer +30s/+1min all no-op after this races.

Not deterministic on every launch (a scheduling race), but reproduced on
2 of 2 manual cold-start attempts during verification.

- `lib/main.dart:8-17`

## Fix

Call `WidgetsFlutterBinding.ensureInitialized()` explicitly as the first
line of `main()`, before creating the `ProviderContainer` or starting the
NTP auto-sync. This guarantees the binding exists before any plugin
channel call, regardless of the `unawaited`/`runApp()` scheduling order.
No change needed to `_autoSyncNtpAtStartup` itself or to
`NtpSyncController`/`sharedPreferencesProvider`.

## Out of scope

- `_autoSyncNtpAtStartup`'s `on Exception catch` not covering `Error`
  subtypes like `FlutterError` — worth hardening separately, but this fix
  removes the only known way that path currently throws one.
- Making `sharedPreferencesProvider` retry after a failure instead of
  caching the error forever — not needed once the root race is gone, and
  a larger change than this bug warrants.

## Verification

- `dart format`
- `flutter analyze`
- `flutter test`
- Debug APK build + manual test on BlueStacks: cold-start the app, confirm
  no "Binding has not yet been initialized" error in `logcat`, then verify
  completion time setting, stopwatch start, and timer +30s/+1min all work.
