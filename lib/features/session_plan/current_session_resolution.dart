import 'package:session_timer/features/session_plan/session_plan_entry.dart';

/// The derived 完了時刻/指定時刻 pair for whichever session is current right
/// now, computed fresh from the wall clock rather than a stored "current
/// index" — calling this again at any time re-derives the right answer
/// without needing sequential calls.
typedef CurrentSessionResolution = ({
  SessionPlanEntry session,
  DateTime completionTarget,
  DateTime? autoTargetStart,
});

/// Picks, among sessions that haven't ended yet, the one ending soonest —
/// that's either the session currently in progress or the next one coming
/// up, since sessions are expected to be chronological and non-overlapping.
/// Returns `null` when [sessions] is empty or every session has already
/// ended.
///
/// `autoTargetStart` is the resolved session's own start time if it hasn't
/// started yet (a countdown to "when this session begins"), or — once it
/// has started — the start time of whichever session comes next after it
/// in start-time order, or `null` if there is no next session to show.
CurrentSessionResolution? resolveCurrentSession(
  List<SessionPlanEntry> sessions,
  DateTime now,
) {
  final notEnded = sessions.where((s) => s.endTime.isAfter(now)).toList()
    ..sort((a, b) => a.endTime.compareTo(b.endTime));
  if (notEnded.isEmpty) return null;
  final selected = notEnded.first;

  if (selected.startTime.isAfter(now)) {
    return (
      session: selected,
      completionTarget: selected.endTime,
      autoTargetStart: selected.startTime,
    );
  }

  final byStart = [...sessions]
    ..sort((a, b) => a.startEpochMs.compareTo(b.startEpochMs));
  final selectedIndex = byStart.indexWhere((s) => s.id == selected.id);
  final next = selectedIndex + 1 < byStart.length
      ? byStart[selectedIndex + 1]
      : null;
  return (
    session: selected,
    completionTarget: selected.endTime,
    autoTargetStart: next?.startTime,
  );
}
