---
name: project-flash-legible-text-and-overlay-zorder
description: Issue #83 (feat/83-timer-flash-and-legibility) — FlashOverlay moved to background z-order, FlashLegibleText black-stroke widget, timerFlashPointsSeconds addition
metadata:
  type: project
---

# Timer flash timing + flash legibility (issue #83, 2026-09-04)

Reviewed uncommitted working tree (not yet pushed as a PR). `flutter analyze` clean, `flutter
test test/features/flash/` (62 tests) all pass, `dart format --set-exit-if-changed` clean.

## New pattern: `TextStyle.copyWith(foreground: ...)` when the base style already has `color` set

`FlashLegibleText` (`lib/features/flash/flash_legible_text.dart`) does
`style.copyWith(foreground: Paint()..style = PaintingStyle.stroke...)` where `style` already has
a non-null `color`. This looks like it should hit Flutter's `TextStyle` "cannot provide both a
color and a foreground" assertion, but doesn't — verified by reading
`C:\src\flutter\packages\flutter\lib\src\painting\text_style.dart` (Flutter 3.47.0):
`copyWith`'s assert only checks the *parameters passed to copyWith itself*
(`color == null || foreground == null` — both are copyWith's own parameters), not `this.color`
vs the `foreground` parameter. The returned `color:` field is computed as
`this.foreground == null && foreground == null ? color ?? this.color : null` — so passing only
`foreground:` correctly drops the inherited `this.color`, no double-set. Confirmed safe by the
passing widget test (`flash_legible_text_test.dart`) too. If a future PR does the reverse
(`copyWith(color: ...)` on a style that already has `foreground` set), the same reasoning applies
symmetrically — check the source in `C:\src\flutter\packages\flutter\lib\src\painting\text_style.dart`
rather than assuming from the docstring alone if it ever looks suspicious again.

## `timerFlashEvents` regrew past 20 lines by hand-rolling a second builder loop instead of
extracting a sibling helper

`timerFlashEvents` (`lib/features/flash/flash_event.dart`) added `timerFlashPointsSeconds = [30,
15, 10]` handling as a manual `for (final s in timerFlashPointsSeconds) FlashEvent(...)` loop
appended after the existing `_exactPlusMinutesBefore(...)` spread, rather than extracting a
sibling `_secondsBefore` helper mirroring the shape already extracted for minutes (see
[[project_flash_event_builder_patterns]], issue #46). This pushed the function to 23 lines,
crossing the 20-line MUST threshold — first time this specific function has been flagged for
length. The plan file (`plans/feat-timer-flash-and-legibility.md`) explicitly and correctly
argues `_exactPlusMinutesBefore` itself should stay minutes-only (it's shared by
completion/target/timer and generalizing it risks the existing id format/tests) — that reasoning
is sound and doesn't justify skipping a *new*, separate seconds-only helper. Not yet observed
whether this gets fixed before merge; check on any review of a follow-up commit.

## Verified clean, no findings

- `clock_screen.dart`: `FlashOverlay` moved from last child (top of `Stack`) to first (behind
  content) — this is a strict improvement over the tap-through concern raised in review, not just
  a mitigation: previously safety relied entirely on `FlashOverlay`'s `IgnorePointer` wrapper;
  now it's structurally behind everything too. No regression possible either way.
- Id-collision claim in the new code comment (trailing `s` suffix keeps second-based ids from
  colliding with minute-based ones) — hand-verified: `timerFlashPointsMinutes = [5, 3, 1]` vs
  `timerFlashPointsSeconds = [30, 15, 10]` never produce overlapping `id.endsWith(...)` matches
  even in the existing tests that use `endsWith(':$m')`, and the `s` suffix format
  (`timer:$epoch:${s}s`) is unambiguous regardless.
- `FlashQueueController`/`notification_event_source.dart` both consume `timerFlashEvents()`
  generically (spread into a sorted candidate list, admitted/merged by generic `FlashEvent`
  shape) — needed zero changes for the new seconds points, confirmed by reading both files. Same
  as the #46 precedent.
- `docs/session-timer-spec.md` 3-1節 (line 62) was **not** updated to mention the new 30/15/10秒前
  points — still reads "5分前・3分前・1分前、および完了ちょうどの瞬間に単発フラッシュ" only.
  Flagged as a doc-maintenance gap (CLAUDE.md workflow step 5) rather than a code defect.

Related: [[project_flash_event_builder_patterns]], [[project_timer_widget_display_patterns]]
