import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/persistence/shared_preferences_provider.dart';
import 'package:session_timer/features/completion/completion_time_controller.dart';
import 'package:session_timer/features/flash/flash_event.dart';
import 'package:shared_preferences/shared_preferences.dart';

const flashPointsMinutesJsonKey = 'flash_points_minutes_json';

final flashPointsControllerProvider =
    AsyncNotifierProvider<FlashPointsController, List<int>>(
      FlashPointsController.new,
    );

/// 完了◯分前 flash points, user-editable via the settings sheet.
///
/// The 12 defaults ([defaultCompletionFlashPointsMinutes]) are a permanent
/// baseline: at every `build()` (app startup only — mirrors
/// `CompletionTimeController`'s own "clear an overdue target at startup"
/// rule, not a continuous check), any default missing from the persisted
/// list is added back, regardless of whether a completion time is set.
/// Non-default (user-added) points are only pruned once their own moment
/// (completion time − minutes) has passed, and only once a completion time
/// exists to measure that against — see [_applyStartupRules].
class FlashPointsController extends AsyncNotifier<List<int>> {
  // Mirrors TimeTargetsController's mutation-queue pattern: see that file
  // for why _lastGood/_initialLoad exist instead of reading state directly.
  Future<void> _mutationQueue = Future.value();
  final Completer<void> _initialLoad = Completer<void>();
  List<int> _lastGood = const [];

  @override
  Future<List<int>> build() async {
    try {
      final prefs = await ref.watch(sharedPreferencesProvider.future);
      if (state.hasValue) return state.value!;

      final raw = prefs.getString(flashPointsMinutesJsonKey);
      final loaded = raw == null ? const <int>[] : _readPersisted(raw);

      // A one-time read (not ref.watch) — this rule only ever applies at
      // startup, so a later completion-time change must not re-trigger it.
      final completion = await ref.read(
        completionTimeControllerProvider.future,
      );
      final points = _applyStartupRules(
        loaded,
        completion.targetTime,
        DateTime.now(),
      );

      await _persist(prefs, points);
      _lastGood = points;
      return points;
    } finally {
      if (!_initialLoad.isCompleted) _initialLoad.complete();
    }
  }

  /// See the class doc for the rule.
  List<int> _applyStartupRules(
    List<int> persisted,
    DateTime? completionTarget,
    DateTime now,
  ) {
    bool isDefault(int minutesBefore) =>
        defaultCompletionFlashPointsMinutes.contains(minutesBefore);

    bool hasPassed(int minutesBefore) {
      final moment = completionTarget!.subtract(
        Duration(minutes: minutesBefore),
      );
      return !moment.isAfter(now);
    }

    final customs = persisted.where((m) => !isDefault(m));
    final survivingCustoms = completionTarget == null
        ? customs
        : customs.where((m) => !hasPassed(m));

    return [...defaultCompletionFlashPointsMinutes, ...survivingCustoms];
  }

  Future<void> addPoint(int minutes) {
    if (minutes <= 0) return Future.value();
    return _mutate(
      (points) => points.contains(minutes) ? points : [...points, minutes],
    );
  }

  Future<void> removePoint(int minutes) =>
      _mutate((points) => points.where((m) => m != minutes).toList());

  Future<void> _mutate(List<int> Function(List<int>) update) {
    final previous = _mutationQueue;
    final result = previous.then((_) => _mutateNow(update));
    _mutationQueue = result.catchError((_) {});
    return result;
  }

  Future<void> _mutateNow(List<int> Function(List<int>) update) async {
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

  AsyncValue<List<int>> _persistenceFailure() {
    return AsyncError(
      Exception(
        'SharedPreferences reported failure to persist '
        '$flashPointsMinutesJsonKey',
      ),
      StackTrace.current,
    );
  }

  /// Corrupt or unparseable data degrades to "no custom points" rather than
  /// re-seeding defaults directly — [_applyStartupRules] adds the defaults
  /// back unconditionally regardless of what this returns.
  List<int> _readPersisted(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];
    return decoded.whereType<int>().where((m) => m > 0).toList();
  }

  Future<bool> _persist(SharedPreferences prefs, List<int> points) {
    return prefs.setString(flashPointsMinutesJsonKey, jsonEncode(points));
  }
}
