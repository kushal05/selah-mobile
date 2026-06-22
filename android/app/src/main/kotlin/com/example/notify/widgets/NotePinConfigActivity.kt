package com.example.notify.widgets

import android.appwidget.AppWidgetManager
import com.example.notify.R
import es.antonborri.home_widget.HomeWidgetPlugin

/** Configuration screen for the pinned-note widget. */
class NotePinConfigActivity : BaseWidgetPinConfigActivity() {
    override val indexKey = "notes_index"
    override val bodyKey = "preview"
    override val prefPrefix = "note_widget"
    override val titleRes = R.string.widget_note_pin_pick
    override val emptyRes = R.string.widget_note_pin_config_empty

    override fun refreshWidget(appWidgetId: Int) {
        NotePinWidgetProvider().onUpdate(
            this,
            AppWidgetManager.getInstance(this),
            intArrayOf(appWidgetId),
            HomeWidgetPlugin.getData(this),
        )
    }
}
