package com.example.scriptapp

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.os.Bundle
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
        val value = intent?.getStringExtra("taskId")
        intent?.removeExtra("taskId")
        return value
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
}
