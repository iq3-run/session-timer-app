/// Formats [diff] as `H:MM:SS` (hours omitted when zero), matching the HTML
/// prototype's `fmtHMS`. A negative [diff] is prefixed with `-`.
String formatCountdown(Duration diff) {
  final sign = diff.isNegative ? '-' : '';
  final abs = diff.abs();
  final hours = abs.inHours;
  final minutes = abs.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = abs.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$sign${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
  }
  return '$sign$minutes:$seconds';
}
