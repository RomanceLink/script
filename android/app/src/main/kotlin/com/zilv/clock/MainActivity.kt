package com.zilv.clock

import android.app.Activity
import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "scriptapp/alarm"
    private val ringtoneRequestCode = 4101
    private var ringtoneResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "replaceAlarms" -> {
                        val reminders = call.argument<List<Map<String, Any?>>>("reminders") ?: emptyList()
                        AlarmScheduler.replaceAlarms(this, reminders)
                        result.success(null)
                    }
                    "consumeLaunchTaskId" -> {
                        result.success(consumeLaunchTaskId())
                    }
                    "pickSystemRingtone" -> {
                        ringtoneResult = result
                        val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
                            putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_ALL)
                            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
                            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
                        }
                        startActivityForResult(intent, ringtoneRequestCode)
                    }
                    "openExactAlarmSettings" -> {
                        openExactAlarmSettings()
                        result.success(null)
                    }
                    "openNotificationSettings" -> {
                        openNotificationSettings()
                        result.success(null)
                    }
                    "openFullScreenIntentSettings" -> {
                        openFullScreenIntentSettings()
                        result.success(null)
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        requestIgnoreBatteryOptimizations()
                        result.success(null)
                    }
                    "openOverlaySettings" -> {
                        val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION).apply {
                            data = Uri.parse("package:$packageName")
                        }
                        startActivity(intent)
                        result.success(null)
                    }
                    "openAccessibilitySettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(null)
                    }
                    "performAutoSwipe" -> {
                        val interval = call.argument<Int>("interval") ?: 30
                        val useRandom = call.argument<Boolean>("useRandom") ?: false
                        AutoSwipeService.updateConfig(interval, useRandom)
                        result.success(null)
                    }
                    "scheduleSelfTest" -> {
                        val reminder = call.argument<Map<String, Any?>>("reminder")
                        if (reminder != null) {
                            AlarmScheduler.scheduleSelfTest(this, reminder)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != ringtoneRequestCode) {
            return
        }
        val callback = ringtoneResult ?: return
        ringtoneResult = null

        if (resultCode != Activity.RESULT_OK) {
            callback.success(null)
            return
        }

        val uri = data?.getParcelableExtra<Uri>(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        if (uri == null) {
            callback.success(null)
            return
        }

        val ringtone = RingtoneManager.getRingtone(this, uri)
        val label = ringtone?.getTitle(this) ?: "系统铃声"
        callback.success(mapOf("uri" to uri.toString(), "label" to label))
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    private fun consumeLaunchTaskId(): String? {
        val value = intent?.getStringExtra("taskId") ?: AlarmLaunchStore.consumePendingTaskId(this)
        intent?.removeExtra("taskId")
        return value
    }

    private fun openExactAlarmSettings() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
            startActivity(intent)
        }
    }

    private fun openNotificationSettings() {
        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        }
        startActivity(intent)
    }

    private fun requestIgnoreBatteryOptimizations() {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (!powerManager.isIgnoringBatteryOptimizations(packageName)) {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
        }
    }

    private fun openFullScreenIntentSettings() {
        try {
            val intent = Intent("android.settings.MANAGE_APP_USE_FULL_SCREEN_INTENT").apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
        } catch (_: Exception) {
            openNotificationSettings()
        }
    }
}

object AlarmLaunchStore {
    private const val prefsName = "alarm_bridge"
    private const val taskKey = "pending_task_id"

    fun setPendingTaskId(context: Context, taskId: String) {
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit()
            .putString(taskKey, taskId)
            .apply()
    }

    fun consumePendingTaskId(context: Context): String? {
        val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        val value = prefs.getString(taskKey, null)
        prefs.edit().remove(taskKey).apply()
        return value
    }
}
