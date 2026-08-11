/// Days and weeks between two session boundaries.
class GapResult {
  const GapResult({required this.days, required this.weeks});

  final int days;
  final int weeks;
}

/// [fromEnd] is the last day of the earlier session (or "today" when one
/// endpoint is the current date); [toStart] is the first day of the later
/// one. Both must already be midnight-normalized dates.
///
/// days = (toStart − fromEnd) − 1: the span strictly between the two,
/// excluding both boundary days.
///
/// weeks = the number of Fridays strictly inside that span, plus one more
/// if [toStart] itself lands on a Friday — the user's rule counts a Friday
/// "arrived at" as a week crossed even though its date is outside the
/// exclusive day range.
GapResult calculateGap({required DateTime fromEnd, required DateTime toStart}) {
  // Arithmetic runs on UTC-anchored copies of the two calendar dates — a
  // `Duration`-based add/subtract or `.difference().inDays` on a local
  // DateTime can land a day off across a daylight-saving transition in
  // non-Japan timezones (this app's timezone follows the device). UTC has
  // no DST, so it's safe here; a date's weekday is unaffected by which
  // flavor represents it.
  final from = _utcDate(fromEnd);
  final to = _utcDate(toStart);
  final days = to.difference(from).inDays - 1;
  final rangeStart = from.add(const Duration(days: 1));
  final rangeEnd = to.subtract(const Duration(days: 1));
  final fridaysInRange = _countFridaysInRange(rangeStart, rangeEnd);
  final landsOnFriday = to.weekday == DateTime.friday ? 1 : 0;
  return GapResult(days: days, weeks: fridaysInRange + landsOnFriday);
}

DateTime _utcDate(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);

/// Counts Fridays in the inclusive date range [start, end]. Uses a
/// closed-form jump to the first Friday rather than iterating day-by-day,
/// since ranges here can span up to roughly a year.
int _countFridaysInRange(DateTime start, DateTime end) {
  if (end.isBefore(start)) return 0;
  final daysUntilFirstFriday = (DateTime.friday - start.weekday + 7) % 7;
  final firstFriday = start.add(Duration(days: daysUntilFirstFriday));
  if (firstFriday.isAfter(end)) return 0;
  final spanAfterFirstFriday = end.difference(firstFriday).inDays;
  return (spanAfterFirstFriday ~/ 7) + 1;
}
