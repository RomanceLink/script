package com.zilv.clock

import android.app.NotificationChannel
import android.app.KeyguardManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val taskId = intent.getStringExtra("taskId") ?: return
        val title = intent.getStringExtra("title") ?: return
        val body = intent.getStringExtra("body") ?: ""
        val notificationId = intent.getIntExtra("notificationId", taskId.hashCode())

        val wakeLock = (context.getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "zclock:alarm")
        wakeLock.acquire(10_000)

        val fullScreenIntent = Intent(context, AlarmActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("notificationId", notificationId)
            putExtras(intent)
        }
        val keyguardManager = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        val isLocked = keyguardManager.isDeviceLocked
        if (isLocked) {
            context.startActivity(fullScreenIntent)
        } else if (!AutoSwipeService.showAlarmReminderOverlay(fullScreenIntent)) {
            context.startActivity(fullScreenIntent)
        }

        val channelId = buildChannelId(intent)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "任务提醒",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "任务全屏提醒"
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                val soundUri = resolveSoundUri(intent)
                if (soundUri != null) {
                    setSound(
                        soundUri,
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .build()
                    )
                } else {
                    setSound(null, null)
                }
            }
            manager.createNotificationChannel(channel)
        }

        val pending = PendingIntent.getActivity(
            context,
            notificationId,
            fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(true)
            .setFullScreenIntent(pending, true)
            .setContentIntent(pending)
            .build()

        NotificationManagerCompat.from(context).notify(notificationId, notification)
        if (wakeLock.isHeld) wakeLock.release()
    }

    private fun buildChannelId(intent: Intent): String {
        val source = intent.getStringExtra("ringtoneSource") ?: "systemDefault"
        val value = intent.getStringExtra("ringtoneValue") ?: "default"
        return "alarm_${source}_${value.hashCode()}"
    }

    private fun resolveSoundUri(intent: Intent): Uri? {
        val source = intent.getStringExtra("ringtoneSource") ?: "systemDefault"
        val value = intent.getStringExtra("ringtoneValue")
        return when (source) {
            "systemAlarm" -> if (value.isNullOrBlank()) {
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            } else {
                Uri.parse(value)
            }
            "systemDefault" -> if (value.isNullOrBlank()) {
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            } else {
                Uri.parse(value)
            }
            else -> null
        }
    }
}
