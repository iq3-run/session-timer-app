---
name: project-readme-maintenance-gap
description: README.md went unupdated across 3 feature PRs (targets/, completion/, stopwatch/) despite CLAUDE.md's documentation-maintenance rule — fixed in PR #11. Re-flag only if it goes stale again.
metadata:
  type: project
---

# README maintenance gap (resolved in PR #11)

`README.md`'s "ディレクトリ構成" section went unupdated across the `targets/`,
`completion/`, and `stopwatch/` feature PRs, even though CLAUDE.md has a MUST
rule requiring it. Flagged during PR #11's review and fixed in that same PR —
the directory-structure section now lists `completion/`, `targets/`, and
`stopwatch/` as implemented.

**Why this is worth remembering**: it was a repeat gap across 3 PRs in a row,
not a one-off, so it's worth staying alert to a recurrence rather than
assuming a single fix makes it permanent.

**How to apply**: no active issue right now. If a future PR adds a new
`features/*` directory without updating README.md's directory-structure
section, flag it again as a Warning, same as before.

**Recurred in `feat/countdown-timer` (2026-08-08), fixed within the same
PR (#18)**: `lib/features/timer/` was added and wired into
`clock_screen.dart`, but README.md line 36/48 still listed `timer/` under
"今後のPRで追加される想定" (not yet implemented). Flagged as Warning during
that PR's local code-reviewer pass and fixed in the same PR before it was
pushed. If it recurs a second time after this, consider whether the
README-update step needs to become a literal checklist item in
`plans/*.md` templates rather than relying on the CLAUDE.md MUST rule
alone.

**Recurred a 3rd time in `feat/flash-effect` (2026-08-09), fixed within the
same PR (#20)**: `lib/features/flash/` was added and wired into
`clock_screen.dart`. README.md's directory-tree code block (line 49) was
updated to list `flash/` — but the prose sentence just above it (line 36,
"現時点で実装済みなのは...`timer/`で、`flash/`・`settings/`は今後のPRで
追加される想定") was initially not, so it briefly claimed `flash/` wasn't
implemented yet even though the tree right below it said otherwise. Flagged
during this PR's local code-reviewer pass and fixed in the same PR (commit
`d292c5c`) before it was pushed. This is a failure mode worth watching for
specifically: a partial README update (tree updated, prose sentence not)
reads as "the README was touched" at a glance, so don't stop checking at
"was README.md modified in this diff" — diff the prose sentence's file list
against the tree's file list independently. Three recurrences now, all
caught and fixed before merge; the CLAUDE.md MUST rule alone isn't
preventing the initial miss — worth proposing a `plans/*.md` checklist item
to the user if it recurs a 4th time.

**Recurred a 4th time in `feat/device-notifications` (2026-08-09)**: `lib/features/notifications/`
was added and wired into `app.dart`, but README.md's directory-tree code block and its prose
sentence (line 36, still listing only `clock/`・`core/theme/`・`completion/`・`targets/`・
`stopwatch/`・`timer/`・`flash/` as implemented) were both left unupdated — unlike the 3rd
recurrence, this time *neither* the tree nor the prose was touched, so there's no "partial
update" nuance, just a plain miss. Flagged during this PR's local code-reviewer pass. Four
recurrences in a row now (PR #11, #18, #20, and this one) despite the CLAUDE.md MUST rule —
per the standing note below, this is worth proposing to the user as a literal checklist item in
the `plans/*.md` template (e.g. a "Docs" section listing README.md explicitly) rather than
continuing to rely on the prose MUST rule alone, since four fix-after-flag cycles is enough
evidence the rule alone isn't preventing the initial miss.

**Recurred a 5th time in `feat/settings-sheet-shell` (2026-08-09, commit
7a8d370)**: `lib/features/settings/` was implemented (UI-only shell, issue
#24). README.md's directory-tree code block already listed `settings/`
(pre-added in an earlier PR in anticipation), but the prose sentence just
above it (line 36) still says `settings/`は今後のPRで追加される想定
("expected to be added in a future PR") — now stale since it's implemented.
Same partial-update failure mode as the 3rd recurrence (tree right, prose
wrong) but this time the tree was *already* right beforehand and only the
prose needed to flip from future-tense to implemented; the PR didn't touch
README.md at all. Flagged during this PR's local code-reviewer pass and
fixed in the same PR (commit 8b6329c) — then CodeRabbit caught a follow-on
gap the fix didn't cover (the tree's inline comment on `settings/` still
only mentioned milestones/notify/NTP, missing flash points), fixed
separately. Five recurrences now across PR #11, #18, #20,
device-notifications PR, and this one. The
standing proposal (checklist item in `plans/*.md` template) has not been
acted on yet — raise it again next time, more insistently.

**Recurred a 6th time in `feat/flash-points-persistence` (2026-08-09, issue #26)**: this PR wired
flash-point add/remove to real persisted state (`FlashPointsController`), but README.md line 36
still says `settings/`（UIの土台のみ、各項目の実配線は別Issue）— "UI shell only, actual wiring is
a separate issue" — which is now false for the flash-points item specifically (still true for
notification/milestone/NTP, which remain ephemeral). README.md was initially missed in the
commit under review, then corrected within the same PR once flagged. Same
"prose goes stale when a feature crosses from shell to wired" failure shape as the 5th
recurrence (settings-sheet-shell PR), just one level more specific (a sub-clause about `settings/`
rather than whether the whole folder exists). Six recurrences now across PR #11, #18, #20,
device-notifications PR, settings-sheet-shell PR, and this one. The standing proposal (a `plans/*.md`
checklist item for README) has still not been acted on — this is the second time this note says
"raise it more insistently"; if it recurs a 7th time, propose it directly to the user rather than
just recording it here again.

**Recurred a 7th time in `feat/22-flash-point-toggles` (2026-08-09)**: this PR wires the
per-flash-point 通知 toggle into real notification scheduling (`notification_event_source.dart`
now filters on `flashEnabled && notifyEnabled`), but README.md line 36 still says
`settings/`（フラッシュポイントは実配線済み、**通知**/週末マイルストーン/NTP同期は今後のIssue
で実配線予定）— claiming notification wiring is still pending, which is now false for the
per-point notify toggle specifically (global milestone/NTP remain genuinely unwired). Same
"prose goes stale when a feature crosses from shell to wired" shape as the 5th/6th recurrences.
Flagged in this PR's local code-reviewer pass. Per the standing note below (6th recurrence said
"raise it more insistently" a second time), this recurrence was escalated directly to the user
in the review report rather than only logged here — seven recurrences across PR #11, #18, #20,
device-notifications PR, settings-sheet-shell PR, flash-points-persistence PR, and this one is
well past the point where logging alone is doing anything. If an eighth recurrence happens after
this, treat "propose the plans/*.md README checklist item" as overdue rather than a fresh
suggestion.

**Resolved (process fix), 2026-08-09**: the user accepted the escalated proposal. The user's
global `~/.claude/CLAUDE.md` Bug Fix / Feature Request Workflow now has an explicit numbered
step (inserted as step 5, between "implement" and "PR description") requiring a README/docs
staleness check before the PR is opened, called out by name as covering the
"shell-to-wired" failure shape specifically. This is a global rule, not project-specific, so it
applies to every repo's workflow, not just this one. Stop escalating this pattern per-PR now that
the process fix exists — if it recurs *after* this date, that means the new workflow step itself
is being skipped (a different problem: workflow-step compliance), not that the step needs
inventing again. Flag that distinction if it comes up.

Related: [[project_stopwatch_pr_patterns]], [[project_notification_scheduler_patterns]]
