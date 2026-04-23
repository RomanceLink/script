package com.zilv.clock

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import android.widget.RemoteViews
import java.util.Calendar
import org.json.JSONArray
import org.json.JSONObject

class TaskOverviewWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { appWidgetId ->
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        updateWidget(context, appWidgetManager, appWidgetId)
    }

    companion object {
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, TaskOverviewWidgetProvider::class.java))
            ids.forEach { appWidgetId ->
                updateWidget(context, manager, appWidgetId)
                manager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_task_list)
            }
        }

        private fun updateWidget(
            context: Context,
            manager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            val widgetData = TaskOverviewWidgetData.load(context)
            val views = RemoteViews(context.packageName, R.layout.widget_task_overview)
            val isNight =
                (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                    Configuration.UI_MODE_NIGHT_YES
            val options = manager.getAppWidgetOptions(appWidgetId)
            val minHeight = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT) ?: 0
            val roomy = minHeight >= 190

            views.setTextViewText(
                R.id.widget_summary,
                "今日 ${widgetData.completedCount}/${widgetData.totalCount} · 待办 ${widgetData.pendingCount}",
            )
            views.setTextViewText(R.id.widget_motto, widgetData.motto)
            views.setTextViewText(R.id.widget_footer, widgetData.attribution.ifBlank { widgetData.nextReminder ?: "轻触打开应用" })
            views.setViewVisibility(
                R.id.widget_footer,
                if (roomy) android.view.View.VISIBLE else android.view.View.GONE,
            )
            views.setViewVisibility(
                R.id.widget_task_empty,
                if (widgetData.tasks.isEmpty()) android.view.View.VISIBLE else android.view.View.GONE,
            )
            views.setViewVisibility(
                R.id.widget_task_list,
                if (widgetData.tasks.isEmpty()) android.view.View.GONE else android.view.View.VISIBLE,
            )

            views.setInt(R.id.widget_summary, "setTextColor", if (isNight) 0xFFDDE3FF.toInt() else 0xFF48605E.toInt())
            views.setInt(R.id.widget_motto, "setTextColor", if (isNight) 0xFFFFFFFF.toInt() else 0xFF172123.toInt())
            views.setInt(R.id.widget_footer, "setTextColor", if (isNight) 0xFFC8CFFF.toInt() else 0xFF61736F.toInt())
            views.setInt(R.id.widget_task_empty, "setTextColor", if (isNight) 0xFFC8CFFF.toInt() else 0xFF61736F.toInt())

            val serviceIntent = Intent(context, TaskOverviewWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                data = android.net.Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
            }
            views.setRemoteAdapter(R.id.widget_task_list, serviceIntent)

            val launchIntent = Intent(context, MainActivity::class.java)
            val pendingIntent =
                PendingIntent.getActivity(
                    context,
                    94003,
                    launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            views.setOnClickPendingIntent(R.id.widget_motto_container, pendingIntent)
            views.setPendingIntentTemplate(R.id.widget_task_list, pendingIntent)

            manager.updateAppWidget(appWidgetId, views)
        }
    }
}

