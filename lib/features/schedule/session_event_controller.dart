import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/persistence/shared_preferences_provider.dart';
import 'package:session_timer/features/schedule/session_event.dart';
import 'package:shared_preferences/shared_preferences.dart';

const sessionEventsJsonKey = 'session_events_json';

const Set<SessionEventType> _singletonTypes = {
  SessionEventType.orientation,
  SessionEventType.completion,
};

final sessionEventControllerProvider =
    AsyncNotifierProvider<SessionEventController, List<SessionEvent>>(
      SessionEventController.new,
    );

/// Persists the full session schedule (OR/WE/WD/CR/SS/CS). Unlike
/// `TimeTargetsController`, past events are never dropped — the chain gap
/// and "直前から" calculations need the full history to stay accurate.
class SessionEventController extends AsyncNotifier<List<SessionEvent>> {
  // Mirrors FlashPointsController's mutation-queue pattern: see that file
  // for why _lastGood/_initialLoad exist instead of reading state directly.
  Future<void> _mutationQueue = Future.value();
  final Completer<void> _initialLoad = Completer<void>();
  List<SessionEvent> _lastGood = const [];

  @override
  Future<List<SessionEvent>> build() async {
    try {
      final prefs = await ref.watch(sharedPreferencesProvider.future);
      if (state.hasValue) return state.value!;

      final events = _readPersisted(prefs);
      _lastGood = events;
      return events;
    } finally {
      if (!_initialLoad.isCompleted) _initialLoad.complete();
    }
  }

  /// No-op if [type] is OR or CS and one already exists — those two are
  /// singletons.
  Future<void> addEvent(SessionEventType type, DateTime date) {
    return _mutate((events) {
      if (_singletonTypes.contains(type) && events.any((e) => e.type == type)) {
        return events;
      }
      final event = SessionEvent(
        id: UniqueKey().toString(),
        type: type,
        date: date,
      );
      return [...events, event];
    });
  }

  Future<void> removeEvent(String id) =>
      _mutate((events) => events.where((e) => e.id != id).toList());

  Future<void> _mutate(
    List<SessionEvent> Function(List<SessionEvent>) update,
  ) {
    final previous = _mutationQueue;
    final result = previous.then((_) => _mutateNow(update));
    _mutationQueue = result.catchError((_) {});
    return result;
  }

  Future<void> _mutateNow(
    List<SessionEvent> Function(List<SessionEvent>) update,
  ) async {
    if (!_initialLoad.isCompleted) await _initialLoad.future;
    final updated = update(_lastGood);
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

  AsyncValue<List<SessionEvent>> _persistenceFailure() {
    return AsyncError(
      Exception(
        'SharedPreferences reported failure to persist $sessionEventsJsonKey',
      ),
      StackTrace.current,
    );
  }

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

  Future<bool> _persist(SharedPreferences prefs, List<SessionEvent> events) {
    final json = jsonEncode(events.map((e) => e.toJson()).toList());
    return prefs.setString(sessionEventsJsonKey, json);
  }
}
