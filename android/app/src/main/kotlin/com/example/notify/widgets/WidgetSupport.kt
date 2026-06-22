package com.example.notify.widgets

import android.app.PendingIntent
import android.content.Context
import android.net.Uri
import com.example.notify.MainActivity
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import org.json.JSONArray

/**
 * Shared helpers for the Selah home-screen widgets.
 *
 * Click targets are `selah://widget/...` URIs. They are launched into
 * [MainActivity] (singleTop) and surfaced to Flutter by the `home_widget`
 * plugin, where `HomeWidgetService.widgetUriToAppPath` maps them to GoRouter
 * paths. Keep these URIs in sync with that mapper.
 */

/** One row of a published index (`notes_index` / `prayers_index`). */
data class WidgetEntry(val id: String, val title: String, val body: String)

/** Builds a `selah://widget/<segments...>[?id=<idQuery>]` Uri. */
fun widgetUri(vararg segments: String, idQuery: String? = null): Uri {
    val builder = Uri.Builder().scheme("selah").authority("widget")
    segments.forEach { builder.appendPath(it) }
    if (idQuery != null) builder.appendQueryParameter("id", idQuery)
    return builder.build()
}

/** Immutable activity [PendingIntent] that launches the app at [uri]. */
fun launchPendingIntent(context: Context, uri: Uri): PendingIntent =
    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, uri)

/** Parses a published index JSON array into entries. [bodyKey] is "preview"
 *  for notes and "content" for prayers. */
fun parseWidgetIndex(json: String?, bodyKey: String): List<WidgetEntry> {
    if (json.isNullOrEmpty()) return emptyList()
    return try {
        val arr = JSONArray(json)
        (0 until arr.length()).mapNotNull { i ->
            val o = arr.optJSONObject(i) ?: return@mapNotNull null
            val id = o.optString("id")
            if (id.isEmpty()) null
            else WidgetEntry(id, o.optString("title"), o.optString(bodyKey))
        }
    } catch (_: Exception) {
        emptyList()
    }
}

/** Finds a single entry by [id] in a published index, or null if absent. */
fun findWidgetEntry(json: String?, id: String, bodyKey: String): WidgetEntry? =
    parseWidgetIndex(json, bodyKey).firstOrNull { it.id == id }
