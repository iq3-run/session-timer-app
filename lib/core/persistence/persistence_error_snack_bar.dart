import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:material_ui/material_ui.dart';
import 'package:session_timer/features/flash/flash_points_controller.dart';
import 'package:session_timer/features/schedule/session_event_controller.dart';
import 'package:session_timer/features/session_plan/session_plan_controller.dart';
import 'package:session_timer/features/stopwatch/stopwatch_controller.dart';
import 'package:session_timer/features/targets/time_targets_controller.dart';
import 'package:session_timer/features/timer/timer_controller.dart';

const saveFailedMessage = '保存できませんでした。もう一度お試しください';
const loadFailedMessage = '保存済みのデータを読み込めませんでした';

/// Tells the user when a stored value could not be saved or loaded.
///
/// The persisted controllers report such a failure only through their state
/// (`AsyncError`), and screens read just the value, which keeps showing the
/// previous list: without this, an edit that was not saved looks like it
/// silently did nothing. Mounted once below `MaterialApp`, so the message
/// shows on whichever screen is open.
class PersistenceErrorSnackBar extends ConsumerWidget {
  const PersistenceErrorSnackBar({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void listen<T>(ProviderListenable<AsyncValue<T>> provider) {
      ref.listen<AsyncValue<T>>(provider, (previous, next) {
        // A new failure, not the same error seen again while the provider
        // rebuilds.
        if (!next.hasError || identical(previous?.error, next.error)) return;
        // A failed save keeps the previous value; a failed first load has
        // none.
        _show(context, next.hasValue ? saveFailedMessage : loadFailedMessage);
      });
    }

    listen(timeTargetsControllerProvider);
    listen(sessionEventControllerProvider);
    listen(sessionPlanControllerProvider);
    listen(flashPointsControllerProvider);
    listen(stopwatchControllerProvider);
    listen(timerControllerProvider);
    return child;
  }

  void _show(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
