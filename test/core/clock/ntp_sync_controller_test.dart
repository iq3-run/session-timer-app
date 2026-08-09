import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/core/clock/ntp_sync_controller.dart';
import 'package:session_timer/core/persistence/shared_preferences_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProviderContainer _buildContainer({required NtpOffsetFetcher fetcher}) {
  return ProviderContainer(
    overrides: [ntpOffsetFetcherProvider.overrideWithValue(fetcher)],
  );
}

Future<int> _neverCalled(String host, {required Duration timeout}) {
  fail('the offset fetcher must not be called');
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
