import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/core/clock/now_provider.dart';
import 'package:session_timer/core/clock/ntp_sync_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

// `nowProvider.future` hangs indefinitely for a bare (non-AsyncNotifier)
// StreamProvider under this Riverpod version unless something is also
// `listen()`ing — `container.read(provider.future)` alone never resolves.
// Capturing the first tick via a `listen()` callback instead sidesteps
// that and matches how `watchNow`'s real widget-side consumers already
// subscribe.
Future<DateTime> _firstTick(ProviderContainer container) {
  final completer = Completer<DateTime>();
  late final ProviderSubscription<AsyncValue<DateTime>> sub;
  sub = container.listen(nowProvider, (previous, next) {
    final value = next.value;
    if (value != null && !completer.isCompleted) completer.complete(value);
  });
  final immediate = sub.read().value;
  if (immediate != null) completer.complete(immediate);
  return completer.future.whenComplete(sub.close);
}

void main() {
  test('nowProvider folds in the current NTP offset', () async {
    SharedPreferences.setMockInitialValues({});
    const offsetMs = 60000;
    final container = ProviderContainer(
      overrides: [
        ntpOffsetFetcherProvider.overrideWithValue(
          (host, {required timeout}) async => offsetMs,
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(ntpSyncControllerProvider.future);
    await container
        .read(ntpSyncControllerProvider.notifier)
        .syncNow(defaultNtpServerHost);

    final before = DateTime.now();
    final tick = await _firstTick(container);
    final after = DateTime.now();

    // A generous tolerance around the test's own execution time, not a
    // claim about NTP precision — the fetcher above is instant/fake.
    const tolerance = Duration(seconds: 2);
    expect(
      tick.isAfter(
        before.add(const Duration(milliseconds: offsetMs) - tolerance),
      ),
      isTrue,
    );
    expect(
      tick.isBefore(
        after.add(const Duration(milliseconds: offsetMs) + tolerance),
      ),
      isTrue,
    );
  });
}
