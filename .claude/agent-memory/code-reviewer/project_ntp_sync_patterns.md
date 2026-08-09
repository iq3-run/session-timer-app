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

Related: [[project_stopwatch_pr_patterns]], [[project_flash_point_toggle_patterns]]
