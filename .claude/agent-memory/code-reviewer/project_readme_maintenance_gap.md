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

Related: [[project_stopwatch_pr_patterns]]
