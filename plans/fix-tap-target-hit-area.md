# Fix: expand tap target hit area on completion/time-target rows

Issue: https://github.com/iq3-run/session-timer-app/issues/13

## Problem

`CompletionCountdownSection` and the tap-to-edit `GestureDetector` inside
`_TimeTargetRow` (`time_targets_section.dart`) wrap their content in a
`GestureDetector` without `behavior: HitTestBehavior.opaque`. Flutter's
default (`deferToChild` when a child is present) means taps only register
where the child actually paints — empty padding/gaps between the text lines
silently swallow taps, so the user must tap precisely on the rendered
glyphs instead of anywhere in the row.

Flagged by an independent Gemini CLI review of PR #11, which fixed the
identical issue in the new `StopwatchSection` widget by adding
`behavior: HitTestBehavior.opaque` to its `GestureDetector`.

## Fix

Add `behavior: HitTestBehavior.opaque` to the `GestureDetector` in:

- `lib/features/completion/completion_countdown_section.dart` —
  `CompletionCountdownSection.build`
- `lib/features/targets/time_targets_section.dart` — `_TimeTargetRow.build`

This restores full-row tappability, matching the original HTML prototype
(`docs/session-timer.html`) where the whole `#completeTime`/row area is
clickable, and matches the pattern already used in `StopwatchSection`.

## Out of scope

`_AddTargetRow` in the same file has the same `GestureDetector` pattern but
was not flagged by the review and is not part of this fix.

## Verification

- `dart format`
- `flutter analyze`
- `flutter test`
