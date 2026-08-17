package com.iq3run.session_timer

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

private val TOGGLE_URI = Uri.parse("homewidget://stopwatch/toggle")
private val RESET_URI = Uri.parse("homewidget://stopwatch/reset")

/**
 * Unlike the other three (display-only) widgets, this one has its own start/pause and reset
 * buttons, so it doesn't share [HomeWidgetChronometerPanel] — that panel assumes the whole
 * container is a single "open the app" tap target, which no longer holds once two child views
 * need their own [RemoteViews.setOnClickPendingIntent].
 */
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
        val isRunning = runningSinceEpochMs != null
        val base =
            accumulatedMs?.let {
                HomeWidgetTimeMath.countUpBase(it, runningSinceEpochMs, ntpOffsetMs)
            }

        appWidgetIds.forEach { widgetId ->
            appWidgetManager.updateAppWidget(widgetId, buildViews(context, base, isRunning))
        }
    }

    private fun buildViews(context: Context, base: Long?, isRunning: Boolean): RemoteViews {
        return RemoteViews(context.packageName, R.layout.stopwatch_widget_layout).apply {
            applyOpenAppIntent(context)
            applyChronometerOrPlaceholder(base, isRunning)
            applyToggleButton(context, isRunning)
            applyResetButton(context)
        }
    }

    private fun RemoteViews.applyOpenAppIntent(context: Context) {
        setOnClickPendingIntent(
            R.id.widget_container,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
        )
    }

    private fun RemoteViews.applyChronometerOrPlaceholder(base: Long?, isRunning: Boolean) {
        if (base != null) {
            setChronometer(R.id.chronometer, base, null, isRunning)
            setViewVisibility(R.id.chronometer, View.VISIBLE)
            setViewVisibility(R.id.placeholder, View.GONE)
        } else {
            setViewVisibility(R.id.chronometer, View.GONE)
            setViewVisibility(R.id.placeholder, View.VISIBLE)
        }
    }

    private fun RemoteViews.applyToggleButton(context: Context, isRunning: Boolean) {
        val glyphRes =
            if (isRunning) {
                R.string.home_widget_stopwatch_toggle_pause_glyph
            } else {
                R.string.home_widget_stopwatch_toggle_start_glyph
            }
        val descriptionRes =
            if (isRunning) {
                R.string.home_widget_stopwatch_toggle_pause_description
            } else {
                R.string.home_widget_stopwatch_toggle_start_description
            }
        setTextViewText(R.id.toggle_button, context.getString(glyphRes))
        setContentDescription(R.id.toggle_button, context.getString(descriptionRes))
        setOnClickPendingIntent(
            R.id.toggle_button,
            HomeWidgetBackgroundIntent.getBroadcast(context, TOGGLE_URI),
        )
    }

    private fun RemoteViews.applyResetButton(context: Context) {
        setOnClickPendingIntent(
            R.id.reset_button,
            HomeWidgetBackgroundIntent.getBroadcast(context, RESET_URI),
        )
    }
}
