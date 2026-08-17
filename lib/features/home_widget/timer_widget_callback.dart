import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/features/home_widget/home_widget_gateway.dart';
import 'package:session_timer/features/home_widget/home_widget_sync_service.dart';
import 'package:session_timer/features/stopwatch/stopwatch_controller.dart';
import 'package:session_timer/features/timer/timer_controller.dart';

/// Mirrors `timer_section.dart`'s `_defaultSetupDuration` — the widget's
/// "start" button can't open the mode/duration picker, so it always starts
/// a fresh 通常タイマー of this length.
const _defaultQuickStartDuration = Duration(minutes: 5);

/// Called by `home_widget`'s background Dart isolate when the operable
/// timer widget's start/+30s/+1min/reset button is tapped (see
/// `TimerControlWidgetProvider.kt` and `home_widget_background_callback.dart`,
/// which is what's actually registered with the plugin). Mirrors
/// `stopwatch_widget_callback.dart` — see that file for why a throwaway
/// `ProviderContainer` is built and disposed per call.
@pragma('vm:entry-point')
Future<void> timerWidgetBackgroundCallback(Uri? uri) async {
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
  final notifier = container.read(timerControllerProvider.notifier);
  // For "homewidget://timer/start", the action is the first *path* segment
  // ("start"), not `uri.host` (which is "timer" — the widget type, already
  // consumed by home_widget_background_callback.dart's dispatch).
  final action = uri?.pathSegments.isNotEmpty ?? false
      ? uri!.pathSegments.first
      : null;
  switch (action) {
    case 'start':
      await notifier.quickStart(_defaultQuickStartDuration);
    case 'add30':
      await notifier.addTime(const Duration(seconds: 30));
    case 'add60':
      await notifier.addTime(const Duration(minutes: 1));
    case 'reset':
      await notifier.reset();
  }
}

/// See `stopwatch_widget_callback.dart`'s equivalent for why the NTP offset
/// is read back from the widget's own store rather than `ntpOffsetMsProvider`.
///
/// Also pushes the stopwatch's state: `quickStart` and a fresh (not
/// currently running) `addTime` both auto-start the stopwatch if it isn't
/// already running (see `TimerController._autoStartStopwatchIfNeeded`), so a
/// timer-widget action can change the stopwatch widget too.
Future<void> _pushUpdatedStateToWidget(ProviderContainer container) async {
  final timerState = await container.read(timerControllerProvider.future);
  final stopwatchState = await container.read(
    stopwatchControllerProvider.future,
  );
  final gateway = container.read(homeWidgetGatewayProvider);
  final rawOffsetMs = await gateway.getWidgetData(ntpOffsetMsKey);
  final ntpOffsetMs = int.tryParse(rawOffsetMs ?? '') ?? 0;
  final syncService = container.read(homeWidgetSyncServiceProvider);
  await syncService.syncTimer(timerState, ntpOffsetMs);
  await syncService.syncStopwatch(stopwatchState, ntpOffsetMs);
}
