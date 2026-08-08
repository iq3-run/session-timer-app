---
name: project-stopwatch-pr-patterns
description: Established Dart/Flutter/Riverpod patterns confirmed while reviewing PR #11 (feat/stopwatch) — read before reviewing future controller/persistence PRs in this repo
metadata:
  type: project
---

# Stopwatch PR (#11) review patterns

This repo (session-timer-app, Flutter/Dart) has a deliberate, repeated architecture for
`AsyncNotifier`-backed persisted state, first established in
`lib/features/targets/time_targets_controller.dart` and now duplicated near-verbatim in
`lib/features/stopwatch/stopwatch_controller.dart`:

- A `Future<void> _mutationQueue` chained with `.then()` (not async/await) to serialize
  mutations — this is a deliberate exception to the "async/await over .then()" rule, needed
  because the queue chain itself has to keep running even when a link errors
  (`.catchError((_) {})` swallows it there; the caller's own awaited `Future` still sees the
  error via `state`). Do not flag this `.then()` usage as a violation.
- A `Completer<void> _initialLoad` gate so mutations queued before `build()` finishes don't
  race the initial disk read.
- A `_lastGood` field mutations read/write instead of `state.value`, because a failed persist
  sets `state = AsyncError(...)` (no retained value), which would otherwise strand later
  mutations with nothing to build on.
- Single-JSON-string-per-feature persistence keys (not one key per field) to avoid partial-write
  inconsistency across related fields — see stopwatch's `stopwatch_state_json` merging
  `accumulatedMs` + `runningSinceEpochMs`.

**Why this matters for review**: this ~70-line skeleton (mutation queue + `_lastGood` +
`_initialLoad` + `_persistenceFailure` + `_readPersisted`/`_persist` pair) is now duplicated
between two controllers. It's a real DRY candidate but was a deliberate choice (plan doc says
"follow the same pattern as TimeTargetsController") rather than an oversight — flag as
**Suggestion** only ("consider extracting a shared base/mixin if a third feature repeats this"),
not Warning/Critical, unless a third instance appears, at which point it should become a Warning.

**Comment style**: this codebase uses multi-line (3-6 line) `//` comment blocks throughout
(not just in the stopwatch PR) to explain non-obvious WHY — clock-skew clamping, mutation-queue
rationale, etc. This exceeds CLAUDE.md's "one short line is the cap" rule literally, but it's a
pervasive, pre-existing, uniform convention across the whole repo (see
`time_targets_controller.dart` lines 18-43 for the original instance). Don't flag individual
instances as new violations — note it once per review as an accepted repo-wide style deviation
and move on.

**Gesture handling**: `GestureDetector` with both `onTap` and `onDoubleTap` set delays single-tap
firing by ~300ms (`kDoubleTapTimeout`) while Flutter disambiguates — this is standard Flutter
behavior, not a bug. In `stopwatch_section.dart` this was pre-emptively documented and accepted
as a tradeoff in `plans/feat-stopwatch.md` itself. Don't raise it as an unaddressed finding if the
plan doc already discusses it; do check whether a future PR's plan doc omits that acknowledgment
before raising it fresh.

**`HitTestBehavior.opaque` sweep**: the fix of adding `behavior: HitTestBehavior.opaque` to a bare
`GestureDetector(onTap: ...)` has now landed 3 times — `StopwatchSection` (PR #11, original),
`CompletionCountdownSection` + `_TimeTargetRow` (PR #14, issue #13), and `_AddTargetRow`
(issue #15, branch `fix/add-target-row-tap-area`). Each instance is a one-line, single-widget fix
with its own `onTap` handler, so there's nothing to DRY out (no shared base widget makes sense for
a one-property addition). If a *new* `GestureDetector(onTap: ...)` without `behavior: opaque` shows
up in a future diff in this repo, flag it immediately by analogy — this is now an established repo
convention, not a one-off.

**Worktree local-`main` staleness**: this repo is reviewed from a git worktree
(`.claude/worktrees/<slug>`) whose local `main` ref can lag `origin/main` by several already-merged
commits (seen: local `main` was 4 commits behind `origin/main`, missing an already-merged sibling PR
#14 entirely). Diffing a feature branch against the stale local `main` pulled in PR #14's already-
merged changes as if they were part of the new diff, which would have produced false findings against
code that was already reviewed and shipped. Always `git fetch origin` and diff against `origin/main`
(or verify `git log main..origin/main` is empty) before trusting a `main...HEAD` diff in this repo.

**Cross-controller wiring via `ref.read`, not `ref.watch`**: `feat/countdown-timer`
(2026-08-08) introduced the first two-way link between sibling `AsyncNotifier`
controllers — `StopwatchController.reset()`/`resetAndRestart()` call into
`TimerController` via `ref.read(timerControllerProvider.notifier)`, and
`TimerController.start()`/`quickStart()`/`addTime()` call back into
`StopwatchController` the same way. Neither `build()` method watches the other
provider, so Riverpod's dependency graph has no edge between them and there's
no circular-initialization risk — confirmed safe. This is the pattern to expect
for the shared flash infrastructure task too (deferred from this PR, will likely
touch stopwatch/timer/targets/completion controllers similarly): cross-controller
calls belong in action methods via `ref.read`, never via `ref.watch` in `build()`,
or a genuine cycle becomes possible.

One real gap found in that PR: `TimerController.start()` captures
`stopwatch = await ref.read(stopwatchControllerProvider.future)` once at the top
(needed early for the linked-mode elapsed-time calc), then reuses that same
stale snapshot for the later "auto-start stopwatch if not running" check instead
of re-reading fresh — while the sibling helper `_autoStartStopwatchIfNeeded()`
(used by `addTime`/`quickStart`) does re-read fresh each time. Flagged as Warning
(DRY + staleness). Watch for the same stale-read-reused-later shape in future
cross-controller methods.

Related: [[project_readme_maintenance_gap]]
