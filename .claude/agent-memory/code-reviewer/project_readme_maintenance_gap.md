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

Related: [[project_stopwatch_pr_patterns]]
