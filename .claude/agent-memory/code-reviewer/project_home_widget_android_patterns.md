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

**RESOLVED same PR.** **Critical, native-only bug — `StopwatchWidgetProvider.kt` hardcodes
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

**RESOLVED same PR.** **DRY across the 3 synced `AppWidgetProvider`s (`StopwatchWidgetProvider`,
`NextTargetWidgetProvider`, `CompletionCountdownWidgetProvider`)** — near-identical `onUpdate`
skeleton (read `ntpOffsetMs`, `forEach widgetId` build `RemoteViews` with the same click-intent +
chronometer-or-placeholder visibility toggle). Each individual `onUpdate` is also ~40 lines,
over the 20-line function mandate — extracting the shared RemoteViews-building logic into a
helper (e.g. an object taking the layout resource + chronometer base + a `PendingIntent`) would
resolve both the DRY and the length finding at once. Flagged as Warning, not yet extracted as of
this review (first review of this feature area, so not "recurring" yet — but worth watching,
this codebase's precedent is that unresolved DRY skeletons recur across PRs until explicitly
extracted, see [[project_stopwatch_pr_patterns]]'s mutation-queue-skeleton history).

**RESOLVED same PR.** **`for`-loop-with-early-return instead of functional iteration — 2nd
confirmed instance in this repo.** `next_time_target.dart`'s `nextTimeTarget()` uses `for (final target in targets) { if
(...) return target; }` instead of `firstWhere`/`firstWhereOrNull`. First instance was
`lib/app.dart`'s `resolveDeviceLocale` (flagged as Warning in
[[project_session_schedule_patterns]]'s 2026-08-14 entry, issue #52) — that one hasn't been
converted either. Treat this as an established recurring gap in this repo, not a fresh
one-off; flag as Warning each time it appears.

**RESOLVED same PR.** **Comment-policy: `AndroidManifest.xml`'s new `<receiver>` block cites
`(issue #54)` directly.**
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

**Issue #61 (branch `feat/61-widget-size-label-unify`, reviewed 2026-08-17, resource/manifest-only
diff, no Dart touched).** Unified all 4 `*_widget_info.xml` to `targetCellWidth="2"`
`targetCellHeight="1"` (API 31+ cell-size hint) and gave each `<receiver>` in `AndroidManifest.xml`
a distinct `android:label` + each widget-info XML an `android:description`, via 8 new
`widget_picker_label_*`/`widget_picker_description_*` strings kept deliberately separate from the
pre-existing `home_widget_label_*` (in-widget text) — verified every receiver → xml file → label/
description string mapping is correct (stopwatch/next_target/completion/current_time all line up).
Deliberately did NOT lower `minWidth`/`minHeight` from the `110dp`/`90dp` set in #55/#58 (rejecting
the issue's own suggested 1-cell literal `minHeight=40dp`) because unsupported launchers fall back
to `minHeight` and 90dp is load-bearing for the text-clipping fix from that earlier PR — a
deliberately-bent-looking value that is actually correct, don't re-flag it. `targetCellWidth`/
`targetCellHeight` verified as safe additive API 31+ attributes given this repo's
`compileSdk = flutter.compileSdkVersion` (unpinned, resolves well above 31); older launchers/API
levels just ignore the attribute and fall back to `minWidth`/`minHeight`. New XML comment in
`strings.xml` explaining picker-strings vs `home_widget_label_*` is 2 lines but matches this
project's existing multi-line-XML-comment convention throughout `AndroidManifest.xml`
(pre-existing, not this PR) — not flagged, unlike the past issue-#-self-reference violations in
this same file. No README update needed — README's widget section describes the 4-panel behavior,
not picker-naming/cell-size internals, and isn't stale.

**Issue #62 (branch `feat/62-stopwatch-widget-buttons`, reviewed 2026-08-17, uncommitted working
tree, not yet pushed).** Interactive start/pause + reset buttons on the stopwatch widget only,
via `HomeWidgetBackgroundReceiver` + `HomeWidgetBackgroundIntent.getBroadcast` two-URI scheme
(`homewidget://stopwatch/toggle` / `/reset`). Design verified sound: `Uri.pathSegments.first` vs
`Uri.host` semantics hand-verified with a real `dart run` (host is the URI *authority*
`"stopwatch"`, action is the first path segment — the code and its comment are both correct);
RemoteViews child-view `setOnClickPendingIntent` correctly overriding the parent
`widget_container`'s "open app" intent only within the child's bounds is standard, documented
Android behavior, not a novel risk. `flutter analyze`/`flutter test`/`dart format
--set-exit-if-changed` all independently re-run clean on every touched file.

