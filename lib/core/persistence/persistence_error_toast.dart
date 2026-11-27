import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:material_ui/material_ui.dart';
import 'package:session_timer/features/completion/completion_time_controller.dart';
import 'package:session_timer/features/flash/flash_points_controller.dart';
import 'package:session_timer/features/schedule/session_event_controller.dart';
import 'package:session_timer/features/session_plan/session_plan_controller.dart';
import 'package:session_timer/features/stopwatch/stopwatch_controller.dart';
import 'package:session_timer/features/targets/time_targets_controller.dart';
import 'package:session_timer/features/timer/timer_controller.dart';

const saveFailedMessage = '保存できませんでした。もう一度お試しください';
const loadFailedMessage = '保存済みのデータを読み込めませんでした';

const _toastDuration = Duration(seconds: 4);

/// Tells the user when a stored value could not be saved or loaded.
///
/// The persisted controllers report such a failure only through their state
/// (`AsyncError`), and screens read just the value, which keeps showing the
/// previous one: without this, an edit that was not saved looks like it
/// silently did nothing.
///
/// Mounted once as `MaterialApp.builder`, so the message is drawn above the
/// navigator — and with it above modal sheets and dialogs, where a
/// `SnackBar` (which belongs to a `Scaffold` under the navigator) would be
/// hidden behind the barrier. The settings sheet, where flash points are
/// edited, is exactly such a place.
class PersistenceErrorToast extends ConsumerStatefulWidget {
  const PersistenceErrorToast({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PersistenceErrorToast> createState() =>
      _PersistenceErrorToastState();
}

class _PersistenceErrorToastState extends ConsumerState<PersistenceErrorToast> {
  String? _message;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _show(String message) {
    _hideTimer?.cancel();
    setState(() => _message = message);
    _hideTimer = Timer(_toastDuration, _hide);
  }

  void _hide() {
    _hideTimer?.cancel();
    if (mounted) setState(() => _message = null);
  }

  void _listen<T>(ProviderListenable<AsyncValue<T>> provider) {
    ref.listen<AsyncValue<T>>(provider, (previous, next) {
      // Only a settled failure. While the framework retries a failed first
      // load the state is `AsyncLoading` carrying the error, and a retry may
      // still succeed. The same error seen again (a rebuild that keeps it)
      // is not a new failure.
      if (next is! AsyncError<T> || next.isLoading) return;
      if (identical(previous?.error, next.error)) return;
      // A failed save keeps the previous value; a failed first load has
      // none.
      _show(next.hasValue ? saveFailedMessage : loadFailedMessage);
    });
  }

  @override
  Widget build(BuildContext context) {
    _listen(timeTargetsControllerProvider);
    _listen(sessionEventControllerProvider);
    _listen(sessionPlanControllerProvider);
    _listen(flashPointsControllerProvider);
    _listen(stopwatchControllerProvider);
    _listen(timerControllerProvider);
    _listen(completionTimeControllerProvider);

    final message = _message;
    return Stack(
      children: [
        widget.child,
        if (message != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(
              child: Material(
                key: const Key('persistenceErrorToast'),
                color: Theme.of(context).colorScheme.inverseSurface,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: _hide,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      message,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onInverseSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
