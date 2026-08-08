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

**Resolved (2026-08-08, same PR #18, CodeRabbit-driven fix)**: the
read-then-toggle race in `_autoStartStopwatchIfNeeded()` (CodeRabbit Major
finding) was fixed by adding `StopwatchController.ensureRunning()` — a
check-and-start that happens *inside* the stopwatch's own `_mutate` queue
closure, so it's atomic regardless of caller ordering. This also fully
resolved the stale-snapshot gap noted above: `start()`'s local `stopwatch`
var is now only used for the linked-mode elapsed-time calc, never reused
for the auto-start check. Verified empirically (temp `git worktree` at the
pre-fix commit, same new concurrent-start test copied in) that the new
regression test fails deterministically on the old code and passes on the
new — confirms the test isn't timing-lucky, it's exercising the actual
mutation-queue ordering guarantee.

Two things this fix's *first* review pass caught that CodeRabbit's 3
findings didn't — both already fixed in the same PR, recorded here as
history/pattern, not as current-state issues:
- *Old implementation* (before the follow-up fix): `ensureRunning()`'s
  "start" branch (`StopwatchState(accumulatedMs: s.accumulatedMs,
  runningSinceEpochMs: nowEpochMs)`) was byte-for-byte duplicated from
  `toggle()`'s `!s.isRunning` branch, right above it in the same file — a
  same-file, same-PR DRY miss, not a multi-PR spread-out pattern like the
  mutation-queue skeleton above. *Current state*: both branches now call
  a shared `_startedFrom()` helper. Pattern to remember: flag new
  duplication introduced within the diff itself as Warning immediately —
  don't apply the "wait for a 3rd instance" leniency that applies to the
  older, already-adjudicated repo-wide patterns in this file.
- *Old implementation*: the comment on `ensureRunning()` named its caller
  ("used by TimerController's auto-start-on-timer-start rule") — this
  repo's accepted multi-line-WHY-comment exemption (see below) covers
  *length*, not *content*. CLAUDE.md's "never reference the current task,
  fix, or callers in comments" rule still applies inside a long WHY block.
  *Current state*: the comment no longer names `TimerController`. Pattern
  to remember: don't let the length exemption imply a content exemption
  too.

**Per-widget `Timer.periodic` ticker lifecycle — now duplicated twice**:
`stopwatch_section.dart`'s `_ElapsedTime`/`_ElapsedTimeState` (`Timer? _ticker`
+ `initState`/`didUpdateWidget`/`dispose`/`_syncTicker` starting/stopping
based on `widget.state?.isRunning`) was copied near-verbatim into
`timer_section.dart`'s `_TimerBody`/`_TimerBodyState` in commit 98cb6c5
(2026-08-08, `feat/countdown-timer`), to decouple `TimerSection`'s
remaining/overdue display from the shared `nowProvider` 1s stream. This is
the intended, deliberate mirroring (commit message says so explicitly), and
correct: `didUpdateWidget` fires on every parent rebuild regardless of
whether `TimerState` content changed (Flutter calls it whenever
`canUpdate` — same runtimeType/key — holds, not only on inequality), so
`_syncTicker` reliably reflects the latest `isRunning` each time. Reviewed
as correct, no leaks/double-timers. Flagged the ~25-line duplication as
**Suggestion only** (2nd instance, same threshold as the mutation-queue
pattern above — becomes Warning at a 3rd instance). Also noted: stopwatch
extracts its interval as a top-level `_tickInterval` constant;
`timer_section.dart` inlines `const Duration(seconds: 1)` in `_syncTicker`
instead — minor inconsistency with the very pattern it mirrors, Suggestion
only, not worth a Warning.

**`_maxEpochMs` bound-check constant — was briefly duplicated, now shared
(resolved same PR)**: fixing CodeRabbit's Critical finding on
`TimerState.tryFromJson` (missing the same out-of-range guard
`TimeTarget.tryFromJson` already had) initially copied the private
`const _maxEpochMs = 8640000000000000;` constant (value + doc comment)
verbatim into `lib/features/timer/timer_state.dart`, duplicating the one
already in `lib/features/targets/time_target.dart`. *Current state*: both
files now import a single public `maxEpochMs` from the new
`lib/core/clock/epoch_bounds.dart`; neither has a private copy anymore.
Pattern to remember: if a 3rd persisted-model file needs the same epoch
bound, it should import `epoch_bounds.dart` too rather than adding another
private copy.

Related: [[project_readme_maintenance_gap]]
