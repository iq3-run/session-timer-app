# Feat: NTP time sync

Issue: <https://github.com/iq3-run/session-timer-app/issues/34>

## Scope (confirmed with the user before starting)

- **Sync mechanism: real UDP NTP protocol** via the `ntp` pub package
  (`NTP.getNtpOffset`, port 123) — not the HTML prototype's HTTP time API
  (`worldtimeapi.org`). A raw NTP query is what makes a free-text "server"
  field meaningful (NICT's `ntp.nict.jp` is a real NTP server, not an HTTP
  endpoint).
- **Server field: free-text input, default `ntp.nict.jp`.** The typed
  hostname persists across app restarts (`shared_preferences`).
- **The offset itself is NOT persisted.** Every real app launch
  (`main()`, not just building the widget tree) attempts one automatic
  sync against the persisted (or default) host; until/unless that
  succeeds, the app runs on device time (offset 0). This was the user's
  explicit choice over "persist both host and offset" and "persist
  nothing."
- Per spec 3-6: on successful sync, ALL app-wide time math switches to the
  NTP-corrected instant (`nowProvider`, and therefore every screen that
  calls `watchNow`); on failure, silently fall back to device time. The
  device's system clock itself is never touched — the offset is applied
  only inside the app's own `DateTime` reads.

## Out of scope

- Persisting the last successful offset across restarts (see above).
- Any change to how the flash/notification scheduling logic itself
  consumes "now" — it already goes through `nowProvider`/`watchNow`, so
  once the offset is wired in there, every downstream feature gets it for
  free with zero changes to flash/notification/timer/target code.

## Critical constraint: no real network calls from widget tests

`nowProvider` is watched by `ClockScreen`/`CurrentTimeDisplay`, which every
existing widget test built on `SessionTimerApp` (`test/widget_test.dart`)
or `SettingsGearButton` (`test/features/settings/settings_sheet_test.dart`)
pumps without any NTP-specific override today. If the NTP auto-sync were
triggered from a provider's `build()` or from a widget mounted
unconditionally in `app.dart`, every one of those tests would kick off a
real UDP socket call to `ntp.nict.jp` — `dart:io` sockets are NOT
platform-channel-mocked under `flutter test` the way `flutter_local_notifications`
is, so this would actually hit the network (flaky, slow, blocked in
sandboxed CI, and `RawDatagramSocket.timeout()`'s internal `Timer` is
liable to trip "A Timer is still pending" test failures).

Fix: the real auto-sync-at-launch trigger lives **only in `main()`**, never
in `NtpSyncController.build()` and never in a widget `app.dart` mounts
unconditionally:

```dart
// lib/main.dart
void main() {
  final container = ProviderContainer();
  unawaited(_autoSyncAtStartup(container));
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const SessionTimerApp(),
    ),
  );
}

Future<void> _autoSyncAtStartup(ProviderContainer container) async {
  final initial = await container.read(ntpSyncControllerProvider.future);
  await container
      .read(ntpSyncControllerProvider.notifier)
      .syncNow(initial.serverHost);
}
```

`widget_test.dart` and `settings_sheet_test.dart` build `SessionTimerApp`/
`SettingsGearButton` directly inside their own fresh `ProviderScope`, never
calling `main()` — so they stay exactly as network-free as they are today,
by construction, with no per-test opt-out to remember. `NtpSyncController.build()`
only loads the persisted hostname and returns an `unsynced` state; it does
not touch the network.

Widget tests that DO exercise the sync button (new NTP settings-section
tests, and the existing "ntp sync button" case in `settings_sheet_test.dart`)
must override `ntpOffsetFetcherProvider` with a fake — this is the one
seam the whole feature is built around (see below).

## New module: `lib/core/clock/ntp_sync_controller.dart`

