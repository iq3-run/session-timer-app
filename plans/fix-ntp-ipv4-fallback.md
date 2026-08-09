# Fix: NTP sync fails on networks with a broken IPv6 route

Issue: <https://github.com/iq3-run/session-timer-app/issues/42>

## Problem

NTP sync fails on Wi-Fi/wired connections but succeeds on mobile data,
reported by the user during manual testing.

Investigated by connecting the user's real device (Sony Xperia, Android 13)
via USB and running `adb shell`:

```console
$ adb shell ping ntp.nict.jp      # IPv4
64 bytes from ntp-a3.nict.go.jp (133.243.238.244): ... success

$ adb shell ping6 ntp.nict.jp     # IPv6
100% packet loss
```

The device has a real global IPv6 address on the affected Wi-Fi network
(via a home router), but the IPv6 route to `ntp.nict.jp` is broken —
100% ICMPv6 loss — while IPv4 works fine. This is a known common failure
mode for home routers (incomplete/broken IPv6 UDP forwarding), not
something specific to this app's environment.

`_fetchViaNtpPackage` (`lib/core/clock/ntp_sync_controller.dart`) calls the
`ntp` package's `NTP.getNtpOffset(lookUpAddress: host, ...)`, which
internally does `InternetAddress.lookup(lookUpAddress)` and unconditionally
uses `addresses.first` — no address-family preference. When DNS resolution
returns an IPv6 address first and that route is broken, the NTP UDP request
times out (`ntpSyncTimeout` = 5s) and sync fails. Mobile data doesn't hit
this because its IPv6 path (if any) or address ordering differs.

## Fix

Resolve the host ourselves first via an injectable `DnsLookup` (defaulting
to `InternetAddress.lookup`), and pass a literal IPv4 address through to
`NTP.getNtpOffset` when one is available — falling back to the lookup's
first result (which may be IPv6) only if no IPv4 address was returned, and
to the original hostname if the lookup itself returned nothing.

The IPv4-preference logic is extracted into `preferIPv4Address` (not
private, `@visibleForTesting`) so it can be unit tested directly against a
fake `DnsLookup` without hitting real DNS or opening a socket — matching
this file's existing `NtpOffsetFetcher` injectable-dependency pattern.

Added `meta` as an explicit `pubspec.yaml` dependency (was only a
transitive one) since `@visibleForTesting` needed it.

## Out of scope

- Falling back to IPv6 if IPv4 *also* fails, or trying multiple resolved
  addresses in sequence — the `ntp` package itself doesn't support retrying
  across addresses, and this fix only needed to unblock the common
  broken-IPv6-route case that was actually reported.
- Detecting/reporting the specific reason a sync failed (e.g.
  distinguishing "IPv6 routing broken" from "server unreachable") to the
  user — the existing generic "同期失敗（インターネット接続を確認してください）"
  message is unchanged.

## Verification

- `dart format`
- `flutter analyze`
- `flutter test` (new tests in `test/core/clock/ntp_sync_controller_test.dart`
  for `preferIPv4Address`: prefers IPv4 when both families are returned,
  falls back to the first result when only IPv6 was returned, falls back
  to the original host when the lookup returns nothing)
- Manual: re-test NTP sync on the user's real device, on the Wi-Fi network
  where it previously failed, and confirm it now succeeds.
