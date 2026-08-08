# Fix: expand tap target on the add-target row to full hit area

Issue: <https://github.com/iq3-run/session-timer-app/issues/15>

## Problem

`_AddTargetRow` in `lib/features/targets/time_targets_section.dart`
(the「＋ 指定時刻を追加」row) wraps its content in a `GestureDetector`
without `behavior: HitTestBehavior.opaque`. This is the same pattern
already fixed in `CompletionCountdownSection` and `_TimeTargetRow`
(#13 / PR #14): Flutter's default `deferToChild` behavior only registers
taps where the child actually paints, so the padding around the text
silently swallows taps.

## Fix

Add `behavior: HitTestBehavior.opaque` to the `GestureDetector` in
`_AddTargetRow.build`.

## Verification

- `dart format`
- `flutter analyze`
- `flutter test`
- `flutter build apk --debug` (local debug build)
- Local review: `code-reviewer` subagent + Gemini CLI review (see the
  repo's `CLAUDE.md` review flow), before the PR is created or pushed
