package com.iq3run.session_timer

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
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

        appWidgetIds.forEach { widgetId ->
            val views =
                RemoteViews(context.packageName, R.layout.stopwatch_widget_layout).apply {
                    setOnClickPendingIntent(
                        R.id.widget_container,
                        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                    )
                    if (accumulatedMs != null) {
                        setChronometer(
                            R.id.chronometer,
                            HomeWidgetTimeMath.countUpBase(
                                accumulatedMs,
                                runningSinceEpochMs,
                                ntpOffsetMs,
                            ),
                            null,
                            true,
                        )
                        setViewVisibility(R.id.chronometer, View.VISIBLE)
                        setViewVisibility(R.id.placeholder, View.GONE)
                    } else {
                        setViewVisibility(R.id.chronometer, View.GONE)
                        setViewVisibility(R.id.placeholder, View.VISIBLE)
                    }
                }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
