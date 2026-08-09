---
name: project-flash-point-toggle-patterns
description: Findings from reviewing feat/22-flash-point-toggles (FlashPointConfig flash/notify toggles) — invariant-only-in-copyWith gap, first over-length Flutter build() method, comment issue-number recurrence
metadata:
  type: project
---

# Flash-point flash/notify toggle PR review patterns (2026-08-09, issue #22)

## Invariant enforced only in `copyWith`, not in the primary constructor — bug class to watch for

**Fixed same-PR (2026-08-09)**: moved the invariant into `FlashPointConfig`'s constructor via the
initializer-list computation shown below. `tryFromJson` and any future call site are safe
automatically now; kept below as a bug-class reference for other models with a similar
cross-field invariant.

`FlashPointConfig`'s doc comment on `copyWith` claims "this is the one place that constraint
[flashEnabled=false forces notifyEnabled=false] is enforced, rather than every call site
remembering to check it." That's true for `copyWith` itself, but the plain `const` constructor
does **not** enforce it, and two real call sites go through the constructor directly instead of
`copyWith`:
- `FlashPointConfig.tryFromJson` builds straight from persisted JSON fields with no invariant
  check — a hand-edited or corrupted `flashEnabled: false, notifyEnabled: true` blob would load
  as-is.
- Three test fixtures (`flash_queue_controller_test.dart`, `flash_points_chip_row_test.dart`,
  `notification_event_source_test.dart`) construct `FlashPointConfig(minutes: X, flashEnabled:
  false)` directly, leaving `notifyEnabled` at its default `true` — i.e. they build the exact
  "impossible" state the feature exists to prevent, and the tests still pass only because every
  consumer (`flash_queue_controller.dart`, `flash_points_chip_row.dart`,
  `notification_event_source.dart`) independently re-derives the effective flag from
  `flashEnabled`/`flashEnabled && notifyEnabled` rather than trusting `notifyEnabled` alone.

No active bug results today because of that redundant downstream filtering, but the "one place
enforced" claim is inaccurate and a future call site that trusts `p.notifyEnabled` in isolation
would be wrong. Flagged as Warning; the fix is to move the invariant into the constructor itself
via an initializer-list computation (works fine with `const`):

```dart
const FlashPointConfig({
  required this.minutes,
  this.flashEnabled = true,
  bool notifyEnabled = true,
}) : notifyEnabled = flashEnabled && notifyEnabled;

final int minutes;
final bool flashEnabled;
final bool notifyEnabled;
```

This is a bug class worth checking for elsewhere in this repo: any model with a `copyWith`-only
enforced cross-field invariant (as opposed to the constructor itself) has the same gap wherever
`tryFromJson` or a test fixture bypasses `copyWith`. `TimeTarget`/`WeekendMilestone` don't have
this specific two-field constraint today, but a future model that adds one should enforce it in
the constructor, not just in `copyWith`.

## First Flutter `build()` method flagged for exceeding 20 lines

**Fixed same-PR (2026-08-09)**: extracted `SettingsRowContainer`/`SettingsDeleteButton` into
`settings_sheet_widgets.dart`, shared by both `SettingsListItem` and `_FlashPointRow`.
`_FlashPointRow.build()` is now well under 20 lines and no longer duplicates the container/
delete-button chrome.

