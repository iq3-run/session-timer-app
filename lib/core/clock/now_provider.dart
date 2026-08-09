import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/clock/ntp_sync_controller.dart';

final nowProvider = StreamProvider<DateTime>((ref) {
  final offsetMs = ref.watch(ntpOffsetMsProvider);
  return _tickingClock().map(
    (deviceTime) => deviceTime.add(Duration(milliseconds: offsetMs)),
  );
});

/// The latest tick from [nowProvider], falling back to [DateTime.now] before
/// the stream's first event has arrived.
DateTime watchNow(WidgetRef ref) =>
    ref.watch(nowProvider).value ?? DateTime.now();

Stream<DateTime> _tickingClock() async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now());
}
