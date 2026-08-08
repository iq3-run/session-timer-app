---
name: project-notification-scheduler-patterns
description: Findings from reviewing feat/device-notifications (lib/features/notifications/) — mutation-queue gap for external side effects, and a comment-policy distinction (plan-file citations vs. stable spec-doc citations)
metadata:
  type: project
---

# Device-notifications PR review patterns (2026-08-09)

## Established mutation-queue pattern should extend to fire-and-forget external side effects

This repo already has a deliberate `Future<void> _mutationQueue` + `.then()` chain pattern
(`stopwatch_controller.dart`, `time_targets_controller.dart` — see
[[project_stopwatch_pr_patterns]]) for serializing concurrent async mutations against shared
state. `notification_service.dart`'s `rescheduleAll()` mutates external OS-level shared state
(the plugin's scheduled-notification set: `cancelAll()` then a loop of `zonedSchedule()` calls)
but has **no serialization**, and it's invoked fire-and-forget (`unawaited(...)`) from
`notification_scheduler.dart`'s `ref.listen` callback on every change to
`notificationCandidateEventsProvider` (which recomputes independently whenever completion,
targets, or timer state changes — three separate providers, not batched). Two edits close
together (e.g. adding two time targets quickly) can fire two overlapping `rescheduleAll` calls;
if the older, slower call's later `zonedSchedule` iterations complete *after* the newer call's
`cancelAll()`, stale/wrong notifications get left scheduled. Flagged as **Critical** in the
initial review (2026-08-09) — the fix pattern is the same queue idiom already established
elsewhere in this repo, so if a similar unserialized-async-loop-over-a-platform-channel shows up
in a future PR, cite this precedent immediately rather than treating it as a fresh discovery.

**Watch for this shape generally**: any `ref.listen(...)` callback that calls an `async` method
which itself loops multiple `await`s over a shared external resource (platform channel, file,
network) without a queue/generation-guard is a candidate for this same race, not just in the
notifications module.

## Comment-policy: plan-file citations are task references, not accepted WHY-doc citations

This repo's accepted long-WHY-comment convention (see [[project_stopwatch_pr_patterns]]) already
tolerates citing **stable, persistent** docs like `docs/session-timer-spec.md` (e.g.
`flash_event.dart`'s "3-5節" references) — those describe product behavior independent of any
one PR. `feat/device-notifications` introduced a different pattern: several comments cited
`plans/feat-device-notifications.md` — e.g. `notification_service.dart`'s class doc ("see
plans/feat-device-notifications.md for why this differs...") and its `_notificationId` doc
("accepted, see Items to Confirm in plans/feat-device-notifications.md"), plus
`notification_event_source.dart` and a manifest XML comment. A `plans/*.md` file is this
specific task's planning artifact (analogous to "see issue #123"), which CLAUDE.md's comment
policy explicitly forbids referencing from source comments — the length exemption for WHY-blocks
doesn't cover this per the same precedent already recorded for `ensureRunning()` in
[[project_stopwatch_pr_patterns]]. Flagged as Warning; fix is to inline the actual rationale
(or drop the trailing citation) rather than pointing at the plan file. Watch for this specifically
whenever a PR's own `plans/*.md` gets cited *from inside implementation comments* — distinguish
that from citing `docs/*.md` spec files, which remains fine.

## Resolved (2026-08-09, same PR #21 branch, commit 9cd8790, code-reviewer-driven fix)

The unserialized `rescheduleAll` race above was fixed by adding `_rescheduleQueue` (`Future<void>`
field, synchronous read-then-reassign per call, `.catchError((_) {})` only on the chain-continuation
so the queue itself never gets stuck on a rejected link) — verified on re-review to structurally
match `StopwatchController._mutationQueue`/`_mutate` exactly: atomic synchronous swap (no `await`
between reading `previous` and writing `_rescheduleQueue`, so no interleaving window even with two
synchronous `rescheduleAll()` calls back to back), no dropped calls (every call's `_rescheduleNow`
still runs because `previous` is always the *caught* version), no deadlock. The `init()`
memoization-caches-failure gap noted below was also fixed the same commit
(`_initFuture = null` inside a `catchError`, then `Error.throwWithStackTrace` to rethrow with the
original stack) — reviewed and confirmed this doesn't race `_rescheduleNow`'s internal `await init()`
call: `_initFuture` and `_rescheduleQueue` are independent memoized-future fields, and Dart's
single-threaded event loop means the synchronous portions of each never interleave. `Future.wait`
parallelizing the per-event `zonedSchedule` calls (replacing the old sequential `for` loop) was also
reviewed as safe: each call schedules an independently-keyed notification (no ordering dependency
between them), `cancelAll()` still runs before all of them, and default `eagerError: false` means one
failing `zonedSchedule` no longer aborts scheduling of the remaining events the way the old
sequential loop did — a net robustness improvement, not a lost guarantee.

**Gap found on this re-review, closed same PR**: the fix commit (9cd8790) shipped with no
regression test proving the queue prevents interleaving. A follow-up commit on the same PR #23
branch (7fc4a0b, "test: add regression test for rescheduleAll serialization") added one —
`test/features/notifications/notification_service_test.dart`'s "serializes overlapping calls
instead of interleaving their cancelAll/zonedSchedule steps" test, which gates a mocked
`zonedSchedule` on a `Completer` and asserts the recorded method-call order stays strictly
`cancelAll → zonedSchedule → cancelAll → zonedSchedule` across two overlapping calls, rather than
both `cancelAll`s landing first. **Still no test for `init()` retrying after a failure** — that
gap remains open. Watch whether this becomes a pattern — if a future queue/race fix in this repo
ships without a proving test *and it doesn't get added before merge*, it's worth raising as a
repo-wide gap rather than a one-off.

## `Future<void>? _cache ??= _computeOnce()` memoization pattern — verify failure semantics

`NotificationService.init()` uses `_initFuture ??= _initNow()` to memoize/dedupe concurrent
initializers. This is a fine pattern for the happy path but as written it also **permanently
caches a failure** — if `_initNow()` throws once, every later `init()` call returns the same
already-errored `Future` forever (no retry), silently disabling a "best-effort" feature for the
rest of the app session. Flagged as Warning; the fix is to reset the cached field to `null` in an
error path so the next call retries. Check for this same `??=`-memoize-a-Future shape elsewhere
before assuming any future instance is safe — it depends on whether retry-after-failure was
actually intended.

Related: [[project_stopwatch_pr_patterns]], [[project_readme_maintenance_gap]]