Findings from the first review pass (working tree, pre-commit) — all fixed same PR before the
first commit landed, in response to that pass:
- `StopwatchWidgetProvider.buildViews` (was 44 lines) — split into `applyOpenAppIntent`/
  `applyChronometerOrPlaceholder`/`applyToggleButton`/`applyResetButton`, each under 20 lines.
  RESOLVED.
- `android.os.Build` dead import in `StopwatchWidgetProvider.kt` — removed. RESOLVED.
- Issue-#-self-reference in `StopwatchWidgetProvider.kt`'s class doc comment ("issue #62") and
  `stopwatch_widget_layout.xml`'s button-row comment ("see issue #62") — both removed. Same
  banned category tracked since issue #54 (1st XML instance); this PR added a 2nd XML instance
  and a new Kotlin-doc-comment instance, both now fixed. RESOLVED.
- `_reloadNow()` in both `StopwatchController`/`TimerController` had no try/catch around
  `prefs.reload()`/`_readPersisted`, unlike the sibling `_mutateNow` and unlike
  `home_widget_scheduler.dart`'s own `_syncStopwatch`/etc. — both `unawaited(...reloadFromDisk())`
  call sites meant a failure would surface as a genuinely unhandled Future error. Both now wrap
  in `try { ... } on Exception catch (e) { debugPrint(...) }`. RESOLVED.

Adjudicated, left as-is:
- New sub-pattern from this PR: several WHY comments name a *specific related file* inline (e.g.
  `stopwatch_widget_callback.dart:8` "(see `StopwatchWidgetProvider.kt`...)",
  `AndroidManifest.xml:69` "(see lib/features/home_widget/stopwatch_widget_callback.dart)").
  Judged OK, not a CLAUDE.md violation: this matches the repo's own pre-existing convention
  (`stopwatch_controller.dart`'s "See TimeTargetsController (path) for why mutations are
  serialized..." predates this PR) of pointing to a *collaborating* file for architectural
  context, which is different in kind from referencing *the current task/fix/caller* (the thing
  CLAUDE.md actually bans, per the `ensureRunning()` precedent in
  [[project_stopwatch_pr_patterns]]). Not flagged as a fix; noting the distinction so a future
  review doesn't re-litigate it from scratch.
- `reloadFromDisk()`/`_reloadNow()` added to both `StopwatchController` and `TimerController` are
  byte-for-byte identical (11 lines each) — the plan file explicitly discusses and re-defers the
  `MutationQueueNotifier<T>` extraction, citing the same prior deferral tracked in
  `.claude/agent-memory` (task_d15ba35c). Deliberate, documented, consistent with precedent.

CodeRabbit's own follow-up pass (after the first commit, before merge) caught two things this
review's first pass missed:
- `toggle_button`/`reset_button` in `stopwatch_widget_layout.xml` had no `minWidth`/`minHeight`,
  well under Android's 48dp accessibility touch-target minimum, despite the widget having grown
  to 110dp×110dp specifically to fit them. Fixed by adding explicit 48dp minimums — **but this
  first fix was itself incomplete**: two 48dp-wide buttons + the existing 12dp gap need 108dp
  alone, which combined with the container's own padding (16dp) and margin (8dp) needs ~132dp,
  exceeding the 110dp `minWidth` the widget still declared. CodeRabbit's own auto-tracking marked
  its comment "✅ Addressed in commit d46cec2" purely because the diff touched the flagged lines
  (added `minWidth`/`minHeight`) — it did not re-verify the arithmetic, and a manual check caught
  the real overflow. Actually fixed by widening `stopwatch_widget_info.xml` to `minWidth="150dp"`
  / `targetCellWidth="3"` (a 3rd commit). **Lesson: don't trust CodeRabbit's own "Addressed"
  auto-tag as proof a fix is complete — it can fire on a pattern match (the flagged attribute now
  exists) without checking whether the fix actually solves the underlying constraint.**
- `test/features/home_widget/home_widget_sync_service_test.dart`'s `_FakeHomeWidgetGateway.valueOf`
  used `.lastWhere(...)` with no `orElse`, throwing `StateError` instead of returning `null` for
  an unsaved key — violating `getWidgetData`'s nullable contract. Latent (no test in that file
  actually hit the throw path) but a real footgun for future tests. Fixed with `.lastOrNull`.

