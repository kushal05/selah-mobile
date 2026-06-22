package com.example.notify.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import com.example.notify.R
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Display widget pinned to a single prayer (chosen in
 * [PrayerPinConfigActivity]).
 *
 * Freshness mirrors [NotePinWidgetProvider]: prefer the live `prayers_index`,
 * fall back to the config-time snapshot (`prayer_widget_<id>_title/_content`).
 */
class PrayerPinWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_prayer_pin)
            val signedOut = widgetData.getBoolean("widget_signed_out", false)
            val boundId = widgetData.getString("prayer_widget_${id}_id", null)

            if (signedOut || boundId.isNullOrEmpty()) {
                views.setTextViewText(
                    R.id.widget_prayer_title,
                    context.getString(R.string.widget_pin_unconfigured),
                )
                views.setTextViewText(
                    R.id.widget_prayer_content,
                    context.getString(R.string.widget_prayer_pin_hint),
                )
                views.setOnClickPendingIntent(
                    R.id.widget_root,
                    launchPendingIntent(context, widgetUri("prayers")),
                )
            } else {
                val fresh = findWidgetEntry(
                    widgetData.getString("prayers_index", null),
                    boundId,
                    "content",
                )
                val title = (fresh?.title?.takeIf { it.isNotEmpty() }
                    ?: widgetData.getString("prayer_widget_${id}_title", "") ?: "")
                    .ifEmpty { context.getString(R.string.widget_prayer_pin_empty) }
                val content = fresh?.body
                    ?: widgetData.getString("prayer_widget_${id}_content", "") ?: ""

                views.setTextViewText(R.id.widget_prayer_title, title)
                views.setTextViewText(R.id.widget_prayer_content, content)
                views.setOnClickPendingIntent(
                    R.id.widget_root,
                    launchPendingIntent(context, widgetUri("prayer", idQuery = boundId)),
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
