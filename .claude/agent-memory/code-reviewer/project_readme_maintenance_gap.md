---
name: project-readme-maintenance-gap
description: README.md has not been updated since project bootstrap despite 3 feature PRs merging — recurring CLAUDE.md documentation-maintenance violation, worth flagging each time it's not fixed
metadata:
  type: project
---

`README.md`'s "ディレクトリ構成" section (line ~36) still says
"現時点で実装済みなのは`clock/`と`core/theme/`のみ" (only clock/ and core/theme/ are implemented
so far). `git log --oneline -- README.md` shows it was last touched at project bootstrap
(`51649d5`) — the `targets/` (time-targets-list), `completion/`, and now `stopwatch/` feature PRs
all shipped without updating this line, even though CLAUDE.md has a MUST rule: "check README.md
after changes and update it to reflect the correct specification."

**Why**: this is a real, repeat gap, not a one-off — as of PR #11 (feat/stopwatch) it's the third
feature merged without a README update, so the "only clock/core-theme implemented" line is now
actively wrong.

**How to apply**: flag this as a Warning in any PR that adds a new `features/*` directory or
otherwise changes what's implemented, pointing at README.md's directory-structure section
specifically. If a future PR finally fixes it, remove/update this memory rather than continuing
to flag it.

Related: [[project_stopwatch_pr_patterns]]
