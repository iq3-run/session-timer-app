package com.iq3run.session_timer

import android.content.Context
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
import org.json.JSONException

private data class ScheduleRowData(
    val label: String,
    val date: String,
    val isToday: Boolean,
    val chainGap: String,
    val todayGap: String,
)

/**
 * Reads the same `home_widget` SharedPreferences store the other widgets use
 * (via [HomeWidgetPlugin.getData], the same public accessor
 * `HomeWidgetProvider.onUpdate` uses internally), independently of
 * [ScheduleWidgetProvider.onUpdate] — a `RemoteViewsFactory` runs in the
 * widget host's own process, so it can't share in-memory state with the
 * provider and must re-read from disk in [onDataSetChanged].
 */
class ScheduleRemoteViewsFactory(private val context: Context) :
    RemoteViewsService.RemoteViewsFactory {
    private var rows: List<ScheduleRowData> = emptyList()

    override fun onCreate() {}

    override fun onDataSetChanged() {
        val json =
            HomeWidgetPlugin.getData(context)
                .getString(HomeWidgetKeys.SCHEDULE_EVENTS_JSON, null)
        rows = if (json == null) emptyList() else parseRowsSafely(json)
    }

    override fun onDestroy() {
        rows = emptyList()
    }

    override fun getCount(): Int = rows.size

    override fun getViewAt(position: Int): RemoteViews {
        val row = rows[position]
        return RemoteViews(context.packageName, R.layout.schedule_widget_list_item).apply {
            setTextViewText(R.id.item_label, row.label)
            setTextViewText(R.id.item_date, row.date)
            val colorRes = if (row.isToday) R.color.home_widget_amber else R.color.home_widget_white
            val color = ContextCompat.getColor(context, colorRes)
            setTextColor(R.id.item_label, color)
            setTextColor(R.id.item_date, color)
            applyGapLine(row)
        }
    }

    // 週末間/今日から mirror the read-only スケジュール screen's two gap columns, which are
    // blank for most rows (only chain rows with a previous entry, and the single nearest-past/
    // nearest-future/CS rows, ever carry one) — combined onto one optional line rather than two
    // always-present columns, since this widget's narrow width can't fit a 4-column table.
    private fun RemoteViews.applyGapLine(row: ScheduleRowData) {
        val parts =
            buildList {
                if (row.chainGap.isNotEmpty()) add("週末間 ${row.chainGap}")
                if (row.todayGap.isNotEmpty()) add("今日から ${row.todayGap}")
            }
        if (parts.isEmpty()) {
            setViewVisibility(R.id.item_gap, View.GONE)
        } else {
            setTextViewText(R.id.item_gap, parts.joinToString("　"))
            setViewVisibility(R.id.item_gap, View.VISIBLE)
        }
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = false

    // A RemoteViewsFactory runs in the widget host process, reading a value this app's own
    // process last wrote — an in-flight app update (old widget process, newer JSON schema) or a
    // partially-written value can hand this a string that isn't valid JSON for the shape below.
    // Falling back to an empty list keeps the widget merely showing "no data" instead of the host
    // process itself crashing on JSONException.
    private fun parseRowsSafely(json: String): List<ScheduleRowData> {
        return try {
            val array = JSONArray(json)
            (0 until array.length()).map { i ->
                val obj = array.getJSONObject(i)
                ScheduleRowData(
                    label = obj.getString("label"),
                    date = obj.getString("date"),
                    isToday = obj.getBoolean("isToday"),
                    // optString, not getString: a JSON payload written by an app version before
                    // these two keys existed would otherwise fail this row's entire parse (and
                    // therefore the whole list, via the outer try/catch) during the brief window
                    // before the app's next sync, instead of just rendering without a gap line.
                    chainGap = obj.optString("chainGap", ""),
                    todayGap = obj.optString("todayGap", ""),
                )
            }
        } catch (e: JSONException) {
            emptyList()
        }
    }
}
