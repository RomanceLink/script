package com.zilv.clock

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.widget.RemoteViews
import android.widget.RemoteViewsService

class TaskOverviewWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return TaskOverviewRemoteViewsFactory(applicationContext, intent)
    }
}

private class TaskOverviewRemoteViewsFactory(
    private val context: Context,
    intent: Intent,
) : RemoteViewsService.RemoteViewsFactory {
    private val appWidgetId =
        intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
    private var items: List<WidgetTaskLine> = emptyList()

    override fun onCreate() = Unit

    override fun onDataSetChanged() {
        val options = AppWidgetManager.getInstance(context).getAppWidgetOptions(appWidgetId)
        val profile = WidgetProfile.fromOptions(options)
        items = TaskOverviewWidgetData.load(context, profile).tasks
    }

    override fun onDestroy() {
        items = emptyList()
    }

    override fun getCount(): Int = items.size

    override fun getViewAt(position: Int): RemoteViews {
        val item = items.getOrNull(position) ?: return RemoteViews(context.packageName, R.layout.widget_task_item)
        val views = RemoteViews(context.packageName, R.layout.widget_task_item)
        val isNight =
            (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        views.setTextViewText(
            R.id.widget_task_item_title,
            "${if (item.urgent) "‼ " else "• "}${item.timeLabel}  ${item.title}",
        )
        views.setTextViewText(R.id.widget_task_item_status, item.status)
        views.setInt(
            R.id.widget_task_item_title,
            "setTextColor",
            if (isNight) 0xFFFFFFFF.toInt() else 0xFF243031.toInt(),
        )
        views.setInt(
            R.id.widget_task_item_status,
            "setTextColor",
            when {
                item.done && isNight -> 0xFFA9B4E8.toInt()
                item.done -> 0xFF6B7A95.toInt()
                item.urgent && isNight -> 0xFFFFB7B7.toInt()
                item.urgent -> 0xFFC74D4D.toInt()
                isNight -> 0xFFC8D1FF.toInt()
                else -> 0xFF52607A.toInt()
            },
        )
        views.setInt(
            R.id.widget_task_item_container,
            "setBackgroundResource",
            when {
                item.done -> R.drawable.widget_task_item_done_bg
                item.urgent -> R.drawable.widget_task_item_urgent_bg
                else -> R.drawable.widget_task_item_bg
            },
        )

        val fillInIntent = Intent()
        views.setOnClickFillInIntent(R.id.widget_task_item_container, fillInIntent)
        return views
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = true
}
