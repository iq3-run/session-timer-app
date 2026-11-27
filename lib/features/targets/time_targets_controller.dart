import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/persistence/mutation_queue_notifier.dart';
import 'package:session_timer/features/targets/time_target.dart';
import 'package:shared_preferences/shared_preferences.dart';

const timeTargetsJsonKey = 'time_targets_json';

final timeTargetsControllerProvider =
    AsyncNotifierProvider<TimeTargetsController, List<TimeTarget>>(
      TimeTargetsController.new,
    );

class TimeTargetsController extends MutationQueueNotifier<List<TimeTarget>> {
  @override
  @protected
  List<TimeTarget> get initialValue => const [];

  @override
  @protected
  String get persistenceFailureMessage =>
      'SharedPreferences reported failure to persist $timeTargetsJsonKey';

  @override
  @protected
  Future<List<TimeTarget>> loadInitial(SharedPreferences prefs) async {
    final nowEpochMs = DateTime.now().millisecondsSinceEpoch;
    final unexpired = _readPersisted(
      prefs,
    ).where((t) => t.epochMs > nowEpochMs).toList();
    await persist(prefs, unexpired);
    return _sorted(unexpired);
  }

  @override
  @protected
  List<TimeTarget> normalize(List<TimeTarget> value) => _sorted(value);

  Future<void> addTarget(DateTime time, {String? title}) async {
    final target = TimeTarget(
      id: UniqueKey().toString(),
      epochMs: time.millisecondsSinceEpoch,
      title: title,
    );
    await mutate((targets) => [...targets, target]);
  }

  Future<void> updateTarget(
    String id,
    DateTime time, {
    String? title,
    bool clearTitle = false,
  }) async {
    await mutate(
      (targets) => [
        for (final t in targets)
          if (t.id == id)
            t.copyWith(
              epochMs: time.millisecondsSinceEpoch,
              title: title,
              clearTitle: clearTitle,
            )
          else
            t,
      ],
    );
  }

  Future<void> removeTarget(String id) async {
    await mutate((targets) => targets.where((t) => t.id != id).toList());
  }

  /// Creates or replaces the target at the caller-chosen [id], unlike
  /// [addTarget] which always mints a fresh `UniqueKey()` id. For callers
  /// that need to keep exactly one auto-managed target up to date across
  /// repeated calls, rather than accumulating a new entry every time.
  Future<void> upsertTarget(String id, DateTime time, {String? title}) async {
    await mutate(
      (targets) => [
        ...targets.where((t) => t.id != id),
        TimeTarget(id: id, epochMs: time.millisecondsSinceEpoch, title: title),
      ],
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

  @override
  @protected
  Future<bool> persist(SharedPreferences prefs, List<TimeTarget> value) {
    final json = jsonEncode(value.map((t) => t.toJson()).toList());
    return prefs.setString(timeTargetsJsonKey, json);
  }

  List<TimeTarget> _sorted(List<TimeTarget> targets) =>
      [...targets]..sort((a, b) => a.epochMs.compareTo(b.epochMs));
}
