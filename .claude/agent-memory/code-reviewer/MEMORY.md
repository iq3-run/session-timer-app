# Code-reviewer memory index

- [Stopwatch PR patterns](project_stopwatch_pr_patterns.md) — mutation-queue/.then()/multi-line-comment/GestureDetector-300ms/cross-controller-ref.read patterns; mutation-queue skeleton now 4 instances (2026-08-09, flash-points PR) — extraction is now a Warning, not Suggestion. `_applyStartupRules` (flash_points_controller.dart) was flagged for length 2026-08-09 (commit 3c569c4) and fixed same-PR (commit 4c8ddfc) by extracting `_defaultsToKeep`/`_customsToKeep`
- [README maintenance gap](project_readme_maintenance_gap.md) — recurred a 6th time in feat/flash-points-persistence (2026-08-09); next recurrence should be raised directly to the user, not just logged
- [Notification scheduler patterns](project_notification_scheduler_patterns.md) — rescheduleAll race/init-memoization fixed+verified 2026-08-09 (commit 9cd8790); regression test added same PR (7fc4a0b); init()-retry-after-failure still untested
