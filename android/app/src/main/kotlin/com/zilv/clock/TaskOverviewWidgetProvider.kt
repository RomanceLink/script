package com.zilv.clock

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
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

abstract class BaseTaskOverviewWidgetProvider(
    private val variant: WidgetVariant,
) : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { appWidgetId ->
            appWidgetManager.updateAppWidget(
                appWidgetId,
                WidgetViews.buildRemoteViews(
                    context = context,
                    appWidgetId = appWidgetId,
                    options = appWidgetManager.getAppWidgetOptions(appWidgetId),
                    variant = variant,
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
            WidgetViews.buildRemoteViews(
                context = context,
                appWidgetId = appWidgetId,
                options = newOptions,
                variant = variant,
            ),
        )
        if (variant.showTaskList) {
            appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_task_list)
        }
    }
}

class TaskOverviewWidgetProvider :
    BaseTaskOverviewWidgetProvider(WidgetVariant.LARGE_5X5) {
    companion object {
        fun refreshAll(context: Context) {
            WidgetViews.refreshAll(context)
        }
    }
}

class TaskOverviewWidgetSmallProvider :
    BaseTaskOverviewWidgetProvider(WidgetVariant.COMPACT_2X2)

class TaskOverviewWidgetMediumProvider :
    BaseTaskOverviewWidgetProvider(WidgetVariant.MEDIUM_3X3)

class TaskOverviewWidgetMottoProvider :
    BaseTaskOverviewWidgetProvider(WidgetVariant.MOTTO_4X4)

enum class WidgetVariant(
    val showSummary: Boolean,
    val showMotto: Boolean,
    val showCurrentTask: Boolean,
    val showTaskList: Boolean,
    val showFooter: Boolean,
    val mottoMaxLines: Int,
    val maxBackgroundEdge: Int,
) {
    COMPACT_2X2(
        showSummary = false,
        showMotto = false,
        showCurrentTask = true,
        showTaskList = false,
        showFooter = false,
        mottoMaxLines = 0,
        maxBackgroundEdge = 512,
    ),
    MEDIUM_3X3(
        showSummary = true,
        showMotto = false,
        showCurrentTask = true,
        showTaskList = false,
        showFooter = false,
        mottoMaxLines = 0,
        maxBackgroundEdge = 768,
    ),
    MOTTO_4X4(
        showSummary = true,
        showMotto = true,
        showCurrentTask = true,
        showTaskList = false,
        showFooter = false,
        mottoMaxLines = 4,
        maxBackgroundEdge = 1024,
    ),
    LARGE_5X5(
        showSummary = true,
        showMotto = true,
        showCurrentTask = false,
        showTaskList = true,
        showFooter = true,
        mottoMaxLines = 5,
        maxBackgroundEdge = 1280,
    ),
}

private object WidgetViews {
    private val providers =
        listOf(
            TaskOverviewWidgetSmallProvider::class.java to WidgetVariant.COMPACT_2X2,
            TaskOverviewWidgetMediumProvider::class.java to WidgetVariant.MEDIUM_3X3,
            TaskOverviewWidgetMottoProvider::class.java to WidgetVariant.MOTTO_4X4,
            TaskOverviewWidgetProvider::class.java to WidgetVariant.LARGE_5X5,
        )

