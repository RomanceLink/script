package com.zilv.clock

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.ComponentName
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Bundle
import android.widget.RemoteViews
import java.io.File
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
            appWidgetManager.updateAppWidget(
                appWidgetId,
                buildRemoteViews(
                    context = context,
                    appWidgetId = appWidgetId,
                    options = appWidgetManager.getAppWidgetOptions(appWidgetId),
                ),
            )
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        appWidgetManager.updateAppWidget(
            appWidgetId,
            buildRemoteViews(context, appWidgetId, newOptions),
        )
        appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_task_list)
    }

    companion object {
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, TaskOverviewWidgetProvider::class.java),
            )
            if (ids.isEmpty()) return
            ids.forEach { id ->
                manager.updateAppWidget(
                    id,
                    buildRemoteViews(
                        context = context,
                        appWidgetId = id,
                        options = manager.getAppWidgetOptions(id),
                    ),
                )
                manager.notifyAppWidgetViewDataChanged(id, R.id.widget_task_list)
            }
        }

        private fun buildRemoteViews(
            context: Context,
            appWidgetId: Int,
            options: Bundle?,
        ): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_task_overview)
            val profile = WidgetProfile.fromOptions(options)
            val data = TaskOverviewWidgetData.load(context, profile)
            val isNight =
                (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES

            views.setTextViewText(
                R.id.widget_summary,
                "总共 ${data.totalCount} 项 · 待完成 ${data.pendingCount} 项 · 已完成 ${data.completedCount} 项",
            )
            views.setTextViewText(R.id.widget_motto, data.motto)
            views.setTextViewText(
                R.id.widget_footer,
                listOfNotNull(
                    data.nextReminder?.takeIf { it.isNotBlank() },
                    data.attribution.takeIf { it.isNotBlank() },
                ).joinToString(" · ").ifBlank { "轻触打开查看全部任务" },
            )

            views.setViewVisibility(
                R.id.widget_summary,
                if (profile.showSummary) android.view.View.VISIBLE else android.view.View.GONE,
            )
            views.setViewVisibility(
                R.id.widget_footer,
                if (profile.showFooter) android.view.View.VISIBLE else android.view.View.GONE,
            )
            views.setInt(R.id.widget_motto, "setMaxLines", profile.mottoMaxLines)
            views.setInt(R.id.widget_summary, "setTextColor", if (isNight) 0xFFC8D1FF.toInt() else 0xFF5A6B6A.toInt())
            views.setInt(R.id.widget_motto, "setTextColor", if (isNight) 0xFFFFFFFF.toInt() else 0xFF1E2528.toInt())
            views.setInt(R.id.widget_footer, "setTextColor", if (isNight) 0xFFA9B4E8.toInt() else 0xFF607372.toInt())
            views.setInt(R.id.widget_task_empty, "setTextColor", if (isNight) 0xFFC8D1FF.toInt() else 0xFF5A6B6A.toInt())

            val taskIntent = Intent(context, TaskOverviewWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                this.data = android.net.Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
            }
            views.setRemoteAdapter(R.id.widget_task_list, taskIntent)
            views.setViewVisibility(
                R.id.widget_task_list,
                if (data.tasks.isEmpty()) android.view.View.GONE else android.view.View.VISIBLE,
            )
            views.setViewVisibility(
                R.id.widget_task_empty,
                if (data.tasks.isEmpty()) android.view.View.VISIBLE else android.view.View.GONE,
            )

            val backgroundBitmap = decodeWidgetBackground(data.imagePath, profile)
            if (backgroundBitmap != null) {
                views.setImageViewBitmap(R.id.widget_bg_image, backgroundBitmap)
                views.setViewVisibility(R.id.widget_bg_image, android.view.View.VISIBLE)
                views.setViewVisibility(R.id.widget_bg_scrim, android.view.View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.widget_bg_image, android.view.View.GONE)
                views.setViewVisibility(R.id.widget_bg_scrim, android.view.View.GONE)
            }

            val launchIntent = Intent(context, MainActivity::class.java)
            val pendingIntent = PendingIntent.getActivity(
                context,
                91001,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            views.setPendingIntentTemplate(R.id.widget_task_list, pendingIntent)
            return views
        }

        private fun decodeWidgetBackground(path: String?, profile: WidgetProfile): Bitmap? {
            if (path.isNullOrBlank()) return null
            return try {
                val file = File(path)
                if (!file.exists()) return null
                val raw = BitmapFactory.decodeFile(file.absolutePath) ?: return null
                val maxEdge = when (profile) {
                    WidgetProfile.COMPACT -> 512
                    WidgetProfile.MEDIUM -> 768
                    WidgetProfile.LARGE -> 1024
                    WidgetProfile.XLARGE -> 1280
                }
                val scale = maxOf(raw.width, raw.height).toFloat() / maxEdge.toFloat()
                if (scale <= 1f) raw else Bitmap.createScaledBitmap(
                    raw,
                    (raw.width / scale).toInt().coerceAtLeast(1),
                    (raw.height / scale).toInt().coerceAtLeast(1),
                    true,
                )
            } catch (_: Exception) {
                null
            }
        }
    }
}

