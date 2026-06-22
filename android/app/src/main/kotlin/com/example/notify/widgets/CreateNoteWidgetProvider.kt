package com.example.notify.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import com.example.notify.R
import es.antonborri.home_widget.HomeWidgetProvider

/** Action widget: tap launches the app straight into the new-note editor. */
class CreateNoteWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_create_note)
            views.setOnClickPendingIntent(
                R.id.widget_root,
                launchPendingIntent(context, widgetUri("notes", "new")),
            )
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
