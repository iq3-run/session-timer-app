---
name: project-android-release-signing-patterns
description: Android release signing config (build.gradle.kts Kotlin DSL) review findings — key.properties handling, secret-leak checks
metadata:
  type: project
---

# Android release signing config (issue #76, branch `feat/76-release-signing-config`)

Reviewed 2026-08-18 JST: first Gradle Kotlin DSL (non-Dart) review in this repo.
`android/app/build.gradle.kts` reads `android/key.properties` (gitignored, confirmed
via both root `.gitignore` line 21 `android/key.properties` and
`android/.gitignore`'s own `key.properties`/`**/*.jks` entries — genuinely
double-covered, no leak path) to build a `release` signingConfig, falling back to
the existing debug signingConfig when the file is absent. Fallback logic and
gitignore coverage verified correct.

Two findings raised, both fixed in the same PR before merge (confirmed via
`git show` on the follow-up commit):

1. `keystoreProperties.load(keystorePropertiesFile.inputStream())` never closed the
   stream — fixed to `keystorePropertiesFile.inputStream().use { keystoreProperties
   .load(it) }`, matching `android/settings.gradle.kts`'s existing convention
   (`file("local.properties").inputStream().use { properties.load(it) }`) one file
   over. Worth checking for on any future Gradle-file-reading PR in this repo.
2. `keystoreProperties["keyAlias"] as String` (and 3 siblings) was an unchecked
   cast that threw a bare `TypeCastException` with no file path or key name on a
   missing/misspelled key — replaced with a `requiredKeystoreProperty(key)` helper
   that fails with `"$key is missing in ${keystorePropertiesFile.path}"`.

CodeRabbit's remote review (same PR) additionally flagged
`buildTypes.release.signingConfig` falling back to the debug signingConfig when
`android/key.properties` is absent, as a CWE-16 security-misconfiguration risk
(a "release" build could ship debug-signed without erroring). Deliberately kept
as-is: this fallback is unchanged from the repo's pre-existing behavior (every
release build was unconditionally debug-signed before this PR; the PR only adds
an opt-in path to real signing), matches Flutter's own official recommended
pattern (flutter.dev/to/review-gradle-config), and Play Console itself rejects
uploads signed with the default debug certificate — so the residual risk is a
confusing local build result, not an actual path to a bad Play Store release.
Revisit only if this repo ever gains multiple contributors building release
APKs for reasons other than local testing.

**Why relevant beyond this PR**: this is the first of what's likely a small series
of Play Store rollout PRs (issue #76 plan file scopes out Play Console setup and
paid-unlock as separate future issues) — expect more Gradle/CI config diffs in this
feature area, where the same `.use{}` / unchecked-cast patterns could recur.