**Post-merge-ready, on-device (BlueStacks) verification found the 150dp width fix above was STILL
wrong** — not a clipping/arithmetic issue this time, a much stranger one: at `minWidth=150dp` the
toggle/reset buttons were entirely absent from the inflated view tree (confirmed via
`uiautomator dump` — not present at all, not just visually clipped), reproducibly, across a full
uninstall/rebuild/reinstall cycle. Widening to `minWidth="220dp"`/`targetCellWidth="4"` fixed it;
root cause not fully isolated (a `Chronometer` sharing a weighted nested `LinearLayout` row with
plain `TextView`s was also tried and didn't inflate as coded — the accessibility tree showed the
time text escaping to its own line regardless of the weight — so the shipped layout reverted to
the original 3-stacked-children structure, just at the wider size). **Lesson: this class of bug
(views silently missing from the inflated RemoteViews tree, not merely mis-sized) is invisible to
`flutter build apk --debug`, `flutter analyze`, and code review — it only surfaces by actually
placing the widget on a device/emulator and dumping the real view hierarchy.** Also found (separate,
unfixed, documented as a known limitation in the plan file): `home_widget` 0.9.3's
`HomeWidgetBackgroundWorker.kt` uses `WorkManager.enqueueUniqueWork(..., ExistingWorkPolicy.APPEND)`
— if a button is tapped before `HomeWidget.registerInteractivityCallback` has ever run (app never
launched once), that first Worker failure permanently blocks all later button taps via the same
APPEND chain, even after the app is later opened and registers the callback. Doesn't affect the
normal flow (open app at least once before/while using the widget) so left as a documented
limitation rather than fixed — it's an upstream plugin bug, not something fixable app-side.