```dart
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

  NtpSyncState copyWith({...});
}

/// Fetches the device-vs-server offset in ms for [host]. Matches
/// `NTP.getNtpOffset`'s signature so the default binding is a direct
/// tear-off; tests override this provider with a fake instead of hitting
/// a real socket.
typedef NtpOffsetFetcher = Future<int> Function(String host, {required Duration timeout});

Future<int> _fetchViaNtpPackage(String host, {required Duration timeout}) =>
    NTP.getNtpOffset(lookUpAddress: host, timeout: timeout);

final ntpOffsetFetcherProvider =
    Provider<NtpOffsetFetcher>((ref) => _fetchViaNtpPackage);

final ntpSyncControllerProvider =
    AsyncNotifierProvider<NtpSyncController, NtpSyncState>(NtpSyncController.new);

/// The correction to apply on top of device time; 0 while unsynced,
/// loading, or failed. Read by `now_provider.dart`.
final ntpOffsetMsProvider = Provider<int>(
  (ref) => ref.watch(ntpSyncControllerProvider).value?.offsetMs ?? 0,
);

class NtpSyncController extends AsyncNotifier<NtpSyncState> {
  @override
  Future<NtpSyncState> build() async {
    final prefs = await ref.watch(sharedPreferencesProvider.future);
    if (state.hasValue) return state.value!;
    final host = prefs.getString(ntpServerHostKey) ?? defaultNtpServerHost;
    return NtpSyncState(serverHost: host); // no network here — see above
  }

  /// Called both by the settings-sheet button and by `main()`'s one-shot
  /// startup attempt. Persists [host] regardless of outcome (so a failed
  /// sync still remembers what the user typed).
  Future<void> syncNow(String host) async {
    final targetHost = host.trim().isEmpty ? defaultNtpServerHost : host.trim();
    final prefs = await ref.read(sharedPreferencesProvider.future);
    state = AsyncData(_current().copyWith(
      serverHost: targetHost,
      status: NtpSyncStatus.syncing,
    ));
    await prefs.setString(ntpServerHostKey, targetHost);
    try {
      final offsetMs = await ref.read(ntpOffsetFetcherProvider)(
        targetHost,
        timeout: ntpSyncTimeout,
      );
      state = AsyncData(NtpSyncState(
        serverHost: targetHost,
        status: NtpSyncStatus.synced,
        offsetMs: offsetMs,
        lastSyncedAt: DateTime.now(),
      ));
    } on Object {
      state = AsyncData(NtpSyncState(
        serverHost: targetHost,
        status: NtpSyncStatus.failed,
      ));
    }
  }

  NtpSyncState _current() =>
      state.value ?? const NtpSyncState(serverHost: defaultNtpServerHost);
}
```

No mutation queue (unlike `FlashPointsController`): the settings UI
disables the sync button while `status == syncing` (and while the
provider itself is still loading its initial persisted host), so at most
one `syncNow` call is ever in flight — nothing to serialize.

## `lib/core/clock/now_provider.dart`

```dart
final nowProvider = StreamProvider<DateTime>((ref) {
  final offsetMs = ref.watch(ntpOffsetMsProvider);
  return _tickingClock().map((t) => t.add(Duration(milliseconds: offsetMs)));
});

Stream<DateTime> _tickingClock() async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now());
}
```

`ref.watch` at the top of the builder (not `ref.read` inside the
generator) — an earlier draft called `ref.read(ntpOffsetMsProvider)` from
inside `_tickingClock`'s `async*` body, which deadlocked: that body only
starts running once something actually listens to the stream, and reading
a second, unrelated provider from within that listen-time execution
reentered the container in a way it never recovered from (`flutter test`
hung for the full 30s timeout, in both a full-app widget test and a
minimal bare-`StreamProvider` repro with no NTP code involved at all).
Watching at build-time is the standard, always-safe Riverpod path — a
successful/failed sync changes `ntpOffsetMsProvider`, Riverpod rebuilds
`nowProvider` (tearing down and restarting the periodic ticker), and the
correction is visible on the very next tick after that, not up to 1s
later as an earlier draft assumed. `watchNow(WidgetRef ref)` itself is
unchanged.

