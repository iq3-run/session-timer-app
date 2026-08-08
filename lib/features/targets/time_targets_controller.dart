import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/persistence/shared_preferences_provider.dart';
import 'package:session_timer/features/targets/time_target.dart';
import 'package:shared_preferences/shared_preferences.dart';

const timeTargetsJsonKey = 'time_targets_json';

final timeTargetsControllerProvider =
    AsyncNotifierProvider<TimeTargetsController, List<TimeTarget>>(
      TimeTargetsController.new,
    );

class TimeTargetsController extends AsyncNotifier<List<TimeTarget>> {
  // Serializes _mutate calls: each waits for the previous one's read of
  // `state` -> persist -> state-update cycle to finish before starting its
  // own, so concurrent add/update/remove calls can't read the same stale
  // `state` and have one silently overwrite the other's persisted result.
  Future<void> _mutationQueue = Future.value();

  @override
  Future<List<TimeTarget>> build() async {
    final prefs = await ref.watch(sharedPreferencesProvider.future);
    // A mutate() call may have already landed on `state` while this build()
    // was awaiting the prefs future above — don't clobber it with a stale
    // read.
    if (state.hasValue) return state.value!;

    final nowEpochMs = DateTime.now().millisecondsSinceEpoch;
    final unexpired = _readPersisted(
      prefs,
    ).where((t) => t.epochMs > nowEpochMs).toList();
    await _persist(prefs, unexpired);
    return _sorted(unexpired);
  }

  Future<void> addTarget(DateTime time) async {
    final target = TimeTarget(
      id: UniqueKey().toString(),
      epochMs: time.millisecondsSinceEpoch,
    );
    await _mutate((targets) => [...targets, target]);
  }

  Future<void> updateTarget(String id, DateTime time) async {
    await _mutate(
      (targets) => [
        for (final t in targets)
          if (t.id == id)
            t.copyWith(epochMs: time.millisecondsSinceEpoch)
          else
            t,
      ],
    );
  }

  Future<void> removeTarget(String id) async {
    await _mutate((targets) => targets.where((t) => t.id != id).toList());
  }

  Future<void> _mutate(
    List<TimeTarget> Function(List<TimeTarget>) update,
  ) {
    final previous = _mutationQueue;
    final result = previous.then((_) => _mutateNow(update));
    // Swallow the error here so it doesn't become an unhandled rejection on
    // the queue chain itself — _mutateNow already reports failures via
    // `state`, and each caller's own awaited `result` still sees it.
    _mutationQueue = result.catchError((_) {});
    return result;
  }

  Future<void> _mutateNow(
    List<TimeTarget> Function(List<TimeTarget>) update,
  ) async {
    try {
      // Must await `future`, not read `state.value` directly: if a mutation
      // is queued before build() has finished loading from SharedPreferences,
      // `state` is still AsyncLoading (value == null) and falling back to []
      // would silently overwrite every already-persisted target on disk.
      final current = await future;
      final updated = _sorted(update(current));
      final prefs = await ref.read(sharedPreferencesProvider.future);
      final persisted = await _persist(prefs, updated);
      state = persisted ? AsyncData(updated) : _persistenceFailure();
    } on Exception catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  AsyncValue<List<TimeTarget>> _persistenceFailure() {
    return AsyncError(
      Exception(
        'SharedPreferences reported failure to persist $timeTargetsJsonKey',
      ),
      StackTrace.current,
    );
  }

  List<TimeTarget> _readPersisted(SharedPreferences prefs) {
    final raw = prefs.getString(timeTargetsJsonKey);
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
        .map(TimeTarget.tryFromJson)
        .whereType<TimeTarget>()
        .toList();
  }

  Future<bool> _persist(SharedPreferences prefs, List<TimeTarget> targets) {
    final json = jsonEncode(targets.map((t) => t.toJson()).toList());
    return prefs.setString(timeTargetsJsonKey, json);
  }

  List<TimeTarget> _sorted(List<TimeTarget> targets) =>
      [...targets]..sort((a, b) => a.epochMs.compareTo(b.epochMs));
}
