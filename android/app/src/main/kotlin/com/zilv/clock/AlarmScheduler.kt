package com.zilv.clock

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import org.json.JSONArray
import org.json.JSONObject

object AlarmScheduler {
    private const val prefsName = "alarm_schedule_store"
    private const val remindersKey = "reminders_json"

    fun replaceAlarms(context: Context, reminders: List<Map<String, Any?>>) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        cancelExisting(context, alarmManager)
        persistReminders(context, reminders)
        scheduleAll(context, alarmManager, reminders)
    }

    fun scheduleSelfTest(context: Context, reminder: Map<String, Any?>) {
        replaceAlarms(context, listOf(reminder))
    }

    fun restorePersistedAlarms(context: Context) {
        val reminders = loadPersistedReminders(context)
        if (reminders.isEmpty()) return
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        cancelExisting(context, alarmManager)
        scheduleAll(context, alarmManager, reminders)
    }

    private fun cancelExisting(context: Context, alarmManager: AlarmManager) {
        for (requestCode in 1000..1150) {
            val intent = Intent(context, AlarmReceiver::class.java)
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarmManager.cancel(pendingIntent)
        }
    }

    private fun scheduleAll(
        context: Context,
        alarmManager: AlarmManager,
        reminders: List<Map<String, Any?>>
    ) {
        reminders.forEachIndexed { index, reminder ->
            val requestCode = 1000 + index
            val intent = Intent(context, AlarmReceiver::class.java).apply {
                putExtra("id", reminder["id"] as String)
                putExtra("taskId", reminder["taskId"] as String)
                putExtra("title", reminder["title"] as String)
                putExtra("body", reminder["body"] as String)
                putExtra("ringtoneSource", reminder["ringtoneSource"] as String)
                putExtra("ringtoneLabel", reminder["ringtoneLabel"] as String)
                putExtra("ringtoneValue", reminder["ringtoneValue"] as String?)
                putExtra("targetAppPackage", reminder["targetAppPackage"] as String?)
                putExtra("targetAppLabel", reminder["targetAppLabel"] as String?)
                putExtra("gestureConfigName", reminder["gestureConfigName"] as String?)
                putExtra("gestureActionsJson", reminder["gestureActionsJson"] as String?)
                putExtra("gestureLoopCount", (reminder["gestureLoopCount"] as? Number)?.toInt())
                putExtra("gestureLoopIntervalMillis", (reminder["gestureLoopIntervalMillis"] as? Number)?.toInt())
                putExtra("notificationId", requestCode)
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val triggerAt = (reminder["whenEpochMillis"] as Number).toLong()
            alarmManager.setAlarmClock(
                AlarmManager.AlarmClockInfo(triggerAt, pendingIntent),
                pendingIntent
            )
        }
    }

    private fun persistReminders(context: Context, reminders: List<Map<String, Any?>>) {
        val array = JSONArray()
        reminders.forEach { reminder ->
            val obj = JSONObject()
            reminder.forEach { (key, value) -> obj.put(key, value) }
            array.put(obj)
        }
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit()
            .putString(remindersKey, array.toString())
            .apply()
    }

    private fun loadPersistedReminders(context: Context): List<Map<String, Any?>> {
        val raw = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .getString(remindersKey, null) ?: return emptyList()
        val array = JSONArray(raw)
        val out = mutableListOf<Map<String, Any?>>()
        for (i in 0 until array.length()) {
            val obj = array.getJSONObject(i)
            out.add(
                mapOf(
                    "id" to obj.getString("id"),
                    "taskId" to obj.getString("taskId"),
                    "title" to obj.getString("title"),
                    "body" to obj.getString("body"),
                    "whenEpochMillis" to obj.getLong("whenEpochMillis"),
                    "ringtoneSource" to obj.getString("ringtoneSource"),
                    "ringtoneLabel" to obj.getString("ringtoneLabel"),
                    "ringtoneValue" to if (obj.isNull("ringtoneValue")) null else obj.getString("ringtoneValue"),
                    "targetAppPackage" to if (obj.isNull("targetAppPackage")) null else obj.getString("targetAppPackage"),
                    "targetAppLabel" to if (obj.isNull("targetAppLabel")) null else obj.getString("targetAppLabel"),
                    "gestureConfigName" to if (obj.isNull("gestureConfigName")) null else obj.getString("gestureConfigName"),
                    "gestureActionsJson" to if (obj.isNull("gestureActionsJson")) null else obj.getString("gestureActionsJson"),
                    "gestureLoopCount" to if (obj.isNull("gestureLoopCount")) null else obj.getInt("gestureLoopCount"),
                    "gestureLoopIntervalMillis" to if (obj.isNull("gestureLoopIntervalMillis")) null else obj.getInt("gestureLoopIntervalMillis"),
                )
            )
        }
        return out
    }
}
