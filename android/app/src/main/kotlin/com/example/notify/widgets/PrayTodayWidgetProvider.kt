package com.example.notify.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import com.example.notify.R
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Today's prayers widget. Renders a fixed set of row slots directly (no
 * RemoteViewsService — that refused to refresh reliably) and shows as many as
 * fit the widget's current height, so it resizes flexibly. Each row opens the
 * prayer's details (title + chevron) or logs it (the check button → the in-app
 * log flow). The header opens the full list and the pill shows the count.
 */
class PrayTodayWidgetProvider : HomeWidgetProvider() {

    private companion object {
        val ROW_IDS = intArrayOf(R.id.row0, R.id.row1, R.id.row2, R.id.row3)
        val OPEN_IDS = intArrayOf(R.id.row0_open, R.id.row1_open, R.id.row2_open, R.id.row3_open)
        val TITLE_IDS = intArrayOf(R.id.row0_title, R.id.row1_title, R.id.row2_title, R.id.row3_title)
        val LOG_IDS = intArrayOf(R.id.row0_log, R.id.row1_log, R.id.row2_log, R.id.row3_log)

        // Approximate dp heights used to fit row slots to the widget's size.
        const val HEADER_DP = 56
        const val ROW_DP = 46
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val items = parseWidgetIndex(widgetData.getString("today_prayers", null), "title")
        for (id in appWidgetIds) {
            renderWidget(context, appWidgetManager, id, items)
        }
    }

    /** Re-render with a new row count when the user resizes the widget. */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        val items = parseWidgetIndex(
            HomeWidgetPlugin.getData(context).getString("today_prayers", null),
            "title",
        )
        renderWidget(context, appWidgetManager, appWidgetId, items)
    }

    private fun renderWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        items: List<WidgetEntry>,
    ) {
        val views = RemoteViews(context.packageName, R.layout.widget_pray_today)

        // Header → /prayers/today
        views.setOnClickPendingIntent(
            R.id.widget_header,
            launchPendingIntent(context, widgetUri("pray-today")),
        )

        if (items.isNotEmpty()) {
            views.setTextViewText(R.id.widget_count, items.size.toString())
            views.setViewVisibility(R.id.widget_count, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.widget_count, View.GONE)
        }

        if (items.isEmpty()) {
            views.setViewVisibility(R.id.widget_rows, View.GONE)
            views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.widget_rows, View.VISIBLE)
            views.setViewVisibility(R.id.widget_empty, View.GONE)
            bindRows(context, views, items, maxRowsForHeight(appWidgetManager, appWidgetId))
        }

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun maxRowsForHeight(appWidgetManager: AppWidgetManager, appWidgetId: Int): Int {
        // In portrait the widget's height is MAX_HEIGHT (MIN_HEIGHT is the
        // shorter landscape bound), so use MAX_HEIGHT to fill the common case.
        val heightDp = appWidgetManager.getAppWidgetOptions(appWidgetId)
            .getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
        if (heightDp <= 0) return ROW_IDS.size
        val rows = (heightDp - HEADER_DP) / ROW_DP
        return rows.coerceIn(1, ROW_IDS.size)
    }

    private fun bindRows(
        context: Context,
        views: RemoteViews,
        items: List<WidgetEntry>,
        maxRows: Int,
    ) {
        val shown = minOf(items.size, maxRows)

        for (i in ROW_IDS.indices) {
            if (i < shown) {
                val item = items[i]
                views.setViewVisibility(ROW_IDS[i], View.VISIBLE)
                views.setTextViewText(TITLE_IDS[i], item.title)
                views.setOnClickPendingIntent(
                    OPEN_IDS[i],
                    launchPendingIntent(context, widgetUri("prayer", idQuery = item.id)),
                )
                views.setOnClickPendingIntent(
                    LOG_IDS[i],
                    launchPendingIntent(context, widgetUri("log-prayer", idQuery = item.id)),
                )
            } else {
                views.setViewVisibility(ROW_IDS[i], View.GONE)
            }
        }

        if (items.size > shown) {
            views.setViewVisibility(R.id.widget_more, View.VISIBLE)
            views.setTextViewText(
                R.id.widget_more,
                context.getString(R.string.widget_pray_today_more, items.size - shown),
            )
            views.setOnClickPendingIntent(
                R.id.widget_more,
                launchPendingIntent(context, widgetUri("pray-today")),
            )
        } else {
            views.setViewVisibility(R.id.widget_more, View.GONE)
        }
    }
}
