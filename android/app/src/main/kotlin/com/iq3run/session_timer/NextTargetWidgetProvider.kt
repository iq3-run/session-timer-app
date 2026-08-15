package com.iq3run.session_timer

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
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

        HomeWidgetChronometerPanel.update(
            context,
            appWidgetManager,
            appWidgetIds,
            layoutId = R.layout.next_target_widget_layout,
            base = targetEpochMs?.let { HomeWidgetTimeMath.countDownBase(it, ntpOffsetMs) },
            countDown = true,
            started = true,
        )
    }
}
