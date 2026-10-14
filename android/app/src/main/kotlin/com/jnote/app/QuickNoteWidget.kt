package com.jnote.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * The home-screen quick-add widget. It shows no note data, so it never needs refreshing:
 * updatePeriodMillis is 0 and nothing else ever updates it.
 */
open class QuickNoteWidget : AppWidgetProvider() {
    override fun onUpdate(ctx: Context, manager: AppWidgetManager, ids: IntArray) {
        val open = PendingIntent.getActivity(
            ctx, 0,
            Intent(ctx, QuickEntryActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK),
            PendingIntent.FLAG_IMMUTABLE
        )
        val views = RemoteViews(ctx.packageName, R.layout.widget_quick_note)
        views.setOnClickPendingIntent(R.id.widget_bar, open)
        manager.updateAppWidget(ids, views)
    }
}

/** The same note bar at 2x1 (sizes are in quick_note_widget_small_info.xml). */
class QuickNoteWidgetSmall : QuickNoteWidget()
