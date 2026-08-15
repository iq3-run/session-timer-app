package com.iq3run.session_timer

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent

/**
 * Unlike the other three widgets, this one needs no data synced from
 * Flutter at all — the layout's `TextClock` view ticks on its own using the
 * device clock, the same mechanism the OS's own clock widgets use. `onUpdate`
 * only needs to (re)attach the tap-to-open action.
 */
class CurrentTimeWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views =
                RemoteViews(context.packageName, R.layout.current_time_widget_layout).apply {
                    setOnClickPendingIntent(
                        R.id.widget_container,
                        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                    )
                }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
