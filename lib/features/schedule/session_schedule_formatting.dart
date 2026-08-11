const _weekdayLabels = ['月', '火', '水', '木', '金', '土', '日'];

/// `M/D(曜)` — shared by the read-only schedule table and the settings
/// screen's add form / full event list.
String formatScheduleDate(DateTime date) =>
    '${date.month}/${date.day}(${_weekdayLabels[date.weekday - 1]})';
