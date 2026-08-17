package com.iq3run.session_timer

import android.os.Build
import android.view.View
import android.widget.RemoteViews

/**
 * The countdown Chronometer/placeholder rendering shared by [TimerWidgetSync]
 * (the flash-driven display widget) and [TimerControlWidgetProvider] (the
 * button-driven controls widget) — both read the same `TIMER_TARGET_EPOCH_MS`
 * and swap the same two views, only their surrounding state (flash windows vs.
 * buttons) differs, which is why they otherwise stay independent
 * `AppWidgetProvider`s rather than sharing a common one.
 */
object TimerWidgetCountdown {
    // Unlike Completion/NextTarget, TimerState.targetEpochMs is built from raw
    // DateTime.now() and the in-app countdown compares it against raw
    // DateTime.now() too (timer_section.dart's _TimerBody), not the
    // NTP-corrected nowProvider — so this base must not apply ntpOffsetMs,
    // unlike the other three widgets.
    fun base(targetEpochMs: Long?): Long? =
        targetEpochMs?.let { HomeWidgetTimeMath.countDownBase(it, ntpOffsetMs = 0L) }

    // setChronometerCountDown is API 24+; on an older OS a count-down base
    // falls back to the static placeholder rather than a Chronometer that
    // would (wrongly) count up instead of down.
    fun RemoteViews.applyChronometerOrPlaceholder(base: Long?) {
        val effectiveBase = if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) null else base
        if (effectiveBase != null) {
            setChronometer(R.id.chronometer, effectiveBase, null, true)
            setChronometerCountDown(R.id.chronometer, true)
            setViewVisibility(R.id.chronometer, View.VISIBLE)
            setViewVisibility(R.id.placeholder, View.GONE)
        } else {
            setViewVisibility(R.id.chronometer, View.GONE)
            setViewVisibility(R.id.placeholder, View.VISIBLE)
        }
    }
}
