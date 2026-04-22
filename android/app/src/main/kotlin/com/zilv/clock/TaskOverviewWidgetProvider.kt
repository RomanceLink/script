package com.zilv.clock

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
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
            appWidgetManager.updateAppWidget(appWidgetId, buildRemoteViews(context))
        }
    }

    companion object {
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, TaskOverviewWidgetProvider::class.java),
            )
            if (ids.isEmpty()) return
            ids.forEach { id ->
                manager.updateAppWidget(id, buildRemoteViews(context))
            }
        }

        private fun buildRemoteViews(context: Context): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_task_overview)
            val data = TaskOverviewWidgetData.load(context)
            views.setTextViewText(R.id.widget_summary, "总共 ${data.totalCount} 项 · 待完成 ${data.pendingCount} 项 · 已完成 ${data.completedCount} 项")
            views.setTextViewText(R.id.widget_motto, data.motto)
            views.setTextViewText(
                R.id.widget_footer,
                listOfNotNull(
                    data.nextReminder?.takeIf { it.isNotBlank() },
                    data.attribution.takeIf { it.isNotBlank() },
                ).joinToString(" · ").ifBlank { "轻触打开查看全部任务" },
            )
            bindTaskLine(views, R.id.widget_task_1, data.tasks.getOrNull(0))
            bindTaskLine(views, R.id.widget_task_2, data.tasks.getOrNull(1))
            bindTaskLine(views, R.id.widget_task_3, data.tasks.getOrNull(2))
            bindTaskLine(views, R.id.widget_task_4, data.tasks.getOrNull(3))

            val launchIntent = Intent(context, MainActivity::class.java)
            val pendingIntent = PendingIntent.getActivity(
                context,
                91001,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            return views
        }

        private fun bindTaskLine(
            views: RemoteViews,
            viewId: Int,
            taskLine: String?,
        ) {
            if (taskLine.isNullOrBlank()) {
                views.setTextViewText(viewId, "")
                views.setViewVisibility(viewId, android.view.View.GONE)
            } else {
                views.setTextViewText(viewId, taskLine)
                views.setViewVisibility(viewId, android.view.View.VISIBLE)
            }
        }
    }
}

private data class TaskOverviewWidgetData(
    val motto: String,
    val attribution: String,
    val totalCount: Int,
    val completedCount: Int,
    val pendingCount: Int,
    val nextReminder: String?,
    val tasks: List<String>,
) {
    companion object {
        fun load(context: Context): TaskOverviewWidgetData {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val mottoEntriesRaw = prefs.getString("flutter.daily_motto_entries_v1", null)
            val pinnedMottoId = prefs.getString("flutter.pinned_daily_motto_id_v1", null)
            val showMeta = prefs.getBoolean("flutter.show_daily_motto_meta_on_home_v1", true)
            val todayStateRaw = prefs.getString("flutter.daily_task_state_v1", null)

            val mottoEntry = parseMottoEntry(mottoEntriesRaw, pinnedMottoId)
            val tasksState = parseTasks(todayStateRaw)
            return TaskOverviewWidgetData(
                motto = mottoEntry.first.ifBlank { "今日箴言未设置" },
                attribution = if (showMeta) mottoEntry.second else "",
                totalCount = tasksState.totalCount,
                completedCount = tasksState.completedCount,
                pendingCount = (tasksState.totalCount - tasksState.completedCount).coerceAtLeast(0),
                nextReminder = tasksState.nextReminder,
                tasks = tasksState.lines,
            )
        }

        private fun parseMottoEntry(raw: String?, pinnedId: String?): Pair<String, String> {
            if (raw.isNullOrBlank()) {
                return "今日箴言未设置" to ""
            }
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
                    val day = Calendar.getInstance().get(Calendar.DAY_OF_YEAR)
                    selected = array.optJSONObject(day % array.length())
                }
                val content = selected?.optString("content")?.trim().orEmpty()
                val author = selected?.optString("author")?.trim().orEmpty()
                val poemTitle = selected?.optString("poemTitle")?.trim().orEmpty()
                val attribution = when {
                    author.isBlank() && poemTitle.isBlank() -> ""
                    author.isBlank() -> "《$poemTitle》"
                    poemTitle.isBlank() -> "-- $author"
                    else -> "-- $author《$poemTitle》"
                }
                content.ifBlank { "今日箴言未设置" } to attribution
            } catch (_: Exception) {
                "今日箴言未设置" to ""
            }
        }

        private fun parseTasks(raw: String?): ParsedTasks {
            if (raw.isNullOrBlank()) {
                return ParsedTasks(0, 0, null, emptyList())
            }
            return try {
                val root = JSONObject(raw)
                val tasks = root.optJSONArray("taskDefinitions") ?: JSONArray()
                val enabled = stringSet(root.optJSONArray("enabledTaskIds"))
                val visible = stringSet(root.optJSONArray("homeVisibleTaskIds"))
                val completed = stringSet(root.optJSONArray("completedTaskIds"))
                val intervalCounts = root.optJSONObject("intervalCompletedCounts") ?: JSONObject()

                val lines = mutableListOf<String>()
                var total = 0
                var done = 0
                var nextReminderMillis: Long? = null
                var nextReminderLabel: String? = null

                for (index in 0 until tasks.length()) {
                    val task = tasks.optJSONObject(index) ?: continue
                    val taskId = task.optString("id")
                    if (!enabled.contains(taskId) || !visible.contains(taskId)) continue
                    total += 1
                    val title = task.optString("title")
                    val kind = task.optString("kind")
                    val doneFlag = if (kind == "adCooldown") {
                        val infinite = task.optBoolean("infiniteLoop", false)
                        val target = task.optInt("targetCount", 0)
                        val current = intervalCounts.optInt(taskId, 0)
                        !infinite && target > 0 && current >= target
                    } else {
                        completed.contains(taskId)
                    }
                    if (doneFlag) done += 1

                    val timeLabel = "${task.optInt("startHour").toString().padStart(2, '0')}:${task.optInt("startMinute").toString().padStart(2, '0')}"
                    val status = if (kind == "adCooldown") {
                        val current = intervalCounts.optInt(taskId, 0)
                        val target = task.optInt("targetCount", 0)
                        if (task.optBoolean("infiniteLoop", false)) {
                            "进行中 $current"
                        } else {
                            "$current/$target"
                        }
                    } else {
                        if (doneFlag) "已完成" else "待完成"
                    }
                    if (lines.size < 4) {
                        lines.add("• $timeLabel  $title  ·  $status")
                    }

                    val reminderMillis = millisForToday(task.optInt("startHour"), task.optInt("startMinute"))
                    if (!doneFlag && reminderMillis != null) {
                        if (nextReminderMillis == null || reminderMillis < nextReminderMillis) {
                            nextReminderMillis = reminderMillis
                            nextReminderLabel = "$timeLabel $title"
                        }
                    }
                }
                ParsedTasks(total, done, nextReminderLabel, lines)
            } catch (_: Exception) {
                ParsedTasks(0, 0, null, emptyList())
            }
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

private data class ParsedTasks(
    val totalCount: Int,
    val completedCount: Int,
    val nextReminder: String?,
    val lines: List<String>,
)
