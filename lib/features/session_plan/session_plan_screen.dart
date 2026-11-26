import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:session_timer/core/theme/session_timer_theme.dart';
import 'package:session_timer/features/completion/completion_time_controller.dart';
import 'package:session_timer/features/session_plan/current_session_resolution.dart';
import 'package:session_timer/features/session_plan/session_plan_controller.dart';
import 'package:session_timer/features/session_plan/session_plan_entry.dart';
import 'package:session_timer/features/targets/time_targets_controller.dart';

/// `SessionTimerTextStyles.label` is a small caption meant to sit alongside
/// a large number elsewhere in the app — on this screen it would be the
/// only text in each row, so rows instead match `SessionScheduleScreen`'s
/// `DataTable` cells, which inherit this same theme style (size from
/// Material 3's default, color overridden to white app-wide).
TextStyle _rowTextStyle(BuildContext context) =>
    Theme.of(context).textTheme.bodyMedium!;

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
    return FilledButton(
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
    await _applyTimes(
      ref,
      completionTarget: resolution.completionTarget,
      autoTargetStart: resolution.autoTargetStart,
      autoTargetTitle: '次のセッション開始',
    );
    if (!context.mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('現在のセッションを設定しました')));
  }
}

/// Sets 完了時刻 to [completionTarget] and the single auto-managed 指定時刻
/// to [autoTargetStart] (or removes it when `null`) — shared by "現在の
/// セッションを設定" and each row's own 適用 button, so both write the same
/// two places.
Future<void> _applyTimes(
  WidgetRef ref, {
  required DateTime completionTarget,
  required DateTime? autoTargetStart,
  required String autoTargetTitle,
}) async {
  // Both notifiers are read before the first await: if the screen is left
  // mid-write, the second write must still happen (the providers outlive
  // the widget), or 完了時刻 and 指定時刻 would end up describing different
  // sessions. `ref` itself can't be used after the widget is gone.
  final completion = ref.read(completionTimeControllerProvider.notifier);
  final targets = ref.read(timeTargetsControllerProvider.notifier);
  await completion.setTarget(completionTarget);
  await (autoTargetStart != null
      ? targets.upsertTarget(
          autoSessionTargetId,
          autoTargetStart,
          title: autoTargetTitle,
        )
      : targets.removeTarget(autoSessionTargetId));
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});

  final SessionPlanEntry session;

  @override
  Widget build(BuildContext context) {
    // A Row lays its two children side by side with no geometric overlap,
    // unlike the Stack/Positioned layout this replaced — that one let the
    // whole-row tap-to-edit region and the close button's own tap region
    // both claim the same pixels, so tapping the button also opened the
    // edit dialog (Stack hit-testing collects every overlapping child, not
    // just the topmost one).
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Expanded(child: _EditSessionLabel(session: session)),
            _ApplySessionButton(session: session),
            _RemoveSessionButton(session: session),
          ],
        ),
      ),
    );
  }
}

class _EditSessionLabel extends ConsumerWidget {
  const _EditSessionLabel({required this.session});

  final SessionPlanEntry session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _editSession(context, ref),
      child: Center(
        child: Text(
          '${session.startLabel}〜${session.endLabel}',
          style: _rowTextStyle(context),
        ),
      ),
    );
  }

  Future<void> _editSession(BuildContext context, WidgetRef ref) async {
    final pickedStart = await showTimePicker(
      context: context,
      initialTime: _timeOfDay(session.startMinutes),
    );
    if (pickedStart == null || !context.mounted) return;
    final startMinutes = _minutesOf(pickedStart);
    final durationMinutes = await _promptSessionDuration(
      context,
      startMinutes: startMinutes,
      initialEndMinutes: session.endMinutes,
    );
    if (durationMinutes == null || !context.mounted) return;
    await ref
        .read(sessionPlanControllerProvider.notifier)
        .updateSession(
          session.id,
          startMinutes: startMinutes,
          durationMinutes: durationMinutes,
        );
  }
}

