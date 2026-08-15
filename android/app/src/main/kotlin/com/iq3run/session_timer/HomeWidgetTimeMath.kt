package com.iq3run.session_timer

import android.os.SystemClock

/**
 * Converts wall-clock ("epoch") state pushed from Flutter into a
 * [android.widget.Chronometer.setBase]-style value in
 * [SystemClock.elapsedRealtime] terms, so a widget's `Chronometer` can
 * free-run without further updates from this app. `ntpOffsetMs` folds in
 * the same correction `lib/core/clock/now_provider.dart` applies app-wide,
 * so the widget's displayed time stays consistent with the app's own
 * NTP-corrected clock rather than this device's raw wall clock.
 */
object HomeWidgetTimeMath {
    fun countUpBase(accumulatedMs: Long, runningSinceEpochMs: Long?, ntpOffsetMs: Long): Long {
        val nowEpochMs = System.currentTimeMillis() + ntpOffsetMs
        val elapsedMs =
            if (runningSinceEpochMs != null) {
                accumulatedMs + maxOf(0L, nowEpochMs - runningSinceEpochMs)
            } else {
                accumulatedMs
            }
        return SystemClock.elapsedRealtime() - elapsedMs
    }

    /**
     * Base for a `Chronometer` in count-down mode
     * ([android.widget.Chronometer.setCountDown]) so it continues ticking
     * into negative values past [targetEpochMs] instead of stopping at
     * zero — matching this app's own overdue display convention (see
     * `formatCountdown` in lib/core/clock/duration_format.dart).
     */
    fun countDownBase(targetEpochMs: Long, ntpOffsetMs: Long): Long {
        val nowEpochMs = System.currentTimeMillis() + ntpOffsetMs
        val remainingMs = targetEpochMs - nowEpochMs
        return SystemClock.elapsedRealtime() + remainingMs
    }
}
