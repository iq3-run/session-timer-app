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

## 実機・エミュレータでの動作確認

実機/エミュレータ（BlueStacks等）でUIの見た目を確認する際は、縦画面・横画面の両方で確認する。
どちらかで要素が見切れる場合は、その場で修正せず、まずユーザーに報告して対応方針（レイアウト
調整の要否・優先度など）を確認してから対応する。

## Reviewers configured for this project

- **CodeRabbit** — runs automatically on every push, configured via
  `.coderabbit.yaml` (chill profile, Japanese, auto-review on).
  `gh workflow list` shows no `Codex`-named GitHub Actions workflow (only
  `Flutter CI` and `Markdown Lint`) — but that only rules out an
  Actions-based integration under an obvious name, not a GitHub App
  installation (e.g. Sourcery) or a Codex step embedded in an existing
  workflow under a different name. Don't treat `gh workflow list` alone as
  proof nothing else is wired up; check workflow file contents and the
  repo's installed GitHub Apps if it matters for a decision.
- **Gemini CLI** — invoked manually (`gemini` is installed on this
  machine). This is specific to this project (decided in Issue #1's
  tracking description) — it is not part of the global CLAUDE.md's default
  review flow, so it must be run explicitly at step 3 above. Headless
  invocation needs `--skip-trust` in this environment. Feed it the full
  diff — committed, staged, and unstaged — not just `main...<branch>`,
  since step 3 runs before the change is necessarily committed:

  ```bash
  {
    git diff --no-ext-diff main...HEAD
    git diff --no-ext-diff --cached
    git diff --no-ext-diff
  } | gemini --skip-trust -p "review this diff for ..."
  ```

- **code-reviewer subagent** — keeps persistent memory under
  `.claude/agent-memory/code-reviewer/`. Per the global CLAUDE.md this
  directory MUST be committed to git so it survives across clones and
  sessions.
