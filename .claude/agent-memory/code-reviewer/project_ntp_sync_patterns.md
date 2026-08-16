---
name: project-ntp-sync-patterns
description: Riverpod NTP-sync feature (feat/34-ntp-sync) review findings — build()-in-main() network-isolation pattern verified correct; recurring findings hit again here
metadata:
  type: project
---

# NTP sync feature (issue #34, branch `feat/34-ntp-sync`) review notes

Reviewed 2026-08-09 at commit `8724705` + uncommitted worktree changes (not yet pushed as a PR).

**Network-isolation-via-`main()` pattern — verified correct and safe.**
`plans/feat-ntp-sync.md`'s "Critical constraint" documents that the real
auto-sync-at-launch call must live only in `main()` (never in
`NtpSyncController.build()` or an unconditionally-mounted widget), because
`dart:io` sockets aren't platform-channel-mocked under `flutter test` the
way `flutter_local_notifications` is. Confirmed by reading
`lib/main.dart`/`lib/core/clock/ntp_sync_controller.dart`/
`lib/core/clock/now_provider.dart` and running the full `flutter test`
suite (149 tests, ~32s, no hangs) — no widget test opens a real socket.
This is the same class of reentrancy/deadlock risk category as
`now_provider.dart`'s documented `ref.watch`-at-build-time-not-`ref.read`
-inside-the-stream-body fix; that fix itself is unchanged and still
correct here. If a future PR adds another provider that needs a real
network/plugin call at startup, this `main()`-only pattern is the one to
follow, and `plans/feat-ntp-sync.md`'s constraint section is the reference
to cite.

**Two known recurring violations, both hit again in this PR and fixed
same-session (post-review):**
- `>20-line build()` (see [[project_flash_point_toggle_patterns]] for the
  precedent) — `NtpSyncSettingsSection`'s `build()` was 28 lines. Fixed by
  extracting the host+button `Row` into `_HostSyncRow`, same move as
  `flash_points_settings_section.dart`'s `_FlashPointRow` and this file's
  own pre-existing `_StatusLine`. `build()` is now ~10 lines.
