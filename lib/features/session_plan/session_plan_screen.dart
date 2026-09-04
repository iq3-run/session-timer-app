import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:session_timer/core/clock/time_of_day_resolver.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/completion/completion_time_controller.dart';
import 'package:session_timer/features/session_plan/current_session_resolution.dart';
import 'package:session_timer/features/session_plan/session_plan_controller.dart';
import 'package:session_timer/features/session_plan/session_plan_entry.dart';
import 'package:session_timer/features/targets/time_targets_controller.dart';

/// `SessionTimerTextStyles.label` (12px) is meant as a small caption
/// alongside a large number elsewhere in the app — on this screen it would
/// be the only text in each row, so rows use this larger size instead.
const _rowTextStyle = TextStyle(color: SessionTimerColors.muted, fontSize: 18);

/// Registers a plan of sessions (start + end time each) and lets the user
/// derive 完了時刻/指定時刻 from whichever one is "current" right now. The
/// list itself persists until removed by hand — it is not tied to, or
/// reset by, a particular calendar day.
class SessionPlanScreen extends ConsumerWidget {
  const SessionPlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionPlanControllerProvider).value ?? const [];
    return Scaffold(
      backgroundColor: SessionTimerColors.background,
      appBar: AppBar(
        backgroundColor: SessionTimerColors.background,
        foregroundColor: SessionTimerColors.white,
        title: const Text('セッションの流れ'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _SetCurrentSessionButton(sessions: sessions),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [
                    for (final session in sessions)
                      _SessionRow(session: session),
                    const _AddSessionRow(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetCurrentSessionButton extends ConsumerWidget {
  const _SetCurrentSessionButton({required this.sessions});

  final List<SessionPlanEntry> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton(
      onPressed: () => _apply(context, ref),
      child: const Text('現在のセッションを設定'),
    );
  }

  Future<void> _apply(BuildContext context, WidgetRef ref) async {
    final resolution = resolveCurrentSession(sessions, DateTime.now());
    final messenger = ScaffoldMessenger.of(context);
    if (resolution == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('該当するセッションがありません')),
      );
      return;
    }
    await ref
        .read(completionTimeControllerProvider.notifier)
        .setTarget(resolution.completionTarget);
    if (!context.mounted) return;
    await _applyAutoTarget(ref, resolution.autoTargetStart);
    if (!context.mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('現在のセッションを設定しました')));
  }

  Future<void> _applyAutoTarget(WidgetRef ref, DateTime? autoTargetStart) {
    final targets = ref.read(timeTargetsControllerProvider.notifier);
    return autoTargetStart != null
        ? targets.upsertTarget(
            autoSessionTargetId,
            autoTargetStart,
            title: '次のセッション開始',
          )
        : targets.removeTarget(autoSessionTargetId);
  }
}

class _SessionRow extends ConsumerWidget {
  const _SessionRow({required this.session});

  final SessionPlanEntry session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final format = DateFormat('H:mm');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _editSession(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Stack(
          children: [
            Center(
              child: Text(
                '${format.format(session.startTime)}〜'
                '${format.format(session.endTime)}',
                style: _rowTextStyle,
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                tooltip: 'このセッションを削除',
                icon: const Icon(
                  Icons.close,
                  color: SessionTimerColors.muted,
                  size: 16,
                ),
                onPressed: () => ref
                    .read(sessionPlanControllerProvider.notifier)
                    .removeSession(session.id),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editSession(BuildContext context, WidgetRef ref) async {
    final pickedStart = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(session.startTime),
    );
    if (pickedStart == null || !context.mounted) return;
    final start = resolveNextOccurrence(pickedStart, DateTime.now());
    final end = await _promptSessionEnd(
      context,
      start: start,
      initialEnd: session.endTime,
    );
    if (end == null || !context.mounted) return;
    await ref
        .read(sessionPlanControllerProvider.notifier)
        .updateSession(session.id, start, end);
  }
}

class _AddSessionRow extends ConsumerWidget {
  const _AddSessionRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _addSession(context, ref),
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text('＋ セッションを追加', style: _rowTextStyle),
      ),
    );
  }

  Future<void> _addSession(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final pickedStart = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (pickedStart == null || !context.mounted) return;
    final start = resolveNextOccurrence(pickedStart, now);
    final end = await _promptSessionEnd(context, start: start);
    if (end == null || !context.mounted) return;
    await ref
        .read(sessionPlanControllerProvider.notifier)
        .addSession(start, end);
  }
}

enum _EndInputMode { duration, exact }

/// Asks how to specify a session's end — a duration from [start] (default
/// 3.5h) or an exact end time — then runs the matching sub-dialog. Returns
/// `null` if the user backs out at any step.
Future<DateTime?> _promptSessionEnd(
  BuildContext context, {
  required DateTime start,
  DateTime? initialEnd,
}) async {
  final mode = await showDialog<_EndInputMode>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('終了時刻の指定方法'),
      children: [
        SimpleDialogOption(
          onPressed: () =>
              Navigator.of(dialogContext).pop(_EndInputMode.duration),
          child: const Text('所要時間で指定（デフォルト3.5時間）'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(dialogContext).pop(_EndInputMode.exact),
          child: const Text('終了時刻を指定'),
        ),
      ],
    ),
  );
  if (mode == null || !context.mounted) return null;
  return mode == _EndInputMode.duration
      ? _promptDurationEnd(context, start: start)
      : _promptExactEnd(context, start: start, initialEnd: initialEnd);
}

Future<DateTime?> _promptDurationEnd(
  BuildContext context, {
  required DateTime start,
}) async {
  final defaultHours = defaultSessionDuration.inMinutes / 60;
  final controller = TextEditingController(text: _formatHours(defaultHours));
  final double? hours;
  try {
    hours = await showDialog<double>(
      context: context,
      builder: (dialogContext) => _DurationHoursDialog(controller: controller),
    );
  } finally {
    controller.dispose();
  }
  if (hours == null || hours <= 0) return null;
  return start.add(Duration(minutes: (hours * 60).round()));
}

Future<DateTime?> _promptExactEnd(
  BuildContext context, {
  required DateTime start,
  DateTime? initialEnd,
}) async {
  final initial = initialEnd ?? start.add(defaultSessionDuration);
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  // start (not DateTime.now()) is the reference instant: resolveNextOccurrence
  // returns the next time that time-of-day occurs after it, guaranteeing the
  // end always lands after the chosen start rather than after "now".
  return picked == null ? null : resolveNextOccurrence(picked, start);
}

String _formatHours(double hours) =>
    hours == hours.roundToDouble() ? hours.toStringAsFixed(0) : '$hours';

class _DurationHoursDialog extends StatelessWidget {
  const _DurationHoursDialog({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('所要時間（時間単位）'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(hintText: '例: 3.5'),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(double.tryParse(controller.text)),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
