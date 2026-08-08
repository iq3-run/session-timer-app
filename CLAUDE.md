# session-timer-app — Claude Code Project Notes

This file holds rules specific to this repository. It supplements — does not
replace — the user's global `~/.claude/CLAUDE.md`, which still governs
everything not covered here (branching, commit prefixes, coding style, the
Bug Fix / Feature Request Workflow, etc.).

## Review flow

Every implementation change goes through two review gates, always in this
order:

1. **実装** — implement the change.
2. **テスト** — `dart format` / `flutter analyze` / `flutter test` (and a
   debug build) locally.
3. **ローカルレビュー（push前）** — independent review before the PR is
   created or pushed:
   - `code-reviewer` subagent
   - Gemini CLI review (see below)
   - Apply valid fixes. If a fix introduces non-trivial new logic, repeat
     step 3 on that fix before moving on — a fix isn't reviewed just
     because the code it replaced was.
4. **PR** — open the PR, or push an additional commit if one already exists.
5. **リモートレビュー（push後）** — CI (`Flutter CI`, `Markdown Lint`) and
   CodeRabbit review the pushed commit.
   - Apply valid fixes. If a fix introduces non-trivial new logic, go back
     to step 3 (local review) before pushing again — a CodeRabbit-driven
     fix doesn't get to skip the local review gate just because CodeRabbit
     is the one that asked for it.
6. Merge only after both gates are clean and CI is green. Confirm with the
   user before merging.

Do not reorder steps 3 and 5 — local review must finish before the PR is
pushed, not be treated as an optional afterthought once CI/CodeRabbit are
already clean.

## Reviewers configured for this project

- **CodeRabbit** — runs automatically on every push, configured via
  `.coderabbit.yaml` (chill profile, Japanese, auto-review on). No Sourcery
  or Codex Action is configured in this repo — `gh workflow list` only shows
  `Flutter CI` and `Markdown Lint`.
- **Gemini CLI** — invoked manually (`gemini` is installed on this
  machine). This is specific to this project (decided in Issue #1's
  tracking description) — it is not part of the global CLAUDE.md's default
  review flow, so it must be run explicitly at step 3 above. Headless
  invocation needs `--skip-trust` in this environment, e.g.:

  ```bash
  git diff main...<branch> | gemini --skip-trust -p "review this diff for ..."
  ```

- **code-reviewer subagent** — keeps persistent memory under
  `.claude/agent-memory/code-reviewer/`. Per the global CLAUDE.md this
  directory MUST be committed to git so it survives across clones and
  sessions.
