import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/persistence/mutation_queue_notifier.dart';
import 'package:session_timer/features/session_plan/session_plan_book.dart';
import 'package:session_timer/features/session_plan/session_plan_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pre-組 storage: a bare JSON list of sessions. Only read (as 組1) when
/// [sessionPlanBookJsonKey] is absent; never written.
const sessionPlanJsonKey = 'session_plan_json';

/// Current storage: every 組 plus the active one's id.
const sessionPlanBookJsonKey = 'session_plan_book_json';

/// Duration used to pre-fill the "所要時間" input when registering a session.
const defaultSessionDuration = Duration(hours: 3, minutes: 30);

/// Fixed id for the single auto-managed指定時刻 entry kept up to date in
/// `TimeTargetsController` — distinct from every `UniqueKey()`-generated id
/// a user's own manually-added target gets, so this entry is always found
/// and replaced rather than accumulating one per update.
const autoSessionTargetId = 'session-plan:auto';

final sessionPlanControllerProvider =
    AsyncNotifierProvider<SessionPlanController, SessionPlanBook>(
      SessionPlanController.new,
    );

/// Persists every 組 of the session flow and which one is active.
///
/// Unlike `TimeTargetsController`, this never drops entries on load: sessions
/// hold only a time of day, so none is ever "already ended" — the plan is
/// kept until the user removes it by hand, not reset per calendar day.
///
/// The session operations ([addSession] / [updateSession] / [removeSession])
/// always act on the active 組. A book saved before 組 existed (a bare list
/// under [sessionPlanJsonKey]) is read as a single 組1; it is only ever
/// written back under [sessionPlanBookJsonKey], so the old key stays as it
/// was.
class SessionPlanController extends MutationQueueNotifier<SessionPlanBook> {
  @override
  @protected
  SessionPlanBook get initialValue => SessionPlanBook.initial();

  @override
  @protected
  String get persistenceFailureMessage =>
      'SharedPreferences reported failure to persist $sessionPlanBookJsonKey';

  @override
  @protected
  Future<SessionPlanBook> loadInitial(SharedPreferences prefs) async =>
      normalize(_readPersisted(prefs));

  @override
  @protected
  SessionPlanBook normalize(SessionPlanBook value) => SessionPlanBook(
    sets: [
      for (final set in value.sets)
        set.copyWith(sessions: _sorted(set.sessions)),
    ],
    activeId: value.activeId,
  );

  Future<void> addSession({
    required int startMinutes,
    required int durationMinutes,
  }) async {
    final entry = SessionPlanEntry(
      id: UniqueKey().toString(),
      startMinutes: startMinutes,
      durationMinutes: durationMinutes,
    );
    await _mutateActive((sessions) => [...sessions, entry]);
  }

  Future<void> updateSession(
    String id, {
    required int startMinutes,
    required int durationMinutes,
  }) async {
    await _mutateActive(
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
    await _mutateActive(
      (sessions) => sessions.where((s) => s.id != id).toList(),
    );
  }

  /// Adds an empty 組 and makes it the active one. Without a [name] it is
  /// called 組N, N being the first number no existing 組 already uses.
  Future<void> addSet({String? name}) async {
    await mutate((book) {
      final clamped = _clamped(name ?? '');
      final set = SessionPlanSet(
        id: UniqueKey().toString(),
        name: clamped.isEmpty ? _nextDefaultName(book) : clamped,
      );
      return SessionPlanBook(sets: [...book.sets, set], activeId: set.id);
    });
  }

  /// Renames [id]. A blank name is ignored — a 組 always has one to show on
  /// its chip.
  Future<void> renameSet(String id, String name) async {
    final clamped = _clamped(name);
    if (clamped.isEmpty) return;
    await mutate(
      (book) => SessionPlanBook(
        sets: [
          for (final s in book.sets)
            if (s.id == id) s.copyWith(name: clamped) else s,
        ],
        activeId: book.activeId,
      ),
    );
  }

  /// Makes [id] the active 組. A no-op for an unknown id.
  Future<void> selectSet(String id) async {
    await mutate((book) {
      if (!book.sets.any((s) => s.id == id)) return book;
      return SessionPlanBook(sets: book.sets, activeId: id);
    });
  }

  /// Removes [id] and its sessions. The last remaining 組 can't be removed.
  /// Removing the active one activates the 組 that was before it (or the
  /// first, when it was the first).
  Future<void> removeSet(String id) async {
    await mutate((book) {
      if (book.sets.length <= 1) return book;
      final index = book.sets.indexWhere((s) => s.id == id);
      if (index < 0) return book;
      final remaining = [...book.sets]..removeAt(index);
      final activeId = book.activeId == id
          ? remaining[index == 0 ? 0 : index - 1].id
          : book.activeId;
      return SessionPlanBook(sets: remaining, activeId: activeId);
    });
  }

  Future<void> _mutateActive(
    List<SessionPlanEntry> Function(List<SessionPlanEntry>) update,
  ) => mutate(
    (book) => SessionPlanBook(
      sets: [
        for (final s in book.sets)
          if (s.id == book.activeId)
            s.copyWith(sessions: update(s.sessions))
          else
            s,
      ],
      activeId: book.activeId,
    ),
  );

  // Cut by code point, not UTF-16 unit, so an emoji is never split into a
  // lone surrogate; trimmed again because the cut can end on a space.
  String _clamped(String name) => String.fromCharCodes(
    name.runes.take(maxSessionPlanSetNameLength),
  ).trim();

  String _nextDefaultName(SessionPlanBook book) {
    final used = {for (final s in book.sets) s.name};
    var n = book.sets.length + 1;
    while (used.contains(defaultSessionPlanSetName(n))) {
      n++;
    }
    return defaultSessionPlanSetName(n);
  }

  SessionPlanBook _readPersisted(SharedPreferences prefs) {
    final book = _readBook(prefs);
    if (book != null) return book;
    return SessionPlanBook.initial(sessions: _readLegacyList(prefs));
  }

  SessionPlanBook? _readBook(SharedPreferences prefs) {
    final raw = prefs.getString(sessionPlanBookJsonKey);
    if (raw == null) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    return SessionPlanBook.tryFromJson(decoded);
  }

  List<SessionPlanEntry> _readLegacyList(SharedPreferences prefs) {
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
  Future<bool> persist(SharedPreferences prefs, SessionPlanBook value) =>
      prefs.setString(sessionPlanBookJsonKey, jsonEncode(value.toJson()));

  // Sessions are a repeating daily rhythm with no calendar date, so each
  // list is simply ordered by time of day.
  List<SessionPlanEntry> _sorted(List<SessionPlanEntry> sessions) =>
      [...sessions]..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
}
