package com.iq3run.session_timer

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import com.iq3run.session_timer.TimerWidgetCountdown.applyChronometerOrPlaceholder
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

private val START_URI = Uri.parse("homewidget://timer/start")
private val ADD_30_URI = Uri.parse("homewidget://timer/add30")
private val ADD_60_URI = Uri.parse("homewidget://timer/add60")
private val RESET_URI = Uri.parse("homewidget://timer/reset")

/**
 * The "operable" timer widget: start/+30s/+1min/reset buttons, no flash effect — flash stays
 * exclusive to [TimerWidgetProvider]'s display-only widget. Doesn't share [TimerWidgetSync]:
 * that object drives a flash state machine this widget doesn't have, the same reason
 * [StopwatchWidgetProvider] doesn't share [HomeWidgetChronometerPanel].
 */
class TimerControlWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val targetEpochMs =
            widgetData.getString(HomeWidgetKeys.TIMER_TARGET_EPOCH_MS, null)?.toLongOrNull()
        val base = TimerWidgetCountdown.base(targetEpochMs)

        appWidgetIds.forEach { widgetId ->
            appWidgetManager.updateAppWidget(widgetId, buildViews(context, base))
        }
    }

    private fun buildViews(context: Context, base: Long?): RemoteViews {
        return RemoteViews(context.packageName, R.layout.timer_control_widget_layout).apply {
            setOnClickPendingIntent(
                R.id.widget_container,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
            )
            applyChronometerOrPlaceholder(base)
            applyButton(context, R.id.start_button, START_URI)
            applyButton(context, R.id.add30_button, ADD_30_URI)
            applyButton(context, R.id.add60_button, ADD_60_URI)
            applyButton(context, R.id.reset_button, RESET_URI)
        }
    }

    private fun RemoteViews.applyButton(context: Context, viewId: Int, uri: Uri) {
        setOnClickPendingIntent(viewId, HomeWidgetBackgroundIntent.getBroadcast(context, uri))
    }
}
