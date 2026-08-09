import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/core/clock/ntp_sync_controller.dart';
import 'package:session_timer/core/persistence/shared_preferences_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

ProviderContainer _buildContainer({required NtpOffsetFetcher fetcher}) {
  return ProviderContainer(
    overrides: [ntpOffsetFetcherProvider.overrideWithValue(fetcher)],
  );
}

Future<int> _neverCalled(String host, {required Duration timeout}) {
  fail('the offset fetcher must not be called');
}

/// Same shape as the `_FlakyStore` test double already duplicated across
/// `flash_points_controller_test.dart`/`stopwatch_controller_test.dart`/
/// `time_targets_controller_test.dart` — makes the next write report
/// failure without a full fake platform implementation.
class _FlakyStore extends InMemorySharedPreferencesStore {
  _FlakyStore.empty() : super.empty();

  bool failNextWrite = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (failNextWrite) {
      failNextWrite = false;
      return Future.value(false);
    }
    return super.setValue(valueType, key, value);
  }
}

void main() {
  group('NtpSyncController.build', () {
    test('defaults to NICT when nothing is persisted', () async {
      SharedPreferences.setMockInitialValues({});
      final container = _buildContainer(fetcher: _neverCalled);
      addTearDown(container.dispose);

      final state = await container.read(ntpSyncControllerProvider.future);

      expect(state.serverHost, defaultNtpServerHost);
      expect(state.status, NtpSyncStatus.unsynced);
    });

    test('loads a previously persisted server host', () async {
      SharedPreferences.setMockInitialValues({
        ntpServerHostKey: 'pool.ntp.org',
      });
      final container = _buildContainer(fetcher: _neverCalled);
      addTearDown(container.dispose);

      final state = await container.read(ntpSyncControllerProvider.future);

      expect(state.serverHost, 'pool.ntp.org');
      expect(state.status, NtpSyncStatus.unsynced);
    });

    test('never queries the network on its own', () async {
      SharedPreferences.setMockInitialValues({});
      final container = _buildContainer(fetcher: _neverCalled);
      addTearDown(container.dispose);

      await container.read(ntpSyncControllerProvider.future);
    });
  });

  group('NtpSyncController.syncNow', () {
    test(
      'applies the fetched offset and persists the host on success',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = _buildContainer(
          fetcher: (host, {required timeout}) async => 1234,
        );
        addTearDown(container.dispose);
        await container.read(ntpSyncControllerProvider.future);

        await container
            .read(ntpSyncControllerProvider.notifier)
            .syncNow('time.example.com');
        final state = container.read(ntpSyncControllerProvider).value!;
        final prefs = await container.read(sharedPreferencesProvider.future);

        expect(state.status, NtpSyncStatus.synced);
        expect(state.offsetMs, 1234);
        expect(state.serverHost, 'time.example.com');
        expect(prefs.getString(ntpServerHostKey), 'time.example.com');
      },
    );

    test('falls back to failed, but still persists the host', () async {
      SharedPreferences.setMockInitialValues({});
      final container = _buildContainer(
        fetcher: (host, {required timeout}) async =>
            throw Exception('no network'),
      );
      addTearDown(container.dispose);
      await container.read(ntpSyncControllerProvider.future);

      await container
          .read(ntpSyncControllerProvider.notifier)
          .syncNow('unreachable.example.com');
      final state = container.read(ntpSyncControllerProvider).value!;
      final prefs = await container.read(sharedPreferencesProvider.future);

      expect(state.status, NtpSyncStatus.failed);
      expect(state.offsetMs, 0);
      expect(prefs.getString(ntpServerHostKey), 'unreachable.example.com');
    });

    test(
      'also falls back to failed for a raw String error (as the ntp '
      'package itself throws on an unresolvable host or empty response)',
      () async {
        SharedPreferences.setMockInitialValues({});
        final container = _buildContainer(
          fetcher: (host, {required timeout}) =>
              Future<int>.error('Could not resolve address for $host.'),
        );
        addTearDown(container.dispose);
        await container.read(ntpSyncControllerProvider.future);

        await container
            .read(ntpSyncControllerProvider.notifier)
            .syncNow('unresolvable.example.com');
        final state = container.read(ntpSyncControllerProvider).value!;

        expect(state.status, NtpSyncStatus.failed);
      },
    );

    test(
      'a failed host persist surfaces as AsyncError instead of proceeding '
      'to sync as if it succeeded',
      () async {
        final previousStore = SharedPreferencesStorePlatform.instance;
        addTearDown(
          () => SharedPreferencesStorePlatform.instance = previousStore,
        );
        SharedPreferences.setMockInitialValues({});
        final store = _FlakyStore.empty();
        SharedPreferencesStorePlatform.instance = store;
        final container = _buildContainer(fetcher: _neverCalled);
        addTearDown(container.dispose);
        await container.read(ntpSyncControllerProvider.future);

        store.failNextWrite = true;
        await container
            .read(ntpSyncControllerProvider.notifier)
            .syncNow('time.example.com');

        expect(
          container.read(ntpSyncControllerProvider),
          isA<AsyncError<NtpSyncState>>(),
        );
      },
    );

    test(
      'lastSyncedAt reflects the NTP-corrected time, not raw device time',
      () async {
        SharedPreferences.setMockInitialValues({});
        const offsetMs = 90000;
        final container = _buildContainer(
          fetcher: (host, {required timeout}) async => offsetMs,
        );
        addTearDown(container.dispose);
        await container.read(ntpSyncControllerProvider.future);

        final before = DateTime.now();
        await container
            .read(ntpSyncControllerProvider.notifier)
            .syncNow(defaultNtpServerHost);
        final after = DateTime.now();
        final syncedAt = container
            .read(ntpSyncControllerProvider)
            .value!
            .lastSyncedAt!;

        expect(
          syncedAt.difference(before).inMilliseconds,
          greaterThanOrEqualTo(offsetMs),
        );
        expect(
          syncedAt.difference(after).inMilliseconds,
          lessThanOrEqualTo(offsetMs + 1000),
        );
      },
    );

    test('blank input falls back to the default host', () async {
      SharedPreferences.setMockInitialValues({});
      final container = _buildContainer(
        fetcher: (host, {required timeout}) async => 0,
      );
      addTearDown(container.dispose);
      await container.read(ntpSyncControllerProvider.future);

      await container.read(ntpSyncControllerProvider.notifier).syncNow('   ');
      final state = container.read(ntpSyncControllerProvider).value!;

      expect(state.serverHost, defaultNtpServerHost);
    });
  });

  group('ntpOffsetMsProvider', () {
    test('is 0 before any successful sync', () async {
      SharedPreferences.setMockInitialValues({});
      final container = _buildContainer(fetcher: _neverCalled);
      addTearDown(container.dispose);
      await container.read(ntpSyncControllerProvider.future);

      expect(container.read(ntpOffsetMsProvider), 0);
    });

    test('reflects the offset from the most recent successful sync', () async {
      SharedPreferences.setMockInitialValues({});
      final container = _buildContainer(
        fetcher: (host, {required timeout}) async => 4321,
      );
      addTearDown(container.dispose);
      await container.read(ntpSyncControllerProvider.future);

      await container
          .read(ntpSyncControllerProvider.notifier)
          .syncNow(defaultNtpServerHost);

      expect(container.read(ntpOffsetMsProvider), 4321);
    });

    test('resets to 0 once a sync fails', () async {
      SharedPreferences.setMockInitialValues({});
      final container = _buildContainer(
        fetcher: (host, {required timeout}) async =>
            throw Exception('no network'),
      );
      addTearDown(container.dispose);
      await container.read(ntpSyncControllerProvider.future);

      await container
          .read(ntpSyncControllerProvider.notifier)
          .syncNow(defaultNtpServerHost);

      expect(container.read(ntpOffsetMsProvider), 0);
    });
  });
}
