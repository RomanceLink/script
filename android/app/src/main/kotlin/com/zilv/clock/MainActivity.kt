package com.zilv.clock

import android.app.Activity
import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import android.graphics.Rect
import android.media.RingtoneManager
import android.net.Uri
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
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
                    "recognizeScreenText" -> {
                        val region = call.argument<Map<String, Any?>>("region")
                        recognizeCurrentActivityText(region) { activityLines ->
                            if (hasUsefulOcrText(activityLines)) {
                                runOnUiThread { result.success(activityLines) }
                                return@recognizeCurrentActivityText
                            }
                            if (!AutoSwipeService.recognizeScreenText(region) { lines ->
                                    runOnUiThread { result.success(lines) }
                                }) {
                                runOnUiThread { result.success(emptyList<Map<String, Any?>>()) }
                            }
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

    private fun recognizeCurrentActivityText(
        region: Map<String, Any?>?,
        callback: (List<Map<String, Any?>>) -> Unit,
    ) {
        val root = window?.decorView?.rootView
        if (root == null || root.width <= 0 || root.height <= 0) {
            callback(emptyList())
            return
        }
        val bitmap = try {
            Bitmap.createBitmap(root.width, root.height, Bitmap.Config.ARGB_8888).also { output ->
                val canvas = Canvas(output)
                canvas.drawColor(Color.WHITE)
                root.draw(canvas)
            }
        } catch (_: Exception) {
            callback(emptyList())
            return
        }
        val source = cropBitmap(bitmap, normalizedRegionToRect(region, bitmap.width, bitmap.height))
        if (source !== bitmap) {
            bitmap.recycle()
        }
        recognizeBitmapText(
            bitmap = source,
            offset = normalizedRegionToRect(region, root.width, root.height)?.let {
                it.left to it.top
            } ?: (0 to 0),
            screenWidth = root.width,
            screenHeight = root.height,
            callback = callback,
        )
    }

    private fun hasUsefulOcrText(lines: List<Map<String, Any?>>): Boolean {
        val text = lines.joinToString("") { (it["text"] ?: "").toString() }
        val chineseCount = text.count { it in '\u4e00'..'\u9fff' }
        return chineseCount >= 6 || text.length >= 16
    }

    private fun cropBitmap(bitmap: Bitmap, rect: Rect?): Bitmap {
        if (rect == null) return bitmap
        return try {
            Bitmap.createBitmap(bitmap, rect.left, rect.top, rect.width(), rect.height())
        } catch (_: Exception) {
            bitmap
        }
    }

    private fun normalizedRegionToRect(region: Map<String, Any?>?, width: Int, height: Int): Rect? {
        if (region == null) return null
        val left = ((region["left"] as? Number)?.toDouble() ?: 0.0) * width
        val top = ((region["top"] as? Number)?.toDouble() ?: 0.0) * height
        val right = ((region["right"] as? Number)?.toDouble() ?: 1.0) * width
        val bottom = ((region["bottom"] as? Number)?.toDouble() ?: 1.0) * height
        val rect = Rect(
            left.toInt().coerceIn(0, width - 1),
            top.toInt().coerceIn(0, height - 1),
            right.toInt().coerceIn(1, width),
            bottom.toInt().coerceIn(1, height),
        )
        return if (rect.width() >= 12 && rect.height() >= 12) rect else null
    }

    private fun recognizeBitmapText(
        bitmap: Bitmap,
        offset: Pair<Int, Int>,
        screenWidth: Int,
        screenHeight: Int,
        callback: (List<Map<String, Any?>>) -> Unit,
    ) {
        val recognizer = TextRecognition.getClient(
            ChineseTextRecognizerOptions.Builder().build(),
        )
        val enhanced = preprocessOcrBitmap(bitmap)
        val collected = linkedMapOf<String, Map<String, Any?>>()

        fun collect(result: com.google.mlkit.vision.text.Text) {
            result.textBlocks.forEach { block ->
                block.lines.forEach { line ->
                    val bounds = line.boundingBox ?: return@forEach
                    val text = line.text.trim()
                    if (text.isBlank()) return@forEach
                    val left = bounds.left + offset.first
                    val top = bounds.top + offset.second
                    val right = bounds.right + offset.first
                    val bottom = bounds.bottom + offset.second
                    val key = "$left,$top,$right,$bottom|$text"
                    collected[key] = mapOf(
                        "text" to text,
                        "bounds" to mapOf(
                            "left" to (left.toDouble() / screenWidth.coerceAtLeast(1)),
                            "top" to (top.toDouble() / screenHeight.coerceAtLeast(1)),
                            "right" to (right.toDouble() / screenWidth.coerceAtLeast(1)),
                            "bottom" to (bottom.toDouble() / screenHeight.coerceAtLeast(1)),
                        ),
                    )
                }
            }
        }

        recognizer.process(InputImage.fromBitmap(bitmap, 0))
            .addOnSuccessListener { original ->
                collect(original)
                recognizer.process(InputImage.fromBitmap(enhanced, 0))
                    .addOnSuccessListener { boosted ->
                        collect(boosted)
                        callback(collected.values.toList())
                    }
                    .addOnFailureListener {
                        callback(collected.values.toList())
                    }
                    .addOnCompleteListener {
                        enhanced.recycle()
                        bitmap.recycle()
                    }
            }
            .addOnFailureListener {
                recognizer.process(InputImage.fromBitmap(enhanced, 0))
                    .addOnSuccessListener { boosted ->
                        collect(boosted)
                        callback(collected.values.toList())
                    }
                    .addOnFailureListener {
                        callback(emptyList())
                    }
                    .addOnCompleteListener {
                        enhanced.recycle()
                        bitmap.recycle()
                    }
            }
    }

    private fun preprocessOcrBitmap(source: Bitmap): Bitmap {
        val output = Bitmap.createBitmap(source.width, source.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val matrix = ColorMatrix().apply { setSaturation(0f) }
        val contrast = 1.45f
        val translate = (-128f * contrast) + 128f
        val contrastMatrix = ColorMatrix(
            floatArrayOf(
                contrast, 0f, 0f, 0f, translate,
                0f, contrast, 0f, 0f, translate,
                0f, 0f, contrast, 0f, 0f, translate,
                0f, 0f, 0f, 1f, 0f,
            ),
        )
        matrix.postConcat(contrastMatrix)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            colorFilter = ColorMatrixColorFilter(matrix)
        }
        canvas.drawBitmap(source, 0f, 0f, paint)
        return output
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
