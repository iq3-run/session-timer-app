package com.iq3run.session_timer

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

private const val ACTION_FLASH_TICK = "com.iq3run.session_timer.action.TIMER_WIDGET_FLASH_TICK"

// PendingIntent identity is keyed on (requestCode, target component, action,
// data, type, categories), so targeting TimerWidgetFlashReceiver already
// keeps these distinct from every other PendingIntent in this app —
// this offset just keeps the eight codes below readable as a group.
private const val REQUEST_CODE_BASE = 9100

/**
 * Schedules the native alarms that redraw [TimerWidgetProvider] at the start
 * and end of each of [TimerWidgetFlashPoints]'s windows, so the widget's
 * background flips even while this app isn't running. Mirrors
 * `NotificationService.rescheduleAll`'s cancel-and-rebuild approach and
 * `_scheduleMode`'s exact-alarm permission fallback.
 */
object TimerWidgetFlashScheduler {
    /**
     * Cancels every previously scheduled tick for this widget, then — if
     * [targetEpochMs] is set — re-schedules one pair (window-start,
     * window-end) per point in [TimerWidgetFlashPoints.deviceWindows] that
     * hasn't fully passed yet. A point whose window is already open (e.g.
     * the app was reopened mid-flash) still gets its end tick scheduled, so
     * the widget doesn't get stuck showing the flash forever — the caller
     * is expected to have just redrawn with the current (already-flashing)
     * state itself.
     */
    fun reschedule(context: Context, targetEpochMs: Long?, ntpOffsetMs: Long) {
        cancelAll(context)
        if (targetEpochMs == null) return

        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
        if (alarmManager == null) return
        val exact = canScheduleExact(alarmManager)
        val nowDeviceMs = System.currentTimeMillis()

        TimerWidgetFlashPoints.deviceWindows(targetEpochMs, ntpOffsetMs)
            .forEachIndexed { index, (windowStartMs, instantMs) ->
                if (instantMs <= nowDeviceMs) return@forEachIndexed
                if (windowStartMs > nowDeviceMs) {
                    schedule(alarmManager, context, windowStartMs, requestCode(index, 0), exact)
                }
                schedule(alarmManager, context, instantMs, requestCode(index, 1), exact)
            }
    }

    fun cancelAll(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
        if (alarmManager == null) return
        for (index in TimerWidgetFlashPoints.MINUTES_BEFORE.indices) {
            alarmManager.cancel(pendingIntent(context, requestCode(index, 0)))
            alarmManager.cancel(pendingIntent(context, requestCode(index, 1)))
        }
    }

    // Exact scheduling requires the user to have granted "Alarms & reminders"
    // on Android 12+; below that, declaring the (normal, pre-S) permission
    // in the manifest is enough. Falls back to inexact rather than failing.
    private fun canScheduleExact(alarmManager: AlarmManager): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()
    }

    private fun schedule(
        alarmManager: AlarmManager,
        context: Context,
        triggerAtMs: Long,
        requestCode: Int,
        exact: Boolean,
    ) {
        val pendingIntent = pendingIntent(context, requestCode)
        if (exact) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                triggerAtMs,
                pendingIntent,
            )
        } else {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pendingIntent)
        }
    }

    // edge: 0 = window start (flash on), 1 = window end (flash off).
    private fun requestCode(pointIndex: Int, edge: Int) = REQUEST_CODE_BASE + pointIndex * 2 + edge

    private fun pendingIntent(context: Context, requestCode: Int): PendingIntent {
        val intent = Intent(context, TimerWidgetFlashReceiver::class.java)
        intent.action = ACTION_FLASH_TICK
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