enum class WidgetProfile(
    val showSummary: Boolean,
    val showFooter: Boolean,
    val mottoMaxLines: Int,
) {
    COMPACT(showSummary = false, showFooter = false, mottoMaxLines = 2),
    MEDIUM(showSummary = true, showFooter = false, mottoMaxLines = 3),
    LARGE(showSummary = true, showFooter = true, mottoMaxLines = 4),
    XLARGE(showSummary = true, showFooter = true, mottoMaxLines = 5),
    ;

    companion object {
        fun fromOptions(options: Bundle?): WidgetProfile {
            val minWidth = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH) ?: 0
            val minHeight = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT) ?: 0
            return when {
                minWidth >= 320 || minHeight >= 300 -> XLARGE
                minWidth >= 250 || minHeight >= 220 -> LARGE
                minWidth >= 180 || minHeight >= 160 -> MEDIUM
                else -> COMPACT
            }
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
    val imagePath: String?,
) {
    companion object {
        fun load(context: Context, profile: WidgetProfile): TaskOverviewWidgetData {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val mottoEntriesRaw = prefs.getString("flutter.daily_motto_entries_v1", null)
            val pinnedMottoId = prefs.getString("flutter.pinned_daily_motto_id_v1", null)
            val showMeta = prefs.getBoolean("flutter.show_daily_motto_meta_on_home_v1", true)
            val todayStateRaw = prefs.getString("flutter.daily_task_state_v1", null)
            val imagePath = prefs.getString("flutter.daily_motto_image_path_v1", null)

            val mottoEntry = parseMottoEntry(mottoEntriesRaw, pinnedMottoId, profile)
            val tasksState = parseTasks(todayStateRaw)
            return TaskOverviewWidgetData(
                motto = mottoEntry.first.ifBlank { "今日箴言未设置" },
                attribution = if (showMeta) mottoEntry.second else "",
                totalCount = tasksState.totalCount,
                completedCount = tasksState.completedCount,
                pendingCount = (tasksState.totalCount - tasksState.completedCount).coerceAtLeast(0),
                nextReminder = tasksState.nextReminder,
                tasks = tasksState.lines,
                imagePath = imagePath?.trim(),
            )
        }

        private fun parseMottoEntry(
            raw: String?,
            pinnedId: String?,
            profile: WidgetProfile,
        ): Pair<String, String> {
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
                formatMotto(content.ifBlank { "今日箴言未设置" }, profile) to attribution
            } catch (_: Exception) {
                "今日箴言未设置" to ""
            }
        }

        private fun formatMotto(content: String, profile: WidgetProfile): String {
            val target = when (profile) {
                WidgetProfile.COMPACT -> 10
                WidgetProfile.MEDIUM -> 14
                WidgetProfile.LARGE -> 18
                WidgetProfile.XLARGE -> 22
            }
            val parts = content
                .split(Regex("(?<=[，。！？；：,.!?;:])"))
                .map { it.trim() }
                .filter { it.isNotEmpty() }
            if (parts.isEmpty()) return content
            val lines = mutableListOf<String>()
            val current = StringBuilder()
            for (part in parts) {
                if (current.isEmpty()) {
                    current.append(part)
                    continue
                }
                if (current.length + part.length > target) {
                    lines.add(current.toString())
                    current.clear()
                    current.append(part)
                } else {
                    current.append(part)
                }
            }
            if (current.isNotEmpty()) lines.add(current.toString())
            return lines.joinToString("\n")
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

                val lines = mutableListOf<WidgetTaskLine>()
                var total = 0
                var done = 0
                var nextReminderMillis: Long? = null
                var nextReminderLabel: String? = null
                val nowMillis = System.currentTimeMillis()

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

                    val reminderMillis = millisForToday(task.optInt("startHour"), task.optInt("startMinute"))
                    val sortDistance = when {
                        reminderMillis == null -> Long.MAX_VALUE
                        doneFlag -> Long.MAX_VALUE - reminderMillis
                        else -> kotlin.math.abs(reminderMillis - nowMillis)
                    }
                    val urgent = !doneFlag && reminderMillis != null && kotlin.math.abs(reminderMillis - nowMillis) <= 60 * 60 * 1000
                    lines.add(
                        WidgetTaskLine(
                            title = title.ifBlank { "未命名任务" },
                            timeLabel = timeLabel,
                            status = status,
                            urgent = urgent,
                            done = doneFlag,
                            sortDistance = sortDistance,
                        ),
                    )
                    if (!doneFlag && reminderMillis != null) {
                        if (nextReminderMillis == null || reminderMillis < nextReminderMillis) {
                            nextReminderMillis = reminderMillis
                            nextReminderLabel = "$timeLabel $title"
                        }
                    }
                }
                val sorted = lines.sortedWith(
                    compareBy<WidgetTaskLine> { it.done }
                        .thenBy { it.sortDistance }
                        .thenBy { it.timeLabel },
                )
                ParsedTasks(total, done, nextReminderLabel, sorted)
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