- Doc-comment content rule (see [[project_stopwatch_pr_patterns]]'s
  "Doc-comment content rule" entry — now flagged+fixed 3 times across this
  repo's history) — `ntp_sync_controller.dart`'s class doc said "See
  `plans/feat-ntp-sync.md`." and `main.dart`'s `_autoSyncNtpAtStartup` doc
  said "(spec 3-6)". Both removed; the technical WHY in both comments
  (test isolation, best-effort fallback) was kept as-is. This pattern (an
  agent citing its own plan file/spec section from inside a doc comment
  it just wrote) seems to recur specifically for larger, plan-file-driven
  features — worth a sharper trigger: **before finishing any doc comment
  that explains a design decision, scan it for `plans/`, `issue #`, `spec
  N-N`, or similar self-referential pointers and cut them**, rather than
  relying on catching it at review time.

**Gemini's 3 round-1 findings, independently re-verified here — all
correct fixes, no regressions:**
1. Status-text timestamp now reads `syncState.lastSyncedAt!`, not a fresh
   `DateTime.now()` — confirmed via a dedicated regression test ("the
   synced status text does not change on an unrelated rebuild") that
   actually exercises an unrelated rebuild (editing the milestone field)
   and asserts the NTP status text is unchanged. The `?? DateTime.now()`
   fallback flagged in review (would've silently reintroduced this exact
   bug class if `lastSyncedAt` were ever left unset) was replaced with a
   non-null assertion post-review, so a future regression fails loudly
   instead of silently.
2. Blank-host `TextField` normalization — `_submit()` now writes the
   normalized host back into `_hostController.text`, verified by a
   dedicated test.
3. `syncNow`'s `SharedPreferences.setString` call is inside the method's
   outer `try`/`on Exception catch (e, st) { state = AsyncError(e, st); }`,
   matching the codebase-wide `on Exception` convention used by
   `TimerController`/`FlashPointsController`/etc. Confirmed correct.

**NTP package API verified against the actual installed source, not
memory** (`ntp-2.0.0`, `NTP.getNtpOffset({lookUpAddress, port, localTime,
timeout})`): the app's `_fetchViaNtpPackage` wrapper's named-argument
shape matches, and the offset-sign convention
(`deviceTime.add(Duration(milliseconds: offsetMs))`) matches the package's
own `NTP.now()` implementation exactly. No sign-flip bug.

**`ntp` package quirk worth remembering for future reviews of this
file**: `NTP.getNtpOffset`'s own source completes some failure paths
(unresolvable host, empty response) with a raw `String` via
`Future.error('...')`, not an `Exception`/`Error` instance. That's why
`NtpSyncController._attemptSync` deliberately catches `on Object` while
every other catch in this codebase (including `syncNow`'s own, in the
same file, for `SharedPreferences` failures) uses `on Exception` — this
is a correct, intentional asymmetry, not an inconsistency to flag.

**Follow-up bug (issue #36, branch `fix/36-startup-binding-race`, reviewed
2026-08-09, uncommitted)**: the `main()`-only network-isolation pattern
above created a startup race the original PR review didn't catch —
`unawaited(_autoSyncNtpAtStartup(container))` runs synchronously up to its
first `await`, and `NtpSyncController.build()`'s
`ref.watch(sharedPreferencesProvider.future)` call happens before that
first `await`, so it could reach `SharedPreferences.getInstance()`'s
platform channel before `runApp()` (which normally calls
`WidgetsFlutterBinding.ensureInitialized()` as its first line) ever ran.
Confirmed on a real device via `adb logcat`; the thrown `FlutterError`
(not an `Exception`) escaped `_autoSyncNtpAtStartup`'s `on Exception`
catch and permanently poisoned Riverpod's cached
`sharedPreferencesProvider` future, breaking every feature that persists
through it for the rest of the app session. **Fix confirmed correct**:
add `WidgetsFlutterBinding.ensureInitialized();` as the literal first line
of `main()`, before `ProviderContainer()` and the `unawaited(...)` call.
Verified idiomatic — matches `runApp()`'s own internal first line
(`flutter/src/widgets/binding.dart`), idempotent, and `WidgetsFlutterBinding`
needs no new import since `package:flutter/material.dart` already
re-exports `widgets.dart`. `dart format`/`flutter analyze` clean on the
file. No regression test is possible for this specific race (`main()` is
never invoked by `flutter test`, same reason the network-isolation
pattern above exists) — the plan file (`plans/fix-startup-binding-race.md`)
correctly scopes verification to manual on-device testing only; don't ask
for a widget test that can't exist here. Comment added at the fix site is
a 4-line WHY block — covered by the repo's established multi-line-comment
exemption (see [[project_stopwatch_pr_patterns]]), and doesn't reference
the issue number or plan file, so it doesn't repeat the doc-comment
content violation flagged elsewhere in that file.

**Issue #42 fix (`fix/42-ntp-ipv4-fallback`, reviewed 2026-08-09, staged not yet
committed): IPv6-broken-route fallback in `_fetchViaNtpPackage`.** Root cause
(confirmed via reading `ntp-2.0.0`'s own source, not memory): `NTP.getNtpOffset`
does `InternetAddress.lookup(lookUpAddress)` and always uses `addresses.first`
with no family preference, and critically its `timeout` param only wraps the
*socket receive* step, never the DNS lookup — so the new app-side `dnsLookup`
call this PR adds is not a new unbounded-network-call risk, it's the exact same
previously-unbounded lookup, just relocated. Confirmed no regression.
`preferIPv4Address(host, dnsLookup)` (`@visibleForTesting`, not private) is
correct on all three branches (prefers IPv4, falls back to first/possibly-IPv6
result, falls back to original hostname string on empty list) and a thrown
`dnsLookup` (e.g. real `SocketException` on lookup failure) propagates
unhandled through `_fetchViaNtpPackage` into `_attemptSync`'s existing
`on Object` catch, same as before — verified by reading, not just asserted.
`@visibleForTesting` is a *good* precedent here, not a violation: this is the
first use in the repo, and it's the objectively correct idiom for unit-testing
a function that's conceptually private but can't be (Dart privacy is per-file,
so a real `_`-prefixed top-level function is unreachable from
`test/.../*_test.dart`). Don't second-guess this pattern in future reviews —
cite it as the precedent if another pure helper needs the same treatment.
`pubspec.yaml`/`pubspec.lock` diff was minimal as expected (`meta` promoted
transitive → direct main, matching version already resolved, no unrelated
bumps).

**Doc-comment content rule — recurred a 4th time here**, same violation
category as [[project_stopwatch_pr_patterns]]'s entry: the new
`preferIPv4Address` doc comment includes "(issue #42)" inline. This is now
4 occurrences across this repo's history (`ensureRunning()`,
`feat/settings-sheet-shell`'s 6 files, `main.dart`'s `_autoSyncNtpAtStartup`
"(spec 3-6)", now this). The multi-line-WHY-block *length* exemption is
solid and shouldn't be re-litigated, but the *content* rule (no issue/task/
plan-file self-references) keeps slipping past the agent that writes the
code, not just past review — worth flagging clearly enough in review comments
that it gets fixed before commit rather than caught after.

**Issue #59 fix (`fix/59-ntp-release-internet-permission`, reviewed
2026-08-16, uncommitted): missing `INTERNET` permission broke NTP sync in
release APKs only.** Root cause confirmed real (not just plan-file
claim): `android/app/src/main/AndroidManifest.xml` never declared
`android.permission.INTERNET`, while `android/app/src/debug/AndroidManifest.xml`
and `android/app/src/profile/AndroidManifest.xml` both already declare it
(standard Flutter-template boilerplate, own comment: "required for
development... hot reload"). Those two variant-specific manifests merge
in only for debug/profile builds; release only merges `src/main`, so it
alone needed the explicit declaration. Fix (single line, first
`uses-permission` entry, plus a WHY comment) is correct and minimal;
nothing else in the repo (tests, lint config, proguard, README/docs)
assumes `INTERNET` is absent, and no connectivity-check plugin
(`connectivity_plus` etc.) is in use, so no second permission was needed.
**Doc-comment content rule stayed clean this time** — the new comment
does not self-reference "issue #59" or the plan file, unlike the pattern
above; worth noting as the fix sticking, not just a one-off pass.
**New, non-recurring finding**: the comment's causal claim — "Flutter's
tooling auto-grants this in debug/profile builds" — is imprecise. It's
not a runtime/ADB auto-grant; it's manifest merging from the sibling
`src/debug`/`src/profile` AndroidManifest.xml fragments (confirmed by
reading them), which is a materially different mechanism for a future
maintainer to know about if a similar release-only gap shows up for a
different permission. Flag the wording, not the fix itself.

Related: [[project_stopwatch_pr_patterns]], [[project_flash_point_toggle_patterns]]
