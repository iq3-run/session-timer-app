package com.iq3run.session_timer

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import es.antonborri.home_widget.HomeWidgetProvider

class TimerWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        TimerWidgetSync.apply(context, appWidgetManager, appWidgetIds, widgetData)
    }

    // Last instance removed from the home screen — stop ticking flash
    // alarms nobody will see redrawn.
    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        TimerWidgetFlashScheduler.cancelAll(context)
    }
}