Also note for any future test of `nowProvider` itself: `container.read(nowProvider.future)`
hangs indefinitely for a bare `StreamProvider` in this project's Riverpod
version unless something is also `listen()`ing (confirmed with a minimal
repro unrelated to this feature) — `.future` works fine on the
`AsyncNotifierProvider`-based `NtpSyncController`, just not here. Use
`container.listen(nowProvider, callback)` instead (see
`test/core/clock/now_provider_test.dart`).

## `lib/features/settings/ntp_sync_settings_section.dart`

Add a hostname `TextField` (same row layout as `_AddMilestoneRow`/
`_AddFlashPointRow`: `Expanded(TextField) + FilledButton`), seeded once
from the controller's current `serverHost` via a `TextEditingController`
in a small `ConsumerStatefulWidget`. Button disabled and status forced to
"同期中…" while `status == syncing` or the provider is still loading.
Status text:

- `unsynced` → `未同期（端末時刻を使用中）` (existing constant, unchanged)
- `syncing` → `同期中…`
- `synced` → `同期完了（誤差補正 ${offsetMs}ms） / ${HH:mm:ss of lastSyncedAt}`
  (`intl` `DateFormat('HH:mm:ss')`, matching `CurrentTimeDisplay`'s own
  formatting — `syncState.lastSyncedAt`, not a live clock read, so the
  timestamp doesn't jump on an unrelated rebuild)
- `failed` → `同期失敗（インターネット接続を確認してください）` (same
  wording as the HTML prototype)

## `lib/features/settings/settings_sheet.dart`

Drop `_ntpStatusText`/`_syncNow` entirely; watch `ntpSyncControllerProvider`
and pass its `AsyncValue<NtpSyncState>` down, same shape as how
`flashPointsControllerProvider` is already wired into `_sections`.

## `lib/main.dart`

Switch to `UncontrolledProviderScope` + a startup `syncNow` call, as shown
above.

## `pubspec.yaml`

Add `ntp: ^2.0.0` via `flutter pub add ntp` (confirmed resolvable against
this project's existing dependency set).

## Tests

- `test/core/clock/ntp_sync_controller_test.dart` (new):
  - `build()` loads a persisted host if present, else defaults to
    `ntp.nict.jp`; does not call the offset fetcher.
  - `syncNow` success: state becomes `synced` with the fetched offset;
    host is persisted.
  - `syncNow` failure (fetcher throws): state becomes `failed`; host is
    still persisted (so the field doesn't revert on a failed attempt).
  - `syncNow('')`/whitespace falls back to `defaultNtpServerHost`.
  - All via `ProviderContainer(overrides: [ntpOffsetFetcherProvider.overrideWithValue(fake)])`
    — never the real `NTP.getNtpOffset`.
- `test/core/clock/now_provider_test.dart` (new): `ntpOffsetMsProvider`
  reflects the controller's `offsetMs` (0 while unsynced/failed, the
  fetched value once synced) — a pure/deterministic check, avoiding any
  assertion on absolute `DateTime.now()` values.
- `test/features/settings/settings_sheet_test.dart`: replace the existing
  placeholder-text "ntp sync button flips the status text" test with one
  that types a host, taps sync, and asserts the real `synced`/`failed`
  status text via an overridden `ntpOffsetFetcherProvider`. Extend
  `_pumpAndOpenSheet`'s `ProviderScope` to always include a default fake
  `ntpOffsetFetcherProvider` override (deterministic, no network) so every
  other test in that file stays network-free without having to know NTP
  exists.

## Verification

- `dart format`
- `flutter analyze`
- `flutter test`
- debug build
- BlueStacks/device: type a real hostname (or leave the NICT default),
  tap sync, confirm the status line and confirm the completion countdown
  visibly reflects the corrected time.
