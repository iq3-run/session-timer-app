import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/persistence/shared_preferences_provider.dart';
import 'package:session_timer/features/completion/completion_time_state.dart';

const completionTimeEpochMsKey = 'completion_time_epoch_ms';

final completionTimeControllerProvider =
    AsyncNotifierProvider<CompletionTimeController, CompletionTimeState>(
      CompletionTimeController.new,
    );

class CompletionTimeController extends AsyncNotifier<CompletionTimeState> {
  @override
  Future<CompletionTimeState> build() async {
    final prefs = await ref.watch(sharedPreferencesProvider.future);
    // A setTarget/clear call may have already landed on `state` while this
    // build() was awaiting the prefs future above — don't clobber it with a
    // stale read.
    if (state.hasValue) return state.value!;

    final storedEpochMs = prefs.getInt(completionTimeEpochMsKey);
    if (storedEpochMs == null) return const CompletionTimeState();

    final nowEpochMs = DateTime.now().millisecondsSinceEpoch;
    if (storedEpochMs <= nowEpochMs) {
      // Best-effort cleanup: the state is "unset" either way since the
      // target has expired, and a failed remove() self-heals — the next
      // build() hits this same expired branch and retries.
      await prefs.remove(completionTimeEpochMsKey);
      return const CompletionTimeState();
    }
    return CompletionTimeState(targetEpochMs: storedEpochMs);
  }

  Future<void> setTarget(DateTime target) async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    final epochMs = target.millisecondsSinceEpoch;
    try {
      final persisted = await prefs.setInt(completionTimeEpochMsKey, epochMs);
      state = persisted
          ? AsyncData(CompletionTimeState(targetEpochMs: epochMs))
          : _persistenceFailure('persist');
    } on Exception catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> clear() async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    try {
      final cleared = await prefs.remove(completionTimeEpochMsKey);
      state = cleared
          ? const AsyncData(CompletionTimeState())
          : _persistenceFailure('clear');
    } on Exception catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  AsyncValue<CompletionTimeState> _persistenceFailure(String action) {
    return AsyncError(
      Exception(
        'SharedPreferences reported failure to $action completion time '
        '($completionTimeEpochMsKey)',
      ),
      StackTrace.current,
    );
  }
}
