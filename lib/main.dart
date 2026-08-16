import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:session_timer/app.dart';
import 'package:session_timer/core/clock/ntp_sync_controller.dart';
import 'package:session_timer/features/home_widget/stopwatch_widget_callback.dart';

void main() {
  // runApp() normally calls WidgetsFlutterBinding.ensureInitialized() as its
  // first line — but the unawaited NTP auto-sync below can hit a platform
  // channel (SharedPreferences) before runApp() executes, so init explicitly.
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  unawaited(_autoSyncNtpAtStartup(container));
  unawaited(_registerStopwatchWidgetCallback());
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const SessionTimerApp(),
    ),
  );
}

/// Tells the `home_widget` plugin which Dart function to invoke from its
/// background isolate when the stopwatch widget's toggle/reset button is
/// tapped. Must run at every app launch — the native side only remembers
/// the callback handle, not the callback itself, and that handle can change
/// across app updates/reinstalls.
///
/// Best-effort like the NTP sync below: this app doesn't support the
/// stopwatch widget on iOS, so a platform-channel failure here is expected
/// there and must not block startup.
Future<void> _registerStopwatchWidgetCallback() async {
  try {
    await HomeWidget.registerInteractivityCallback(
      stopwatchWidgetBackgroundCallback,
    );
  } on Exception {
    // Fall through silently — the widget's buttons simply won't do
    // anything until the next successful registration.
  }
}

/// One-shot NTP sync attempt at real app launch. Deliberately lives here,
/// not in `NtpSyncController.build()` or a widget mounted in
/// `app.dart` — those run on every `pumpWidget` in tests too, which would
/// open a real UDP socket. `main()` is never invoked by widget tests, so
/// this stays the only path that actually touches the network at startup.
///
/// Best-effort: `NtpSyncController.syncNow` already turns an NTP fetch
/// failure into a normal `failed` state, but a lower-level failure (e.g.
/// reading `SharedPreferences` itself) must not become an unhandled async
/// error — the app already falls back to running on device time either
/// way, so a startup sync attempt gone wrong should never crash the app.
Future<void> _autoSyncNtpAtStartup(ProviderContainer container) async {
  try {
    final initial = await container.read(ntpSyncControllerProvider.future);
    await container
        .read(ntpSyncControllerProvider.notifier)
        .syncNow(initial.serverHost);
  } on Exception {
    // Fall through silently — the app already runs on device time.
  }
}
