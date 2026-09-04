import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/persistence/shared_preferences_provider.dart';
import 'package:session_timer/features/session_plan/session_plan_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

const sessionPlanJsonKey = 'session_plan_json';

/// Duration used to pre-fill the "所要時間" input when registering a session.
const defaultSessionDuration = Duration(hours: 3, minutes: 30);

/// Fixed id for the single auto-managed指定時刻 entry kept up to date in
/// `TimeTargetsController` — distinct from every `UniqueKey()`-generated id
/// a user's own manually-added target gets, so this entry is always found
/// and replaced rather than accumulating one per update.
const autoSessionTargetId = 'session-plan:auto';

final sessionPlanControllerProvider =
    AsyncNotifierProvider<SessionPlanController, List<SessionPlanEntry>>(
      SessionPlanController.new,
    );

/// Unlike `TimeTargetsController`, this deliberately never drops
/// already-ended entries on load — the plan is kept until the user removes
/// it by hand, not reset per calendar day.
class SessionPlanController extends AsyncNotifier<List<SessionPlanEntry>> {
  Future<void> _mutationQueue = Future.value();
  final Completer<void> _initialLoad = Completer<void>();
  List<SessionPlanEntry> _lastGood = const [];

  @override
  Future<List<SessionPlanEntry>> build() async {
    try {
      final prefs = await ref.watch(sharedPreferencesProvider.future);
      if (state.hasValue) return state.value!;

      final sorted = _sorted(_readPersisted(prefs));
      _lastGood = sorted;
      return sorted;
    } finally {
      if (!_initialLoad.isCompleted) _initialLoad.complete();
    }
  }

  Future<void> addSession(DateTime start, DateTime end) async {
    final entry = SessionPlanEntry(
      id: UniqueKey().toString(),
      startEpochMs: start.millisecondsSinceEpoch,
      endEpochMs: end.millisecondsSinceEpoch,
    );
    await _mutate((sessions) => [...sessions, entry]);
  }

  Future<void> updateSession(String id, DateTime start, DateTime end) async {
    await _mutate(
      (sessions) => [
        for (final s in sessions)
          if (s.id == id)
            SessionPlanEntry(
              id: id,
              startEpochMs: start.millisecondsSinceEpoch,
              endEpochMs: end.millisecondsSinceEpoch,
            )
          else
            s,
      ],
    );
  }

  Future<void> removeSession(String id) async {
    await _mutate((sessions) => sessions.where((s) => s.id != id).toList());
  }

  Future<void> _mutate(
    List<SessionPlanEntry> Function(List<SessionPlanEntry>) update,
  ) {
    final previous = _mutationQueue;
    final result = previous.then((_) => _mutateNow(update));
    _mutationQueue = result.catchError((_) {});
    return result;
  }

  Future<void> _mutateNow(
    List<SessionPlanEntry> Function(List<SessionPlanEntry>) update,
  ) async {
    if (!_initialLoad.isCompleted) await _initialLoad.future;
    final updated = _sorted(update(_lastGood));
    try {
      final prefs = await ref.read(sharedPreferencesProvider.future);
      final persisted = await _persist(prefs, updated);
      if (persisted) {
        _lastGood = updated;
        state = AsyncData(updated);
      } else {
        state = _persistenceFailure();
      }
    } on Exception catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  AsyncValue<List<SessionPlanEntry>> _persistenceFailure() {
    return AsyncError(
      Exception(
        'SharedPreferences reported failure to persist $sessionPlanJsonKey',
      ),
      StackTrace.current,
    );
  }

  List<SessionPlanEntry> _readPersisted(SharedPreferences prefs) {
    final raw = prefs.getString(sessionPlanJsonKey);
    if (raw == null) return const [];
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(SessionPlanEntry.tryFromJson)
        .whereType<SessionPlanEntry>()
        .toList();
  }

  Future<bool> _persist(
    SharedPreferences prefs,
    List<SessionPlanEntry> sessions,
  ) {
    final json = jsonEncode(sessions.map((s) => s.toJson()).toList());
    return prefs.setString(sessionPlanJsonKey, json);
  }

  // Sessions represent a repeating daily rhythm (e.g. AM/PM/evening blocks),
  // not one-off dated appointments — each entry's stored date only reflects
  // which calendar day `resolveNextOccurrence` happened to land on when it
  // was registered, not anything the user actually chose. Sorting by the
  // full epoch would group entries by that incidental date first, showing
  // e.g. "today 19:00, tomorrow 9:00, tomorrow 13:30" instead of the
  // expected daily order — so this sorts by time-of-day only.
  List<SessionPlanEntry> _sorted(List<SessionPlanEntry> sessions) =>
      [...sessions]..sort(
        (a, b) =>
            _minutesOfDay(a.startTime).compareTo(_minutesOfDay(b.startTime)),
      );

  int _minutesOfDay(DateTime time) => time.hour * 60 + time.minute;
}
