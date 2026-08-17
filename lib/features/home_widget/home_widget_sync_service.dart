import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/features/home_widget/home_widget_gateway.dart';
import 'package:session_timer/features/stopwatch/stopwatch_state.dart';
import 'package:session_timer/features/targets/time_target.dart';
import 'package:session_timer/features/timer/timer_state.dart';

// Shared across all four synced widgets: each `AppWidgetProvider` reads
// this independently in its own `onUpdate`, so it's written alongside every
// sync call rather than once — a stale value on just one widget (from a
// missed write) would let that widget's Chronometer base drift out of sync
// with the app's NTP-corrected clock while the others stay correct.
const ntpOffsetMsKey = 'ntp_offset_ms';

const stopwatchAccumulatedMsKey = 'stopwatch_accumulated_ms';
const stopwatchRunningSinceEpochMsKey = 'stopwatch_running_since_epoch_ms';
const stopwatchWidgetAndroidName = 'StopwatchWidgetProvider';

const nextTargetEpochMsKey = 'next_target_epoch_ms';
const nextTargetWidgetAndroidName = 'NextTargetWidgetProvider';

const completionTargetEpochMsKey = 'completion_target_epoch_ms';
const completionWidgetAndroidName = 'CompletionCountdownWidgetProvider';

const timerTargetEpochMsKey = 'timer_target_epoch_ms';
const timerWidgetAndroidName = 'TimerWidgetProvider';

/// Pushes app state to the Android home screen widgets' own data store
/// (a `SharedPreferences` file separate from the app's own, owned by the
/// `home_widget` plugin) and asks each widget's `AppWidgetProvider` to
/// redraw. Each widget then free-runs its own `Chronometer` view natively —
/// this is only called when the underlying state actually changes, not on
/// every clock tick.
///
/// Every numeric value is sent through `saveWidgetData` as a [String], never
/// a Dart `int` directly. The plugin's method channel encodes a Dart `int`
/// as a platform Int32 or Int64 depending on its *magnitude* (Flutter's
/// standard codec, not a fixed Dart type), and the Android side stores
/// whichever it receives via `SharedPreferences.putInt`/`putLong`. A small
/// `accumulatedMs` (e.g. `0` right after a reset) round-trips as Int32, but
/// the same key later holds a multi-hour value that round-trips as Int64 —
/// so a native reader fixed on `getLong` would throw `ClassCastException`
/// against an entry that was actually stored as `Int`. Sending a String and
/// parsing it natively with `toLongOrNull()` sidesteps this entirely. `null`
/// is still passed through as-is (not the string `"null"`) so the plugin's
/// own null handling removes the key, matching "unset" on the native side.
class HomeWidgetSyncService {
  HomeWidgetSyncService(this._gateway);

  final HomeWidgetGateway _gateway;

  Future<void> syncStopwatch(StopwatchState state, int ntpOffsetMs) async {
    await _gateway.saveWidgetData(
      stopwatchAccumulatedMsKey,
      state.accumulatedMs.toString(),
    );
    await _gateway.saveWidgetData(
      stopwatchRunningSinceEpochMsKey,
      state.runningSinceEpochMs?.toString(),
    );
    await _gateway.saveWidgetData(ntpOffsetMsKey, ntpOffsetMs.toString());
    await _gateway.updateWidget(androidName: stopwatchWidgetAndroidName);
  }

  Future<void> syncNextTarget(TimeTarget? target, int ntpOffsetMs) async {
    await _gateway.saveWidgetData(
      nextTargetEpochMsKey,
      target?.epochMs.toString(),
    );
    await _gateway.saveWidgetData(ntpOffsetMsKey, ntpOffsetMs.toString());
    await _gateway.updateWidget(androidName: nextTargetWidgetAndroidName);
  }

  Future<void> syncCompletion(DateTime? target, int ntpOffsetMs) async {
    await _gateway.saveWidgetData(
      completionTargetEpochMsKey,
      target?.millisecondsSinceEpoch.toString(),
    );
    await _gateway.saveWidgetData(ntpOffsetMsKey, ntpOffsetMs.toString());
    await _gateway.updateWidget(androidName: completionWidgetAndroidName);
  }

  Future<void> syncTimer(TimerState? state, int ntpOffsetMs) async {
    await _gateway.saveWidgetData(
      timerTargetEpochMsKey,
      state?.targetEpochMs?.toString(),
    );
    await _gateway.saveWidgetData(ntpOffsetMsKey, ntpOffsetMs.toString());
    await _gateway.updateWidget(androidName: timerWidgetAndroidName);
  }
}

final homeWidgetSyncServiceProvider = Provider<HomeWidgetSyncService>(
  (ref) => HomeWidgetSyncService(ref.watch(homeWidgetGatewayProvider)),
);
