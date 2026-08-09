import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ntp/ntp.dart';
import 'package:session_timer/core/persistence/shared_preferences_provider.dart';

const ntpServerHostKey = 'ntp_server_host';
const defaultNtpServerHost = 'ntp.nict.jp';
const ntpSyncTimeout = Duration(seconds: 5);

enum NtpSyncStatus { unsynced, syncing, synced, failed }

class NtpSyncState {
  const NtpSyncState({
    required this.serverHost,
    this.status = NtpSyncStatus.unsynced,
    this.offsetMs = 0,
    this.lastSyncedAt,
  });

  final String serverHost;
  final NtpSyncStatus status;
  final int offsetMs;
  final DateTime? lastSyncedAt;

  NtpSyncState copyWith({String? serverHost, NtpSyncStatus? status}) {
    return NtpSyncState(
      serverHost: serverHost ?? this.serverHost,
      status: status ?? this.status,
      offsetMs: offsetMs,
      lastSyncedAt: lastSyncedAt,
    );
  }
}

/// Fetches the device-vs-server offset in ms for [host]. Matches
/// `NTP.getNtpOffset`'s signature so the default binding below is a
/// direct tear-off; tests override this provider with a fake so they
/// never open a real socket.
typedef NtpOffsetFetcher =
    Future<int> Function(String host, {required Duration timeout});

Future<int> _fetchViaNtpPackage(String host, {required Duration timeout}) =>
    NTP.getNtpOffset(lookUpAddress: host, timeout: timeout);

/// Blank/whitespace-only input falls back to [defaultNtpServerHost]. Also
/// used by the settings UI so the server field reflects the same
/// normalization `syncNow` applies, instead of showing what the user
/// typed while a different host was actually synced.
String normalizeNtpHost(String host) {
  final trimmed = host.trim();
  return trimmed.isEmpty ? defaultNtpServerHost : trimmed;
}

final ntpOffsetFetcherProvider = Provider<NtpOffsetFetcher>(
  (ref) => _fetchViaNtpPackage,
);

final ntpSyncControllerProvider =
    AsyncNotifierProvider<NtpSyncController, NtpSyncState>(
      NtpSyncController.new,
    );

/// The correction to apply on top of device time; 0 while unsynced,
/// loading, or failed. Read by `now_provider.dart`.
final ntpOffsetMsProvider = Provider<int>(
  (ref) => ref.watch(ntpSyncControllerProvider).value?.offsetMs ?? 0,
);

/// Resolves the persisted (or default) NTP server and, on success, makes
/// [ntpOffsetMsProvider] reflect the server-vs-device offset app-wide via
/// `now_provider.dart`. The device's system clock is never touched — the
/// offset only affects the app's own `DateTime` reads.
///
/// [build] deliberately never queries the network itself — only
/// [syncNow] does. The real "sync automatically on app launch" behavior
/// lives in `main()`, not here, so that pumping the widget tree in tests
/// never opens a socket.
class NtpSyncController extends AsyncNotifier<NtpSyncState> {
  @override
  Future<NtpSyncState> build() async {
    final prefs = await ref.watch(sharedPreferencesProvider.future);
    if (state.hasValue) return state.value!;
    final host = prefs.getString(ntpServerHostKey) ?? defaultNtpServerHost;
    return NtpSyncState(serverHost: host);
  }

  /// Persists [host] regardless of outcome — a failed attempt still
  /// remembers what the user typed, rather than reverting the field.
  /// No mutation queue: the settings UI disables the sync control while
  /// `status == syncing` (or the provider is still loading its initial
  /// persisted host), so at most one call is ever in flight.
  ///
  /// An unexpected `SharedPreferences` failure (not the NTP fetch itself,
  /// which [_attemptSync] already handles) surfaces as `AsyncError` —
  /// matching `CompletionTimeController`/`FlashPointsController` — rather
  /// than leaving `state` stuck at `syncing` forever.
  Future<void> syncNow(String host) async {
    final targetHost = normalizeNtpHost(host);
    try {
      final prefs = await ref.read(sharedPreferencesProvider.future);
      state = AsyncData(
        _current().copyWith(
          serverHost: targetHost,
          status: NtpSyncStatus.syncing,
        ),
      );
      await prefs.setString(ntpServerHostKey, targetHost);
      state = AsyncData(await _attemptSync(targetHost));
    } on Exception catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  // `on Object`, not `on Exception` (unlike syncNow's own catch below) —
  // the `ntp` package's own source completes some failures (unresolvable
  // host, empty response) with a raw `String` via `Future.error(...)`,
  // which doesn't implement `Exception` and would otherwise slip past a
  // narrower catch uncaught.
  Future<NtpSyncState> _attemptSync(String host) async {
    try {
      final offsetMs = await ref.read(ntpOffsetFetcherProvider)(
        host,
        timeout: ntpSyncTimeout,
      );
      return NtpSyncState(
        serverHost: host,
        status: NtpSyncStatus.synced,
        offsetMs: offsetMs,
        lastSyncedAt: DateTime.now(),
      );
    } on Object {
      return NtpSyncState(serverHost: host, status: NtpSyncStatus.failed);
    }
  }

  NtpSyncState _current() =>
      state.value ?? const NtpSyncState(serverHost: defaultNtpServerHost);
}
