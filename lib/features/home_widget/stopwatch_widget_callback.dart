import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/features/home_widget/home_widget_gateway.dart';
import 'package:session_timer/features/home_widget/home_widget_sync_service.dart';
import 'package:session_timer/features/stopwatch/stopwatch_controller.dart';
import 'package:session_timer/features/timer/timer_controller.dart';

/// Called by `home_widget`'s background Dart isolate when the stopwatch
/// widget's toggle/reset button is tapped (see `StopwatchWidgetProvider.kt`
/// and the `HomeWidget.registerInteractivityCallback` call in `main.dart`).
/// That isolate is a separate `FlutterEngine` from the app's own — it has no
/// access to the foreground `ProviderContainer`, so this builds and disposes
/// a throwaway one for the single call.
///
/// Must stay a top-level function annotated with `vm:entry-point`: the
/// plugin resolves it via `PluginUtilities.getCallbackHandle`, which needs a
/// stable handle that survives AOT tree-shaking in release builds.
@pragma('vm:entry-point')
Future<void> stopwatchWidgetBackgroundCallback(Uri? uri) async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  try {
    await _applyAction(container, uri);
    await _pushUpdatedStateToWidget(container);
  } finally {
    container.dispose();
  }
}

Future<void> _applyAction(ProviderContainer container, Uri? uri) async {
  final notifier = container.read(stopwatchControllerProvider.notifier);
  // For "homewidget://stopwatch/toggle", the action is the first *path*
  // segment ("toggle"), not `uri.host` (which is "stopwatch" — the
  // authority component of this URI, not the action).
  final action = uri?.pathSegments.isNotEmpty ?? false
      ? uri!.pathSegments.first
      : null;
  switch (action) {
    case 'toggle':
      await notifier.toggle();
    case 'reset':
      await notifier.reset();
  }
}

/// Pushes the just-mutated state straight to the widget's own data store and
/// redraws it immediately, rather than waiting for the app to next come to
/// the foreground and have `HomeWidgetScheduler` do it.
///
/// The NTP offset is read back from the widget's own store (already kept
/// current by `HomeWidgetScheduler` while the app runs) instead of through
/// `ntpOffsetMsProvider` — that provider's backing `NtpSyncController`
/// starts every fresh isolate at an unsynced `offsetMs: 0` and deliberately
/// never fetches over the network on `build()`, so reading it here would
/// silently drop whatever offset the foreground app last resolved.
///
/// Also pushes the timer's state: `reset()` cascades into
/// `TimerController.reset()` too (see `StopwatchController.reset`'s own
/// doc comment), so a timer widget left stale by that cascade needs
/// redrawing here as well, not just this stopwatch widget.
Future<void> _pushUpdatedStateToWidget(ProviderContainer container) async {
  final stopwatchState = await container.read(
    stopwatchControllerProvider.future,
  );
  final timerState = await container.read(timerControllerProvider.future);
  final gateway = container.read(homeWidgetGatewayProvider);
  final rawOffsetMs = await gateway.getWidgetData(ntpOffsetMsKey);
  final ntpOffsetMs = int.tryParse(rawOffsetMs ?? '') ?? 0;
  final syncService = container.read(homeWidgetSyncServiceProvider);
  await syncService.syncStopwatch(stopwatchState, ntpOffsetMs);
  await syncService.syncTimer(timerState, ntpOffsetMs);
}