/// Applies this one session — whichever it is, not just the current one —
/// to 完了時刻 and 指定時刻 using [resolveSessionOccurrence]'s rules: an
/// upcoming session applies as is, one in progress applies with its start
/// already past (so the remaining time reads negative), and one that has
/// ended applies to tomorrow.
class _ApplySessionButton extends ConsumerWidget {
  const _ApplySessionButton({required this.session});

  final SessionPlanEntry session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton(
      key: Key('applySession_${session.id}'),
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      onPressed: () => _apply(context, ref),
      child: const Text('適用'),
    );
  }

  Future<void> _apply(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final occurrence = resolveSessionOccurrence(session, DateTime.now());
    await _applyTimes(
      ref,
      completionTarget: occurrence.end,
      autoTargetStart: occurrence.start,
      autoTargetTitle: 'セッション開始',
    );
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('${session.startLabel}〜${session.endLabel} を適用しました'),
      ),
    );
  }
}

class _RemoveSessionButton extends ConsumerWidget {
  const _RemoveSessionButton({required this.session});

  final SessionPlanEntry session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      key: Key('removeSession_${session.id}'),
      tooltip: 'このセッションを削除',
      icon: const Icon(Icons.close, color: SessionTimerColors.muted, size: 16),
      onPressed: () => ref
          .read(sessionPlanControllerProvider.notifier)
          .removeSession(session.id),
    );
  }
}

class _AddSessionRow extends ConsumerWidget {
  const _AddSessionRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _addSession(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text('＋ セッションを追加', style: _rowTextStyle(context)),
      ),
    );
  }

  Future<void> _addSession(BuildContext context, WidgetRef ref) async {
    final pickedStart = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(DateTime.now()),
    );
    if (pickedStart == null || !context.mounted) return;
    final startMinutes = _minutesOf(pickedStart);
    final durationMinutes = await _promptSessionDuration(
      context,
      startMinutes: startMinutes,
    );
    if (durationMinutes == null || !context.mounted) return;
    await ref
        .read(sessionPlanControllerProvider.notifier)
        .addSession(
          startMinutes: startMinutes,
          durationMinutes: durationMinutes,
        );
  }
}

int _minutesOf(TimeOfDay time) => time.hour * 60 + time.minute;

TimeOfDay _timeOfDay(int minutes) =>
    TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

enum _EndInputMode { duration, exact }

/// Asks how to specify a session's end — a duration (default 3.5h) or an
/// exact end time — then runs the matching sub-dialog. Returns the session's
/// length in minutes, or `null` if the user backs out at any step.
Future<int?> _promptSessionDuration(
  BuildContext context, {
  required int startMinutes,
  int? initialEndMinutes,
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
      ? _promptDurationMinutes(context)
      : _promptExactEndDuration(
          context,
          startMinutes: startMinutes,
          initialEndMinutes: initialEndMinutes,
        );
}

/// Returns the entered length in minutes, or `null` if cancelled or not a
/// positive length of at most 24 hours (a session repeats daily, so it can't
/// be longer than a day) — in the latter case after telling the user why.
Future<int?> _promptDurationMinutes(BuildContext context) async {
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
  if (hours == null) return null;
  // Range-check before rounding: NaN/Infinity (or a product that overflows
  // to Infinity) would make `.round()` throw. NaN fails every comparison.
  final minutes = hours > 0 && hours <= 24 ? (hours * 60).round() : 0;
  if (minutes > 0 && minutes <= minutesPerDay) return minutes;
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('所要時間は0より大きく24時間以内で入力してください')),
    );
  }
  return null;
}

/// Asks for an end time of day and converts it to a length: the time from
/// [startMinutes] to the next occurrence of that time (so an end earlier
/// than the start runs past midnight, and an identical time is a full day).
Future<int?> _promptExactEndDuration(
  BuildContext context, {
  required int startMinutes,
  int? initialEndMinutes,
}) async {
  final initialEnd =
      initialEndMinutes ??
      (startMinutes + defaultSessionDuration.inMinutes) % minutesPerDay;
  final picked = await showTimePicker(
    context: context,
    initialTime: _timeOfDay(initialEnd),
  );
  if (picked == null) return null;
  final difference = (_minutesOf(picked) - startMinutes) % minutesPerDay;
  return difference == 0 ? minutesPerDay : difference;
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
