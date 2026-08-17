import 'package:session_timer/features/home_widget/stopwatch_widget_callback.dart';
import 'package:session_timer/features/home_widget/timer_widget_callback.dart';

/// The single entry point `home_widget` invokes from its background isolate
/// for every widget button tap in this app.
///
/// `HomeWidget.registerInteractivityCallback` only remembers one callback
/// handle at a time on the native side — registering a second callback
/// (e.g. one per widget) overwrites the first rather than adding to it. This
/// dispatches by `uri.host` (`"stopwatch"`/`"timer"`, the widget type) to the
/// per-widget handler instead, so `main.dart` only ever registers this one
/// function.
@pragma('vm:entry-point')
Future<void> homeWidgetBackgroundCallback(Uri? uri) async {
  switch (uri?.host) {
    case 'stopwatch':
      await stopwatchWidgetBackgroundCallback(uri);
    case 'timer':
      await timerWidgetBackgroundCallback(uri);
    default:
      // An unrecognized (or null/hostless) URI is a deliberate no-op —
      // matches each per-widget handler's own unrecognized-action handling.
      break;
  }
}
