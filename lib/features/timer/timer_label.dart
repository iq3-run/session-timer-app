import 'package:intl/intl.dart';
import 'package:session_timer/features/timer/timer_state.dart';

/// The "タイマー"/"連動タイマー" label shown above the countdown value, with
/// the end time appended while running (e.g. "タイマー(21:45まで)") so it
/// stays visible without needing a separate display. "（超過）" is inserted
/// between the mode name and the end time once overdue.
String timerLabel(TimerState? state, DateTime now) {
  if (state == null || !state.isRunning) return 'タイマー';
  final modeLabel = state.mode == TimerMode.linked ? '連動タイマー' : 'タイマー';
  final overdueSuffix = state.isOverdueAt(now) ? '（超過）' : '';
  final endTime = DateFormat('H:mm').format(state.targetTime!);
  return '$modeLabel$overdueSuffix($endTimeまで)';
}
