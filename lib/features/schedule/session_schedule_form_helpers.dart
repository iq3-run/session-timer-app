import 'package:session_timer/features/schedule/session_event.dart';

/// Shared bounds for every `showDatePicker` call on this screen (add form
/// and per-row edit alike).
final earliestScheduleDate = DateTime(2000);
final latestScheduleDate = DateTime(2100);

/// Keeps a `showDatePicker` `initialDate` within [earliestScheduleDate,
/// latestScheduleDate] — `showDatePicker` asserts on an out-of-range value,
/// and [date] may come from already-persisted data this screen didn't
/// itself just pick (e.g. an older/foreign import) rather than always being
/// bounded by this screen's own picker calls.
DateTime clampToScheduleRange(DateTime date) {
  if (date.isBefore(earliestScheduleDate)) return earliestScheduleDate;
  if (date.isAfter(latestScheduleDate)) return latestScheduleDate;
  return date;
}

const Map<SessionEventType, String> scheduleTypeNames = {
  SessionEventType.orientation: 'オリエンテーション(OR)',
  SessionEventType.weekend: '週末(WE)',
  SessionEventType.workday: 'ワークデー(WD)',
  SessionEventType.classroom: 'クラスルーム(CR)',
  SessionEventType.specialSession: '特別セッション(SS)',
  SessionEventType.completion: '完了セッション(CS)',
};

/// Empty (auto) or a positive integer — shared by the add form's number
/// field and the edit dialog's, so both accept/reject the same input.
bool isValidManualNumberText(String text) {
  final trimmed = text.trim();
  return trimmed.isEmpty || (int.tryParse(trimmed) ?? -1) > 0;
}

/// `null` for empty (auto) text; the caller is expected to have already
/// checked [isValidManualNumberText].
int? parseManualNumberText(String text) {
  final trimmed = text.trim();
  return trimmed.isEmpty ? null : int.tryParse(trimmed);
}

/// Whether [event] gets a show/hide-on-`SessionScheduleScreen` toggle — CS,
/// the first WE, and CR always show there and never expose one (see
/// `session_chain.dart`'s `_isVisibleOnScheduleScreen`, which this mirrors).
bool hasVisibilityToggle(SessionEvent event, Map<String, int> numbers) {
  if (event.type == SessionEventType.completion) return false;
  if (event.type == SessionEventType.classroom) return false;
  if (event.type == SessionEventType.weekend && numbers[event.id] == 1) {
    return false;
  }
  return true;
}
