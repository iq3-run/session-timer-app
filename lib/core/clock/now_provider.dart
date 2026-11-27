import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:session_timer/core/clock/ntp_sync_controller.dart';

final nowProvider = StreamProvider<DateTime>((ref) {
  final offsetMs = ref.watch(ntpOffsetMsProvider);
  return _tickingClock().map(
    (deviceTime) => deviceTime.add(Duration(milliseconds: offsetMs)),
  );
});

/// The current NTP-corrected time, read on demand: `ref.read(
/// correctedNowProvider)()`.
///
/// For absolute times (a target's moment, whether a session has started or a
/// stored time has passed). Elapsed time — the stopwatch and the countdown
/// timer — stays on the device clock instead: it only compares the device
/// clock with itself, and correcting it would make it jump at every sync.
/// The offset is read at each call, so a later sync is picked up without
/// rebuilding anything that holds this function.
final correctedNowProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().add(
        Duration(milliseconds: ref.read(ntpOffsetMsProvider)),
      ),
);

/// The latest tick from [nowProvider], falling back to [DateTime.now] before
/// the stream's first event has arrived.
DateTime watchNow(WidgetRef ref) =>
    ref.watch(nowProvider).value ?? DateTime.now();

Stream<DateTime> _tickingClock() async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now());
}
