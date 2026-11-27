import 'package:material_ui/material_ui.dart';
import 'package:session_timer/features/session_plan/session_plan_controller.dart';
import 'package:session_timer/features/session_plan/session_plan_entry.dart';

int minutesOfTimeOfDay(TimeOfDay time) => time.hour * 60 + time.minute;

TimeOfDay timeOfDayFromMinutes(int minutes) =>
    TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

enum _EndInputMode { duration, exact }

/// Asks how to specify a session's end — a duration (default 3.5h) or an
/// exact end time — then runs the matching sub-dialog. Returns the session's
/// length in minutes, or `null` if the user backs out at any step.
Future<int?> promptSessionDuration(
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
    initialTime: timeOfDayFromMinutes(initialEnd),
  );
  if (picked == null) return null;
  final difference =
      (minutesOfTimeOfDay(picked) - startMinutes) % minutesPerDay;
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
