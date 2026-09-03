---
name: project-session-plan-patterns
description: Issue #78 (session plan / "1日のセッションの流れ") review findings — cancel-flow verification, TimeTargetsController.upsertTarget, and recurring repo-wide issues re-surfaced by this PR
metadata:
  type: project
---

# Session plan feature (issue #78, branch feat/78-session-plan) review notes

Reviewed 2026-09-03, before PR creation (local review gate). Builds on issue
#79 (per-target titles, already merged as PR #81).

**Cancel-flow across the 3-stage dialog — verified correct, no bug found**:
`session_plan_screen.dart`'s `_editSession`/`_addSession` →
`_promptSessionEnd` → `_promptDurationEnd`/`_promptExactEnd` chain was the
PR's own stated focus area (issue #79 had two independent reviewers catch a
cancel-clobbers-existing-value bug there). Hand-traced every await boundary:
each step checks `if (x == null || !context.mounted) return` before
proceeding, and the controller mutation (`addSession`/`updateSession`) only
fires after the full chain resolves non-null end-to-end. No side effect on
partial cancel at any stage. `_promptDurationEnd`/`_promptExactEnd` don't
re-check `context.mounted` internally after their own dialog await, but this
is fine — they don't touch `context`/`Navigator` again before returning; the
mounted re-check happens at the caller before its next context-touching step,
consistent with `time_targets_section.dart`'s existing `_editTarget`/
`_addTarget` pattern.

**`TimeTargetsController.upsertTarget` — consistent, correctly tested**: new
method mirrors `addTarget`/`updateTarget`'s use of the shared `_mutate`
machinery (filter-out-by-id + append, then `_mutate`'s own `_sorted` restores
epoch order regardless of push order). Two new tests cover create-at-id and
replace-at-id-not-add-second. No `clearTitle` param needed (unlike
`updateTarget`) because upsert always fully replaces the entry rather than
merging into an existing one.

**Doc-comment issue-#/caller self-reference — recurred again, ~7 instances
across 5 new/touched files in one PR**: `session_plan_entry.dart:3`,
`session_plan_controller.dart:13` and `:30`, `session_plan_screen.dart:14`
all cite "issue #78" directly in doc comments. Separately,
`session_plan_controller.dart:16-21` (`autoSessionTargetId` doc),
`time_targets_controller.dart:98-102` (`upsertTarget` doc), and
`current_session_resolution.dart:3` all name the caller UI feature/button
text ("現在のセッションを設定") as the reason for a design decision — this
is the "never reference ... callers" half of the rule, not just the
issue-number half. Distinguish from the accepted "(see
TimeTargetsController (path) for why...)" file-pointer convention (judged OK
in the home-widget PRs) — pointing at a *file* for elaboration is fine;
naming the specific *feature/button* that motivated the code is the
violation. This is now a well-established recurring pattern across the whole
repo (NTP sync, session-schedule, settings-sheet, and now session-plan) —
treat every new instance as a repeat, not a fresh discovery, and cite this
file plus [[project_ntp_sync_patterns]] / [[project_session_schedule_patterns]].

**`SessionPlanEntryButton`/`SessionScheduleEntryButton` — 2nd instance of an
`Align > IconButton > push MaterialPageRoute` entry-button shape**: structurally
identical widget (only tooltip/icon/target screen differ), ~20 lines each.
Per this repo's own established threshold (2-instance = Suggestion, 3rd+ =
Warning — see the ticker-lifecycle-duplication precedent in
[[project_stopwatch_pr_patterns]]), flagged as Suggestion only. If a 3rd
`ClockScreen`-corner entry button appears, escalate to Warning and propose a
shared `ScreenEntryButton({icon, tooltip, screenBuilder})`.

**`resolveCurrentSession` — correct, borderline on the 20-line rule**:
hand-traced against not-started/in-progress/no-next/tie-among-not-ended
cases, all correct and all covered by
`current_session_resolution_test.dart`. Body is ~22 non-blank lines,
slightly over the MUST threshold; flagged as Suggestion (single cohesive
computation, splitting would add indirection for little clarity gain) rather
than Warning.

Related: [[project_stopwatch_pr_patterns]], [[project_session_schedule_patterns]], [[project_ntp_sync_patterns]]
