import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/persistence/shared_preferences_provider.dart';
import 'package:session_timer/features/flash/flash_event.dart';
import 'package:shared_preferences/shared_preferences.dart';

const flashPointsMinutesJsonKey = 'flash_points_minutes_json';

final flashPointsControllerProvider =
    AsyncNotifierProvider<FlashPointsController, List<int>>(
      FlashPointsController.new,
    );

/// 完了◯分前 flash points, user-editable via the settings sheet. Seeded
/// from [defaultCompletionFlashPointsMinutes] on first launch; an empty
/// persisted list after that means the user deliberately removed every
/// point, not "uninitialized" — see [_readPersisted].
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
      final points = raw == null
          ? [...defaultCompletionFlashPointsMinutes]
          : _readPersisted(raw);
      await _persist(prefs, points);
      _lastGood = points;
      return points;
    } finally {
      if (!_initialLoad.isCompleted) _initialLoad.complete();
    }
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

  List<int> _readPersisted(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return [...defaultCompletionFlashPointsMinutes];
    }
    if (decoded is! List) return [...defaultCompletionFlashPointsMinutes];
    return decoded.whereType<int>().where((m) => m > 0).toList();
  }

  Future<bool> _persist(SharedPreferences prefs, List<int> points) {
    return prefs.setString(flashPointsMinutesJsonKey, jsonEncode(points));
  }
}