Prior widget `build()` methods in this repo topped out around 24 lines (e.g.
`weekend_milestones_settings_section.dart`'s add-row build), which had not previously been
flagged — declarative widget-tree bodies get some slack versus imperative code. This PR's
`_FlashPointRow.build()` (`flash_points_settings_section.dart`) is 42 lines (signature to closing
brace), roughly double that ceiling, and reimplements `SettingsListItem`'s exact
`Container`/`BoxDecoration(border: Border.all(color: SessionTimerColors.line), borderRadius:
BorderRadius.circular(8))`/delete-`TextButton` styling verbatim instead of extending or wrapping
it — the plan doc explicitly decided not to reuse `SettingsListItem` wholesale because it doesn't
support the two extra `Switch` widgets, which is a legitimate reason not to reuse the *whole*
widget, but doesn't justify re-copying its container chrome and delete-button styling. Flagged as
Warning (length) + Warning (DRY vs. `SettingsListItem`), fix is to extract the shared
decoration/delete-button into something both files use. If a future PR adds a third near-copy of
`SettingsListItem`'s container styling, treat that as a third instance of an already-flagged
pattern.

## Comment issue-number reference — recurred again

`flash_points_settings_section.dart` has two comments citing `issue #22` directly (class doc line
7, inline WHY comment line 89) — the same recurring violation tracked in
[[project_stopwatch_pr_patterns]] (`ensureRunning()`, `settings-sheet-shell`'s six files). Grepped
the rest of the diff; no other file in this PR does this. Fixed reference: drop the `（issue
#22）`/`、issue #22）` trailing citations, keep the WHY.

## Queue-purge gap when a source's candidate set shrinks mid-session — found by CodeRabbit, fixed same-PR

`FlashQueueController.build()` recomputes `candidates` fresh every build from current source
state, but only ever fed new candidates into `_admit()` — it never purged `_queue` entries whose
id dropped out of the current candidate set (e.g. a flash point's `flashEnabled` flipping off
while its event was already sitting in `_queue`, not yet promoted to `_active`). Real bug, but
narrower than CodeRabbit's "Major/already-registered events survive indefinitely" framing — the
window is only `flashAnimationDuration` (3s) wide, so an event can only be mid-queue for a few
seconds total, not indefinitely. Fixed by purging `_queue` entries not present in the current
build's `candidateIds` before the `_admit` loop (`_purgeQueuedEventsNoLongerCandidates`).
Deliberately left `_active` (a currently-*playing* animation) untouched — interrupting it needs
`FlashOverlay`'s completion callback to validate the event id before calling `advance()`, which is
a UX decision (cut the flash short vs. let it finish), not a pure bug fix. Spun out as issue #33
(2026-08-09) rather than bundled into this fix.

General pattern worth watching for in this codebase: any provider that builds a mutable queue/set
incrementally across rebuilds from a recomputed candidate list needs an explicit purge step for
entries that drop out of the candidate set — admission-only logic (`_admit`-shaped) silently
leaves stale entries unless something explicitly diffs against the new candidate set.

### Edge case found reviewing the purge fix itself (commit ebf31f8, 2026-08-09) — fixed same-round

**Fixed** in the immediate follow-up commit: `build()` now watches each of the four
`AsyncValue`s explicitly and only calls `_purgeQueuedEventsNoLongerCandidates` when all four
`hasValue` this build — the guard suggested below, applied wholesale to the purge call site
rather than per-source scoping (simpler, and the purge is the only consumer of `candidates` that
needed it; the `_admit` loop was already safe on a source shrinking for one build).

`_purgeQueuedEventsNoLongerCandidates` trusts `candidates` as ground truth every build, but
`candidates` is built from `ref.watch(...).value` on four `AsyncNotifier`s
(`completionTimeControllerProvider`, `timeTargetsControllerProvider`, `timerControllerProvider`,
`flashPointsControllerProvider`), each with an existing `_persistenceFailure()` path that sets
`state = AsyncError(...)` **without** a retained previous value (confirmed via
`riverpod-3.4.2/lib/src/core/async_value.dart`: `AsyncValue.value` is `_value?.$1`, safely
null — not a throw — so this doesn't crash, it silently empties that source's candidates for the
build). `flashPointsControllerProvider` going to `AsyncError` is the worst case: `flashEnabledMinutes`
becomes `[]`, which zeroes out *every* completion-point flash event from `candidates` — including
ones from flash points that had nothing to do with the failed mutation — and the new purge would
then drop any of those that happened to be sitting in `_queue`. Before this commit, a
source-shrinks-for-one-build glitch just meant "no new admits that build"; now it can actively
erase an already-legitimately-queued event. A real, already-tested path in this repo (see
`flash_points_controller_test.dart`'s "a failed persist surfaces as AsyncError" test), but rare in
practice — a queued (not yet active) item only exists for a ~3s window
(`flashAnimationDuration`) per event, so the failure has to land in that narrow overlap. Raised as
Warning (not Critical) in the ebf31f8 review; not fixed in that commit. If touching this file
again, consider guarding the purge (and ideally the whole `_admit` loop) on `hasValue` for the
four watched providers, or scoping the purge per source-prefix the way `_purgeStaleFiredIds`
already does, rather than diffing against the full merged id set. Don't re-derive the
`AsyncValue.value` semantics from scratch next time — it's confirmed safe (null, not throw) for
riverpod 3.4.2, recorded here so future reviews can cite it directly.

Related: [[project_stopwatch_pr_patterns]], [[project_readme_maintenance_gap]]
