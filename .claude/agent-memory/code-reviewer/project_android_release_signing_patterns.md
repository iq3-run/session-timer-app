---
name: project-android-release-signing-patterns
description: Android release signing config (build.gradle.kts Kotlin DSL) review findings — key.properties handling, secret-leak checks
metadata:
  type: project
---

Issue #76 / PR (branch feat/76-release-signing-config, 2026-08-18 JST): first Gradle
Kotlin DSL (non-Dart) review in this repo. `android/app/build.gradle.kts` reads
`android/key.properties` (gitignored, confirmed via both root `.gitignore` line 21
`android/key.properties` and `android/.gitignore`'s own `key.properties`/`**/*.jks`
entries — genuinely double-covered, no leak path) to build a `release` signingConfig,
falling back to the existing debug signingConfig when the file is absent. Fallback
logic and gitignore coverage verified correct.

Two findings raised (not yet confirmed fixed — check on next pass):
1. `keystoreProperties.load(keystorePropertiesFile.inputStream())` (build.gradle.kts
   ~line 12) never closes the stream. Notably, `android/settings.gradle.kts` right
   next to it already does this correctly: `file("local.properties").inputStream()
   .use { properties.load(it) }` — same pattern, same repo, established convention
   the new code didn't follow. Worth checking for on any future Gradle-file-reading
   PR in this repo (Play Store rollout will likely need more, e.g. CI release
   workflow, versioning bumps).
2. `keystoreProperties["keyAlias"] as String` (and 3 siblings) is an unchecked cast
   — if `key.properties` exists but is missing/misspells a key, this throws a bare
   `TypeCastException` with no file path or key name, violating this repo's
   "error messages carry context" rule. Prefer `getProperty(key) ?: error("$key
   missing in ${file.path}")`.

**Why relevant beyond this PR**: this is the first of what's likely a small series
of Play Store rollout PRs (issue #76 plan file scopes out Play Console setup and
paid-unlock as separate future issues) — expect more Gradle/CI config diffs in this
feature area, where the same `.use{}` / unchecked-cast patterns could recur.
