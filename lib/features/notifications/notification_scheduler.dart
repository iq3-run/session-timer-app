import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class _NotificationSchedulerState extends ConsumerState<NotificationScheduler> {
  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
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
    return widget.child;
  }

  Future<void> _reschedule(List<FlashEvent> events) async {
    try {
      await ref.read(notificationServiceProvider).rescheduleAll(events);
    } on Exception catch (e) {
      debugPrint('NotificationScheduler: failed to reschedule: $e');
    }
  }
}
