package com.zilv.clock

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import android.widget.TextView
import androidx.activity.ComponentActivity
import com.zilv.clock.R
import java.io.File

class AlarmActivity : ComponentActivity() {
    private var ringtone: Ringtone? = null
    private var mediaPlayer: MediaPlayer? = null
    private var notificationId: Int = 0
    private var taskId: String = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        taskId = intent.getStringExtra("taskId") ?: ""
        notificationId = intent.getIntExtra("notificationId", 0)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }

        val title = intent.getStringExtra("title") ?: "任务提醒"
        val body = intent.getStringExtra("body") ?: "你的任务现在需要完成。"
        renderUi(title = title, body = body)
        startSound()
    }

    private fun renderUi(title: String, body: String) {
        setContentView(R.layout.activity_alarm)
        val targetAppPackage = intent.getStringExtra("targetAppPackage")
        val targetAppLabel = intent.getStringExtra("targetAppLabel") ?: "目标应用"
        val configName = intent.getStringExtra("gestureConfigName")
        val actionsJson = intent.getStringExtra("gestureActionsJson")
        val loopCount = intent.getIntExtra("gestureLoopCount", 1).coerceAtLeast(1)
        val loopIntervalMillis = intent.getIntExtra("gestureLoopIntervalMillis", 0).coerceAtLeast(0)
        findViewById<TextView>(R.id.alarmTitle).text = title
        findViewById<TextView>(R.id.alarmBody).text = body
        findViewById<TextView>(R.id.alarmHint).text = if (configName.isNullOrBlank()) {
            "提醒已触发，点击下方按钮打开 $targetAppLabel。"
        } else {
            "绑定配置：$configName（$loopCount 次，间隔 ${loopIntervalMillis} 毫秒），打开 $targetAppLabel 后 5 秒自动执行。"
        }
        findViewById<TextView>(R.id.openTaskButton).text = "打开$targetAppLabel"
        findViewById<TextView>(R.id.openTaskButton).setOnClickListener {
            stopSound()
            if (!targetAppPackage.isNullOrBlank()) {
                AutoSwipeService.openAppAndRunConfig(
                    this@AlarmActivity,
                    targetAppPackage,
                    targetAppLabel,
                    configName,
                    AutoSwipeService.parseActionsJson(actionsJson),
                    loopCount,
                    loopIntervalMillis,
                    5
                )
            } else {
                AlarmLaunchStore.setPendingTaskId(this@AlarmActivity, taskId)
                val launchIntent = Intent(this@AlarmActivity, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    putExtra("taskId", taskId)
                }
                startActivity(launchIntent)
            }
            finishAlarm()
        }
        findViewById<TextView>(R.id.dismissButton).setOnClickListener {
            finishAlarm()
        }
    }

    private fun startSound() {
        stopSound()
        val source = intent.getStringExtra("ringtoneSource") ?: "systemDefault"
        val value = intent.getStringExtra("ringtoneValue")

        when (source) {
            "filePath" -> {
                if (!value.isNullOrBlank()) {
                    val file = File(value)
                    if (file.exists()) {
                        mediaPlayer = MediaPlayer().apply {
                            setAudioAttributes(
                                AudioAttributes.Builder()
                                    .setUsage(AudioAttributes.USAGE_ALARM)
                                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                                    .build()
                            )
                            setDataSource(this@AlarmActivity, Uri.fromFile(file))
                            isLooping = true
                            prepare()
                            start()
                        }
                        return
                    }
                }
                playSystemAlarm()
            }
            "systemAlarm" -> {
                val uri = if (!value.isNullOrBlank()) Uri.parse(value) else
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                playRingtone(uri)
            }
            else -> {
                val uri = if (!value.isNullOrBlank()) Uri.parse(value) else
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                playRingtone(uri)
            }
        }
    }

    private fun playSystemAlarm() {
        playRingtone(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM))
    }

    private fun playRingtone(uri: Uri?) {
        if (uri == null) return
        ringtone = RingtoneManager.getRingtone(this, uri)?.apply {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                isLooping = true
            }
            play()
        }
    }

    private fun stopSound() {
        ringtone?.stop()
        ringtone = null
        mediaPlayer?.stop()
        mediaPlayer?.release()
        mediaPlayer = null
    }

    private fun finishAlarm() {
        stopSound()
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(notificationId)
        finish()
    }

    override fun onDestroy() {
        stopSound()
        super.onDestroy()
    }
}
