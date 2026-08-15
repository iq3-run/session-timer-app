package com.iq3run.session_timer

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class NextTargetWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val targetEpochMs =
            widgetData.getString(HomeWidgetKeys.NEXT_TARGET_EPOCH_MS, null)?.toLongOrNull()
        val ntpOffsetMs =
            widgetData.getString(HomeWidgetKeys.NTP_OFFSET_MS, null)?.toLongOrNull() ?: 0L

        appWidgetIds.forEach { widgetId ->
            val views =
                RemoteViews(context.packageName, R.layout.next_target_widget_layout).apply {
                    setOnClickPendingIntent(
                        R.id.widget_container,
                        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                    )
                    // setChronometerCountDown (API 24+) is what makes the Chronometer
                    // count down to, then past, targetEpochMs — on an older OS this
                    // falls back to the static placeholder rather than a (wrongly)
                    // counting-up Chronometer.
                    if (targetEpochMs != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
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
