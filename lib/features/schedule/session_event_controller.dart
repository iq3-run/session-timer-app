import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/persistence/mutation_queue_notifier.dart';
import 'package:session_timer/features/schedule/session_event.dart';
import 'package:shared_preferences/shared_preferences.dart';

const sessionEventsJsonKey = 'session_events_json';

final sessionEventControllerProvider =
    AsyncNotifierProvider<SessionEventController, List<SessionEvent>>(
      SessionEventController.new,
    );

/// Persists the full session schedule (OR/WE/WD/CR/SS/CS). Unlike
/// `TimeTargetsController`, past events are never dropped — the chain gap
/// and "直前から" calculations need the full history to stay accurate.
class SessionEventController extends MutationQueueNotifier<List<SessionEvent>> {
  @override
  @protected
  List<SessionEvent> get initialValue => const [];

  @override
  @protected
  String get persistenceFailureMessage =>
      'SharedPreferences reported failure to persist $sessionEventsJsonKey';

  @override
  @protected
  Future<List<SessionEvent>> loadInitial(SharedPreferences prefs) async =>
      _readPersisted(prefs);

  /// No-op if [type] is OR or CS and one already exists — those two are
  /// singletons. [manualNumber], when given, overrides the auto-assigned
  /// sequence number in this event's label (see `SessionEvent.manualNumber`).
  Future<void> addEvent(
    SessionEventType type,
    DateTime date, {
    int? manualNumber,
    SessionTrack track = SessionTrack.common,
  }) {
    return mutate((events) {
      if (singletonEventTypes.contains(type) &&
          events.any((e) => e.type == type)) {
        return events;
      }
      final event = SessionEvent(
        id: UniqueKey().toString(),
        type: type,
        date: date,
        manualNumber: manualNumber,
        // Only WE/WD can be on the A or B schedule.
        track: SessionEvent.supportsTrack(type) ? track : SessionTrack.common,
      );
      return [...events, event];
    });
  }

  Future<void> removeEvent(String id) =>
      mutate((events) => events.where((e) => e.id != id).toList());

  /// Removes every event whose id is in [ids] in one persisted write
  /// (unlike calling [removeEvent] per id, a failed save can't leave only
  /// some of them gone). Takes the ids rather than "everything" so that an
  /// event added after the caller confirmed with the user — which this
  /// can't undo — is never deleted along with them.
  Future<void> removeEvents(Set<String> ids) =>
      mutate((events) => events.where((e) => !ids.contains(e.id)).toList());

  /// Toggles whether [id]'s row shows on the read-only "セッションスケ
  /// ジュール" screen (see `SessionEvent.visible`). A no-op if no event
  /// with that id exists.
  Future<void> setVisible(String id, {required bool visible}) {
    return mutate(
      (events) => _replaceEvent(
        events,
        id,
        (e) => SessionEvent(
          id: e.id,
          type: e.type,
          date: e.date,
          visible: visible,
          manualNumber: e.manualNumber,
          track: e.track,
        ),
      ),
    );
  }

  /// Sets or clears (via `null`) [id]'s displayed-number override (see
  /// `SessionEvent.manualNumber`). A no-op if no event with that id exists.
  Future<void> setManualNumber(String id, int? manualNumber) {
    return mutate(
      (events) => _replaceEvent(
        events,
        id,
        (e) => SessionEvent(
          id: e.id,
          type: e.type,
          date: e.date,
          visible: e.visible,
          manualNumber: manualNumber,
          track: e.track,
        ),
      ),
    );
  }

  /// Changes [id]'s date, leaving its type/visible/manualNumber unchanged.
  /// A no-op if no event with that id exists.
  Future<void> setDate(String id, DateTime date) {
    return mutate(
      (events) => _replaceEvent(
        events,
        id,
        (e) => SessionEvent(
          id: e.id,
          type: e.type,
          date: date,
          visible: e.visible,
          manualNumber: e.manualNumber,
          track: e.track,
        ),
      ),
    );
  }

  List<SessionEvent> _replaceEvent(
    List<SessionEvent> events,
    String id,
    SessionEvent Function(SessionEvent) update,
  ) => [
    for (final e in events)
      if (e.id == id) update(e) else e,
  ];

  List<SessionEvent> _readPersisted(SharedPreferences prefs) {
    final raw = prefs.getString(sessionEventsJsonKey);
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
        .map(SessionEvent.tryFromJson)
        .whereType<SessionEvent>()
        .toList();
  }

  @override
  @protected
  Future<bool> persist(SharedPreferences prefs, List<SessionEvent> value) {
    final json = jsonEncode(value.map((e) => e.toJson()).toList());
    return prefs.setString(sessionEventsJsonKey, json);
  }
}
