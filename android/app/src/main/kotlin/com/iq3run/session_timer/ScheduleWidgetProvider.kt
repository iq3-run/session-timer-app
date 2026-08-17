package com.iq3run.session_timer

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Unlike the other six (Chronometer/TextClock self-driving, or plain static
 * text) widgets, this one hosts a variable-length `ListView` backed by
 * [ScheduleWidgetService]'s `RemoteViewsFactory` — the standard Android
 * pattern for a scrollable collection inside an AppWidget. [onUpdate] only
 * wires up the adapter and the click target; the row data itself is read
 * independently by [ScheduleRemoteViewsFactory] from the same `home_widget`
 * SharedPreferences store, since that factory runs in the widget host's own
 * process.
 */
class ScheduleWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            appWidgetManager.updateAppWidget(widgetId, buildViews(context, widgetId))
            // setRemoteAdapter alone doesn't reload an already-bound widget instance's row
            // data — this is what actually triggers ScheduleRemoteViewsFactory.onDataSetChanged().
            appWidgetManager.notifyAppWidgetViewDataChanged(widgetId, R.id.schedule_list)
        }
    }

    private fun buildViews(context: Context, widgetId: Int): RemoteViews {
        return RemoteViews(context.packageName, R.layout.schedule_widget_layout).apply {
            setOnClickPendingIntent(
                R.id.widget_header,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
            )
            val serviceIntent =
                Intent(context, ScheduleWidgetService::class.java).apply {
                    // A distinct data URI per widget instance so the OS doesn't treat every
                    // instance's factory as interchangeable/cacheable across widget ids.
                    data = Uri.parse("homewidget://schedule/$widgetId")
                }
            setRemoteAdapter(R.id.schedule_list, serviceIntent)
            setEmptyView(R.id.schedule_list, R.id.schedule_empty)
        }
    }
}
