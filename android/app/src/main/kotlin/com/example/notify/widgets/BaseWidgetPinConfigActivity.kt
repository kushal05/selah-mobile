package com.example.notify.widgets

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ArrayAdapter
import android.widget.ListView
import android.widget.TextView
import com.example.notify.R
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Shared configuration screen for the pinned-note / pinned-prayer widgets.
 *
 * Lists the recent items the app published to the `home_widget` shared prefs
 * ([indexKey]) and, on selection, binds the chosen entity to this widget
 * instance by writing a snapshot (`<prefPrefix>_<appWidgetId>_id/_title/_<bodyKey>`)
 * that the provider renders. No app launch — pure native picker.
 */
abstract class BaseWidgetPinConfigActivity : Activity() {

    /** Published index key, e.g. "notes_index". */
    protected abstract val indexKey: String

    /** Body field name in the index and the snapshot, e.g. "preview"/"content". */
    protected abstract val bodyKey: String

    /** Snapshot key prefix, e.g. "note_widget"/"prayer_widget". */
    protected abstract val prefPrefix: String

    protected abstract val titleRes: Int
    protected abstract val emptyRes: Int

    /** Re-render the bound widget instance immediately after selection. */
    protected abstract fun refreshWidget(appWidgetId: Int)

    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Backing out of configuration cancels the widget placement.
        setResult(RESULT_CANCELED)

        appWidgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        setContentView(R.layout.activity_widget_config)
        findViewById<TextView>(R.id.config_title).setText(titleRes)

        val emptyView = findViewById<TextView>(R.id.config_empty)
        emptyView.setText(emptyRes)

        val entries = parseWidgetIndex(
            HomeWidgetPlugin.getData(this).getString(indexKey, null),
            bodyKey,
        )
        val listView = findViewById<ListView>(R.id.config_list)
        listView.emptyView = emptyView
        listView.adapter = EntryAdapter(this, entries)
        listView.setOnItemClickListener { _, _, position, _ -> bind(entries[position]) }
    }

    private fun bind(entry: WidgetEntry) {
        HomeWidgetPlugin.getData(this).edit().apply {
            putString("${prefPrefix}_${appWidgetId}_id", entry.id)
            putString("${prefPrefix}_${appWidgetId}_title", entry.title)
            putString("${prefPrefix}_${appWidgetId}_$bodyKey", entry.body)
            apply()
        }
        refreshWidget(appWidgetId)
        setResult(
            RESULT_OK,
            Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId),
        )
        finish()
    }
}

private class EntryAdapter(
    context: Context,
    private val entries: List<WidgetEntry>,
) : ArrayAdapter<WidgetEntry>(context, R.layout.item_widget_config, entries) {

    override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
        val view = convertView ?: LayoutInflater.from(context)
            .inflate(R.layout.item_widget_config, parent, false)
        val entry = entries[position]
        view.findViewById<TextView>(R.id.config_item_title).text =
            entry.title.ifEmpty { context.getString(R.string.widget_untitled) }
        val subtitle = view.findViewById<TextView>(R.id.config_item_subtitle)
        subtitle.text = entry.body
        subtitle.visibility = if (entry.body.isEmpty()) View.GONE else View.VISIBLE
        return view
    }
}
