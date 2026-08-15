package com.iq3run.session_timer

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class CompletionCountdownWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val targetEpochMs =
            widgetData.getString(HomeWidgetKeys.COMPLETION_TARGET_EPOCH_MS, null)?.toLongOrNull()
        val ntpOffsetMs =
            widgetData.getString(HomeWidgetKeys.NTP_OFFSET_MS, null)?.toLongOrNull() ?: 0L

        appWidgetIds.forEach { widgetId ->
            val views =
                RemoteViews(context.packageName, R.layout.completion_countdown_widget_layout)
                    .apply {
                        setOnClickPendingIntent(
                            R.id.widget_container,
                            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                        )
                        // See NextTargetWidgetProvider for why this is gated on API 24+.
                        if (
                            targetEpochMs != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N
                        ) {
                            setChronometer(
                                R.id.chronometer,
                                HomeWidgetTimeMath.countDownBase(targetEpochMs, ntpOffsetMs),
                                null,
                                true,
                            )
                            setChronometerCountDown(R.id.chronometer, true)
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
