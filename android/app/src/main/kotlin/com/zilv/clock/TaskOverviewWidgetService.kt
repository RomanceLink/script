package com.zilv.clock

import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.text.SpannableString
import android.text.Spanned
import android.text.style.StrikethroughSpan
import android.widget.RemoteViews
import android.widget.RemoteViewsService

class TaskOverviewWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return TaskOverviewRemoteViewsFactory(applicationContext)
    }
}

private class TaskOverviewRemoteViewsFactory(
    private val context: Context,
) : RemoteViewsService.RemoteViewsFactory {
    private var items: List<WidgetTaskLine> = emptyList()

    override fun onCreate() = Unit

    override fun onDataSetChanged() {
        items = TaskOverviewWidgetData.load(context).tasks
    }

    override fun onDestroy() {
        items = emptyList()
    }

    override fun getCount(): Int = items.size

    override fun getViewAt(position: Int): RemoteViews {
        val item =
            items.getOrNull(position)
                ?: return RemoteViews(context.packageName, R.layout.widget_task_item)
        val views = RemoteViews(context.packageName, R.layout.widget_task_item)
        val isNight =
            (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                Configuration.UI_MODE_NIGHT_YES

        val rawTitle = "${if (item.urgent) "!" else "-"} ${item.timeLabel}  ${item.title}"
        if (item.done) {
            val spannable = SpannableString(rawTitle)
            spannable.setSpan(StrikethroughSpan(), 0, rawTitle.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            views.setTextViewText(R.id.widget_task_item_title, spannable)
        } else {
            views.setTextViewText(R.id.widget_task_item_title, rawTitle)
        }
        views.setTextViewText(R.id.widget_task_item_status, item.status)
        views.setInt(
            R.id.widget_task_item_title,
            "setTextColor",
            context.getColor(if (item.done) R.color.widget_task_text_done else R.color.widget_text_primary)
        )
        views.setInt(
            R.id.widget_task_item_status,
            "setTextColor",
            context.getColor(
                when {
                    item.done -> R.color.widget_task_status_done
                    item.urgent -> R.color.widget_task_status_urgent
                    else -> R.color.widget_task_status_normal
                }
            )
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
        views.setOnClickFillInIntent(R.id.widget_task_item_container, Intent())
        return views
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = true
}
