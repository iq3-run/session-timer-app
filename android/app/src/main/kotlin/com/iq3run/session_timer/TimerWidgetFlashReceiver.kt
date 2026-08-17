package com.iq3run.session_timer

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Fires when a [TimerWidgetFlashScheduler] alarm reaches its trigger time.
 * Not exported: only ever targeted by a `PendingIntent` this app creates
 * for its own scheduled ticks (see `StopwatchWidgetProvider`'s background
 * button receiver for the same exported=false reasoning).
 */
class TimerWidgetFlashReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val appWidgetIds =
            appWidgetManager.getAppWidgetIds(ComponentName(context, TimerWidgetProvider::class.java))
        if (appWidgetIds.isEmpty()) return
        TimerWidgetSync.apply(context, appWidgetManager, appWidgetIds, HomeWidgetPlugin.getData(context))
    }
}
