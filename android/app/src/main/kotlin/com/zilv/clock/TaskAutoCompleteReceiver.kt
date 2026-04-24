package com.zilv.clock

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.util.Calendar
import org.json.JSONException
import org.json.JSONArray
import org.json.JSONObject

class TaskAutoCompleteReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val taskId = intent.getStringExtra("taskId") ?: return
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val raw = prefs.getString("flutter.daily_task_state_v1", null) ?: return
        val root = try {
            JSONObject(raw)
        } catch (_: Exception) {
            return
        }
        val todayKey = intent.getStringExtra("dateKey") ?: return
        if (root.optString("dateKey") != todayKey) {
            return
        }

        val definitions = root.optJSONArray("taskDefinitions") ?: JSONArray()
        var taskDef: JSONObject? = null
        for (index in 0 until definitions.length()) {
            val obj = definitions.optJSONObject(index) ?: continue
            if (obj.optString("id") == taskId) {
                taskDef = obj
                break
            }
        }
        val task = taskDef ?: return
        if (!containsString(root.optJSONArray("enabledTaskIds"), taskId)) {
            return
        }

        val kind = task.optString("kind")
        var changed = false
        when (kind) {
            "adCooldown" -> {
                val nextAvailable = root.optJSONObject("intervalNextAvailableAt")
                val currentNext = nextAvailable?.optLong(taskId, 0L) ?: 0L
                if (currentNext > System.currentTimeMillis()) {
                    return
                }
                val counts = root.optJSONObject("intervalCompletedCounts") ?: JSONObject()
                val current = counts.optInt(taskId, 0)
                val infinite = task.optBoolean("infiniteLoop", false)
                val targetCount = task.optInt("targetCount", 0)
                val nextCount = if (infinite) current + 1 else (current + 1).coerceAtMost(targetCount)
                counts.put(taskId, nextCount)
                root.put("intervalCompletedCounts", counts)

                val nextTimes = nextAvailable ?: JSONObject()
                if (!infinite && nextCount >= targetCount) {
                    nextTimes.remove(taskId)
                } else {
                    nextTimes.put(taskId, System.currentTimeMillis() + cooldownMillis(task))
                }
                root.put("intervalNextAvailableAt", nextTimes)
                changed = true
                scheduleNextCooldownReminder(context, prefs, root, task, nextCount)
            }
            else -> {
                val completed = root.optJSONArray("completedTaskIds") ?: JSONArray()
                if (containsString(completed, taskId)) {
                    return
                }
                completed.put(taskId)
                root.put("completedTaskIds", completed)
                changed = true
            }
        }

        if (changed) {
            prefs.edit().putString("flutter.daily_task_state_v1", root.toString()).apply()
            TaskOverviewWidgetProvider.refreshAll(context)
        }
    }

    private fun scheduleNextCooldownReminder(
        context: Context,
        prefs: android.content.SharedPreferences,
        root: JSONObject,
        task: JSONObject,
        completedCount: Int,
    ) {
        val infinite = task.optBoolean("infiniteLoop", false)
        val targetCount = task.optInt("targetCount", 0)
        if (!infinite && completedCount >= targetCount) {
            return
        }

        val nextAt = root.optJSONObject("intervalNextAvailableAt")
            ?.optLong(task.optString("id"), 0L)
            ?.takeIf { it > System.currentTimeMillis() }
            ?: return

        val targetAppPackage = root.optString("selectedAppPackage").takeIf { it.isNotBlank() }
        val targetAppLabel = root.optString("selectedAppLabel").takeIf { it.isNotBlank() } ?: "目标应用"
        val reminderIntent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra("id", "auto_${task.optString("id")}")
            putExtra("taskId", task.optString("id"))
            putExtra("title", task.optString("title"))
            putExtra("body", "间隔结束，可开始下一次。")
            putExtra("ringtoneSource", task.optString("ringtoneSource", "systemDefault"))
            putExtra("ringtoneLabel", task.optString("ringtoneLabel", "默认铃声"))
            putExtra("ringtoneValue", task.optString("ringtoneValue").takeIf { it.isNotBlank() })
            putExtra("targetAppPackage", targetAppPackage)
            putExtra("targetAppLabel", targetAppLabel)
            putExtra("autoOpenDelaySeconds", task.optInt("autoOpenDelaySeconds", 0))
            putExtra("autoCompleteDelaySeconds", task.optInt("autoCompleteDelaySeconds", 0))
            putExtra("notificationId", 70000 + task.optString("id").hashCode())
        }

        val configs = loadGestureConfigs(prefs)
        addGestureExtras(reminderIntent, task.optString("gestureConfigId"), "gesture", configs)
        addGestureExtras(reminderIntent, task.optString("preGestureConfigId"), "preGesture", configs)

        val pending = PendingIntent.getBroadcast(
            context,
            70000 + task.optString("id").hashCode(),
            reminderIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, nextAt, pending)
    }

    companion object {
        private const val REQUEST_BASE = 60000

        private data class ResolvedGesturePlan(
            val name: String,
            val beforeLoopActions: JSONArray,
            val loopActions: JSONArray,
            val loopCount: Int,
            val loopIntervalMillis: Int,
            val infiniteLoop: Boolean,
        )

        fun schedule(context: Context, taskId: String, dateKey: String, delaySeconds: Int) {
            cancel(context, taskId)
            if (delaySeconds <= 0) return
            val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, TaskAutoCompleteReceiver::class.java).apply {
                putExtra("taskId", taskId)
                putExtra("dateKey", dateKey)
            }
            val pending = PendingIntent.getBroadcast(
                context,
                REQUEST_BASE + taskId.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val triggerAt = System.currentTimeMillis() + delaySeconds * 1000L
            manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
        }

        fun todayKey(nowMillis: Long = System.currentTimeMillis()): String {
            val calendar = Calendar.getInstance().apply {
                timeInMillis = nowMillis
            }
            val year = calendar.get(Calendar.YEAR)
            val month = (calendar.get(Calendar.MONTH) + 1).toString().padStart(2, '0')
            val day = calendar.get(Calendar.DAY_OF_MONTH).toString().padStart(2, '0')
            return "$year-$month-$day"
        }

        fun cancel(context: Context, taskId: String) {
            val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, TaskAutoCompleteReceiver::class.java)
            val pending = PendingIntent.getBroadcast(
                context,
                REQUEST_BASE + taskId.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            manager.cancel(pending)
        }

        private fun containsString(array: JSONArray?, value: String): Boolean {
            if (array == null) return false
            for (index in 0 until array.length()) {
                if (array.optString(index) == value) return true
            }
            return false
        }

        private fun cooldownMillis(task: JSONObject): Long {
            val value = task.optInt("cooldownValue", 0).coerceAtLeast(0)
            return when (task.optString("intervalUnit", "minutes")) {
                "seconds" -> value * 1000L
                "hours" -> value * 60L * 60L * 1000L
                "days" -> value * 24L * 60L * 60L * 1000L
                else -> value * 60L * 1000L
            }
        }

        private fun loadGestureConfigs(prefs: android.content.SharedPreferences): JSONArray {
            val raw = prefs.getString("flutter.gesture_configs_v1", null) ?: return JSONArray()
            return try {
                JSONArray(raw)
            } catch (_: JSONException) {
                JSONArray()
            }
        }

        private fun addGestureExtras(
            intent: Intent,
            configId: String?,
            prefix: String,
            configs: JSONArray,
        ) {
            if (configId.isNullOrBlank()) return
            val config = findConfig(configs, configId) ?: return
            val allowInfinite = prefix != "preGesture"
            val plan = resolveGesturePlan(
                config = config,
                configs = configs,
                allowInfinite = allowInfinite,
            )
            intent.putExtra("${prefix}ConfigName", plan.name)
            if (prefix == "preGesture") {
                val flattened = JSONArray().apply {
                    mergeJsonArray(plan.beforeLoopActions)
                    mergeJsonArray(plan.loopActions)
                }
                intent.putExtra("${prefix}ActionsJson", flattened.toString())
                intent.putExtra("${prefix}LoopCount", 1)
                intent.putExtra("${prefix}LoopIntervalMillis", 0)
                return
            }
            intent.putExtra("${prefix}BeforeLoopActionsJson", plan.beforeLoopActions.toString())
            intent.putExtra("${prefix}ActionsJson", plan.loopActions.toString())
            intent.putExtra("${prefix}LoopCount", plan.loopCount)
            intent.putExtra("${prefix}LoopIntervalMillis", plan.loopIntervalMillis)
            intent.putExtra("${prefix}InfiniteLoop", plan.infiniteLoop)
        }

        private fun findConfig(configs: JSONArray, id: String): JSONObject? {
            for (index in 0 until configs.length()) {
                val obj = configs.optJSONObject(index) ?: continue
                if (obj.optString("id") == id) return obj
            }
            return null
        }

        private fun resolveGesturePlan(
            config: JSONObject,
            configs: JSONArray,
            allowInfinite: Boolean,
            visited: MutableSet<String> = mutableSetOf(),
        ): ResolvedGesturePlan {
            val configId = config.optString("id")
            if (configId.isNotBlank() && !visited.add(configId)) {
                return ResolvedGesturePlan(
                    name = config.optString("name", "配置"),
                    beforeLoopActions = expandLoopedActionsJson(
                        config.optJSONArray("actions"),
                        config.optInt("loopCount", 1),
                        config.optInt("loopIntervalMillis", 0),
                    ),
                    loopActions = JSONArray(),
                    loopCount = 1,
                    loopIntervalMillis = 0,
                    infiniteLoop = false,
                )
            }
            val name = config.optString("name", "配置")
            val infiniteLoop = config.optBoolean("infiniteLoop", false)
            if (infiniteLoop && allowInfinite) {
                return ResolvedGesturePlan(
                    name = name,
                    beforeLoopActions = JSONArray(),
                    loopActions = cloneJsonArray(config.optJSONArray("actions")),
                    loopCount = config.optInt("loopCount", 1).coerceIn(1, 9999),
                    loopIntervalMillis = config.optInt("loopIntervalMillis", 0).coerceAtLeast(0),
                    infiniteLoop = true,
                )
            }
            val current = expandLoopedActionsJson(
                config.optJSONArray("actions"),
                config.optInt("loopCount", 1),
                config.optInt("loopIntervalMillis", 0),
            )
            val followUpId = config.optString("followUpConfigId").takeIf { it.isNotBlank() }
            val child = followUpId?.let { findConfig(configs, it) }
            if (child == null) {
                return ResolvedGesturePlan(
                    name = name,
                    beforeLoopActions = current,
                    loopActions = JSONArray(),
                    loopCount = 1,
                    loopIntervalMillis = 0,
                    infiniteLoop = false,
                )
            }
            val childPlan = resolveGesturePlan(child, configs, allowInfinite, visited)
            current.mergeJsonArray(childPlan.beforeLoopActions)
            return ResolvedGesturePlan(
                name = "$name -> ${childPlan.name}",
                beforeLoopActions = current,
                loopActions = cloneJsonArray(childPlan.loopActions),
                loopCount = childPlan.loopCount,
                loopIntervalMillis = childPlan.loopIntervalMillis,
                infiniteLoop = childPlan.infiniteLoop,
            )
        }

        private fun expandLoopedActionsJson(
            actions: JSONArray?,
            loopCount: Int,
            loopIntervalMillis: Int,
        ): JSONArray {
            val out = JSONArray()
            val loops = loopCount.coerceIn(1, 9999)
            for (i in 0 until loops) {
                out.mergeJsonArray(actions)
                if (i < loops - 1 && loopIntervalMillis > 0) {
                    out.put(
                        JSONObject().apply {
                            put("type", "wait")
                            put("waitMode", "fixed")
                            put("seconds", ((loopIntervalMillis + 999) / 1000).coerceIn(1, 10000))
                            put("waitMillis", loopIntervalMillis.coerceIn(1, 10_000_000))
                        },
                    )
                }
            }
            return out
        }

        private fun cloneJsonArray(source: JSONArray?): JSONArray {
            val out = JSONArray()
            out.mergeJsonArray(source)
            return out
        }

        private fun JSONArray.mergeJsonArray(source: JSONArray?) {
            if (source == null) return
            for (index in 0 until source.length()) {
                put(source.opt(index))
            }
        }
    }
}
