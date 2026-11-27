import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/clock/ntp_sync_controller.dart';
import 'package:session_timer/features/flash/flash_event.dart';
import 'package:session_timer/features/notifications/notification_event_source.dart';
import 'package:session_timer/features/notifications/notification_service.dart';

/// Mounted once at the app root. Owns the notification plugin's lifecycle:
/// initializes it and requests permission on startup, then re-schedules all
/// future notifications whenever the flash-point candidates change. Kept as
/// a widget rather than a `Notifier` because the scheduling work is async
/// and shouldn't run inside a provider's synchronous `build()`.
class NotificationScheduler extends ConsumerStatefulWidget {
  const NotificationScheduler({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<NotificationScheduler> createState() =>
      _NotificationSchedulerState();
}

class _NotificationSchedulerState extends ConsumerState<NotificationScheduler>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A flash's notification is cancelled when its flash starts on screen
  /// (#95). If the app then leaves the foreground before the flash ends
  /// (Home pressed, screen off), nobody sees the rest of it — schedule the
  /// notifications back so the moment still notifies.
  ///
  /// `inactive` is ignored: it also happens with the app still on screen
  /// (notification shade, a system dialog), and rescheduling then would
  /// bring back a notification for a flash that is being watched. Going to
  /// the background passes through `hidden` and `paused`; only the first one
  /// has anything to restore.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive) {
      return;
    }
    if (ref.read(notificationServiceProvider).clearSuppressed()) {
      _restorePending = true;
    }
    unawaited(_restoreIfPending());
  }

  /// Set once suppressed notifications were forgotten, and cleared only when
  /// the reschedule that brings them back has succeeded: if it fails (the
  /// plugin throws), the next trip to the background retries, instead of
  /// the notifications being lost for good.
  bool _restorePending = false;
  bool _restoring = false;

  Future<void> _restoreIfPending() async {
    // `hidden` and `paused` arrive back to back; one reschedule covers both.
    // A request that comes in while one is running is picked up by the loop:
    // the flag is cleared *before* each pass, so it can't wipe a newer one.
    if (_restoring) return;
    _restoring = true;
    try {
      while (_restorePending) {
        _restorePending = false;
        final ok = await _reschedule(
          ref.read(notificationCandidateEventsProvider),
        );
        if (!ok) {
          _restorePending = true; // retried on the next trip to background
          break;
        }
      }
    } finally {
      _restoring = false;
    }
  }

  /// A device without notification support (or a test environment without
  /// the plugin registered) shouldn't crash the app — this is a best-effort
  /// background feature, not something the rest of the UI depends on.
  Future<void> _bootstrap() async {
    final service = ref.read(notificationServiceProvider);
    try {
      await service.init();
      await service.requestPermissions();
      // `ref.listen` in build() only fires on a *change* to the candidate
      // list, not for its current value — schedule explicitly for whatever
      // it already is by the time init finishes, rather than relying on a
      // source provider happening to still be mid-load.
      await service.rescheduleAll(
        ref.read(notificationCandidateEventsProvider),
        ntpOffsetMs: ref.read(ntpOffsetMsProvider),
      );
    } on Exception catch (e) {
      debugPrint('NotificationScheduler: failed to initialize: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(notificationCandidateEventsProvider, (previous, next) {
      unawaited(_reschedule(next));
    });
    // The alarms are registered by the device clock, shifted by the offset:
    // the first sync lands a few seconds after launch, and a later one can
    // change it, so what is already registered has to move with it.
    ref.listen(ntpOffsetMsProvider, (previous, next) {
      unawaited(_reschedule(ref.read(notificationCandidateEventsProvider)));
    });
    return widget.child;
  }

  /// Whether the reschedule went through.
  Future<bool> _reschedule(List<FlashEvent> events) async {
    try {
      await ref
          .read(notificationServiceProvider)
          .rescheduleAll(events, ntpOffsetMs: ref.read(ntpOffsetMsProvider));
      return true;
    } on Object catch (e) {
      debugPrint('NotificationScheduler: failed to reschedule: $e');
      return false;
    }
  }
}