    fun refreshAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        providers.forEach { (providerClass, variant) ->
            val ids = manager.getAppWidgetIds(ComponentName(context, providerClass))
            if (ids.isEmpty()) return@forEach
            ids.forEach { id ->
                manager.updateAppWidget(
                    id,
                    buildRemoteViews(
                        context = context,
                        appWidgetId = id,
                        options = manager.getAppWidgetOptions(id),
                        variant = variant,
                    ),
                )
                if (variant.showTaskList) {
                    manager.notifyAppWidgetViewDataChanged(id, R.id.widget_task_list)
                }
            }
        }
    }

    fun buildRemoteViews(
        context: Context,
        appWidgetId: Int,
        options: Bundle?,
        variant: WidgetVariant,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_task_overview)
        val data = TaskOverviewWidgetData.load(context, variant)
        val isNight =
            (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                Configuration.UI_MODE_NIGHT_YES

        views.setViewVisibility(
            R.id.widget_summary,
            if (variant.showSummary) android.view.View.VISIBLE else android.view.View.GONE,
        )
        views.setViewVisibility(
            R.id.widget_motto_container,
            if (variant.showMotto) android.view.View.VISIBLE else android.view.View.GONE,
        )
        views.setViewVisibility(
            R.id.widget_current_card,
            if (variant.showCurrentTask) android.view.View.VISIBLE else android.view.View.GONE,
        )
        views.setViewVisibility(
            R.id.widget_task_list_frame,
            if (variant.showTaskList) android.view.View.VISIBLE else android.view.View.GONE,
        )
        views.setViewVisibility(
            R.id.widget_footer,
            if (variant.showFooter && data.attribution.isNotBlank()) {
                android.view.View.VISIBLE
            } else {
                android.view.View.GONE
            },
        )

        views.setTextViewText(
            R.id.widget_summary,
            "总任务 ${data.totalCount} · 待完成 ${data.pendingCount}",
        )
        views.setTextViewText(R.id.widget_motto, data.motto)
        views.setTextViewText(R.id.widget_footer, data.attribution)
        views.setInt(R.id.widget_motto, "setMaxLines", variant.mottoMaxLines)

        val currentTask = data.currentTask
        views.setTextViewText(
            R.id.widget_current_title,
            currentTask?.title ?: if (data.totalCount == 0) "暂无任务" else "当前无待办",
        )
        views.setTextViewText(
            R.id.widget_current_time,
            currentTask?.timeLabel ?: if (data.nextReminder.isNullOrBlank()) "--:--" else "下一项",
        )
        views.setTextViewText(
            R.id.widget_current_status,
            currentTask?.status ?: (data.nextReminder ?: "轻触打开查看全部任务"),
        )

        views.setInt(
            R.id.widget_summary,
            "setTextColor",
            if (isNight) 0xFFC8D1FF.toInt() else 0xFF5A6B6A.toInt(),
        )
        views.setInt(
            R.id.widget_motto,
            "setTextColor",
            if (isNight) 0xFFFFFFFF.toInt() else 0xFF1E2528.toInt(),
        )
        views.setInt(
            R.id.widget_footer,
            "setTextColor",
            if (isNight) 0xFFA9B4E8.toInt() else 0xFF607372.toInt(),
        )
        views.setInt(
            R.id.widget_current_title,
            "setTextColor",
            if (isNight) 0xFFFFFFFF.toInt() else 0xFF1E2528.toInt(),
        )
        views.setInt(
            R.id.widget_current_time,
            "setTextColor",
            if (isNight) 0xFFAFC1FF.toInt() else 0xFF4E67C3.toInt(),
        )
        views.setInt(
            R.id.widget_current_status,
            "setTextColor",
            if (isNight) 0xFFC8D1FF.toInt() else 0xFF607372.toInt(),
        )
        views.setInt(
            R.id.widget_task_empty,
            "setTextColor",
            if (isNight) 0xFFC8D1FF.toInt() else 0xFF5A6B6A.toInt(),
        )

        if (variant.showTaskList) {
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
        } else {
            views.setViewVisibility(R.id.widget_task_list, android.view.View.GONE)
            views.setViewVisibility(R.id.widget_task_empty, android.view.View.GONE)
        }

        val backgroundBitmap = decodeWidgetBackground(data.imagePath, variant)
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
            91001 + variant.ordinal,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
        views.setOnClickPendingIntent(R.id.widget_current_card, pendingIntent)
        views.setOnClickPendingIntent(R.id.widget_motto_container, pendingIntent)
        if (variant.showTaskList) {
            views.setPendingIntentTemplate(R.id.widget_task_list, pendingIntent)
        }
        return views
    }

    private fun decodeWidgetBackground(path: String?, variant: WidgetVariant): Bitmap? {
        if (path.isNullOrBlank()) return null
        return try {
            val file = File(path)
            if (!file.exists()) return null
            val raw = BitmapFactory.decodeFile(file.absolutePath) ?: return null
            val scale =
                maxOf(raw.width, raw.height).toFloat() / variant.maxBackgroundEdge.toFloat()
            if (scale <= 1f) {
                raw
            } else {
                Bitmap.createScaledBitmap(
                    raw,
                    (raw.width / scale).toInt().coerceAtLeast(1),
                    (raw.height / scale).toInt().coerceAtLeast(1),
                    true,
                )
            }
        } catch (_: Exception) {
            null
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
    val currentTask: WidgetTaskLine?,
    val tasks: List<WidgetTaskLine>,
    val imagePath: String?,
) {
    companion object {
        fun load(context: Context, variant: WidgetVariant): TaskOverviewWidgetData {
            val prefs =
                context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val mottoEntriesRaw = prefs.getString("flutter.daily_motto_entries_v1", null)
            val pinnedMottoId = prefs.getString("flutter.pinned_daily_motto_id_v1", null)
            val showMeta = prefs.getBoolean("flutter.show_daily_motto_meta_on_home_v1", true)
            val todayStateRaw = prefs.getString("flutter.daily_task_state_v1", null)
            val imagePath = prefs.getString("flutter.daily_motto_image_path_v1", null)

            val mottoEntry = parseMottoEntry(mottoEntriesRaw, pinnedMottoId, variant)
            val tasksState = parseTasks(todayStateRaw)
            return TaskOverviewWidgetData(
                motto = mottoEntry.first.ifBlank { "今日箴言未设置" },
                attribution = if (showMeta) mottoEntry.second else "",
                totalCount = tasksState.totalCount,
                completedCount = tasksState.completedCount,
                pendingCount = (tasksState.totalCount - tasksState.completedCount).coerceAtLeast(0),
                nextReminder = tasksState.nextReminder,
                currentTask = tasksState.lines.firstOrNull { !it.done },
                tasks = tasksState.lines,
                imagePath = imagePath?.trim(),
            )
        }

        private fun parseMottoEntry(
            raw: String?,
            pinnedId: String?,
            variant: WidgetVariant,
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
                formatMotto(content.ifBlank { "今日箴言未设置" }, variant) to attribution
            } catch (_: Exception) {
                "今日箴言未设置" to ""
            }
        }

        private fun normalizeText(value: String?): String {
            val text = value?.trim().orEmpty()
            return if (text.equals("null", ignoreCase = true)) "" else text
        }

        private fun formatMotto(content: String, variant: WidgetVariant): String {
            if (!variant.showMotto) return content
            val target =
                when (variant) {
                    WidgetVariant.COMPACT_2X2 -> 10
                    WidgetVariant.MEDIUM_3X3 -> 14
                    WidgetVariant.MOTTO_4X4 -> 18
                    WidgetVariant.LARGE_5X5 -> 22
                }
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
                    val title = normalizeText(task.optString("title")).ifBlank { "未命名任务" }
                    val kind = task.optString("kind")
                    val doneFlag =
                        if (kind == "adCooldown") {
                            val infinite = task.optBoolean("infiniteLoop", false)
                            val target = task.optInt("targetCount", 0)
                            val current = intervalCounts.optInt(taskId, 0)
                            !infinite && target > 0 && current >= target
                        } else {
                            completed.contains(taskId)
                        }
                    if (doneFlag) done += 1

                    val timeLabel =
                        "${task.optInt("startHour").toString().padStart(2, '0')}:${task.optInt("startMinute").toString().padStart(2, '0')}"
                    val status =
                        if (kind == "adCooldown") {
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

                    val reminderMillis =
                        millisForToday(task.optInt("startHour"), task.optInt("startMinute"))
                    val sortDistance =
                        when {
                            reminderMillis == null -> Long.MAX_VALUE
                            doneFlag -> Long.MAX_VALUE - reminderMillis
                            else -> kotlin.math.abs(reminderMillis - nowMillis)
                        }
                    val urgent =
                        !doneFlag &&
                            reminderMillis != null &&
                            kotlin.math.abs(reminderMillis - nowMillis) <= 60 * 60 * 1000
                    lines.add(
                        WidgetTaskLine(
                            title = title,
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
