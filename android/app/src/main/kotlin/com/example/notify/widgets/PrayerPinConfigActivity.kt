package com.example.notify.widgets

import android.appwidget.AppWidgetManager
import com.example.notify.R
import es.antonborri.home_widget.HomeWidgetPlugin

/** Configuration screen for the pinned-prayer widget. */
class PrayerPinConfigActivity : BaseWidgetPinConfigActivity() {
    override val indexKey = "prayers_index"
    override val bodyKey = "content"
    override val prefPrefix = "prayer_widget"
    override val titleRes = R.string.widget_prayer_pin_pick
    override val emptyRes = R.string.widget_prayer_pin_config_empty

    override fun refreshWidget(appWidgetId: Int) {
        PrayerPinWidgetProvider().onUpdate(
            this,
            AppWidgetManager.getInstance(this),
            intArrayOf(appWidgetId),
            HomeWidgetPlugin.getData(this),
        )
    }
}
