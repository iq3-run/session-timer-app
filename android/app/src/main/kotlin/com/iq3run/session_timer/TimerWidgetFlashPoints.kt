package com.iq3run.session_timer

/**
 * Mirrors `timerFlashPointsMinutes` + the exact-completion (0分) point from
 * lib/features/flash/flash_event.dart, and `flashAnimationDuration` from the
 * same file. Kept as plain data (not a shared constant with Dart, which
 * isn't possible across the platform boundary) — if the Dart side changes
 * these, update here too.
 */
object TimerWidgetFlashPoints {
    val MINUTES_BEFORE = listOf(5, 3, 1, 0)
    const val FLASH_WINDOW_MS = 3000L
    private const val MILLIS_PER_MINUTE = 60_000L

    /**
     * One (deviceWindowStartMs, deviceInstantMs) pair per point in
     * [MINUTES_BEFORE], converted from the NTP-corrected instant the app
     * would show to the device's own [System.currentTimeMillis] terms that
     * `AlarmManager.RTC_WAKEUP` needs (`correctedNow = deviceNow +
     * ntpOffsetMs`, solved for deviceNow).
     */
    fun deviceWindows(targetEpochMs: Long, ntpOffsetMs: Long): List<Pair<Long, Long>> {
        return MINUTES_BEFORE.map { minutes ->
            val instant = targetEpochMs - minutes * MILLIS_PER_MINUTE
            val windowStart = instant - FLASH_WINDOW_MS
            Pair(windowStart - ntpOffsetMs, instant - ntpOffsetMs)
        }
    }

    /**
     * Whether [nowDeviceMs] falls inside any of this timer's flash windows.
     * Half-open at the end so the moment a window's end alarm actually fires
     * doesn't still read as flashing.
     */
    fun isFlashing(targetEpochMs: Long?, ntpOffsetMs: Long, nowDeviceMs: Long): Boolean {
        if (targetEpochMs == null) return false
        return deviceWindows(targetEpochMs, ntpOffsetMs).any { (start, end) ->
            nowDeviceMs >= start && nowDeviceMs < end
        }
    }
}
