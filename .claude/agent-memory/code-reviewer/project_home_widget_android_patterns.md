---
name: project-home-widget-android-patterns
description: issue #54 (feat/54-home-widget-android) — 4 Android AppWidgetProviders + Dart sync service review findings
metadata:
  type: project
---

# Home-widget Android feature (issue #54, branch `feat/54-home-widget-android`) review notes

Reviewed 2026-08-15 against the staged diff (not yet pushed as a PR at review time).
`flutter analyze`, `dart format --set-exit-if-changed`, and `flutter test` on the touched
files were all run directly and are clean (10/10 new tests pass, 0 analyzer issues).

**Critical, native-only bug — `StopwatchWidgetProvider.kt` hardcodes
`setChronometer(..., started = true)` regardless of pause state.** `RemoteViews.setChronometer`'s
4th positional arg is `started` (public, stable Android API since API 1): `true` calls
`Chronometer.start()`, so the widget's Chronometer free-runs (ticks upward) even when
`runningSinceEpochMs == null` (app-side stopwatch paused). Confirmed by hand-tracing
`HomeWidgetTimeMath.countUpBase`: when paused, `elapsedMs` is pinned to `accumulatedMs`, but
`started=true` still starts the tick, so the widget visibly drifts upward from the correct
paused value until the next Dart-triggered sync — and since `updatePeriodMillis=1800000` also
fires `onUpdate` with the same stale (unpaused-looking) widgetData every 30 min, this is a
recurring sawtooth, not a one-off glitch. Fix is `started = runningSinceEpochMs != null` instead
of the literal `true`. `NextTargetWidgetProvider`/`CompletionCountdownWidgetProvider` are correct
as `true` — those targets have no "paused" concept, always ticking is right for them. Verified
`RemoteViews.setChronometer`/`Chronometer` display-formula semantics
(`base - elapsedRealtime()` for countdown, `elapsedRealtime() - base` otherwise) and confirmed
`countUpBase`/`countDownBase`'s math is otherwise correct by hand-trace — this is purely the
`started` flag bug, not a base-value bug.

**DRY across the 3 synced `AppWidgetProvider`s (`StopwatchWidgetProvider`,
`NextTargetWidgetProvider`, `CompletionCountdownWidgetProvider`)** — near-identical `onUpdate`
skeleton (read `ntpOffsetMs`, `forEach widgetId` build `RemoteViews` with the same click-intent +
chronometer-or-placeholder visibility toggle). Each individual `onUpdate` is also ~40 lines,
over the 20-line function mandate — extracting the shared RemoteViews-building logic into a
helper (e.g. an object taking the layout resource + chronometer base + a `PendingIntent`) would
resolve both the DRY and the length finding at once. Flagged as Warning, not yet extracted as of
this review (first review of this feature area, so not "recurring" yet — but worth watching,
this codebase's precedent is that unresolved DRY skeletons recur across PRs until explicitly
extracted, see [[project_stopwatch_pr_patterns]]'s mutation-queue-skeleton history).

**`for`-loop-with-early-return instead of functional iteration — 2nd confirmed instance in this
repo.** `next_time_target.dart`'s `nextTimeTarget()` uses `for (final target in targets) { if
(...) return target; }` instead of `firstWhere`/`firstWhereOrNull`. First instance was
`lib/app.dart`'s `resolveDeviceLocale` (flagged as Warning in
[[project_session_schedule_patterns]]'s 2026-08-14 entry, issue #52) — that one hasn't been
converted either. Treat this as an established recurring gap in this repo, not a fresh
one-off; flag as Warning each time it appears.

**Comment-policy: `AndroidManifest.xml`'s new `<receiver>` block cites `(issue #54)` directly.**
Same banned self-reference category tracked extensively in [[project_session_schedule_patterns]]
and [[project_ntp_sync_patterns]] (previously only ever seen in Dart doc comments) — this is the
first instance of the pattern appearing in an XML comment rather than a `///` doc comment. The
rest of the comment (explaining these are independently-addable panels) is fine; only the
`(issue #54)` clause needs to go.

**Verified correct / clean, no findings**: `home_widget` plugin API surface (v0.9.3, read from
the actual pub cache source, not assumed) — `es.antonborri.home_widget` package path,
`HomeWidgetProvider.onUpdate(context, appWidgetManager, appWidgetIds, widgetData)` signature,
`HomeWidgetLaunchIntent.getActivity(context, Class<T>)`, and native `saveWidgetData`/`updateWidget`
handlers (`Class.forName("${packageName}.${androidName}")`, `null` data → `prefs.remove(id)`,
type-branched `putInt`/`putLong`/`putString`) all match what the Dart-side doc comments in
`home_widget_sync_service.dart` claim — the String-serialization Int32/Int64-ambiguity rationale
in that class's doc comment is not speculative, it's an accurate description of the plugin's own
Kotlin source. `home_widget_colors.xml`'s claim to mirror `SessionTimerColors` verified exact
hex-for-hex (amber/cyan/white/muted/red/panel all match `lib/core/theme/session_timer_theme.dart`).
Manifest widget-provider `Build.VERSION_CODES.N` gates are real (not dead defensive code) since
`minSdk = flutter.minSdkVersion` allows pre-24 devices. `nextTimeTarget`'s use of raw
`DateTime.now()` instead of `nowProvider`/NTP-corrected time matches existing precedent
(`time_targets_controller.dart` also uses raw `DateTime.now()`), not a new inconsistency to flag.
No native Kotlin test infra exists anywhere in this repo (`android/app` has no test source set at
all) — absence of a `HomeWidgetTimeMathTest` is consistent with zero prior precedent, Suggestion
only, not a gap introduced by this PR specifically.

Related: [[project_session_schedule_patterns]], [[project_ntp_sync_patterns]], [[project_stopwatch_pr_patterns]]
