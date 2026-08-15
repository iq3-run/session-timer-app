import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/clock/ntp_sync_controller.dart';
import 'package:session_timer/features/completion/completion_time_controller.dart';
import 'package:session_timer/features/home_widget/home_widget_sync_service.dart';
import 'package:session_timer/features/home_widget/next_time_target.dart';
import 'package:session_timer/features/stopwatch/stopwatch_controller.dart';
import 'package:session_timer/features/stopwatch/stopwatch_state.dart';
import 'package:session_timer/features/targets/time_target.dart';

/// Mounted once at the app root, alongside `NotificationScheduler`. Pushes
/// stopwatch/next-target/completion state to the Android home screen
/// widgets whenever it changes, plus once at startup so a widget already on
/// the home screen reflects whatever state exists by the time this widget
/// mounts. Kept as a widget rather than a `Notifier` for the same reason as
/// `NotificationScheduler`: the sync work is async and shouldn't run inside
/// a provider's synchronous `build()`.
class HomeWidgetScheduler extends ConsumerStatefulWidget {
  const HomeWidgetScheduler({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<HomeWidgetScheduler> createState() =>
      _HomeWidgetSchedulerState();
}

class _HomeWidgetSchedulerState extends ConsumerState<HomeWidgetScheduler> {
  @override
  void initState() {
    super.initState();
    unawaited(_syncAll(ref.read(ntpOffsetMsProvider)));
  }

  @override
  Widget build(BuildContext context) {
    _listenForChanges();
    return widget.child;
  }

  void _listenForChanges() {
    ref.listen(stopwatchControllerProvider, (previous, next) {
      final value = next.value;
      if (value == null) return;
      unawaited(_syncStopwatch(value, ref.read(ntpOffsetMsProvider)));
    });
    ref.listen(nextTimeTargetProvider, (previous, next) {
      unawaited(_syncNextTarget(next, ref.read(ntpOffsetMsProvider)));
    });
    ref.listen(completionTimeControllerProvider, (previous, next) {
      unawaited(
        _syncCompletion(next.value?.targetTime, ref.read(ntpOffsetMsProvider)),
      );
    });
    // The NTP offset itself changing (a resync) means every already-synced
    // widget's Chronometer base is now stale relative to the app's
    // corrected clock, even though the underlying epoch values didn't
    // change — re-push all three rather than waiting for their own state to
    // change again.
    ref.listen(ntpOffsetMsProvider, (previous, next) {
      unawaited(_syncAll(next));
    });
  }

  Future<void> _syncAll(int ntpOffsetMs) => Future.wait([
    _syncStopwatch(ref.read(stopwatchControllerProvider).value, ntpOffsetMs),
    _syncNextTarget(ref.read(nextTimeTargetProvider), ntpOffsetMs),
    _syncCompletion(
      ref.read(completionTimeControllerProvider).value?.targetTime,
      ntpOffsetMs,
    ),
  ]);

  /// A sync failure (e.g. the platform channel not ready yet) is a
  /// best-effort background feature failing, not something the rest of the
  /// UI depends on — same tolerance as `NotificationScheduler`.
  Future<void> _syncStopwatch(StopwatchState? value, int ntpOffsetMs) async {
    if (value == null) return;
    try {
      await ref
          .read(homeWidgetSyncServiceProvider)
          .syncStopwatch(
            value,
            ntpOffsetMs,
          );
    } on Exception catch (e) {
      debugPrint('HomeWidgetScheduler: failed to sync stopwatch: $e');
    }
  }

  Future<void> _syncNextTarget(TimeTarget? target, int ntpOffsetMs) async {
    try {
      await ref
          .read(homeWidgetSyncServiceProvider)
          .syncNextTarget(target, ntpOffsetMs);
    } on Exception catch (e) {
      debugPrint('HomeWidgetScheduler: failed to sync next target: $e');
    }
  }

  Future<void> _syncCompletion(DateTime? target, int ntpOffsetMs) async {
    try {
      await ref
          .read(homeWidgetSyncServiceProvider)
          .syncCompletion(target, ntpOffsetMs);
    } on Exception catch (e) {
      debugPrint('HomeWidgetScheduler: failed to sync completion: $e');
    }
  }
}
