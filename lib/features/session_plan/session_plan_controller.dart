import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/persistence/mutation_queue_notifier.dart';
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

/// Unlike `TimeTargetsController`, this never drops entries on load: sessions
/// hold only a time of day, so none is ever "already ended" — the plan is
/// kept until the user removes it by hand, not reset per calendar day.
class SessionPlanController
    extends MutationQueueNotifier<List<SessionPlanEntry>> {
  @override
  @protected
  List<SessionPlanEntry> get initialValue => const [];

  @override
  @protected
  String get persistenceFailureMessage =>
      'SharedPreferences reported failure to persist $sessionPlanJsonKey';

  @override
  @protected
  Future<List<SessionPlanEntry>> loadInitial(SharedPreferences prefs) async =>
      _sorted(_readPersisted(prefs));

  @override
  @protected
  List<SessionPlanEntry> normalize(List<SessionPlanEntry> value) =>
      _sorted(value);

  Future<void> addSession({
    required int startMinutes,
    required int durationMinutes,
  }) async {
    final entry = SessionPlanEntry(
      id: UniqueKey().toString(),
      startMinutes: startMinutes,
      durationMinutes: durationMinutes,
    );
    await mutate((sessions) => [...sessions, entry]);
  }

  Future<void> updateSession(
    String id, {
    required int startMinutes,
    required int durationMinutes,
  }) async {
    await mutate(
      (sessions) => [
        for (final s in sessions)
          if (s.id == id)
            SessionPlanEntry(
              id: id,
              startMinutes: startMinutes,
              durationMinutes: durationMinutes,
            )
          else
            s,
      ],
    );
  }

  Future<void> removeSession(String id) async {
    await mutate((sessions) => sessions.where((s) => s.id != id).toList());
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

  @override
  @protected
  Future<bool> persist(
    SharedPreferences prefs,
    List<SessionPlanEntry> value,
  ) {
    final json = jsonEncode(value.map((s) => s.toJson()).toList());
    return prefs.setString(sessionPlanJsonKey, json);
  }

  // Sessions are a repeating daily rhythm with no calendar date, so the
  // list is simply ordered by time of day.
  List<SessionPlanEntry> _sorted(List<SessionPlanEntry> sessions) =>
      [...sessions]..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
}
