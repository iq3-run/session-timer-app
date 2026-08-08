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
      await prefs.remove(completionTimeEpochMsKey);
      return const CompletionTimeState();
    }
    return CompletionTimeState(targetEpochMs: storedEpochMs);
  }

  Future<void> setTarget(DateTime target) async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    final epochMs = target.millisecondsSinceEpoch;
    try {
      await prefs.setInt(completionTimeEpochMsKey, epochMs);
      state = AsyncData(CompletionTimeState(targetEpochMs: epochMs));
    } on Exception catch (e, st) {
      state = AsyncError(
        Exception(
          'Failed to persist completion time ($completionTimeEpochMsKey): $e',
        ),
        st,
      );
    }
  }

  Future<void> clear() async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    try {
      await prefs.remove(completionTimeEpochMsKey);
      state = const AsyncData(CompletionTimeState());
    } on Exception catch (e, st) {
      state = AsyncError(
        Exception(
          'Failed to clear completion time ($completionTimeEpochMsKey): $e',
        ),
        st,
      );
    }
  }
}