data class TaskOverviewWidgetData(
    val motto: String,
    val attribution: String,
    val totalCount: Int,
    val completedCount: Int,
    val pendingCount: Int,
    val nextReminder: String?,
    val tasks: List<WidgetTaskLine>,
) {
    companion object {
        fun load(context: Context): TaskOverviewWidgetData {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val mottoEntriesRaw = prefs.getString("flutter.daily_motto_entries_v1", null)
            val pinnedMottoId = prefs.getString("flutter.pinned_daily_motto_id_v1", null)
            val showMeta = prefs.getBoolean("flutter.show_daily_motto_meta_on_home_v1", true)
            val taskStateRaw = prefs.getString("flutter.daily_task_state_v1", null)
            val motto = parseMottoEntry(mottoEntriesRaw, pinnedMottoId)
            val tasks = parseTasks(taskStateRaw)
            return TaskOverviewWidgetData(
                motto = motto.first.ifBlank { "今日箴言未设置" },
                attribution = if (showMeta) motto.second else "",
                totalCount = tasks.totalCount,
                completedCount = tasks.completedCount,
                pendingCount = (tasks.totalCount - tasks.completedCount).coerceAtLeast(0),
                nextReminder = tasks.nextReminder,
                tasks = tasks.lines,
            )
        }

        private fun parseMottoEntry(raw: String?, pinnedId: String?): Pair<String, String> {
            if (raw.isNullOrBlank()) return "今日箴言未设置" to ""
            return try {
                val array = JSONArray(raw)
                var selected: JSONObject? = null
                if (!pinnedId.isNullOrBlank()) {
                    for (index in 0 until array.length()) {
                        val item = array.optJSONObject(index) ?: continue
                        if (item.optString("id") == pinnedId) {
                            selected = item
                            break
                        }
                    }
                }
                if (selected == null && array.length() > 0) {
                    selected = array.optJSONObject(Calendar.getInstance().get(Calendar.DAY_OF_YEAR) % array.length())
                }
                val content = normalizeText(selected?.optString("content"))
                val author = normalizeText(selected?.optString("author"))
                val poemTitle = normalizeText(selected?.optString("poemTitle"))
                val attribution =
                    when {
                        author.isBlank() && poemTitle.isBlank() -> ""
                        author.isBlank() -> "《$poemTitle》"
                        poemTitle.isBlank() -> author
                        else -> "$author《$poemTitle》"
                    }
                formatMotto(content.ifBlank { "今日箴言未设置" }) to attribution
            } catch (_: Exception) {
                "今日箴言未设置" to ""
            }
        }

        private fun parseTasks(raw: String?): ParsedTasks {
            if (raw.isNullOrBlank()) return ParsedTasks(0, 0, null, emptyList())
            return try {
                val root = JSONObject(raw)
                val taskDefinitions = root.optJSONArray("taskDefinitions") ?: JSONArray()
                val enabled = stringSet(root.optJSONArray("enabledTaskIds"))
                val visible = stringSet(root.optJSONArray("homeVisibleTaskIds"))
                val completed = stringSet(root.optJSONArray("completedTaskIds"))
                val intervalCounts = root.optJSONObject("intervalCompletedCounts") ?: JSONObject()
                val now = System.currentTimeMillis()
                var total = 0
                var done = 0
                var nextReminderMillis: Long? = null
                var nextReminderLabel: String? = null
                val lines = mutableListOf<WidgetTaskLine>()

                for (index in 0 until taskDefinitions.length()) {
                    val task = taskDefinitions.optJSONObject(index) ?: continue
                    val taskId = task.optString("id")
                    if (taskId.isBlank()) continue
                    if (enabled.isNotEmpty() && !enabled.contains(taskId)) continue
                    if (visible.isNotEmpty() && !visible.contains(taskId)) continue

                    val kind = task.optString("kind")
                    val title = normalizeText(task.optString("title")).ifBlank { "未命名任务" }
                    val target = task.optInt("targetCount", 0)
                    val current = intervalCounts.optInt(taskId, 0)
                    val doneFlag =
                        if (kind == "adCooldown") {
                            !task.optBoolean("infiniteLoop", false) && target > 0 && current >= target
                        } else {
                            completed.contains(taskId)
                        }
                    val timeLabel =
                        "${task.optInt("startHour").toString().padStart(2, '0')}:${task.optInt("startMinute").toString().padStart(2, '0')}"
                    val status =
                        if (kind == "adCooldown") {
                            if (task.optBoolean("infiniteLoop", false)) "循环 $current" else "$current/$target"
                        } else if (doneFlag) {
                            "已完成"
                        } else {
                            "待完成"
                        }
                    val reminderMillis = millisForToday(task.optInt("startHour"), task.optInt("startMinute"))
                    val urgent =
                        !doneFlag &&
                            reminderMillis != null &&
                            kotlin.math.abs(reminderMillis - now) <= 60 * 60 * 1000
                    val sortDistance =
                        when {
                            reminderMillis == null -> Long.MAX_VALUE
                            doneFlag -> Long.MAX_VALUE - reminderMillis
                            else -> kotlin.math.abs(reminderMillis - now)
                        }

                    total += 1
                    if (doneFlag) done += 1
                    if (!doneFlag && reminderMillis != null) {
                        if (nextReminderMillis == null || reminderMillis < nextReminderMillis) {
                            nextReminderMillis = reminderMillis
                            nextReminderLabel = "$timeLabel $title"
                        }
                    }
                    lines.add(WidgetTaskLine(title, timeLabel, status, urgent, doneFlag, sortDistance))
                }

                val sorted =
                    lines.sortedWith(
                        compareBy<WidgetTaskLine> { it.done }
                            .thenBy { it.sortDistance }
                            .thenBy { it.timeLabel },
                    )
                ParsedTasks(total, done, nextReminderLabel, sorted)
            } catch (_: Exception) {
                ParsedTasks(0, 0, null, emptyList())
            }
        }

        private fun normalizeText(value: String?): String {
            val text = value?.trim().orEmpty()
            return if (text.equals("null", ignoreCase = true)) "" else text
        }

        private fun formatMotto(content: String): String {
            val parts =
                content
                    .split(Regex("(?<=[，。！？；：,.!?;:])"))
                    .map { it.trim() }
                    .filter { it.isNotEmpty() }
            if (parts.isEmpty()) return content
            val lines = mutableListOf<String>()
            val current = StringBuilder()
            for (part in parts) {
                if (current.isEmpty()) {
                    current.append(part)
                } else if (current.length + part.length > 18) {
                    lines.add(current.toString())
                    current.clear()
                    current.append(part)
                } else {
                    current.append(part)
                }
            }
            if (current.isNotEmpty()) lines.add(current.toString())
            return lines.take(2).joinToString("\n")
        }

        private fun stringSet(array: JSONArray?): Set<String> {
            if (array == null) return emptySet()
            val values = mutableSetOf<String>()
            for (index in 0 until array.length()) {
                values.add(array.optString(index))
            }
            return values
        }

        private fun millisForToday(hour: Int, minute: Int): Long? {
            return try {
                Calendar.getInstance().apply {
                    set(Calendar.HOUR_OF_DAY, hour)
                    set(Calendar.MINUTE, minute)
                    set(Calendar.SECOND, 0)
                    set(Calendar.MILLISECOND, 0)
                }.timeInMillis
            } catch (_: Exception) {
                null
            }
        }
    }
}

data class ParsedTasks(
    val totalCount: Int,
    val completedCount: Int,
    val nextReminder: String?,
    val lines: List<WidgetTaskLine>,
)

data class WidgetTaskLine(
    val title: String,
    val timeLabel: String,
    val status: String,
    val urgent: Boolean,
    val done: Boolean,
    val sortDistance: Long,
)
