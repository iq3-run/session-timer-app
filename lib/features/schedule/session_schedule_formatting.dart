import 'package:session_timer/features/schedule/session_chain.dart';
import 'package:session_timer/features/schedule/session_event.dart';
import 'package:session_timer/features/schedule/session_gap_calculation.dart';

const _weekdayLabels = ['月', '火', '水', '木', '金', '土', '日'];

/// `M/D(曜)` — shared by the read-only schedule table and the settings
/// screen's add form / full event list.
String formatScheduleDate(DateTime date) =>
    '${date.month}/${date.day}(${_weekdayLabels[date.weekday - 1]})';

/// `Nd(MW)`, or `''` when [gap] is `null` (the read-only schedule table
/// leaves 週末間 blank for the first chain row, and 今日から blank for an
/// ongoing event and the synthetic 今日 row — see `session_chain.dart`).
String formatGap(GapResult? gap) =>
    gap == null ? '' : '${gap.days}日(${gap.weeks}W)';

/// A row's 週末間 cell. Usually [formatGap] of its single value; on the row
/// where the A and B schedules merge, one line per schedule
/// (`A:20日(3W)` / `B:13日(2W)`), since each is measured from its own
/// previous event.
String formatChainGap(ScheduleRow row) {
  if (row.trackChainGaps.isEmpty) return formatGap(row.chainGap);
  return row.trackChainGaps
      .map((g) => '${_trackLetter(g.track)}:${formatGap(g.gap)}')
      .join('\n');
}

String _trackLetter(SessionTrack track) => switch (track) {
  SessionTrack.a => 'A',
  SessionTrack.b => 'B',
  SessionTrack.common => '',
};
