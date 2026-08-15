import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/persistence/shared_preferences_provider.dart';
import 'package:session_timer/features/completion/completion_time_controller.dart';
import 'package:session_timer/features/flash/flash_event.dart';
import 'package:session_timer/features/flash/flash_point_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

const flashPointsMinutesJsonKey = 'flash_points_minutes_json';

final flashPointsControllerProvider =
    AsyncNotifierProvider<FlashPointsController, List<FlashPointConfig>>(
      FlashPointsController.new,
    );

/// 完了◯分前 flash points, user-editable via the settings sheet, each with
/// its own flash/notify toggle (see `FlashPointConfig`).
///
/// The 12 defaults ([defaultCompletionFlashPointsMinutes]) are a baseline
/// applied at every `build()` (app startup only — mirrors
/// `CompletionTimeController`'s own "clear an overdue target at startup"
/// rule, not a continuous check): a default already present always stays.
/// A default missing from the persisted list (the user removed it) is
/// revived once its own moment (completion time − minutes) has passed —
/// or unconditionally if no completion time is set at all, since there's
/// nothing to measure a moment against. A missing default does *not* come
/// back early just because it's missing; it only returns once its window
/// would have passed. Non-default (user-added) points follow the mirror
/// image: kept while no completion time is set, otherwise dropped once
/// their own moment has passed — see [_applyStartupRules]. A revived
/// default always comes back with both toggles ON — its prior toggle state
/// isn't remembered while it was absent.
class FlashPointsController extends AsyncNotifier<List<FlashPointConfig>> {
  // Mirrors TimeTargetsController's mutation-queue pattern: see that file
  // for why _lastGood/_initialLoad exist instead of reading state directly.
  Future<void> _mutationQueue = Future.value();
  final Completer<void> _initialLoad = Completer<void>();
  List<FlashPointConfig> _lastGood = const [];

  @override
  Future<List<FlashPointConfig>> build() async {
    try {
      final prefs = await ref.watch(sharedPreferencesProvider.future);
      if (state.hasValue) return state.value!;

      final raw = prefs.getString(flashPointsMinutesJsonKey);
      final loaded = raw == null
          ? const <FlashPointConfig>[]
          : _readPersisted(raw);

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

  /// See the class doc for the rule. Note: `completionTarget` is never
  /// actually overdue here in practice — `CompletionTimeController`
  /// self-heals an expired target to null before this read resolves (see
  /// `CompletionTimeController.build()`). The "overdue but non-null" case
  /// this handles is belt-and-suspenders, not something that currently
  /// fires.
  List<FlashPointConfig> _applyStartupRules(
    List<FlashPointConfig> persisted,
    DateTime? completionTarget,
    DateTime now,
  ) {
    return [
      ..._defaultsToKeep(persisted, completionTarget, now),
      ..._customsToKeep(persisted, completionTarget, now),
    ];
  }

  /// A present default always stays. A missing one is revived
  /// unconditionally when there's no completion time to measure against,
  /// and otherwise only once its own moment has passed — it does NOT come
  /// back early just because it's missing.
  Iterable<FlashPointConfig> _defaultsToKeep(
    List<FlashPointConfig> persisted,
    DateTime? completionTarget,
    DateTime now,
  ) {
    final presentMinutes = persisted.map((p) => p.minutes).toSet();
    final missing = defaultCompletionFlashPointsMinutes.where(
      (m) => !presentMinutes.contains(m),
    );
    final revived = completionTarget == null
        ? missing
        : missing.where((m) => _hasPassed(m, completionTarget, now));
    return [
      ...persisted.where((p) => _isDefault(p.minutes)),
      ...revived.map((m) => FlashPointConfig(minutes: m)),
    ];
  }

  /// Kept unconditionally when there's no completion time set; otherwise
  /// dropped once a point's own moment has passed.
  Iterable<FlashPointConfig> _customsToKeep(
    List<FlashPointConfig> persisted,
    DateTime? completionTarget,
    DateTime now,
  ) {
    final customs = persisted.where((p) => !_isDefault(p.minutes));
    return completionTarget == null
        ? customs
        : customs.where((p) => !_hasPassed(p.minutes, completionTarget, now));
  }

  bool _isDefault(int minutesBefore) =>
      defaultCompletionFlashPointsMinutes.contains(minutesBefore);

  bool _hasPassed(int minutesBefore, DateTime completionTarget, DateTime now) {
    final moment = completionTarget.subtract(Duration(minutes: minutesBefore));
    return !moment.isAfter(now);
  }

  Future<void> addPoint(int minutes) {
    if (minutes <= 0) return Future.value();
    return _mutate(
      (points) => points.any((p) => p.minutes == minutes)
          ? points
          : [...points, FlashPointConfig(minutes: minutes)],
    );
  }

  Future<void> removePoint(int minutes) =>
      _mutate((points) => points.where((p) => p.minutes != minutes).toList());

  Future<void> setFlashEnabled(int minutes, {required bool enabled}) => _mutate(
    (points) => _updatePoint(points, minutes, (p) {
      return p.copyWith(flashEnabled: enabled);
    }),
  );

  /// A no-op when the target point's flash is off — the settings UI
  /// disables the control in that state, and this is the defensive second
  /// layer (see `FlashPointConfig.copyWith`, which already forces
  /// `notifyEnabled` false whenever `flashEnabled` is false).
  Future<void> setNotifyEnabled(int minutes, {required bool enabled}) =>
      _mutate(
        (points) => _updatePoint(points, minutes, (p) {
          if (!p.flashEnabled) return p;
          return p.copyWith(notifyEnabled: enabled);
        }),
      );

  List<FlashPointConfig> _updatePoint(
    List<FlashPointConfig> points,
    int minutes,
    FlashPointConfig Function(FlashPointConfig) update,
  ) {
    return [
      for (final p in points)
        if (p.minutes == minutes) update(p) else p,
    ];
  }

  Future<void> _mutate(
    List<FlashPointConfig> Function(List<FlashPointConfig>) update,
  ) {
    final previous = _mutationQueue;
    final result = previous.then((_) => _mutateNow(update));
    _mutationQueue = result.catchError((_) {});
    return result;
  }

  Future<void> _mutateNow(
    List<FlashPointConfig> Function(List<FlashPointConfig>) update,
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

  AsyncValue<List<FlashPointConfig>> _persistenceFailure() {
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
  /// back unconditionally regardless of what this returns. Data from the
  /// pre-toggle `List<int>` format also degrades this way (every element
  /// fails the `Map` check), resetting to the default baseline.
  List<FlashPointConfig> _readPersisted(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(FlashPointConfig.tryFromJson)
        .nonNulls
        .toList();
  }

  Future<bool> _persist(
    SharedPreferences prefs,
    List<FlashPointConfig> points,
  ) {
    return prefs.setString(
      flashPointsMinutesJsonKey,
      jsonEncode(points.map((p) => p.toJson()).toList()),
    );
  }
}
