package com.iq3run.session_timer

import android.appwidget.AppWidgetManager
import android.content.Context
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent

/**
 * Shared rendering for the three Chronometer-driven widgets (stopwatch,
 * next target, completion countdown): attaches the tap-to-open action, then
 * either starts the `Chronometer` at [base] or falls back to the layout's
 * static placeholder when there's no data to show yet.
 */
object HomeWidgetChronometerPanel {
    fun update(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        layoutId: Int,
        base: Long?,
        countDown: Boolean,
        started: Boolean,
    ) {
        val chronometerBase = effectiveBase(base, countDown)
        appWidgetIds.forEach { widgetId ->
            appWidgetManager.updateAppWidget(
                widgetId,
                buildViews(context, layoutId, chronometerBase, countDown, started),
            )
        }
    }

    // setChronometerCountDown is API 24+; on an older OS a count-down
    // widget falls back to the static placeholder rather than a Chronometer
    // that would (wrongly) count up instead of down.
    private fun effectiveBase(base: Long?, countDown: Boolean): Long? {
        if (base == null) return null
        if (countDown && Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return null
        return base
    }

    private fun buildViews(
        context: Context,
        layoutId: Int,
        base: Long?,
        countDown: Boolean,
        started: Boolean,
    ): RemoteViews {
        return RemoteViews(context.packageName, layoutId).apply {
            setOnClickPendingIntent(
                R.id.widget_container,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
            )
            if (base != null) {
                setChronometer(R.id.chronometer, base, null, started)
                if (countDown) setChronometerCountDown(R.id.chronometer, true)
                setViewVisibility(R.id.chronometer, View.VISIBLE)
                setViewVisibility(R.id.placeholder, View.GONE)
            } else {
                setViewVisibility(R.id.chronometer, View.GONE)
                setViewVisibility(R.id.placeholder, View.VISIBLE)
            }
        }
    }
}
