import 'package:flutter_riverpod/flutter_riverpod.dart';

final nowProvider = StreamProvider<DateTime>((ref) => _tickingClock());

/// The latest tick from [nowProvider], falling back to [DateTime.now] before
/// the stream's first event has arrived.
DateTime watchNow(WidgetRef ref) =>
    ref.watch(nowProvider).value ?? DateTime.now();

Stream<DateTime> _tickingClock() async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now());
}
