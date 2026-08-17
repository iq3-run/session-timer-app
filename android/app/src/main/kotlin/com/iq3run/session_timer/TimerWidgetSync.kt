package com.iq3run.session_timer

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent

/**
 * Redraws every [TimerWidgetProvider] instance from [widgetData] and
 * (re)arms [TimerWidgetFlashScheduler] for the next flash windows. Called
 * both from `onUpdate` (when Flutter pushes a new target) and from
 * [TimerWidgetFlashReceiver] (when a previously scheduled flash tick
 * fires) — the same entry point either way, since both just mean "the
 * flash state may have changed, redraw now and re-plan ahead".
 *
 * Doesn't share [HomeWidgetChronometerPanel]: unlike the other two
 * Chronometer-driven display widgets, this one has a flash state the
 * shared panel doesn't model — the same reason [StopwatchWidgetProvider]
 * stays independent of it.
 */
object TimerWidgetSync {
    fun apply(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val targetEpochMs =
            widgetData.getString(HomeWidgetKeys.TIMER_TARGET_EPOCH_MS, null)?.toLongOrNull()
        val ntpOffsetMs =
            widgetData.getString(HomeWidgetKeys.NTP_OFFSET_MS, null)?.toLongOrNull() ?: 0L
        val flashing =
            TimerWidgetFlashPoints.isFlashing(targetEpochMs, ntpOffsetMs, System.currentTimeMillis())
        // Unlike Completion/NextTarget, TimerState.targetEpochMs is built from
        // raw DateTime.now() and the in-app countdown compares it against raw
        // DateTime.now() too (timer_section.dart's _TimerBody), not the
        // NTP-corrected nowProvider — so the Chronometer base must not apply
        // ntpOffsetMs here, even though the flash windows above correctly do
        // (they mirror FlashQueueController, which compares this same raw
        // target against NTP-corrected "now").
        val base = targetEpochMs?.let { HomeWidgetTimeMath.countDownBase(it, ntpOffsetMs = 0L) }

        appWidgetIds.forEach { widgetId ->
            appWidgetManager.updateAppWidget(widgetId, buildViews(context, base, flashing))
        }
        TimerWidgetFlashScheduler.reschedule(context, targetEpochMs, ntpOffsetMs)
    }

    private fun buildViews(context: Context, base: Long?, flashing: Boolean): RemoteViews {
        return RemoteViews(context.packageName, R.layout.timer_widget_layout).apply {
            setOnClickPendingIntent(
                R.id.widget_container,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
            )
            applyFlashState(base, flashing)
        }
    }

    private fun RemoteViews.applyFlashState(base: Long?, flashing: Boolean) {
        setInt(
            R.id.widget_container,
            "setBackgroundResource",
            if (flashing) R.drawable.home_widget_background_flash else R.drawable.home_widget_background,
        )
        if (flashing) {
            // Mirrors FlashOverlay covering the whole screen with an opaque
            // amber box — the countdown is hidden, not just recolored,
            // while a flash window is open.
            setViewVisibility(R.id.label, View.GONE)
            setViewVisibility(R.id.chronometer, View.GONE)
            setViewVisibility(R.id.placeholder, View.GONE)
            return
        }
        setViewVisibility(R.id.label, View.VISIBLE)
        applyChronometerOrPlaceholder(base)
    }

    // setChronometerCountDown is API 24+; on an older OS a count-down base
    // falls back to the static placeholder rather than a Chronometer that
    // would (wrongly) count up instead of down — matches
    // HomeWidgetChronometerPanel.effectiveBase.
    private fun RemoteViews.applyChronometerOrPlaceholder(base: Long?) {
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
