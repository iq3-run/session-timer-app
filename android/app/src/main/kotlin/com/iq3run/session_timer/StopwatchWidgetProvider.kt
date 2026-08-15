package com.iq3run.session_timer

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import es.antonborri.home_widget.HomeWidgetProvider

class StopwatchWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val accumulatedMs =
            widgetData.getString(HomeWidgetKeys.STOPWATCH_ACCUMULATED_MS, null)?.toLongOrNull()
        val runningSinceEpochMs =
            widgetData
                .getString(HomeWidgetKeys.STOPWATCH_RUNNING_SINCE_EPOCH_MS, null)
                ?.toLongOrNull()
        val ntpOffsetMs =
            widgetData.getString(HomeWidgetKeys.NTP_OFFSET_MS, null)?.toLongOrNull() ?: 0L

        HomeWidgetChronometerPanel.update(
            context,
            appWidgetManager,
            appWidgetIds,
            layoutId = R.layout.stopwatch_widget_layout,
            base =
                accumulatedMs?.let {
                    HomeWidgetTimeMath.countUpBase(it, runningSinceEpochMs, ntpOffsetMs)
                },
            countDown = false,
            // A paused stopwatch (runningSinceEpochMs == null) must not keep
            // ticking on the widget just because the Chronometer view itself
            // free-runs once started.
            started = runningSinceEpochMs != null,
        )
    }
}
