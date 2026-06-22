package com.example.notify.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import com.example.notify.R
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Display widget pinned to a single note (chosen in [NotePinConfigActivity]).
 *
 * Freshness: prefer the title/preview from the live `notes_index`; if the note
 * has aged out of that bounded index, fall back to the snapshot captured at
 * config time (`note_widget_<id>_title/_preview`).
 */
class NotePinWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_note_pin)
            val signedOut = widgetData.getBoolean("widget_signed_out", false)
            val boundId = widgetData.getString("note_widget_${id}_id", null)

            if (signedOut || boundId.isNullOrEmpty()) {
                views.setTextViewText(
                    R.id.widget_note_title,
                    context.getString(R.string.widget_pin_unconfigured),
                )
                views.setTextViewText(
                    R.id.widget_note_preview,
                    context.getString(R.string.widget_note_pin_hint),
                )
                views.setOnClickPendingIntent(
                    R.id.widget_root,
                    launchPendingIntent(context, widgetUri("notes")),
                )
            } else {
                val fresh = findWidgetEntry(
                    widgetData.getString("notes_index", null),
                    boundId,
                    "preview",
                )
                val title = (fresh?.title?.takeIf { it.isNotEmpty() }
                    ?: widgetData.getString("note_widget_${id}_title", "") ?: "")
                    .ifEmpty { context.getString(R.string.widget_note_pin_empty) }
                val preview = fresh?.body
                    ?: widgetData.getString("note_widget_${id}_preview", "") ?: ""

                views.setTextViewText(R.id.widget_note_title, title)
                views.setTextViewText(R.id.widget_note_preview, preview)
                views.setOnClickPendingIntent(
                    R.id.widget_root,
                    launchPendingIntent(context, widgetUri("note", idQuery = boundId)),
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