**Issue #70 (branch `feat/70-timer-widget-interactive-android`, reviewed 2026-08-17, staged diff,
not yet pushed).** Operable timer widget (`TimerControlWidgetProvider`, start/+30s/+1min/reset)
alongside display-only `TimerWidgetProvider` (#69), reusing #62's interactive-button pattern.
Introduced `homeWidgetBackgroundCallback` (`home_widget_background_callback.dart`) as a single
`uri.host`-dispatching entry point, confirming via the plugin's own pub-cache source that
`registerInteractivityCallback` can only hold one native callback handle — real constraint, not
speculative. Findings, all RESOLVED same PR (fixed in response to code-reviewer's own first pass,
before pushing):
- Warning, DRY: `TimerControlWidgetProvider.kt`'s `applyChronometerOrPlaceholder` (lines 62-73) was
  byte-for-byte identical to `TimerWidgetSync.kt`'s (lines 85-96), and the `base` computation +
  its explanatory "why ntpOffsetMs=0" comment was duplicated too. Fixed by extracting a new shared
  `TimerWidgetCountdown` object (`base()` + the `applyChronometerOrPlaceholder` extension function)
  used by both `TimerWidgetSync.kt` and `TimerControlWidgetProvider.kt`. This closes the same class
  of DRY-across-AppWidgetProviders gap first flagged in issue #54 (still unextracted as of #61) —
  first time it's actually been fixed rather than deferred in this feature area.
- Warning, test DRY: `_FakeHomeWidgetChannel` (a ~30-line fake `home_widget` method-channel) had
  gone from 1 copy (pre-existing in `stopwatch_widget_callback_test.dart`, from #62) to 3
  byte-for-byte duplicates. Fixed by extracting to a new shared
  `test/features/home_widget/fake_home_widget_channel.dart` (exported as `FakeHomeWidgetChannel`,
  public since it's now cross-file), imported by all 3 test files. First shared test-helpers file in
  this repo.
- Warning, recurring comment-policy violation: 4 `#69`/`#70` issue-self-references in doc comments
  (`TimerControlWidgetProvider.kt`, `home_widget_sync_service.dart`, `stopwatch_widget_callback.dart`,
  `timer_widget_callback.dart`) — same banned category tracked since issue #54 — all removed,
  keeping only the WHY.
- Verified clean: no issue-#-self-reference in the new XML files this time (`timer_control_widget_layout.xml`
  has zero `issue #` occurrences) — the XML-comment instance of this violation (from #54/#62) did
  NOT recur here, unlike the Dart/Kotlin doc-comment instances above.
- Verified correct: `timer_control_widget_info.xml` ships `minWidth="220dp"`/`targetCellWidth="4"`
  from the start (not the too-narrow 110dp/150dp that #62's stopwatch widget had to be walked up to
  after an on-device inflation failure) — the lesson from that earlier bug was applied proactively
  this time. `updatePeriodMillis="1800000"` matches the other 4 synced widgets' existing convention,
  not a fresh magic number. Button semantics (`quickStart(Duration(minutes: 5))`/`addTime`/`reset`),
  the reverse-cascade bug fix (`stopwatch_widget_callback.dart` now also syncs timer state on
  `reset()`'s cascade; `timer_widget_callback.dart` symmetrically syncs stopwatch state since
  `quickStart`/fresh-`addTime` can auto-start it), and `HomeWidgetSyncService.syncTimer` now calling
  `updateWidget` for both `timerWidgetAndroidName`/`timerControlWidgetAndroidName` were all hand-
  verified against `timer_controller.dart`'s actual `quickStart`/`addTime`/`reset`/
  `_autoStartStopwatchIfNeeded` implementations — all accurate, no drift between comment claims and
  code.

**Issue #64 (branch `feat/64-schedule-widget-android`, reviewed 2026-08-17, uncommitted working
tree, not yet pushed).** First `RemoteViewsService`/`RemoteViewsFactory`-backed widget in this repo
(a scrollable `ListView` for the unbounded-length session schedule, vs. the prior 6 widgets' either
self-driving `Chronometer`/`TextClock` or static single-value `RemoteViews`). `ScheduleWidgetProvider`
(`AppWidgetProvider`, wires `setRemoteAdapter`+`setEmptyView`+`notifyAppWidgetViewDataChanged`),
`ScheduleWidgetService` (trivial `RemoteViewsService`), `ScheduleRemoteViewsFactory` (reads
`schedule_events_json` via `HomeWidgetPlugin.getData(context)` directly in `onDataSetChanged`, since
a `RemoteViewsFactory` runs in the widget host's own process and can't share in-memory state with
the provider). Dart side reuses `buildScheduleRows`/`ScheduleRow` from `session_chain.dart` verbatim
via a new `scheduleWidgetRowsProvider`, plus a day-only `scheduleWidgetTodayProvider`
(`nowProvider.select`) so the widget re-syncs once a day instead of every second — verified by
hand-trace to match `SessionScheduleScreen`'s own `today = DateTime(now.year, now.month, now.day)`
exactly (same `watchNow` fallback-to-`DateTime.now()` semantics).
- Warning, no findings from prior instances of this feature area recurred: zero issue-#/plan-file
  self-references in any new file (Kotlin, XML, *and* Dart doc comments) — first time this comment-
  policy violation didn't need fixing at all in this feature area since #54. README's per-file Kotlin
  listing convention confirmed to be one-line-per-`*WidgetProvider.kt` only (support files like
  `HomeWidgetKeys.kt`/`TimerWidgetCountdown.kt` were never listed either) — omitting
  `ScheduleWidgetService.kt`/`ScheduleRemoteViewsFactory.kt` from that list is consistent, not a gap.
- Warning, RESOLVED same PR: `ScheduleRemoteViewsFactory.onDataSetChanged`/`parseRows` had no
  try/catch around `JSONArray(json)` — first native JSON-parsing point in this repo (all prior
  native code used typed `SharedPreferences` getters, no parsing). Gemini CLI's independent review
  flagged the same gap. Fixed by wrapping in `try`/`catch (e: JSONException) { emptyList() }`
  (renamed to `parseRowsSafely`), with a WHY comment explaining the widget-host-process/app-process
  boundary rather than a bare catch.
- Warning, RESOLVED same PR: the plan file's promised `scheduleWidgetTodayProvider` day-only-
  recompute test was missing from the first pass. Added as a `testWidgets` test in
  `schedule_widget_rows_test.dart` driving a `StreamController<DateTime>` override of `nowProvider`
  through `tester.pump()` (a bare `test()` with `Future.delayed(Duration.zero)` between stream
  `add()` calls proved unreliable — one emission was consistently dropped before the final `expect`,
  even though the async chain conceptually should have settled; switching to `tester.pump()` fixed
  it deterministically). Lesson for future `nowProvider`-driven timing tests in this repo: prefer
  `testWidgets`+`tester.pump()` over bare `test()`+`Future.delayed(Duration.zero)` when asserting on
  more than one stream emission.
- Suggestion, RESOLVED same PR: `schedule_widget_list_item.xml`'s `item_label` TextView had a fixed
  `layout_width="48dp"` (not `wrap_content`); labels can reach 4 chars (`"12WE"` — sequence numbers
  grow unboundedly since past events are kept forever) or full-width `"次回CR"`/`"今日"`. Changed to
  `wrap_content` + `minWidth="40dp"`. **On-device (BlueStacks) verification confirmed the fix**: added
  a real `12WE` event (via the settings screen's `番号` override field) and a future `CR` (rendering
  as `次回CR`), placed the widget via `adb shell input draganddrop` (a bare long-press-then-`swipe`
  gesture did NOT register as a drag in Nova Launcher's widget picker — `draganddrop` was needed),
  and confirmed both labels render fully with the `isToday` amber highlight correct and no clipping —
  this milder risk category (TextView wrapping/clipping vs. #62's "views entirely absent from the
  inflated tree") did not recur here. Also verified the header tap opens `MainActivity`
  (`dumpsys window` showed `mFocusedApp` switch) and the widget picker correctly reports the
  `3x4`/`セッションタイマー：スケジュール` label. Home-screen widget layout is governed by the
  launcher's grid, not the app, so this project's portrait/landscape screen-rotation check doesn't
  meaningfully apply here (and Nova Launcher's home screen didn't rotate on this BlueStacks setup
  regardless of the `user_rotation` setting — a launcher limitation, not something in this PR's
  scope) — noted rather than blocked on.
- Also verified: `ContextCompat.getColor` (Gemini CLI's suggestion) replaced a manual
  `Build.VERSION.SDK_INT >= M` branch for the row text color — simplification with no behavior
  change, `androidx.core` already implied available via `android.useAndroidX=true`.
- Verified correct, no findings: `setRemoteAdapter(int viewId, Intent intent)` 2-arg overload (the
  *non*-deprecated one — the 3-arg `appWidgetId`-bundling overload is the deprecated one, easy to get
  backwards) with a per-widgetId-unique `data` URI on the service `Intent` (standard, avoids the OS
  treating every widget instance's factory as interchangeable); `notifyAppWidgetViewDataChanged` is
  what actually triggers `onDataSetChanged` on an already-bound instance (`setRemoteAdapter` alone
  doesn't reload data); `resolveColor`'s `Build.VERSION_CODES.M` gate for `getColor`/deprecated
  `resources.getColor` fallback is real (matches the already-verified pattern that this codebase's
  `minSdk = flutter.minSdkVersion` genuinely goes below API 23); `hasStableIds()=false` justified by
  the synthetic "今日" row + date-rollover row churn (per the plan's own design-decision #3);
  `HomeWidgetPlugin.getData(context)` matches the exact accessor already verified real in
  `TimerWidgetFlashReceiver.kt` (#63). `test/features/home_widget/home_widget_sync_service_test.dart`'s
  `_FakeHomeWidgetGateway.valueOf` (pre-existing, untouched by this diff) is actually a manual
  reverse-scan `for` loop with a comment, not `.lastOrNull` as an earlier memory entry (#62's
  CodeRabbit-follow-up note) described — correcting that detail here; behaviorally equivalent
  (returns `null` for an unsaved key) so not a regression, just a stale memory citation.

Related: [[project_session_schedule_patterns]], [[project_ntp_sync_patterns]], [[project_stopwatch_pr_patterns]], [[project_timer_widget_display_patterns]]
