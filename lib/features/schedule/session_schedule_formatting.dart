import 'package:session_timer/features/schedule/session_gap_calculation.dart';

const _weekdayLabels = ['月', '火', '水', '木', '金', '土', '日'];

/// `M/D(曜)` — shared by the read-only schedule table and the settings
/// screen's add form / full event list.
String formatScheduleDate(DateTime date) =>
    '${date.month}/${date.day}(${_weekdayLabels[date.weekday - 1]})';

/// `Nd(MW)`, or `''` when [gap] is `null` (the read-only schedule table
/// leaves 週末間/今日から blank for rows with no gap — see
/// `_todayGapFor`/chain-row logic in `session_chain.dart`).
String formatGap(GapResult? gap) =>
    gap == null ? '' : '${gap.days}日(${gap.weeks}W)';
