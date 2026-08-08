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

/// Formats [elapsed] as `MM:SS.d` (hours included when present) with a
/// tenths-of-a-second digit, matching the HTML prototype's `fmtHMSTenths`.
/// Used only by the stopwatch, whose elapsed time never goes negative.
String formatElapsedTenths(Duration elapsed) {
  final hours = elapsed.inHours;
  final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
  final tenths = elapsed.inMilliseconds.remainder(1000) ~/ 100;
  final core = hours > 0
      ? '${hours.toString().padLeft(2, '0')}:$minutes:$seconds'
      : '$minutes:$seconds';
  return '$core.$tenths';
}
