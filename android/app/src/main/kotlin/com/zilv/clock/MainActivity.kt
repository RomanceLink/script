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
                    "consumeOverlayCommand" -> {
                        result.success(consumeOverlayCommand())
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
                    "enterPickerMode" -> {
                        val type = call.argument<String>("type") ?: "click"
                        AutoSwipeService.onPickerResult = { resultData ->
                            runOnUiThread {
                                AutoSwipeService.onPickerResult = null
                                result.success(resultData)
                            }
                        }
                        if (!AutoSwipeService.enterPickerMode(type)) {
                            AutoSwipeService.onPickerResult = null
                            result.success(null)
                        }
                    }
                    "showAutomationMenu" -> {
                        val configs = call.argument<List<Map<String, Any?>>>("configs") ?: emptyList()
                        result.success(AutoSwipeService.showAutomationMenu(configs))
                    }
                    "syncAutomationConfigs" -> {
                        val configs = call.argument<List<Map<String, Any?>>>("configs") ?: emptyList()
                        result.success(AutoSwipeService.syncAutomationConfigs(configs))
                    }
                    "openAppAndRunConfig" -> {
                        val packageName = call.argument<String>("packageName")
                        val packageLabel = call.argument<String>("packageLabel") ?: "目标应用"
                        val preConfigName = call.argument<String>("preConfigName")
                        val preActions = call.argument<List<Map<String, Any?>>>("preActions") ?: emptyList()
                        val preLoopCount = call.argument<Int>("preLoopCount") ?: 1
                        val preLoopIntervalMillis = call.argument<Int>("preLoopIntervalMillis") ?: 0
                        val configName = call.argument<String>("configName")
                        val beforeLoopActions = call.argument<List<Map<String, Any?>>>("beforeLoopActions") ?: emptyList()
                        val actions = call.argument<List<Map<String, Any?>>>("actions") ?: emptyList()
                        val loopCount = call.argument<Int>("loopCount") ?: 1
                        val loopIntervalMillis = call.argument<Int>("loopIntervalMillis") ?: 0
                        val infiniteLoop = call.argument<Boolean>("infiniteLoop") ?: false
                        val delaySeconds = call.argument<Int>("delaySeconds") ?: 5
                        if (packageName.isNullOrBlank()) {
                            result.success(false)
                        } else {
                            result.success(
                                AutoSwipeService.openAppAndRunConfig(
                                    this,
                                    packageName,
                                    packageLabel,
                                    preConfigName,
                                    preActions,
                                    preLoopCount,
                                    preLoopIntervalMillis,
                                    configName,
                                    beforeLoopActions,
                                    actions,
                                    loopCount,
                                    loopIntervalMillis,
                                    infiniteLoop,
                                    delaySeconds
                                )
                            )
                        }
                    }
                    "verifyUnlockScript" -> {
                        result.success(AutoSwipeService.verifyUnlockScript(this))
                    }
                    "performAutoSwipe" -> {
                        val min = call.argument<Int>("min") ?: 30
                        val max = call.argument<Int>("max") ?: 60
                        val name = call.argument<String>("name")
                        val beforeLoopActions = call.argument<List<Map<String, Any?>>>("beforeLoopActions") ?: emptyList()
                        val actions = call.argument<List<Map<String, Any?>>>("actions") ?: emptyList()
                        val loopCount = call.argument<Int>("loopCount") ?: 1
                        val loopIntervalMillis = call.argument<Int>("loopIntervalMillis") ?: 0
                        val infiniteLoop = call.argument<Boolean>("infiniteLoop") ?: false
                        AutoSwipeService.updateConfig(
                            min,
                            max,
                            actions,
                            name,
                            loopCount,
                            loopIntervalMillis,
                            beforeLoopActions,
                            infiniteLoop,
                        )
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

    private fun consumeOverlayCommand(): String? {
        val stored = AlarmLaunchStore.consumePendingOverlayCommand(this)
        val value = intent?.getStringExtra("overlayCommand") ?: stored
        intent?.removeExtra("overlayCommand")
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
    private const val overlayCommandKey = "pending_overlay_command"

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

    fun setPendingOverlayCommand(context: Context, command: String) {
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit()
            .putString(overlayCommandKey, command)
            .apply()
    }

    fun consumePendingOverlayCommand(context: Context): String? {
        val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        val value = prefs.getString(overlayCommandKey, null)
        prefs.edit().remove(overlayCommandKey).apply()
        return value
    }
}
