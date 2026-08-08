import 'package:flutter/material.dart';

/// The next DateTime matching [time]'s hour/minute — today if that moment
/// hasn't passed yet, otherwise tomorrow. Mirrors the HTML prototype's
/// `timeInputToEpoch`.
DateTime resolveNextOccurrence(TimeOfDay time, DateTime now) {
  final today = DateTime(now.year, now.month, now.day, time.hour, time.minute);
  if (today.isAfter(now)) return today;
  // DateTime(..., day + 1, ...) rather than today.add(Duration(days: 1)):
  // the latter adds a fixed 24h and can land on the wrong wall-clock hour
  // across a DST transition.
  return DateTime(now.year, now.month, now.day + 1, time.hour, time.minute);
}
