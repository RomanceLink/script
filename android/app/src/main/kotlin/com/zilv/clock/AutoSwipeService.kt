package com.zilv.clock

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.app.NotificationManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.text.InputType
import android.graphics.Typeface
import android.util.Base64
import android.util.DisplayMetrics
import android.content.res.Configuration
import android.view.Gravity
import android.view.Display
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.renderer.FlutterUiDisplayListener
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.Random
import kotlin.math.abs
import kotlin.math.max

class AutoSwipeService : AccessibilityService() {

    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var floatingLayoutParams: WindowManager.LayoutParams? = null
    private var chooserOverlay: View? = null
    private var flutterOverlayRoot: FrameLayout? = null
    private var flutterOverlayParams: WindowManager.LayoutParams? = null
    private var flutterOverlayEngine: FlutterEngine? = null
    private var flutterOverlayView: FlutterView? = null
    private var flutterOverlayChannel: MethodChannel? = null
    private var pickerOverlay: View? = null
    private var reminderOverlay: View? = null
    private var reminderAutoOpenRunnable: Runnable? = null
    private var startMenuButton: ImageView? = null
    private var pauseMenuButton: ImageView? = null
    private var endMenuButton: ImageView? = null
    private var statusPrimaryView: TextView? = null
    private var statusSecondaryView: TextView? = null
    private var statusLoopView: TextView? = null
    private var statusStepView: TextView? = null
    private var statusTimeView: TextView? = null
    private var statusWaitView: TextView? = null
    private var collapsedMenuButton: View? = null

    private var isRunning = false
    private var isPaused = false
    private var minSeconds = 0
    private var maxSeconds = 0
    private var loopCount = 1
    private var infiniteLoop = false
    private var loopIntervalMillis = 0L
    private var remainingLoops = 0
    private var scriptName: String? = null
    private var collapsed = false
    private var collapsedEdgeRight = true
    private var flutterOverlayAttached = false
    private var selectedConfigIndex = -1
    private var lastNightModeMask = Configuration.UI_MODE_NIGHT_UNDEFINED

    private val gestureActions = mutableListOf<Map<String, Any?>>()
    private val setupActions = mutableListOf<Map<String, Any?>>()
    private val runtimeActions = mutableListOf<Map<String, Any?>>()
    private val availableConfigs = mutableListOf<Map<String, Any?>>()
    private val floatingRecordActions = mutableListOf<Map<String, Any?>>()
    private var floatingRecordName = ""
    private val pickerData: MutableMap<String, Float> = mutableMapOf()
    private var pickerMode: String? = null
    private var nativePickerResult: ((Map<String, Any?>) -> Unit)? = null
    private var runStartedAt = 0L
    private var runTotalMillis = 0L
    private var currentActionIndex = -1
    private var resumeActionIndex = 0
    private var currentWaitUntilMillis = 0L
    private var pausedWaitRemainingMillis = 0L
    private var loopStartIndex = 0
    private var runSessionId = 0L
    private var playbackTicker: Runnable? = null
    private var activeRecordingSurface: RecordingSurface? = null
    private var activeRecordingAutoStopOnHome = false
    private var unlockMotionRecorder: MotionEventRecorder? = null
    private var unlockMotionCaptureOverlay: View? = null
    private var unlockMotionCaptureVisible = false
    private var unlockMotionControl: View? = null
    private var unlockMotionControlParams: WindowManager.LayoutParams? = null
    private var unlockMotionControlVisible = false
    private var unlockMotionStatusView: TextView? = null
    private var unlockMotionStartedAt = 0L
    private var unlockMotionTicker: Runnable? = null
    private var unlockMotionTrailOverlay: View? = null
    private var unlockMotionTrailVisible = false
    private var gesturePreviewOverlay: View? = null
    private val unlockMotionTrailSegments = mutableListOf<RecordedSegment>()
    private var unlockRecordWaitingForRecord = false
    private var unlockRecordFinalizing = false

    private val handler = Handler(Looper.getMainLooper())
    private val random = Random()
    private val alarmChannelName = "scriptapp/alarm"

    companion object {
        var instance: AutoSwipeService? = null
        var onPickerResult: ((Map<String, Any?>) -> Unit)? = null

        fun updateConfig(
            min: Int,
            max: Int,
            actions: List<Map<String, Any?>>,
            name: String? = null,
            loopCount: Int = 1,
            loopIntervalMillis: Int = 0,
            setupActions: List<Map<String, Any?>> = emptyList(),
            infiniteLoop: Boolean = false,
        ) {
            instance?.apply {
                handler.removeCallbacksAndMessages(null)
                isRunning = false
                minSeconds = min
                maxSeconds = max
                this.loopCount = loopCount.coerceIn(1, 9999)
                this.infiniteLoop = infiniteLoop
                this.loopIntervalMillis = loopIntervalMillis.coerceIn(0, 10_000_000).toLong()
                remainingLoops = if (this.infiniteLoop) Int.MAX_VALUE else this.loopCount
                scriptName = name
                this.setupActions.clear()
                this.setupActions.addAll(setupActions.map(::normalizeMap))
                gestureActions.clear()
                gestureActions.addAll(actions.map(::normalizeMap))
                updateStatusText()

                if (min == 0 && max == 0 && (gestureActions.isNotEmpty() || this.setupActions.isNotEmpty())) {
                    startScriptRun()
                }
            }
        }

        fun showAutomationMenu(configs: List<Map<String, Any?>>): Boolean {
            val service = instance ?: return false
            return service.showAutomationMenuInternal(configs)
        }

        fun syncAutomationConfigs(configs: List<Map<String, Any?>>): Boolean {
            val service = instance ?: return false
            service.setAvailableConfigs(configs)
            if (service.chooserOverlay != null) {
                service.showConfigChooser()
            }
            return true
        }

        fun enterPickerMode(type: String): Boolean {
            val service = instance ?: return false
            service.showPickerOverlay(type)
            return true
        }

        fun recognizeScreenText(
            region: Map<String, Any?>?,
            callback: (List<Map<String, Any?>>) -> Unit,
        ): Boolean {
            val service = instance ?: return false
            service.handler.post {
                service.recognizeScreenTextForMotto(
                    region = region,
                    onSuccess = { nodes ->
                        val (screenWidth, screenHeight) = service.screenSize()
                        callback(nodes.map { it.toTextResult(screenWidth, screenHeight) })
                    },
                    onFailure = { callback(emptyList()) },
                )
            }
            return true
        }

        fun openAppAndRunConfig(
            context: Context,
            packageName: String,
            packageLabel: String,
            preConfigName: String?,
            preActions: List<Map<String, Any?>>,
            preLoopCount: Int = 1,
            preLoopIntervalMillis: Int = 0,
            configName: String?,
            beforeLoopActions: List<Map<String, Any?>> = emptyList(),
            actions: List<Map<String, Any?>>,
            loopCount: Int = 1,
            loopIntervalMillis: Int = 0,
            infiniteLoop: Boolean = false,
            delaySeconds: Int = 5,
        ): Boolean {
            val service = instance
            val unlockActions = if (isDeviceLocked(context)) {
                loadUnlockActions(context)
            } else {
                emptyList()
            }
            if (service != null && unlockActions.isNotEmpty()) {
                val combinedActions = mutableListOf<Map<String, Any?>>()
                combinedActions.addAll(unlockActions)
                combinedActions.add(fixedWaitMap(800))
                if (preActions.isNotEmpty()) {
                    combinedActions.addAll(expandLoopedActions(preActions, preLoopCount, preLoopIntervalMillis))
                    combinedActions.add(fixedWaitMap(500))
                }
                combinedActions.add(
                    mapOf(
                        "type" to "launchApp",
                        "packageName" to packageName,
                        "label" to packageLabel,
                    ),
                )
                combinedActions.add(fixedWaitMap(delaySeconds.coerceAtLeast(0) * 1000))
                combinedActions.addAll(beforeLoopActions.map(::normalizeMap))
                service.handler.post {
                    service.stopScriptRun()
                    updateConfig(
                        0,
                        0,
                        actions,
                        buildRunName(preConfigName, configName, packageLabel, true),
                        loopCount,
                        loopIntervalMillis,
                        combinedActions,
                        infiniteLoop,
                    )
                }
                return true
            }

            if (service != null && preActions.isNotEmpty()) {
                val combinedActions = mutableListOf<Map<String, Any?>>()
                combinedActions.addAll(expandLoopedActions(preActions, preLoopCount, preLoopIntervalMillis))
                combinedActions.add(fixedWaitMap(500))
                combinedActions.add(
                    mapOf(
                        "type" to "launchApp",
                        "packageName" to packageName,
                        "label" to packageLabel,
                    ),
                )
                combinedActions.add(fixedWaitMap(delaySeconds.coerceAtLeast(0) * 1000))
                combinedActions.addAll(beforeLoopActions.map(::normalizeMap))
                service.handler.post {
                    service.stopScriptRun()
                    updateConfig(
                        0,
                        0,
                        actions,
                        buildRunName(preConfigName, configName, packageLabel, false),
                        loopCount,
                        loopIntervalMillis,
                        combinedActions,
                        infiniteLoop,
                    )
                }
                return true
            }

            val launchIntent = context.packageManager.getLaunchIntentForPackage(packageName)
                ?: return false
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(launchIntent)

            service ?: return true
            service.handler.postDelayed({
                service.showFloatingWindow(expanded = false, attachToRightEdge = true)
                if (actions.isNotEmpty() || beforeLoopActions.isNotEmpty()) {
                    updateConfig(
                        0,
                        0,
                        actions,
                        configName ?: packageLabel,
                        loopCount,
                        loopIntervalMillis,
                        beforeLoopActions,
                        infiniteLoop,
                    )
                }
            }, delaySeconds.coerceAtLeast(0) * 1000L)
            return true
        }

        fun showAlarmReminderOverlay(intent: Intent): Boolean {
            val service = instance ?: return false
            service.handler.post {
                service.showAlarmReminderOverlayInternal(intent)
            }
            return true
        }

        fun verifyUnlockScript(context: Context): Boolean {
            val service = instance ?: return false
            val unlockActions = loadUnlockActions(context)
            if (unlockActions.isEmpty()) return false
            service.handler.post {
                service.hideFlutterOverlayWindow()
                if (isDeviceLocked(context)) {
                    updateConfig(0, 0, unlockActions, "验证锁屏解锁", 1, 0)
                } else {
                    service.performLockScreenAction(runToken = Long.MIN_VALUE) {
                        service.handler.postDelayed({
                            updateConfig(0, 0, unlockActions, "验证锁屏解锁", 1, 0)
                        }, 1500)
                    }
                }
            }
            return true
        }

        private fun isDeviceLocked(context: Context): Boolean {
            val keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                keyguard?.isDeviceLocked == true
            } else {
                keyguard?.isKeyguardLocked == true
            }
        }

        private fun loadUnlockActions(context: Context): List<Map<String, Any?>> {
            val raw = context
                .getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getString("flutter.unlock_gesture_config_v1", null)
                ?: return emptyList()
            return try {
                val obj = JSONObject(raw)
                val array = obj.optJSONArray("actions") ?: return emptyList()
                jsonArrayToList(array)
            } catch (_: Exception) {
                emptyList()
            }
        }

        private fun expandLoopedActions(
            actions: List<Map<String, Any?>>,
            loopCount: Int,
            loopIntervalMillis: Int,
        ): List<Map<String, Any?>> {
            val loops = loopCount.coerceIn(1, 9999)
            val interval = loopIntervalMillis.coerceIn(0, 10_000_000)
            val out = mutableListOf<Map<String, Any?>>()
            repeat(loops) { index ->
                out.addAll(actions.map(::normalizeMap))
                if (index < loops - 1 && interval > 0) {
                    out.add(fixedWaitMap(interval))
                }
            }
            return out
        }

        private fun fixedWaitMap(milliseconds: Int): Map<String, Any?> {
            val millis = milliseconds.coerceIn(1, 10_000_000)
            return mapOf(
                "type" to "wait",
                "waitMode" to "fixed",
                "waitMillis" to millis,
                "seconds" to ((millis + 999) / 1000).coerceIn(1, 10000),
            )
        }

        private fun buildRunName(
            preConfigName: String?,
            configName: String?,
            packageLabel: String,
            includesUnlock: Boolean,
        ): String {
            val pre = if (preConfigName.isNullOrBlank()) "" else "前置 ${preConfigName} -> "
            val main = configName ?: packageLabel
            return if (includesUnlock) {
                "解锁并执行 ${pre}${main}"
            } else {
                "${pre}${main}"
            }
        }

        fun parseActionsJson(raw: String?): List<Map<String, Any?>> {
            if (raw.isNullOrBlank()) return emptyList()
            return try {
                jsonArrayToList(JSONArray(raw))
            } catch (_: Exception) {
                emptyList()
            }
        }

        private fun normalizeMap(map: Map<*, *>): Map<String, Any?> {
            return map.entries.associate { entry -> entry.key.toString() to entry.value }
        }

        private fun jsonArrayToList(array: JSONArray): List<Map<String, Any?>> {
            val out = mutableListOf<Map<String, Any?>>()
            for (index in 0 until array.length()) {
                val obj = array.optJSONObject(index) ?: continue
                out.add(jsonObjectToMap(obj))
            }
            return out
        }

        private fun jsonObjectToMap(obj: JSONObject): Map<String, Any?> {
            val map = mutableMapOf<String, Any?>()
            val keys = obj.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                map[key] = when (val value = obj.get(key)) {
                    is JSONObject -> jsonObjectToMap(value)
                    is JSONArray -> {
                        val list = mutableListOf<Any?>()
                        for (index in 0 until value.length()) {
                            list.add(
                                when (val item = value.get(index)) {
                                    is JSONObject -> jsonObjectToMap(item)
                                    is JSONArray -> item.toString()
                                    JSONObject.NULL -> null
                                    else -> item
                                },
                            )
                        }
                        list
                    }
                    JSONObject.NULL -> null
                    else -> value
                }
            }
            return map
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        lastNightModeMask = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        handler.postDelayed({
            ensureFlutterAutomationOverlay()
            updateFlutterOverlayTheme()
        }, 800)
    }

    private fun showAutomationMenuInternal(configs: List<Map<String, Any?>>): Boolean {
        setAvailableConfigs(configs)
        return showFloatingWindow(expanded = true)
    }

    private fun setAvailableConfigs(configs: List<Map<String, Any?>>) {
        availableConfigs.clear()
        availableConfigs.addAll(configs.map(::normalizeMap))
        selectedConfigIndex = when {
            availableConfigs.isEmpty() -> -1
            selectedConfigIndex in availableConfigs.indices -> selectedConfigIndex
            else -> 0
        }
    }

    private fun overlayType(): Int {
        return if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP_MR1) {
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
    }

    private fun baseOverlayParams(): WindowManager.LayoutParams {
        return WindowManager.LayoutParams().apply {
            type = overlayType()
            format = PixelFormat.TRANSLUCENT
            flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
            width = WindowManager.LayoutParams.WRAP_CONTENT
            height = WindowManager.LayoutParams.WRAP_CONTENT
            gravity = Gravity.TOP or Gravity.START
            x = floatingLayoutParams?.x ?: 100
            y = floatingLayoutParams?.y ?: 120
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
    }

    private fun fullScreenOverlayParams(focusable: Boolean = false): WindowManager.LayoutParams {
        return baseOverlayParams().apply {
            width = WindowManager.LayoutParams.MATCH_PARENT
            height = WindowManager.LayoutParams.MATCH_PARENT
            gravity = Gravity.TOP or Gravity.START
            x = 0
            y = 0
            flags = if (focusable) {
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
            } else {
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
            }
        }
    }

    private fun isDarkModeActive(): Boolean {
        val nightMode = resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK
        return nightMode == android.content.res.Configuration.UI_MODE_NIGHT_YES
    }

    private fun showFloatingWindow(
        expanded: Boolean,
        attachToRightEdge: Boolean = false,
    ): Boolean {
        removeFloatingWindow()
        removeChooserOverlay()
        collapsed = !expanded

        val layoutParams = baseOverlayParams()
        if (!expanded) {
            collapsedEdgeRight = if (attachToRightEdge) {
                true
            } else {
                shouldCollapseToRight(layoutParams)
            }
        }
        val root = if (expanded) createExpandedMenu(layoutParams) else createCollapsedMenu(layoutParams)
        if (expanded) {
            clampOverlayPosition(root, layoutParams)
        } else {
            snapOverlayToHorizontalEdge(root, layoutParams, collapsedEdgeRight)
        }

        return try {
            windowManager?.addView(root, layoutParams)
            floatingView = root
            floatingLayoutParams = layoutParams
            updateStatusText()
            handler.post {
                val params = floatingLayoutParams ?: return@post
                val view = floatingView ?: return@post
                if (expanded) {
                    clampOverlayPosition(view, params)
                } else {
                    snapOverlayToHorizontalEdge(view, params, collapsedEdgeRight)
                }
                try {
                    windowManager?.updateViewLayout(view, params)
                } catch (_: Exception) {
                }
            }
            true
        } catch (_: Exception) {
            floatingView = null
            floatingLayoutParams = null
            false
        }
    }

    private fun createExpandedMenu(layoutParams: WindowManager.LayoutParams): View {
        val darkMode = isDarkModeActive()
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(5), dp(5), dp(5), dp(5))
            background = roundedBackground(
                if (darkMode) 0xE6151A1E.toInt() else 0xEEF7FAF8.toInt(),
                dp(20).toFloat(),
                if (darkMode) 0x55FFFFFF else 0x33212C2E,
            )
        }

        startMenuButton = null
        pauseMenuButton = null
        endMenuButton = null
        statusPrimaryView = null
        statusSecondaryView = null
        statusLoopView = null
        statusStepView = null
        statusTimeView = null
        statusWaitView = null

        if (isRunning || isPaused) {
            val pauseButton = iconButton(
                if (isPaused) R.drawable.ic_overlay_play else R.drawable.ic_overlay_pause,
                if (isPaused) "继续" else "暂停",
                0xFFFFC46B.toInt(),
            ) {
                if (isPaused) {
                    resumeScriptRun()
                } else {
                    pauseScriptRun()
                }
            }
            val endButton = iconButton(R.drawable.ic_overlay_stop, "结束", 0xFFFF8A80.toInt()) {
                stopScriptRun()
            }
            pauseMenuButton = pauseButton
            endMenuButton = endButton
            attachDrag(pauseButton, layoutParams)
            attachDrag(endButton, layoutParams)
            row.addView(pauseButton, LinearLayout.LayoutParams(dp(32), dp(32)).apply { marginEnd = dp(4) })
            row.addView(endButton, LinearLayout.LayoutParams(dp(32), dp(32)).apply { marginEnd = dp(4) })

            val statusGrid = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(8), 0, dp(8), 0)
            }

            val r1 = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
            val r2 = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; setPadding(0, dp(1), 0, 0) }

            fun createCell(isBold: Boolean = false): TextView {
                return TextView(this@AutoSwipeService).apply {
                    textSize = 10f
                    includeFontPadding = false
                    setTextColor(if (darkMode) Color.WHITE else 0xFF1F2A2C.toInt())
                    if (isBold) typeface = Typeface.DEFAULT_BOLD
                    gravity = Gravity.START or Gravity.CENTER_VERTICAL
                }
            }

            statusLoopView = createCell(true)
            statusTimeView = createCell()
            statusStepView = createCell(true)
            statusWaitView = createCell()

            r1.addView(statusLoopView, LinearLayout.LayoutParams(dp(72), -2))
            r1.addView(statusTimeView, LinearLayout.LayoutParams(dp(70), -2))
            r2.addView(statusStepView, LinearLayout.LayoutParams(dp(72), -2))
            r2.addView(statusWaitView, LinearLayout.LayoutParams(dp(70), -2))

            statusGrid.addView(r1)
            statusGrid.addView(r2)
            row.addView(statusGrid)

            attachDrag(statusGrid, layoutParams)
            attachDrag(row, layoutParams)
            return row
        }

        val configButton = iconButton(R.drawable.ic_overlay_settings, "配置", 0xFF7ED8C3.toInt()) {
            showFlutterAutomationOverlay("configs")
        }
        val startButton = iconButton(R.drawable.ic_overlay_play, "启动", 0xFF8EB8FF.toInt()) {
            if (isRunning) {
                stopScriptRun()
            } else {
                showFlutterAutomationOverlay("run")
            }
        }
        startMenuButton = startButton
        val recordButton = iconButton(R.drawable.ic_overlay_record, "录制", 0xFFFFB989.toInt()) {
            showFlutterAutomationOverlay("create")
        }
        val closeButton = iconButton(R.drawable.ic_overlay_close, "关闭", 0xFFFF8A80.toInt()) {
            closeAutomationMenu()
        }
        val foldButton = iconButton(R.drawable.ic_overlay_fold, "折叠", 0xFFE8A8FF.toInt()) {
            showFloatingWindow(expanded = false)
        }

        listOf(configButton, startButton, recordButton, closeButton, foldButton).forEach { button ->
            attachDrag(button, layoutParams)
            row.addView(
                button,
                LinearLayout.LayoutParams(dp(32), dp(32)).apply {
                    marginEnd = dp(4)
                },
            )
        }
        attachDrag(row, layoutParams)
        return row
    }

    private fun createCollapsedMenu(layoutParams: WindowManager.LayoutParams): View {
        val darkMode = isDarkModeActive()
        val bubble = ImageView(this).apply {
            setImageResource(if (collapsedEdgeRight) R.drawable.ic_overlay_chevron_left else R.drawable.ic_overlay_chevron_right)
            imageTintList = android.content.res.ColorStateList.valueOf(if (darkMode) Color.WHITE else 0xFF1F2A2C.toInt())
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            // 缩小比例后，Padding 也要相应减小
            setPadding(dp(3), dp(6), dp(3), dp(6))
            contentDescription = "展开"
            background = sideRoundedBackground(
                if (darkMode) 0xE6151A1E.toInt() else 0xEEF7FAF8.toInt(),
                dp(10).toFloat(),
                if (darkMode) 0x66FFFFFF else 0x33212C2E,
                isRightSide = collapsedEdgeRight
            )
            setOnClickListener { showFloatingWindow(expanded = true) }
        }
        collapsedMenuButton = bubble
        
        attachDrag(bubble, layoutParams, snapToEdgeOnRelease = true)
        return FrameLayout(this).apply {
            addView(bubble, FrameLayout.LayoutParams(dp(22), dp(45)))
        }
    }

    private fun iconButton(
        iconRes: Int,
        description: String,
        color: Int,
        onClick: () -> Unit,
    ): ImageView {
        return ImageView(this).apply {
            setImageResource(iconRes)
            imageTintList = android.content.res.ColorStateList.valueOf(color)
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            contentDescription = description
            background = null
            minimumWidth = dp(32)
            minimumHeight = dp(32)
            // 如果是设置图标，多给一点 padding 缩小视觉尺寸
            val extraPadding = if (iconRes == R.drawable.ic_overlay_settings) dp(2) else 0
            val p = dp(4) + extraPadding
            setPadding(p, p, p, p)
            adjustViewBounds = false
            setOnClickListener { onClick() }
        }
    }

    private fun menuButton(label: String, color: Int, onClick: () -> Unit): TextView {
        return TextView(this).apply {
            text = label
            textSize = 12f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            background = roundedBackground(color and 0xCCFFFFFF.toInt(), dp(18).toFloat(), 0x33FFFFFF)
            setOnClickListener { onClick() }
        }
    }

    private fun attachDrag(
        view: View,
        layoutParams: WindowManager.LayoutParams,
        snapToEdgeOnRelease: Boolean = false,
    ) {
        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f
        var moving = false

        view.setOnTouchListener { touchedView, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = layoutParams.x
                    initialY = layoutParams.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    moving = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - initialTouchX
                    val dy = event.rawY - initialTouchY
                    if (abs(dx) > 10 || abs(dy) > 10) {
                        moving = true
                        layoutParams.x = initialX + dx.toInt()
                        layoutParams.y = initialY + dy.toInt()
                        val root = floatingView ?: view
                        clampOverlayPosition(root, layoutParams)
                        floatingView?.let { windowManager?.updateViewLayout(it, layoutParams) }
                        repositionChooser()
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (moving) {
                        if (snapToEdgeOnRelease) {
                            val root = floatingView ?: view
                            snapOverlayToNearestHorizontalEdge(root, layoutParams)
                            floatingView?.let { windowManager?.updateViewLayout(it, layoutParams) }
                        }
                        true
                    } else {
                        touchedView.performClick()
                        false
                    }
                }
                else -> false
            }
        }
    }

    private fun clampOverlayPosition(
        view: View?,
        layoutParams: WindowManager.LayoutParams,
    ) {
        val (screenWidth, screenHeight) = screenSize()
        val fallbackWidth = if (collapsed) dp(30) else dp(220)
        val fallbackHeight = if (collapsed) dp(45) else dp(48)
        val viewWidth = view?.width ?: 0
        val viewHeight = view?.height ?: 0
        val width = when {
            viewWidth > 0 -> viewWidth
            layoutParams.width > 0 -> layoutParams.width
            else -> fallbackWidth
        }
        val height = when {
            viewHeight > 0 -> viewHeight
            layoutParams.height > 0 -> layoutParams.height
            else -> fallbackHeight
        }
        val maxX = (screenWidth - width).coerceAtLeast(0)
        val maxY = (screenHeight - height).coerceAtLeast(0)
        layoutParams.x = layoutParams.x.coerceIn(0, maxX)
        layoutParams.y = layoutParams.y.coerceIn(0, maxY)
    }

    private fun snapOverlayToNearestHorizontalEdge(
        view: View?,
        layoutParams: WindowManager.LayoutParams,
    ) {
        val (screenWidth, _) = screenSize()
        val width = overlayWidth(view, layoutParams, if (collapsed) dp(30) else dp(220))
        collapsedEdgeRight = layoutParams.x + width / 2 >= screenWidth / 2
        snapOverlayToHorizontalEdge(view, layoutParams, collapsedEdgeRight)
    }

    private fun snapOverlayToHorizontalEdge(
        view: View?,
        layoutParams: WindowManager.LayoutParams,
        right: Boolean,
    ) {
        collapsedEdgeRight = right
        val (screenWidth, screenHeight) = screenSize()
        val width = overlayWidth(view, layoutParams, if (collapsed) dp(30) else dp(220))
        val height = overlayHeight(view, layoutParams, if (collapsed) dp(45) else dp(48))
        val maxX = (screenWidth - width).coerceAtLeast(0)
        val maxY = (screenHeight - height).coerceAtLeast(0)
        layoutParams.x = if (right) maxX else 0
        layoutParams.y = layoutParams.y.coerceIn(0, maxY)
        updateCollapsedArrow()
    }

    private fun shouldCollapseToRight(layoutParams: WindowManager.LayoutParams): Boolean {
        val (screenWidth, _) = screenSize()
        val estimatedWidth = dp(220)
        return layoutParams.x + estimatedWidth / 2 >= screenWidth / 2
    }

    private fun screenSize(): Pair<Int, Int> {
        val wm = windowManager ?: return resources.displayMetrics.widthPixels to resources.displayMetrics.heightPixels
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealMetrics(metrics)
        if (metrics.widthPixels > 0 && metrics.heightPixels > 0) {
            return metrics.widthPixels to metrics.heightPixels
        }
        val fallback = resources.displayMetrics
        return fallback.widthPixels to fallback.heightPixels
    }

    private fun overlayWidth(
        view: View?,
        layoutParams: WindowManager.LayoutParams,
        fallback: Int,
    ): Int {
        return when {
            (view?.width ?: 0) > 0 -> view?.width ?: fallback
            layoutParams.width > 0 -> layoutParams.width
            else -> fallback
        }
    }

    private fun overlayHeight(
        view: View?,
        layoutParams: WindowManager.LayoutParams,
        fallback: Int,
    ): Int {
        return when {
            (view?.height ?: 0) > 0 -> view?.height ?: fallback
            layoutParams.height > 0 -> layoutParams.height
            else -> fallback
        }
    }

    private fun updateCollapsedArrow() {
        val darkMode = isDarkModeActive()
        val view = collapsedMenuButton ?: return
        if (view is ImageView) {
            view.setImageResource(if (collapsedEdgeRight) R.drawable.ic_overlay_chevron_left else R.drawable.ic_overlay_chevron_right)
        }
        view.background = sideRoundedBackground(
            if (darkMode) 0xE6151A1E.toInt() else 0xEEF7FAF8.toInt(),
            dp(12).toFloat(),
            if (darkMode) 0x66FFFFFF else 0x33212C2E,
            isRightSide = collapsedEdgeRight
        )
    }

    private fun floatingPanelParams(
        widthDp: Int,
        height: Int = WindowManager.LayoutParams.WRAP_CONTENT,
        focusable: Boolean = false,
    ): WindowManager.LayoutParams {
        return baseOverlayParams().apply {
            width = dp(widthDp)
            this.height = height
            flags = if (focusable) {
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
            } else {
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
            }
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
            x = 0
            y = 0
        }
    }

    private fun addChooserPanel(view: View, layoutParams: WindowManager.LayoutParams) {
        try {
            val modalParams = WindowManager.LayoutParams().apply {
                type = overlayType()
                format = PixelFormat.TRANSLUCENT
                flags = layoutParams.flags
                width = WindowManager.LayoutParams.MATCH_PARENT
                height = WindowManager.LayoutParams.MATCH_PARENT
                gravity = Gravity.TOP or Gravity.START
                x = 0
                y = 0
                softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
            }
            val dm = resources.displayMetrics
            val availableWidth = (dm.widthPixels - dp(24)).coerceAtLeast(dp(240))
            val panelWidth = availableWidth.coerceAtMost(dp(520))
            val panelMaxHeight = (dm.heightPixels - dp(80)).coerceAtLeast(dp(260))
            val requestedHeight = when {
                layoutParams.height > 0 -> layoutParams.height.coerceAtMost(panelMaxHeight)
                else -> WindowManager.LayoutParams.WRAP_CONTENT
            }
            val modalRoot = FrameLayout(this).apply {
                setBackgroundColor(0x33000000)
                isClickable = true
                isFocusable = true
            }
            if (requestedHeight == WindowManager.LayoutParams.WRAP_CONTENT) {
                val scrollView = object : ScrollView(this) {
                    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
                        val maxHeightSpec = View.MeasureSpec.makeMeasureSpec(
                            panelMaxHeight,
                            View.MeasureSpec.AT_MOST,
                        )
                        super.onMeasure(widthMeasureSpec, maxHeightSpec)
                    }
                }.apply {
                    isFillViewport = false
                    addView(
                        view,
                        FrameLayout.LayoutParams(
                            FrameLayout.LayoutParams.MATCH_PARENT,
                            FrameLayout.LayoutParams.WRAP_CONTENT,
                        ),
                    )
                }
                modalRoot.addView(
                    scrollView,
                    FrameLayout.LayoutParams(
                        panelWidth,
                        FrameLayout.LayoutParams.WRAP_CONTENT,
                    ).apply {
                        gravity = Gravity.CENTER
                    },
                )
            } else {
                modalRoot.addView(
                    view,
                    FrameLayout.LayoutParams(panelWidth, requestedHeight).apply {
                        gravity = Gravity.CENTER
                    },
                )
            }
            windowManager?.addView(modalRoot, modalParams)
            chooserOverlay = modalRoot
        } catch (_: Exception) {
            chooserOverlay = null
        }
    }

    private fun showFlutterAutomationOverlay(mode: String) {
        removeChooserOverlay()
        ensureFlutterAutomationOverlay()
        updateFlutterOverlayMode(mode)
        handler.postDelayed({
            updateFlutterOverlayMode(mode)
            showFlutterOverlayWindow()
        }, 80)
    }

    private fun ensureFlutterAutomationOverlay() {
        if (flutterOverlayEngine != null && flutterOverlayRoot != null) {
            return
        }

        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)

        val engine = FlutterEngine(this)
        GeneratedPluginRegistrant.registerWith(engine)
        engine.serviceControlSurface.attachToService(this, null, false)
        engine.navigationChannel.setInitialRoute("/")
        installFlutterOverlayChannel(engine)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "overlayMain"),
        )

        val flutterView = FlutterView(this, RenderMode.texture).apply {
            isFocusable = true
            isFocusableInTouchMode = true
            addOnFirstFrameRenderedListener(
                object : FlutterUiDisplayListener {
                    override fun onFlutterUiDisplayed() {
                        flutterOverlayRoot?.setBackgroundColor(Color.TRANSPARENT)
                        removeOnFirstFrameRenderedListener(this)
                    }

                    override fun onFlutterUiNoLongerDisplayed() {}
                },
            )
            attachToFlutterEngine(engine)
        }
        flutterOverlayEngine = engine
        flutterOverlayView = flutterView
        flutterOverlayRoot = FrameLayout(this).apply {
            setBackgroundColor(Color.TRANSPARENT)
            isClickable = true
            isFocusable = true
            isFocusableInTouchMode = true
            addView(
                flutterView,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )
        }
        flutterOverlayParams = WindowManager.LayoutParams().apply {
            type = overlayType()
            format = PixelFormat.TRANSLUCENT
            flags = WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
            width = WindowManager.LayoutParams.MATCH_PARENT
            height = WindowManager.LayoutParams.MATCH_PARENT
            gravity = Gravity.TOP or Gravity.START
            x = 0
            y = 0
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
        }
    }

    private fun updateFlutterOverlayMode(mode: String) {
        flutterOverlayChannel?.invokeMethod("setOverlayMode", mapOf("mode" to mode))
        updateFlutterOverlayTheme()
    }

    private fun updateFlutterOverlayTheme() {
        flutterOverlayChannel?.invokeMethod("setOverlayTheme", mapOf("dark" to isDarkModeActive()))
    }

    private fun installFlutterOverlayChannel(engine: FlutterEngine) {
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, alarmChannelName)
        flutterOverlayChannel = channel
        channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "enterPickerMode" -> {
                        val type = call.argument<String>("type") ?: "click"
                        hideFlutterOverlayWindow()
                        handler.postDelayed({
                            startNativePicker(type) { resultData ->
                                showFlutterOverlayWindow()
                                result.success(resultData)
                            }
                        }, 260)
                    }
                    "syncAutomationConfigs" -> {
                        val configs = call.argument<List<Map<String, Any?>>>("configs") ?: emptyList()
                        setAvailableConfigs(configs)
                        result.success(true)
                    }
                    "performAutoSwipe" -> {
                        val min = call.argument<Int>("min") ?: 0
                        val max = call.argument<Int>("max") ?: 0
                        val name = call.argument<String>("name")
                        val beforeLoopActions = call.argument<List<Map<String, Any?>>>("beforeLoopActions") ?: emptyList()
                        val actions = call.argument<List<Map<String, Any?>>>("actions") ?: emptyList()
                        val loopCount = call.argument<Int>("loopCount") ?: 1
                        val loopIntervalMillis = call.argument<Int>("loopIntervalMillis") ?: 0
                        val infiniteLoop = call.argument<Boolean>("infiniteLoop") ?: false
                        result.success(null)
                        handler.post {
                            hideFlutterOverlayWindow()
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
                        }
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
                        result.success(
                            if (packageName.isNullOrBlank()) {
                                false
                            } else {
                                handler.post { hideFlutterOverlayWindow() }
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
                                    delaySeconds,
                                )
                            },
                        )
                    }
                    "verifyUnlockScript" -> {
                        result.success(AutoSwipeService.verifyUnlockScript(this))
                    }
                    "closeAutomationOverlay" -> {
                        result.success(null)
                        handler.post { hideFlutterOverlayWindow() }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun showFlutterOverlayWindow() {
        val root = flutterOverlayRoot ?: return
        val params = flutterOverlayParams ?: return
        if (flutterOverlayAttached) return
        try {
            windowManager?.addView(root, params)
            flutterOverlayAttached = true
            flutterOverlayEngine?.lifecycleChannel?.appIsResumed()
            root.requestFocus()
            flutterOverlayView?.requestFocus()
        } catch (_: Exception) {
            flutterOverlayAttached = false
        }
    }

    private fun hideFlutterOverlayWindow() {
        val root = flutterOverlayRoot ?: return
        if (!flutterOverlayAttached) return
        
        // 先通知引擎暂停，停止渲染尝试，减少 EGL 错误
        flutterOverlayEngine?.lifecycleChannel?.appIsPaused()
        
        try {
            windowManager?.removeView(root)
        } catch (_: Exception) {
        }
        flutterOverlayAttached = false
    }

    private fun destroyFlutterAutomationOverlay() {
        hideFlutterOverlayWindow()
        flutterOverlayRoot?.removeAllViews()
        try {
            flutterOverlayView?.detachFromFlutterEngine()
        } catch (_: Exception) {
        }
        try {
            flutterOverlayEngine?.serviceControlSurface?.detachFromService()
            flutterOverlayEngine?.lifecycleChannel?.appIsDetached()
            flutterOverlayEngine?.destroy()
        } catch (_: Exception) {
        }
        flutterOverlayRoot = null
        flutterOverlayParams = null
        flutterOverlayEngine = null
        flutterOverlayView = null
        flutterOverlayChannel = null
    }

    private fun showConfigChooser() {
        showFlutterAutomationOverlay("run")
    }

    private fun showFloatingRecorder() {
        removeChooserOverlay()
        ensureFloatingRecordName()

        val panelHeight = (resources.displayMetrics.heightPixels - dp(120)).coerceIn(dp(360), dp(580))
        val layoutParams = floatingPanelParams(widthDp = 340, height = panelHeight, focusable = true)
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(12), dp(14), dp(12))
            background = roundedBackground(0xF21F252B.toInt(), dp(18).toFloat(), 0x44FFFFFF)
        }

        panel.addView(panelTitle("悬浮自动化配置"))

        val nameInput = inputField(
            value = floatingRecordName,
            hint = "配置名称",
            numberOnly = false,
        )
        panel.addView(
            nameInput,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(42),
            ).apply {
                bottomMargin = dp(8)
            },
        )

        panel.addView(TextView(this).apply {
            text = "${floatingRecordActions.size} 个动作 · 预计 ${estimateActionsDurationLabel(floatingRecordActions)}"
            textSize = 12f
            setTextColor(0xFFB8C0C8.toInt())
            setPadding(0, 0, 0, dp(8))
        })

        val list = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        if (floatingRecordActions.isEmpty()) {
            list.addView(TextView(this).apply {
                text = "点击“添加内容”添加第一个动作"
                textSize = 13f
                gravity = Gravity.CENTER
                setTextColor(0xFFB8C0C8.toInt())
                setPadding(dp(8), dp(34), dp(8), dp(34))
                background = roundedBackground(0x22111111, dp(12).toFloat(), 0x22FFFFFF)
            })
        } else {
            floatingRecordActions.forEachIndexed { index, action ->
                list.addView(floatingActionRow(index, action, nameInput))
            }
        }

        panel.addView(
            ScrollView(this).apply {
                addView(list)
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ),
        )

        panel.addView(
            menuButton("添加内容", 0xFF7ED8C3.toInt()) {
                rememberFloatingRecordName(nameInput)
                showFloatingAddMenu()
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(44),
            ).apply {
                topMargin = dp(10)
            },
        )

        val bottomRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(8), 0, 0)
        }
        bottomRow.addView(
            menuButton("取消", 0xFFFF8A80.toInt()) {
                floatingRecordActions.clear()
                floatingRecordName = ""
                removeChooserOverlay()
            },
            LinearLayout.LayoutParams(0, dp(42), 1f).apply {
                marginEnd = dp(8)
            },
        )
        bottomRow.addView(
            menuButton("保存配置", 0xFF4CAF50.toInt()) {
                rememberFloatingRecordName(nameInput)
                if (floatingRecordActions.isNotEmpty()) {
                    saveFloatingRecordedConfig(floatingRecordName)
                    floatingRecordActions.clear()
                    floatingRecordName = ""
                    removeChooserOverlay()
                    showFloatingWindow(expanded = true)
                }
            },
            LinearLayout.LayoutParams(0, dp(42), 1f),
        )
        panel.addView(bottomRow)

        addChooserPanel(panel, layoutParams)
    }

    private fun floatingActionRow(index: Int, action: Map<String, Any?>, nameInput: EditText): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(10), dp(8), dp(8), dp(8))
            background = roundedBackground(0x22111111, dp(12).toFloat(), 0x22FFFFFF)
        }

        val copy = normalizeMap(action)
        val textColumn = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        textColumn.addView(TextView(this).apply {
            text = "${index + 1}. ${nativeActionTitle(copy)}"
            textSize = 13f
            setTextColor(Color.WHITE)
        })
        textColumn.addView(TextView(this).apply {
            text = nativeActionSubtitle(copy)
            textSize = 11f
            setTextColor(0xFFB8C0C8.toInt())
            setPadding(0, dp(2), 0, 0)
        })
        row.addView(
            textColumn,
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f),
        )

        val controls = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
        }
        if (isFloatingActionEditable(copy)) {
            controls.addView(
                compactButton("改", 0xFF8EB8FF.toInt()) {
                    rememberFloatingRecordName(nameInput)
                    editFloatingAction(index)
                },
                LinearLayout.LayoutParams(dp(34), dp(34)).apply {
                    marginStart = dp(4)
                },
            )
        }
        controls.addView(
            compactButton("上", 0xFF607D8B.toInt()) {
                rememberFloatingRecordName(nameInput)
                moveFloatingAction(index, -1)
            },
            LinearLayout.LayoutParams(dp(34), dp(34)).apply {
                marginStart = dp(4)
            },
        )
        controls.addView(
            compactButton("下", 0xFF607D8B.toInt()) {
                rememberFloatingRecordName(nameInput)
                moveFloatingAction(index, 1)
            },
            LinearLayout.LayoutParams(dp(34), dp(34)).apply {
                marginStart = dp(4)
            },
        )
        controls.addView(
            compactButton("删", 0xFFFF8A80.toInt()) {
                rememberFloatingRecordName(nameInput)
                removeFloatingAction(index)
            },
            LinearLayout.LayoutParams(dp(34), dp(34)).apply {
                marginStart = dp(4)
            },
        )
        row.addView(controls)

        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(row)
            setPadding(0, 0, 0, dp(8))
        }
    }

    private fun showFloatingAddMenu() {
        removeChooserOverlay()
        val layoutParams = floatingPanelParams(widthDp = 320)
        val panel = floatingPanel("添加内容")
        panel.addView(sectionLabel("手势"))
        panel.addView(optionRow("录制手势", "添加点击、滑动、完整轨迹", 0xFF4A90E2.toInt()) {
            showFloatingGestureTypeMenu()
        })
        panel.addView(sectionLabel("逻辑"))
        panel.addView(optionRow("按钮识别", "识别屏幕按钮，找不到可重试", 0xFF5C6BC0.toInt()) {
            startFloatingButtonDetect()
        })
        panel.addView(optionRow("图片识别", "圈住图片区域，后续用图片匹配", 0xFF26A69A.toInt()) {
            startFloatingImageButtonDetect()
        })
        panel.addView(sectionLabel("等待"))
        panel.addView(optionRow("随机等待", "在秒数范围内随机等待", 0xFFFFB74D.toInt()) {
            showFloatingWaitEditor(randomWait = true)
        })
        panel.addView(optionRow("毫秒等待", "用于动作前后缓冲，避免冲突", 0xFFFF9800.toInt()) {
            showFloatingWaitEditor(randomWait = false, milliseconds = true)
        })
        panel.addView(optionRow("固定等待", "固定等待指定秒数，最多 10000 秒", 0xFF8D6E63.toInt()) {
            showFloatingWaitEditor(randomWait = false)
        })
        panel.addView(sectionLabel("系统"))
        panel.addView(optionRow("导航动作", "返回键、回到桌面、多任务", 0xFF4CAF50.toInt()) {
            showFloatingNavMenu()
        })
        panel.addView(optionRow("锁屏", "执行到这里时锁定屏幕", 0xFFFF5252.toInt()) {
            floatingRecordActions.add(mapOf("type" to "lockScreen"))
            showFloatingRecorder()
        })
        panel.addView(optionRow("启动应用", "选择任意已安装应用", 0xFFAB47BC.toInt()) {
            showFloatingAppPicker()
        })
        panel.addView(
            menuButton("返回", 0xFF607D8B.toInt()) {
                showFloatingRecorder()
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(42),
            ).apply {
                topMargin = dp(8)
            },
        )
        addChooserPanel(panel, layoutParams)
    }

    private fun showFloatingGestureTypeMenu() {
        removeChooserOverlay()
        val layoutParams = floatingPanelParams(widthDp = 330)
        val panel = floatingPanel("录制手势")
        panel.addView(optionRow("录制完整手势轨迹", "点击开始录制，完成后点保存", 0xFFFF7043.toInt()) {
            startFloatingGesturePicker("record")
        })
        panel.addView(optionRow("录制点击步骤", "每次点击生成编号圆点，保存后变成步骤", 0xFF4A90E2.toInt()) {
            startFloatingGesturePicker("clickSteps")
        })
        panel.addView(optionRow("手动标点：单次点击", "拖动点击点到目标位置", 0xFF8EB8FF.toInt()) {
            startFloatingGesturePicker("click")
        })
        panel.addView(optionRow("手动标点：直线滑动", "拖动起点和终点", 0xFF7ED8C3.toInt()) {
            startFloatingGesturePicker("swipe")
        })
        panel.addView(
            menuButton("返回", 0xFF607D8B.toInt()) {
                showFloatingAddMenu()
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(42),
            ).apply {
                topMargin = dp(8)
            },
        )
        addChooserPanel(panel, layoutParams)
    }

    private fun showFloatingNavMenu() {
        removeChooserOverlay()
        val layoutParams = floatingPanelParams(widthDp = 300)
        val panel = floatingPanel("导航动作")
        panel.addView(optionRow("返回键", "模拟系统返回", 0xFF4CAF50.toInt()) {
            floatingRecordActions.add(mapOf("type" to "nav", "navType" to "back"))
            showFloatingRecorder()
        })
        panel.addView(optionRow("回到桌面", "模拟系统 Home", 0xFF4CAF50.toInt()) {
            floatingRecordActions.add(mapOf("type" to "nav", "navType" to "home"))
            showFloatingRecorder()
        })
        panel.addView(optionRow("多任务界面", "模拟系统最近任务", 0xFF4CAF50.toInt()) {
            floatingRecordActions.add(mapOf("type" to "nav", "navType" to "recents"))
            showFloatingRecorder()
        })
        panel.addView(
            menuButton("返回", 0xFF607D8B.toInt()) {
                showFloatingAddMenu()
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(42),
            ).apply {
                topMargin = dp(8)
            },
        )
        addChooserPanel(panel, layoutParams)
    }

    private fun showFloatingWaitEditor(
        randomWait: Boolean,
        milliseconds: Boolean = false,
        editIndex: Int? = null,
    ) {
        removeChooserOverlay()
        val layoutParams = floatingPanelParams(widthDp = 320, focusable = true)
        val panel = floatingPanel(if (randomWait) "随机等待" else if (milliseconds) "毫秒等待" else "固定等待")
        val editing = editIndex != null
        val current = editIndex?.let { floatingRecordActions.getOrNull(it) }
        val cancelAction = {
            if (editing) {
                showFloatingRecorder()
            } else {
                showFloatingAddMenu()
            }
        }

        if (randomWait) {
            val minInput = inputField(
                ((current?.get("minSeconds") as? Number)?.toInt() ?: 30).toString(),
                "最小秒数",
                numberOnly = true,
            )
            val maxInput = inputField(
                ((current?.get("maxSeconds") as? Number)?.toInt() ?: 120).toString(),
                "最大秒数",
                numberOnly = true,
            )
            panel.addView(fieldLabel("最小秒数"))
            panel.addView(minInput, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(42),
            ))
            panel.addView(fieldLabel("最大秒数"), LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = dp(8)
            })
            panel.addView(maxInput, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(42),
            ))
            panel.addView(actionButtonRow(
                onCancel = cancelAction,
                onConfirm = {
                    val rawMin = (minInput.text?.toString()?.trim()?.toIntOrNull() ?: 30).coerceIn(1, 10000)
                    val rawMax = (maxInput.text?.toString()?.trim()?.toIntOrNull() ?: 120).coerceIn(1, 10000)
                    val min = kotlin.math.min(rawMin, rawMax)
                    val max = kotlin.math.max(rawMin, rawMax)
                    upsertFloatingWaitAction(
                        editIndex,
                        mapOf(
                            "type" to "wait",
                            "waitMode" to "random",
                            "seconds" to min,
                            "minSeconds" to min,
                            "maxSeconds" to max,
                            "minMillis" to min * 1000,
                            "maxMillis" to max * 1000,
                            "waitMillis" to min * 1000,
                        ),
                    )
                    showFloatingRecorder()
                },
                confirmLabel = if (editing) "保存" else "添加",
            ))
        } else if (milliseconds) {
            val fallbackMillis = 1000
            val defaultMillis = ((current?.get("waitMillis") as? Number)?.toInt()
                ?: ((current?.get("seconds") as? Number)?.toInt()?.times(1000))
                ?: fallbackMillis).coerceIn(1, 10_000_000)
            val millisInput = inputField(defaultMillis.toString(), "等待毫秒", numberOnly = true)
            panel.addView(fieldLabel("等待毫秒，比如 300 或 800"))
            panel.addView(millisInput, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(42),
            ))
            panel.addView(actionButtonRow(
                onCancel = cancelAction,
                onConfirm = {
                    val millis = (millisInput.text?.toString()?.trim()?.toIntOrNull()
                        ?: fallbackMillis).coerceIn(1, 10_000_000)
                    upsertFloatingWaitAction(editIndex, fixedMillisWaitAction(millis))
                    showFloatingRecorder()
                },
                confirmLabel = if (editing) "保存" else "添加",
            ))
        } else {
            val secondsInput = inputField(
                ((current?.get("seconds") as? Number)?.toInt() ?: 5).toString(),
                "等待秒数",
                numberOnly = true,
            )
            panel.addView(fieldLabel("等待秒数，最多 10000 秒"))
            panel.addView(secondsInput, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(42),
            ))
            panel.addView(actionButtonRow(
                onCancel = cancelAction,
                onConfirm = {
                    val seconds = (secondsInput.text?.toString()?.trim()?.toIntOrNull() ?: 5).coerceIn(1, 10000)
                    upsertFloatingWaitAction(
                        editIndex,
                        mapOf(
                            "type" to "wait",
                            "waitMode" to "fixed",
                            "seconds" to seconds,
                            "waitMillis" to seconds * 1000,
                        ),
                    )
                    showFloatingRecorder()
                },
                confirmLabel = if (editing) "保存" else "添加",
            ))
        }

        addChooserPanel(panel, layoutParams)
    }

    private fun showFloatingAppPicker() {
        removeChooserOverlay()
        val panelHeight = (resources.displayMetrics.heightPixels - dp(160)).coerceIn(dp(360), dp(560))
        val layoutParams = floatingPanelParams(widthDp = 340, height = panelHeight)
        val panel = floatingPanel("启动应用")

        val launchIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        val apps = packageManager.queryIntentActivities(launchIntent, 0)
            .sortedBy { it.loadLabel(packageManager).toString().lowercase(Locale.getDefault()) }

        val list = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        if (apps.isEmpty()) {
            list.addView(TextView(this).apply {
                text = "没有找到可启动应用"
                textSize = 13f
                gravity = Gravity.CENTER
                setTextColor(0xFFB8C0C8.toInt())
                setPadding(dp(8), dp(28), dp(8), dp(28))
            })
        } else {
            apps.forEach { info ->
                val packageName = info.activityInfo?.packageName ?: return@forEach
                val label = info.loadLabel(packageManager)?.toString()?.takeIf { it.isNotBlank() } ?: packageName
                list.addView(optionRow(label, packageName, 0xFFAB47BC.toInt()) {
                    floatingRecordActions.add(
                        mapOf(
                            "type" to "launchApp",
                            "packageName" to packageName,
                            "label" to label,
                        ),
                    )
                    showFloatingRecorder()
                })
            }
        }

        panel.addView(
            ScrollView(this).apply {
                addView(list)
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ),
        )
        panel.addView(
            menuButton("返回", 0xFF607D8B.toInt()) {
                showFloatingAddMenu()
            },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(42),
            ).apply {
                topMargin = dp(8)
            },
        )
        addChooserPanel(panel, layoutParams)
    }

    private fun startFloatingGesturePicker(type: String) {
        removeChooserOverlay()
        startNativePicker(type) { result ->
            if (result["cancelled"] != true) {
                appendFloatingPickerResult(result)
            }
            showFloatingRecorder()
        }
    }

    private fun startFloatingButtonDetect() {
        removeChooserOverlay()
        startNativePicker("buttonDetect") { result ->
            if (result["cancelled"] == true) {
                showFloatingRecorder()
                return@startNativePicker
            }
            showFloatingButtonEditor(normalizeMap(result))
        }
    }

    private fun startFloatingImageButtonDetect() {
        removeChooserOverlay()
        startNativePicker("imageButtonDetect") { result ->
            if (result["cancelled"] == true) {
                showFloatingRecorder()
                return@startNativePicker
            }
            showFloatingButtonEditor(normalizeMap(result) + mapOf("source" to "imageTemplate"))
        }
    }

    private fun showFloatingButtonEditor(seed: Map<String, Any?>, editIndex: Int? = null) {
        removeChooserOverlay()
        val layoutParams = floatingPanelParams(widthDp = 340, focusable = true)
        val panel = floatingPanel("按钮识别")
        val source = seed["source"] as? String ?: "accessibility"
        var selectedMatchMode = seed["matchMode"] as? String ?: "contains"
        var selectedRegionMode = seed["regionMode"] as? String ?: "full"
        var selectedFailAction = seed["failAction"] as? String ?: "notify"
        val pickedRegion = normalizeMap(
            (seed["region"] as? Map<*, *>) ?: (seed["bounds"] as? Map<*, *>) ?: emptyMap<String, Any?>(),
        )
        val textInput = inputField(seed["buttonText"] as? String ?: "", "按钮文字", numberOnly = false)
        val idInput = inputField(seed["buttonId"] as? String ?: "", "按钮ID", numberOnly = false)
        val descInput = inputField(seed["buttonDescription"] as? String ?: "", "按钮描述", numberOnly = false)
        val retryInput = inputField(((seed["retryCount"] as? Number)?.toInt() ?: 3).toString(), "重试次数", numberOnly = true)
        val waitInput = inputField(((seed["retryWaitMillis"] as? Number)?.toInt() ?: 800).toString(), "重试等待毫秒", numberOnly = true)

        panel.addView(TextView(this).apply {
            text = if (source == "imageTemplate") {
                "识别来源：图片识别"
            } else if (source == "imageText") {
                "识别来源：图片文字 OCR"
            } else {
                "识别来源：无障碍按钮"
            }
            textSize = 12f
            setTextColor(0xFFB8C0C8.toInt())
            setPadding(0, 0, 0, dp(8))
        })
        panel.addView(fieldLabel("识别方式"))
        val matchStatus = TextView(this).apply {
            text = if (selectedMatchMode == "exact") "当前：完全相同" else "当前：包含文字"
            textSize = 12f
            setTextColor(0xFFB8C0C8.toInt())
            setPadding(0, 0, 0, dp(6))
        }
        panel.addView(matchStatus)
        val matchRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        matchRow.addView(menuButton("完全相同", 0xFF8EB8FF.toInt()) {
            selectedMatchMode = "exact"
            matchStatus.text = "当前：完全相同"
        }, LinearLayout.LayoutParams(0, dp(38), 1f).apply { marginEnd = dp(8) })
        matchRow.addView(menuButton("包含文字", 0xFF4CAF50.toInt()) {
            selectedMatchMode = "contains"
            matchStatus.text = "当前：包含文字"
        }, LinearLayout.LayoutParams(0, dp(38), 1f))
        panel.addView(matchRow)
        panel.addView(fieldLabel("识别区域"), LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(8) })
        val regionStatus = TextView(this).apply {
            text = if (selectedRegionMode == "custom") "当前：当前按钮区域" else "当前：全屏"
            textSize = 12f
            setTextColor(0xFFB8C0C8.toInt())
            setPadding(0, 0, 0, dp(6))
        }
        panel.addView(regionStatus)
        val regionRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        regionRow.addView(menuButton("全屏", 0xFF8EB8FF.toInt()) {
            selectedRegionMode = "full"
            regionStatus.text = "当前：全屏"
        }, LinearLayout.LayoutParams(0, dp(38), 1f).apply { marginEnd = dp(8) })
        regionRow.addView(menuButton("当前区域", 0xFF4CAF50.toInt()) {
            selectedRegionMode = "custom"
            regionStatus.text = "当前：当前按钮区域"
        }, LinearLayout.LayoutParams(0, dp(38), 1f))
        panel.addView(regionRow)
        panel.addView(fieldLabel("按钮文字"))
        panel.addView(textInput, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(42)))
        panel.addView(fieldLabel("按钮ID"), LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(8) })
        panel.addView(idInput, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(42)))
        panel.addView(fieldLabel("按钮描述"), LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(8) })
        panel.addView(descInput, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(42)))

        val retryRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(8), 0, 0)
        }
        retryRow.addView(retryInput, LinearLayout.LayoutParams(0, dp(42), 1f).apply {
            marginEnd = dp(8)
        })
        retryRow.addView(waitInput, LinearLayout.LayoutParams(0, dp(42), 1f))
        panel.addView(retryRow)

        panel.addView(TextView(this).apply {
            text = "识别成功默认点击；识别失败会按重试次数等待后再找，最终失败默认全屏通知。"
            textSize = 12f
            setTextColor(0xFFB8C0C8.toInt())
            setPadding(0, dp(8), 0, dp(8))
        })
        panel.addView(fieldLabel("重试失败后"))
        val failStatus = TextView(this).apply {
            text = if (selectedFailAction == "lockScreen") "当前：锁屏" else "当前：全屏通知脚本执行失败"
            textSize = 12f
            setTextColor(0xFFB8C0C8.toInt())
            setPadding(0, 0, 0, dp(6))
        }
        panel.addView(failStatus)
        val failRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        failRow.addView(menuButton("通知失败", 0xFF8EB8FF.toInt()) {
            selectedFailAction = "notify"
            failStatus.text = "当前：全屏通知脚本执行失败"
        }, LinearLayout.LayoutParams(0, dp(38), 1f).apply { marginEnd = dp(8) })
        failRow.addView(menuButton("锁屏", 0xFFFF5252.toInt()) {
            selectedFailAction = "lockScreen"
            failStatus.text = "当前：锁屏"
        }, LinearLayout.LayoutParams(0, dp(38), 1f))
        panel.addView(failRow)

        fun save() {
            val action = mapOf(
                    "type" to "buttonRecognize",
                    "source" to source,
                    "buttonText" to textInput.text?.toString()?.trim().orEmpty(),
                    "buttonId" to idInput.text?.toString()?.trim().orEmpty(),
                    "buttonDescription" to descInput.text?.toString()?.trim().orEmpty(),
                    "templateImage" to (seed["templateImage"] as? String).orEmpty(),
                    "templateWidth" to ((seed["templateWidth"] as? Number)?.toInt() ?: 0),
                    "templateHeight" to ((seed["templateHeight"] as? Number)?.toInt() ?: 0),
                    "matchMode" to selectedMatchMode,
                    "regionMode" to selectedRegionMode,
                    "region" to if (selectedRegionMode == "custom") pickedRegion else null,
                    "successMode" to "defaultClick",
                    "retryCount" to ((retryInput.text?.toString()?.trim()?.toIntOrNull() ?: 3).coerceIn(0, 20)),
                    "retryWaitMillis" to ((waitInput.text?.toString()?.trim()?.toIntOrNull() ?: 800).coerceIn(0, 10_000_000)),
                    "retrySuccessMode" to "defaultClick",
                    "failAction" to selectedFailAction,
            )
            if (editIndex != null && editIndex in floatingRecordActions.indices) {
                floatingRecordActions[editIndex] = action
            } else {
                floatingRecordActions.add(action)
            }
            showFloatingRecorder()
        }

        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(8), 0, 0)
        }
        row.addView(menuButton("取消", 0xFFFF8A80.toInt()) {
            showFloatingRecorder()
        }, LinearLayout.LayoutParams(0, dp(42), 1f).apply { marginEnd = dp(8) })
        row.addView(menuButton("保存", 0xFF4CAF50.toInt()) {
            save()
        }, LinearLayout.LayoutParams(0, dp(42), 1f))
        panel.addView(row)

        addChooserPanel(panel, layoutParams)
    }

    private fun appendFloatingPickerResult(result: Map<String, Any?>) {
        floatingRecordActions.addAll(floatingActionsFromPickerResult(result))
    }

    private fun floatingActionsFromPickerResult(result: Map<String, Any?>): List<Map<String, Any?>> {
        val type = result["type"] as? String
        if (type == "buttonRecognize") {
            return listOf(normalizeMap(result))
        }
        return when (type) {
            "clickSteps" -> {
                val points = result["points"] as? List<*> ?: emptyList<Any?>()
                val sortedPoints = points.mapNotNull { it as? Map<*, *> }
                    .sortedBy { (it["t"] as? Number)?.toLong() ?: 0L }
                val actions = mutableListOf<Map<String, Any?>>()
                var previousTime = 0L
                sortedPoints.forEach { map ->
                    val time = ((map["t"] as? Number)?.toLong() ?: previousTime).coerceIn(0L, 10_000_000L)
                    val waitMillis = (time - previousTime).coerceAtLeast(0L)
                    if (waitMillis > 0L) {
                        actions.add(fixedMillisWaitAction(waitMillis.toInt()))
                    }
                    actions.add(
                        mapOf(
                            "type" to "click",
                            "x1" to ((map["x"] as? Number)?.toDouble() ?: 0.5),
                            "y1" to ((map["y"] as? Number)?.toDouble() ?: 0.5),
                            "duration" to 50,
                        ),
                    )
                    previousTime = time
                }
                actions
            }
            "recorded" -> {
                recordedActionsFromResult(result)
            }
            "click" -> {
                listOf(
                    mapOf(
                        "type" to "click",
                        "x1" to ((result["x1"] as? Number)?.toDouble() ?: 0.5),
                        "y1" to ((result["y1"] as? Number)?.toDouble() ?: 0.5),
                        "duration" to 50,
                    ),
                )
            }
            "swipe" -> {
                listOf(
                    mapOf(
                        "type" to "swipe",
                        "x1" to ((result["x1"] as? Number)?.toDouble() ?: 0.5),
                        "y1" to ((result["y1"] as? Number)?.toDouble() ?: 0.7),
                        "x2" to ((result["x2"] as? Number)?.toDouble() ?: 0.5),
                        "y2" to ((result["y2"] as? Number)?.toDouble() ?: 0.3),
                        "duration" to 400,
                    ),
                )
            }
            else -> emptyList()
        }
    }

    private fun recordedActionsFromResult(result: Map<String, Any?>): List<Map<String, Any?>> {
        val segments = asMapList(result["segments"])
            .mapNotNull { segment ->
                val points = asMapList(segment["points"])
                    .sortedBy { (it["t"] as? Number)?.toLong() ?: 0L }
                if (points.isEmpty()) return@mapNotNull null
                normalizeMap(segment) + mapOf("points" to points)
            }
            .sortedBy { segment ->
                ((asMapList(segment["points"]).firstOrNull()?.get("t") as? Number)?.toLong()
                    ?: ((segment["start"] as? Number)?.toLong() ?: 0L))
            }
        if (segments.isEmpty()) return emptyList()

        val actions = mutableListOf<Map<String, Any?>>()
        var previousEnd = 0L
        segments.forEach { segment ->
            val points = asMapList(segment["points"])
            val firstPoint = normalizeMap(points.first())
            val lastPoint = normalizeMap(points.last())
            val start = ((firstPoint["t"] as? Number)?.toLong()
                ?: (segment["start"] as? Number)?.toLong()
                ?: 0L).coerceAtLeast(0L)
            val end = ((lastPoint["t"] as? Number)?.toLong() ?: start).coerceAtLeast(start)
            val waitMillis = (start - previousEnd).coerceAtLeast(0L)
            if (waitMillis > 0L) {
                actions.add(fixedMillisWaitAction(waitMillis.toInt()))
            }

            val normalizedPoints = points.map { point ->
                val item = normalizeMap(point)
                item + mapOf("t" to (((item["t"] as? Number)?.toLong() ?: start) - start).coerceAtLeast(0L))
            }
            if (isRecordedTap(points)) {
                actions.add(
                    mapOf(
                        "type" to "click",
                        "x1" to ((firstPoint["x"] as? Number)?.toDouble() ?: 0.5),
                        "y1" to ((firstPoint["y"] as? Number)?.toDouble() ?: 0.5),
                        "duration" to 50,
                    ),
                )
            } else {
                actions.add(
                    mapOf(
                        "type" to "recorded",
                        "duration" to (end - start).coerceAtLeast(50L),
                        "segments" to listOf(
                            mapOf(
                                "start" to 0,
                                "duration" to (end - start).coerceAtLeast(50L),
                                "points" to normalizedPoints,
                            ),
                        ),
                    ),
                )
            }
            previousEnd = end
        }
        return actions
    }

    private fun isRecordedTap(points: List<Map<String, Any?>>): Boolean {
        if (points.isEmpty()) return false
        if (points.size == 1) return true
        val first = normalizeMap(points.first())
        val startX = (first["x"] as? Number)?.toFloat() ?: 0.5f
        val startY = (first["y"] as? Number)?.toFloat() ?: 0.5f
        val maxDistance = points.maxOf { point ->
            val item = normalizeMap(point)
            val dx = ((item["x"] as? Number)?.toFloat() ?: startX) - startX
            val dy = ((item["y"] as? Number)?.toFloat() ?: startY) - startY
            dx * dx + dy * dy
        }
        val firstT = (first["t"] as? Number)?.toLong() ?: 0L
        val lastT = (normalizeMap(points.last())["t"] as? Number)?.toLong() ?: firstT
        return maxDistance <= 0.0004f && (lastT - firstT) <= 220L
    }

    private fun fixedMillisWaitAction(milliseconds: Int): Map<String, Any?> {
        val millis = milliseconds.coerceIn(1, 10_000_000)
        val seconds = ((millis + 999) / 1000).coerceIn(1, 10000)
        return mapOf(
            "type" to "wait",
            "waitMode" to "fixed",
            "waitMillis" to millis,
            "seconds" to seconds,
        )
    }

    private fun upsertFloatingWaitAction(index: Int?, action: Map<String, Any?>) {
        if (index != null && index in floatingRecordActions.indices) {
            floatingRecordActions[index] = action
        } else {
            floatingRecordActions.add(action)
        }
    }

    private fun isRandomWait(action: Map<String, Any?>): Boolean {
        return action["waitMode"] == "random" ||
            action["minSeconds"] != null ||
            action["maxSeconds"] != null ||
            action["minMillis"] != null ||
            action["maxMillis"] != null
    }

    private fun hasMillisWait(action: Map<String, Any?>): Boolean {
        return action["waitMillis"] != null || action["minMillis"] != null || action["maxMillis"] != null
    }

    private fun replaceFloatingActionFromPicker(index: Int, result: Map<String, Any?>) {
        val replacements = floatingActionsFromPickerResult(result)
        if (replacements.isEmpty()) return
        if (index in floatingRecordActions.indices) {
            floatingRecordActions[index] = replacements.first()
            if (replacements.size > 1) {
                floatingRecordActions.addAll(index + 1, replacements.drop(1))
            }
        }
    }

    private fun editFloatingAction(index: Int) {
        val action = floatingRecordActions.getOrNull(index) ?: return
        if ((action["type"] as? String) == "wait") {
            showFloatingWaitEditor(
                randomWait = isRandomWait(action),
                milliseconds = hasMillisWait(action),
                editIndex = index,
            )
            return
        }
        if ((action["type"] as? String) == "buttonRecognize") {
            showFloatingButtonEditor(action, editIndex = index)
            return
        }
        val pickerType = when (action["type"] as? String) {
            "click" -> "click"
            "swipe" -> "swipe"
            "recorded" -> "record"
            else -> return
        }
        removeChooserOverlay()
        startNativePicker(pickerType) { result ->
            if (result["cancelled"] != true) {
                replaceFloatingActionFromPicker(index, result)
            }
            showFloatingRecorder()
        }
    }

    private fun moveFloatingAction(index: Int, delta: Int) {
        val target = index + delta
        if (index !in floatingRecordActions.indices || target !in floatingRecordActions.indices) {
            showFloatingRecorder()
            return
        }
        val action = floatingRecordActions.removeAt(index)
        floatingRecordActions.add(target, action)
        showFloatingRecorder()
    }

    private fun removeFloatingAction(index: Int) {
        if (index in floatingRecordActions.indices) {
            floatingRecordActions.removeAt(index)
        }
        showFloatingRecorder()
    }

    private fun isFloatingActionEditable(action: Map<String, Any?>): Boolean {
        return when (action["type"] as? String) {
            "click", "swipe", "recorded", "wait" -> true
            "buttonRecognize" -> true
            else -> false
        }
    }

    private fun ensureFloatingRecordName() {
        if (floatingRecordName.isBlank()) {
            floatingRecordName = "自动化配置 ${SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())}"
        }
    }

    private fun rememberFloatingRecordName(input: EditText) {
        floatingRecordName = input.text?.toString()?.trim().orEmpty()
    }

    private fun nativeActionTitle(action: Map<String, Any?>): String {
        if ((action["type"] as? String) == "wait") {
            return if (isRandomWait(action)) {
                "随机等待"
            } else if (hasMillisWait(action)) {
                "毫秒等待"
            } else {
                "固定等待"
            }
        }
        return when (action["type"] as? String ?: "swipe") {
            "click" -> "点击手势"
            "swipe" -> "滑动手势"
            "recorded" -> "录制轨迹"
            "nav" -> "导航动作"
            "launchApp" -> "启动应用"
            "buttonRecognize" -> "按钮识别"
            "lockScreen" -> "锁屏"
            else -> "未知动作"
        }
    }

    private fun nativeActionSubtitle(action: Map<String, Any?>): String {
        return when (action["type"] as? String ?: "swipe") {
            "click" -> "坐标 (${formatRatio(action["x1"])}, ${formatRatio(action["y1"])})"
            "swipe" -> "从 (${formatRatio(action["x1"])}, ${formatRatio(action["y1"])}) 到 (${formatRatio(action["x2"])}, ${formatRatio(action["y2"])})"
            "recorded" -> "${asMapList(action["segments"]).size} 段轨迹，约 ${formatElapsed((action["duration"] as? Number)?.toLong() ?: 0L)}"
            "nav" -> when (action["navType"] as? String ?: "back") {
                "home" -> "模拟回到桌面"
                "recents" -> "模拟多任务"
                else -> "模拟返回键"
            }
            "wait" -> {
                if (isRandomWait(action)) {
                    val min = waitMinMillis(action)
                    val max = waitMaxMillis(action)
                    "${formatWaitDuration(min)}-${formatWaitDuration(max)} 内随机"
                } else {
                    "固定等待 ${formatWaitDuration(resolveWaitMillis(action))}"
                }
            }
            "launchApp" -> "拉起 ${(action["label"] as? String) ?: (action["packageName"] as? String) ?: "应用"}"
            "buttonRecognize" -> {
                val mode = if ((action["matchMode"] as? String) == "exact") "完全相同" else "包含"
                val text = action["buttonText"] as? String ?: "按钮"
                val source = when (action["source"] as? String) {
                    "imageTemplate" -> "图片识别"
                    "imageText" -> "图片文字"
                    else -> "无障碍"
                }
                "$source · 识别“$text” · $mode · 失败重试 ${((action["retryCount"] as? Number)?.toInt() ?: 3)} 次"
            }
            "lockScreen" -> "执行到这里时锁定屏幕"
            else -> ""
        }
    }

    private fun formatRatio(value: Any?): String {
        val number = (value as? Number)?.toDouble() ?: 0.0
        return String.format(Locale.US, "%.3f", number)
    }

    private fun panelTitle(title: String): TextView {
        return TextView(this).apply {
            text = title
            textSize = 15f
            setTextColor(Color.WHITE)
            setPadding(0, 0, 0, dp(8))
        }
    }

    private fun floatingPanel(title: String): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(12), dp(14), dp(12))
            background = roundedBackground(0xF21F252B.toInt(), dp(18).toFloat(), 0x44FFFFFF)
            addView(panelTitle(title))
        }
    }

    private fun optionRow(title: String, subtitle: String, color: Int, onClick: () -> Unit): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(10), dp(9), dp(10), dp(9))
            background = roundedBackground(0x22111111, dp(12).toFloat(), color and 0x88FFFFFF.toInt())
            setOnClickListener { onClick() }
        }
        row.addView(TextView(this).apply {
            text = ""
            background = roundedBackground(color and 0xCCFFFFFF.toInt(), dp(8).toFloat(), 0x33FFFFFF)
        }, LinearLayout.LayoutParams(dp(10), dp(36)).apply {
            marginEnd = dp(10)
        })
        val texts = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        texts.addView(TextView(this).apply {
            text = title
            textSize = 13f
            setTextColor(Color.WHITE)
        })
        texts.addView(TextView(this).apply {
            text = subtitle
            textSize = 11f
            setTextColor(0xFFB8C0C8.toInt())
            setPadding(0, dp(2), 0, 0)
        })
        row.addView(texts, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(row)
            setPadding(0, 0, 0, dp(8))
        }
    }

    private fun inputField(value: String, hint: String, numberOnly: Boolean): EditText {
        return EditText(this).apply {
            setText(value)
            setHint(hint)
            textSize = 13f
            setSingleLine(true)
            setSelectAllOnFocus(true)
            setTextColor(Color.WHITE)
            setHintTextColor(0xFF8F98A3.toInt())
            setPadding(dp(10), 0, dp(10), 0)
            background = roundedBackground(0x22111111, dp(10).toFloat(), 0x33FFFFFF)
            inputType = if (numberOnly) {
                InputType.TYPE_CLASS_NUMBER
            } else {
                InputType.TYPE_CLASS_TEXT
            }
        }
    }

    private fun fieldLabel(label: String): TextView {
        return TextView(this).apply {
            text = label
            textSize = 12f
            setTextColor(0xFFB8C0C8.toInt())
            setPadding(0, 0, 0, dp(5))
        }
    }

    private fun sectionLabel(label: String): TextView {
        return TextView(this).apply {
            text = label
            textSize = 12f
            setTextColor(0xFF8EB8FF.toInt())
            setPadding(dp(2), dp(8), 0, dp(6))
        }
    }

    private fun actionButtonRow(
        onCancel: () -> Unit,
        onConfirm: () -> Unit,
        confirmLabel: String = "添加",
    ): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(12), 0, 0)
        }
        row.addView(
            menuButton("取消", 0xFFFF8A80.toInt(), onCancel),
            LinearLayout.LayoutParams(0, dp(42), 1f).apply {
                marginEnd = dp(8)
            },
        )
        row.addView(
            menuButton(confirmLabel, 0xFF4CAF50.toInt(), onConfirm),
            LinearLayout.LayoutParams(0, dp(42), 1f),
        )
        return row
    }

    private fun compactButton(label: String, color: Int, onClick: () -> Unit): TextView {
        return TextView(this).apply {
            text = label
            textSize = 11f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            background = roundedBackground(color and 0xCCFFFFFF.toInt(), dp(12).toFloat(), 0x33FFFFFF)
            setOnClickListener { onClick() }
        }
    }

    private fun startNativePicker(type: String, callback: (Map<String, Any?>) -> Unit) {
        nativePickerResult = callback
        showPickerOverlay(type)
    }

    private fun saveFloatingRecordedConfig(rawName: String) {
        val id = "gesture_${System.currentTimeMillis()}"
        val name = rawName.trim().ifBlank {
            "自动化配置 ${SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())}"
        }
        val config = mapOf(
            "id" to id,
            "name" to name,
            "actions" to floatingRecordActions.map(::normalizeMap),
            "loopCount" to 1,
            "loopIntervalMillis" to 0,
        )
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val key = "flutter.gesture_configs_v1"
        val array = try {
            JSONArray(prefs.getString(key, "[]") ?: "[]")
        } catch (_: Exception) {
            JSONArray()
        }
        array.put(mapToJson(config))
        prefs.edit().putString(key, array.toString()).apply()
        availableConfigs.add(config)
        selectedConfigIndex = availableConfigs.lastIndex
    }

    private fun repositionChooser() {
        // Chooser panels are full-screen centered overlays now, so they do not follow the menu.
    }

    private data class ResolvedConfigPlan(
        val name: String,
        val setupActions: List<Map<String, Any?>>,
        val loopActions: List<Map<String, Any?>>,
        val loopCount: Int,
        val loopIntervalMillis: Int,
        val infiniteLoop: Boolean,
    )

    private fun resolveConfigPlan(
        config: Map<String, Any?>,
        visited: MutableSet<String> = mutableSetOf(),
    ): ResolvedConfigPlan {
        val configId = config["id"] as? String
        if (!configId.isNullOrBlank() && !visited.add(configId)) {
            val actions = asMapList(config["actions"]).map(::normalizeMap)
            return ResolvedConfigPlan(
                name = config["name"] as? String ?: "配置",
                setupActions = actions,
                loopActions = emptyList(),
                loopCount = 1,
                loopIntervalMillis = 0,
                infiniteLoop = false,
            )
        }
        val name = config["name"] as? String ?: "配置"
        val actions = asMapList(config["actions"]).map(::normalizeMap)
        val loops = ((config["loopCount"] as? Number)?.toInt() ?: 1).coerceIn(1, 9999)
        val interval = ((config["loopIntervalMillis"] as? Number)?.toInt() ?: 0).coerceIn(0, 10_000_000)
        val infinite = config["infiniteLoop"] as? Boolean ?: false
        val followUpId = config["followUpConfigId"] as? String
        if (infinite) {
            return ResolvedConfigPlan(
                name = name,
                setupActions = emptyList(),
                loopActions = actions,
                loopCount = loops,
                loopIntervalMillis = interval,
                infiniteLoop = true,
            )
        }
        val setup = expandLoopedActions(actions, loops, interval).map(::normalizeMap).toMutableList()
        val child = availableConfigs.firstOrNull { (it["id"] as? String) == followUpId }
        if (child == null) {
            return ResolvedConfigPlan(
                name = name,
                setupActions = setup,
                loopActions = emptyList(),
                loopCount = 1,
                loopIntervalMillis = 0,
                infiniteLoop = false,
            )
        }
        val childPlan = resolveConfigPlan(child, visited)
        setup.addAll(childPlan.setupActions)
        return ResolvedConfigPlan(
            name = "$name -> ${childPlan.name}",
            setupActions = setup,
            loopActions = childPlan.loopActions,
            loopCount = childPlan.loopCount,
            loopIntervalMillis = childPlan.loopIntervalMillis,
            infiniteLoop = childPlan.infiniteLoop,
        )
    }

    private fun startConfig(config: Map<String, Any?>) {
        val plan = resolveConfigPlan(config)
        if (plan.setupActions.isEmpty() && plan.loopActions.isEmpty()) {
            return
        }
        handler.removeCallbacksAndMessages(null)
        minSeconds = 0
        maxSeconds = 0
        loopCount = plan.loopCount.coerceIn(1, 9999)
        infiniteLoop = plan.infiniteLoop
        loopIntervalMillis = plan.loopIntervalMillis.toLong().coerceIn(0L, 10_000_000L)
        remainingLoops = if (infiniteLoop) Int.MAX_VALUE else loopCount
        scriptName = plan.name
        setupActions.clear()
        setupActions.addAll(plan.setupActions)
        gestureActions.clear()
        gestureActions.addAll(plan.loopActions)
        startScriptRun()
    }

    private fun startScriptRun() {
        if (gestureActions.isEmpty() && setupActions.isEmpty()) {
            return
        }
        runSessionId += 1L
        runtimeActions.clear()
        runtimeActions.addAll(setupActions.map(::planRuntimeAction))
        loopStartIndex = runtimeActions.size
        runtimeActions.addAll(gestureActions.map(::planRuntimeAction))
        remainingLoops = if (infiniteLoop) Int.MAX_VALUE else loopCount.coerceAtLeast(1)
        runStartedAt = SystemClock.uptimeMillis()
        val singleRunMillis = estimateActionsMillis(runtimeActions)
        val loopOnlyMillis = estimateActionsMillis(runtimeActions.drop(loopStartIndex))
        runTotalMillis =
            if (infiniteLoop) {
                0L
            } else if (loopStartIndex >= runtimeActions.size) {
                singleRunMillis.toLong()
            } else {
                singleRunMillis.toLong() +
                    loopOnlyMillis * (remainingLoops - 1).coerceAtLeast(0).toLong() +
                    loopIntervalMillis * (remainingLoops - 1).coerceAtLeast(0).toLong()
            }
        isRunning = true
        isPaused = false
        currentActionIndex = -1
        resumeActionIndex = 0
        currentWaitUntilMillis = 0L
        pausedWaitRemainingMillis = 0L
        updateStatusText()
        showFloatingWindow(expanded = true)
        startPlaybackTicker()
        executeActionIndex(0)
    }

    private fun stopScriptRun() {
        runSessionId += 1L
        isRunning = false
        isPaused = false
        handler.removeCallbacksAndMessages(null)
        clearGesturePreviewOverlay()
        playbackTicker = null
        setupActions.clear()
        runtimeActions.clear()
        loopStartIndex = 0
        infiniteLoop = false
        remainingLoops = 0
        currentActionIndex = -1
        resumeActionIndex = 0
        currentWaitUntilMillis = 0L
        pausedWaitRemainingMillis = 0L
        updateStatusText()
        if (floatingView != null) {
            showFloatingWindow(expanded = true)
        }
    }

    private fun isRunSessionActive(token: Long): Boolean {
        return isRunning && token == runSessionId
    }

    private fun clearGesturePreviewOverlay() {
        val overlay = gesturePreviewOverlay ?: return
        gesturePreviewOverlay = null
        try {
            if (overlay.isAttachedToWindow) {
                windowManager?.removeViewImmediate(overlay)
            }
        } catch (_: Exception) {
            try {
                windowManager?.removeView(overlay)
            } catch (_: Exception) {
            }
        }
    }

    private fun pauseScriptRun() {
        if (!isRunning || isPaused) return
        isPaused = true
        val now = SystemClock.uptimeMillis()
        if (currentWaitUntilMillis > now) {
            pausedWaitRemainingMillis = currentWaitUntilMillis - now
        }
        handler.removeCallbacksAndMessages(null)
        playbackTicker = null
        if (currentWaitUntilMillis > 0L) {
            resumeActionIndex = (currentActionIndex + 1).coerceAtLeast(0)
        }
        currentWaitUntilMillis = 0L
        updateStatusText()
        showFloatingWindow(expanded = true)
    }

    private fun resumeScriptRun() {
        if (!isRunning || !isPaused) return
        isPaused = false
        updateStatusText()
        showFloatingWindow(expanded = true)
        startPlaybackTicker()
        val nextIndex = resumeActionIndex.coerceAtLeast(0)
        if (pausedWaitRemainingMillis > 0L) {
            val remaining = pausedWaitRemainingMillis
            pausedWaitRemainingMillis = 0L
            currentWaitUntilMillis = SystemClock.uptimeMillis() + remaining
            handler.postDelayed({
                currentWaitUntilMillis = 0L
                currentActionIndex = nextIndex
                executeActionIndex(nextIndex)
            }, remaining)
        } else {
            executeActionIndex(nextIndex)
        }
    }

    private fun isScreenOn(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
        return pm?.isInteractive ?: true
    }

    private fun executeActionIndex(index: Int) {
        if (!isRunning) return
        val runToken = runSessionId
        if (isPaused) {
            resumeActionIndex = index
            return
        }

        if (!isScreenOn()) {
            handler.postDelayed({
                if (isRunSessionActive(runToken)) executeActionIndex(index)
            }, 1000L)
            return
        }

        if (index >= runtimeActions.size) {
            currentActionIndex = runtimeActions.size
            currentWaitUntilMillis = 0L
            if (loopStartIndex < runtimeActions.size && (infiniteLoop || remainingLoops > 1)) {
                if (!infiniteLoop) {
                    remainingLoops -= 1
                }
                val delay = loopIntervalMillis.coerceAtLeast(0L)
                updateStatusText()
                handler.postDelayed({
                    if (isRunSessionActive(runToken)) executeActionIndex(loopStartIndex)
                }, delay)
            } else if (minSeconds > 0 || maxSeconds > 0) {
                val delay = if (maxSeconds > minSeconds) {
                    (random.nextInt(maxSeconds - minSeconds + 1) + minSeconds) * 1000L
                } else {
                    minSeconds * 1000L
                }
                updateStatusText()
                handler.postDelayed({
                    if (isRunSessionActive(runToken)) executeActionIndex(0)
                }, delay)
            } else {
                isRunning = false
                isPaused = false
                playbackTicker = null
                setupActions.clear()
                runtimeActions.clear()
                loopStartIndex = 0
                infiniteLoop = false
                remainingLoops = 0
                currentActionIndex = -1
                resumeActionIndex = 0
                currentWaitUntilMillis = 0L
                pausedWaitRemainingMillis = 0L
                updateStatusText()
                if (floatingView != null) {
                    showFloatingWindow(expanded = true)
                }
            }
            return
        }

        val action = runtimeActions[index]
        currentActionIndex = index
        resumeActionIndex = index
        currentWaitUntilMillis = 0L
        updateStatusText()
        when (action["type"] as? String ?: "swipe") {
            "swipe", "click", "recorded" -> {
                showGestureActionPreview(action) {
                    if (!isRunSessionActive(runToken)) return@showGestureActionPreview
                    performGestureAction(action, runToken) {
                        resumeActionIndex = index + 1
                        executeActionIndex(index + 1)
                    }
                }
            }
            "nav" -> {
                val navType = action["navType"] as? String ?: "back"
                performNavigationAction(navType, runToken) {
                    resumeActionIndex = index + 1
                    executeActionIndex(index + 1)
                }
            }
            "wait" -> {
                val waitMillis = resolveWaitMillis(action)
                currentWaitUntilMillis = SystemClock.uptimeMillis() + waitMillis
                resumeActionIndex = index + 1
                updateStatusText()
                handler.postDelayed({
                    if (isRunSessionActive(runToken)) executeActionIndex(index + 1)
                }, waitMillis)
            }
            "launchApp" -> {
                val packageName = action["packageName"] as? String
                if (packageName != null) {
                    packageManager.getLaunchIntentForPackage(packageName)?.let { intent ->
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                    }
                }
                resumeActionIndex = index + 1
                handler.postDelayed({
                    if (isRunSessionActive(runToken)) executeActionIndex(index + 1)
                }, 1000)
            }
            "buttonRecognize" -> {
                performButtonRecognizeAction(action, runToken) {
                    resumeActionIndex = index + 1
                    executeActionIndex(index + 1)
                }
            }
            "lockScreen" -> {
                performLockScreenAction(runToken) {
                    resumeActionIndex = index + 1
                    executeActionIndex(index + 1)
                }
            }
            else -> executeActionIndex(index + 1)
        }
    }

    private fun planRuntimeAction(action: Map<String, Any?>): Map<String, Any?> {
        if ((action["type"] as? String) != "wait") {
            return action
        }
        val millis = resolveWaitMillis(action)
        return action + mapOf(
            "waitMode" to "fixed",
            "waitMillis" to millis,
            "seconds" to ((millis + 999) / 1000).coerceIn(1L, 10000L),
        )
    }

    private fun startPlaybackTicker() {
        val ticker = object : Runnable {
            override fun run() {
                if (!isRunning) return
                updateStatusText()
                handler.postDelayed(this, 500)
            }
        }
        playbackTicker = ticker
        handler.post(ticker)
    }

    private fun resolveWaitSeconds(action: Map<String, Any?>): Long {
        return ((resolveWaitMillis(action) + 999L) / 1000L).coerceIn(1L, 10000L)
    }

    private fun resolveWaitMillis(action: Map<String, Any?>): Long {
        val mode = action["waitMode"] as? String
        val millis = ((action["waitMillis"] as? Number)?.toLong()
            ?: ((action["seconds"] as? Number)?.toLong() ?: 1L) * 1000L).coerceIn(1L, 10_000_000L)
        if (mode != "random" &&
            action["minSeconds"] == null &&
            action["maxSeconds"] == null &&
            action["minMillis"] == null &&
            action["maxMillis"] == null
        ) {
            return millis
        }
        val rawMin = waitMinMillis(action)
        val rawMax = waitMaxMillis(action)
        val min = kotlin.math.min(rawMin, rawMax)
        val max = kotlin.math.max(rawMin, rawMax)
        if (max <= min) return min
        return random.nextInt((max - min + 1).toInt()).toLong() + min
    }

    private fun waitMinMillis(action: Map<String, Any?>): Long {
        val seconds = ((action["seconds"] as? Number)?.toLong() ?: 1L).coerceIn(1L, 10000L)
        return ((action["minMillis"] as? Number)?.toLong()
            ?: ((action["minSeconds"] as? Number)?.toLong()?.times(1000L))
            ?: ((action["waitMillis"] as? Number)?.toLong())
            ?: seconds * 1000L).coerceIn(1L, 10_000_000L)
    }

    private fun waitMaxMillis(action: Map<String, Any?>): Long {
        return ((action["maxMillis"] as? Number)?.toLong()
            ?: ((action["maxSeconds"] as? Number)?.toLong()?.times(1000L))
            ?: waitMinMillis(action)).coerceIn(1L, 10_000_000L)
    }

    private fun performButtonRecognizeAction(action: Map<String, Any?>, runToken: Long, onDone: () -> Unit) {
        val retryCount = ((action["retryCount"] as? Number)?.toInt() ?: 3).coerceIn(0, 20)
        val retryWait = ((action["retryWaitMillis"] as? Number)?.toLong() ?: 800L).coerceIn(0L, 10_000_000L)
        val retryActions = asMapList(action["retryActions"])

        fun attempt(remaining: Int, afterRetry: Boolean) {
            if (!isRunSessionActive(runToken)) return
            findMatchingButtonTarget(action) { match ->
            if (!isRunSessionActive(runToken)) return@findMatchingButtonTarget
            if (match != null) {
                val modeKey = if (afterRetry) "retrySuccessMode" else "successMode"
                val actionsKey = if (afterRetry) "retrySuccessActions" else "successActions"
                val mode = action[modeKey] as? String ?: "defaultClick"
                val customActions = asMapList(action[actionsKey])
                if (mode == "custom" && customActions.isNotEmpty()) {
                    executeInlineActions(customActions, runToken, onDone)
                } else {
                    showMatchedButtonPreview(match.bounds) {
                        if (!isRunSessionActive(runToken)) return@showMatchedButtonPreview
                        performButtonTargetClick(match) {
                            handler.postDelayed({
                                if (isRunSessionActive(runToken)) onDone()
                            }, 250)
                        }
                    }
                }
                return@findMatchingButtonTarget
            }

            if (remaining > 0) {
                executeInlineActions(retryActions, runToken) {
                    handler.postDelayed({
                        if (isRunSessionActive(runToken)) {
                            attempt(remaining - 1, afterRetry = true)
                        }
                    }, retryWait)
                }
                return@findMatchingButtonTarget
            }

            when (action["failAction"] as? String ?: "notify") {
                "lockScreen" -> performLockScreenAction(runToken, onDone)
                "notify" -> {
                    showScriptFailureNotice(action)
                    if (isRunSessionActive(runToken)) onDone()
                }
                else -> if (isRunSessionActive(runToken)) onDone()
            }
            }
        }

        attempt(retryCount, afterRetry = false)
    }

    private fun executeInlineActions(actions: List<Map<String, Any?>>, runToken: Long, onDone: () -> Unit) {
        fun runAt(index: Int) {
            if (!isRunSessionActive(runToken)) return
            if (index >= actions.size) {
                onDone()
                return
            }
            val action = actions[index]
            when (action["type"] as? String ?: "swipe") {
                "swipe", "click", "recorded" -> {
                    showGestureActionPreview(action) {
                        if (!isRunSessionActive(runToken)) return@showGestureActionPreview
                        performGestureAction(action, runToken) { runAt(index + 1) }
                    }
                }
                "nav" -> performNavigationAction(action["navType"] as? String ?: "back", runToken) { runAt(index + 1) }
                "wait" -> handler.postDelayed({
                    if (isRunSessionActive(runToken)) runAt(index + 1)
                }, resolveWaitMillis(action))
                "launchApp" -> {
                    val packageName = action["packageName"] as? String
                    if (packageName != null) {
                        packageManager.getLaunchIntentForPackage(packageName)?.let { intent ->
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                        }
                    }
                    handler.postDelayed({
                        if (isRunSessionActive(runToken)) runAt(index + 1)
                    }, 1000)
                }
                "lockScreen" -> performLockScreenAction(runToken) { runAt(index + 1) }
                else -> runAt(index + 1)
            }
        }
        runAt(0)
    }

    private fun findMatchingButtonTarget(action: Map<String, Any?>, onResult: (ButtonMatchTarget?) -> Unit) {
        val source = action["source"] as? String
        if (source == "imageTemplate") {
            findMatchingImageTemplate(action, onResult)
            return
        }
        if (source == "imageText") {
            findMatchingOcrText(action, onResult)
            return
        }
        onResult(findMatchingButton(action))
    }

    private fun findMatchingImageTemplate(action: Map<String, Any?>, onResult: (ButtonMatchTarget?) -> Unit) {
        val templateBase64 = action["templateImage"] as? String
        if (templateBase64.isNullOrBlank()) {
            onResult(null)
            return
        }
        val template = try {
            val bytes = Base64.decode(templateBase64, Base64.DEFAULT)
            android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        } catch (_: Exception) {
            null
        }
        if (template == null || template.width < 4 || template.height < 4) {
            onResult(null)
            return
        }
        captureScreenBitmap(
            onSuccess = { screen ->
                Thread {
                    val match = try {
                        findBestTemplateMatch(
                            screen,
                            template,
                            actionRegionRect(action),
                            actionSavedBoundsRect(action),
                        )
                    } catch (_: Exception) {
                        null
                    }
                    try {
                        screen.recycle()
                    } catch (_: Exception) {
                    }
                    try {
                        template.recycle()
                    } catch (_: Exception) {
                    }
                    handler.post { onResult(match) }
                }.start()
            },
            onFailure = {
                template.recycle()
                onResult(null)
            },
        )
    }

    private fun findMatchingOcrText(action: Map<String, Any?>, onResult: (ButtonMatchTarget?) -> Unit) {
        recognizeScreenText(
            onSuccess = { nodes ->
                val targetText = ((action["buttonText"] as? String) ?: (action["text"] as? String) ?: "").trim()
                val exact = (action["matchMode"] as? String) == "exact"
                val region = actionRegionRect(action)
                val match = nodes.firstOrNull { node ->
                    if (region != null && !Rect.intersects(region, node.bounds)) {
                        return@firstOrNull false
                    }
                    textMatches(node.text, targetText, exact)
                }
                if (match == null) {
                    onResult(null)
                    return@recognizeScreenText
                }
                val clickableTarget = findNearestClickableTargetForOcr(match.bounds)
                onResult(
                    clickableTarget
                        ?: ButtonMatchTarget(bounds = expandTapRect(match.bounds, dp(22), dp(26))),
                )
            },
            onFailure = { onResult(null) },
        )
    }

    private fun findMatchingButton(action: Map<String, Any?>): ButtonMatchTarget? {
        val nodes = collectButtonNodes(rootInActiveWindow)
        val idCounts = nodes.groupingBy { it.viewId }.eachCount()
        val targetText = ((action["buttonText"] as? String) ?: (action["text"] as? String) ?: "").trim()
        val targetId = ((action["buttonId"] as? String) ?: (action["viewId"] as? String) ?: "").trim()
        val targetDescription = ((action["buttonDescription"] as? String) ?: (action["description"] as? String) ?: "").trim()
        val exact = (action["matchMode"] as? String) == "exact"
        val region = actionRegionRect(action)
        val savedBounds = actionSavedBoundsRect(action)
        val match = nodes
            .asSequence()
            .filter { node ->
                if (region != null && !Rect.intersects(region, node.bounds)) {
                    return@filter false
                }
                val textMatched = targetText.isNotEmpty() &&
                    textMatches(node.text.ifBlank { node.description }, targetText, exact)
                val idMatched = targetId.isNotEmpty() && idMatches(node.viewId, targetId)
                val descriptionMatched = targetDescription.isNotEmpty() &&
                    textMatches(node.description, targetDescription, exact)
                textMatched || idMatched || descriptionMatched
            }
            .maxByOrNull { node ->
                buttonMatchScore(
                    node = node,
                    idCounts = idCounts,
                    targetText = targetText,
                    targetId = targetId,
                    targetDescription = targetDescription,
                    exact = exact,
                    savedBounds = savedBounds,
                )
            }
        return match?.let {
            ButtonMatchTarget(
                bounds = it.bounds,
                accessibilityNode = it.accessibilityNode,
            )
        }
    }

    private fun textMatches(value: String, target: String, exact: Boolean): Boolean {
        if (value.isBlank() || target.isBlank()) return false
        return if (exact) {
            value.trim() == target.trim()
        } else {
            value.contains(target, ignoreCase = true)
        }
    }

    private fun idMatches(value: String, target: String): Boolean {
        if (value.isBlank() || target.isBlank()) return false
        val normalizedValue = value.trim()
        val normalizedTarget = target.trim()
        return normalizedValue.equals(normalizedTarget, ignoreCase = true) ||
            normalizedValue.endsWith("/${normalizedTarget.substringAfterLast('/')}") ||
            normalizedValue.contains(normalizedTarget, ignoreCase = true)
    }

    private fun buttonMatchScore(
        node: ButtonNodeInfo,
        idCounts: Map<String, Int>,
        targetText: String,
        targetId: String,
        targetDescription: String,
        exact: Boolean,
        savedBounds: Rect?,
    ): Long {
        var score = 0L
        if (targetId.isNotBlank()) {
            val idCount = idCounts[node.viewId] ?: 1
            if (node.viewId.equals(targetId, ignoreCase = true)) {
                score += if (idCount == 1) 420_000L else 90_000L
            } else if (idMatches(node.viewId, targetId)) {
                score += if (idCount == 1) 180_000L else 40_000L
            }
        }
        if (targetText.isNotBlank()) {
            val nodeText = node.text.ifBlank { node.description }
            if (nodeText.equals(targetText, ignoreCase = true)) {
                score += 700_000L
            } else if (textMatches(nodeText, targetText, exact)) {
                score += 220_000L
            }
        }
        if (targetDescription.isNotBlank()) {
            if (node.description.equals(targetDescription, ignoreCase = true)) {
                score += 80_000L
            } else if (textMatches(node.description, targetDescription, exact)) {
                score += 40_000L
            }
        }
        if (savedBounds != null) {
            val overlap = overlapArea(savedBounds, node.bounds)
            score += overlap.toLong() * 20L
            val centerDistance = centerDistanceSquared(savedBounds, node.bounds)
            score -= centerDistance.toLong()
        }
        score -= (node.bounds.width() * node.bounds.height()).toLong() / 20L
        return score
    }

    private fun actionSavedBoundsRect(action: Map<String, Any?>): Rect? {
        val region = normalizeMap(
            (action["region"] as? Map<*, *>)
                ?: (action["bounds"] as? Map<*, *>)
                ?: return null,
        )
        val (screenWidth, screenHeight) = screenSize()
        val left = (((region["left"] as? Number)?.toFloat() ?: 0f) * screenWidth).toInt()
        val top = (((region["top"] as? Number)?.toFloat() ?: 0f) * screenHeight).toInt()
        val right = (((region["right"] as? Number)?.toFloat() ?: 1f) * screenWidth).toInt()
        val bottom = (((region["bottom"] as? Number)?.toFloat() ?: 1f) * screenHeight).toInt()
        return Rect(left, top, right, bottom)
    }

    private fun overlapArea(first: Rect, second: Rect): Int {
        val left = kotlin.math.max(first.left, second.left)
        val top = kotlin.math.max(first.top, second.top)
        val right = kotlin.math.min(first.right, second.right)
        val bottom = kotlin.math.min(first.bottom, second.bottom)
        return if (right > left && bottom > top) {
            (right - left) * (bottom - top)
        } else {
            0
        }
    }

    private fun centerDistanceSquared(first: Rect, second: Rect): Int {
        val dx = first.centerX() - second.centerX()
        val dy = first.centerY() - second.centerY()
        return dx * dx + dy * dy
    }

    private fun findNearestClickableTargetForOcr(ocrBounds: Rect): ButtonMatchTarget? {
        val nodes = collectButtonNodes(rootInActiveWindow)
        val match = nodes.maxByOrNull { node ->
            val overlap = overlapArea(ocrBounds, node.bounds)
            val distancePenalty = centerDistanceSquared(ocrBounds, node.bounds)
            overlap.toLong() * 100L - distancePenalty.toLong()
        } ?: return null
        return ButtonMatchTarget(
            bounds = Rect(match.bounds),
            accessibilityNode = match.accessibilityNode,
        )
    }

    private fun expandTapRect(bounds: Rect, horizontal: Int, vertical: Int): Rect {
        val (screenWidth, screenHeight) = screenSize()
        return Rect(
            (bounds.left - horizontal).coerceAtLeast(0),
            (bounds.top - vertical).coerceAtLeast(0),
            (bounds.right + horizontal).coerceAtMost(screenWidth),
            (bounds.bottom + vertical).coerceAtMost(screenHeight),
        )
    }

    private fun actionRegionRect(action: Map<String, Any?>): Rect? {
        if ((action["regionMode"] as? String ?: "full") != "custom") return null
        val region = normalizeMap(
            (action["region"] as? Map<*, *>) ?: (action["bounds"] as? Map<*, *>) ?: return null,
        )
        val (screenWidth, screenHeight) = screenSize()
        val left = (((region["left"] as? Number)?.toFloat() ?: 0f) * screenWidth).toInt()
        val top = (((region["top"] as? Number)?.toFloat() ?: 0f) * screenHeight).toInt()
        val right = (((region["right"] as? Number)?.toFloat() ?: 1f) * screenWidth).toInt()
        val bottom = (((region["bottom"] as? Number)?.toFloat() ?: 1f) * screenHeight).toInt()
        return Rect(left, top, right, bottom)
    }

    private fun showMatchedButtonPreview(bounds: Rect, onDone: () -> Unit) {
        val lp = fullScreenOverlayParams().apply {
            flags = flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        }
        val preview = object : View(this) {
            private val density = resources.displayMetrics.density
            private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = 0xFFFF3B30.toInt()
                style = Paint.Style.STROKE
                strokeWidth = 3f * density
            }
            private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = 0x22FF3B30
                style = Paint.Style.FILL
            }

            override fun onDraw(canvas: Canvas) {
                super.onDraw(canvas)
                canvas.drawRect(bounds, fill)
                canvas.drawRect(bounds, stroke)
            }
        }
        try {
            windowManager?.addView(preview, lp)
            handler.postDelayed({
                try {
                    windowManager?.removeView(preview)
                } catch (_: Exception) {
                }
                handler.postDelayed(onDone, 140)
            }, 220)
        } catch (_: Exception) {
            onDone()
        }
    }

    private fun showGestureActionPreview(action: Map<String, Any?>, onDone: () -> Unit) {
        val lp = fullScreenOverlayParams().apply {
            flags = flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        }
        clearGesturePreviewOverlay()
        val overlay = object : View(this) {
            private val density = resources.displayMetrics.density
            private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = 0xFF40C4FF.toInt()
                style = Paint.Style.STROKE
                strokeWidth = 3f * density
            }
            private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = 0x2240C4FF
                style = Paint.Style.FILL
            }
            private val pointFill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = 0xFF40C4FF.toInt()
                style = Paint.Style.FILL
            }

            override fun onDraw(canvas: Canvas) {
                super.onDraw(canvas)
                val width = width.toFloat()
                val height = height.toFloat()
                when (action["type"] as? String ?: "swipe") {
                    "click" -> {
                        val x = (((action["x1"] as? Number)?.toFloat() ?: 0.5f) * width)
                        val y = (((action["y1"] as? Number)?.toFloat() ?: 0.5f) * height)
                        canvas.drawCircle(x, y, 20f * density, fill)
                        canvas.drawCircle(x, y, 20f * density, stroke)
                    }
                    "swipe" -> {
                        val x1 = (((action["x1"] as? Number)?.toFloat() ?: 0.5f) * width)
                        val y1 = (((action["y1"] as? Number)?.toFloat() ?: 0.6f) * height)
                        val x2 = (((action["x2"] as? Number)?.toFloat() ?: 0.5f) * width)
                        val y2 = (((action["y2"] as? Number)?.toFloat() ?: 0.4f) * height)
                        canvas.drawLine(x1, y1, x2, y2, stroke)
                        canvas.drawCircle(x1, y1, 10f * density, pointFill)
                        canvas.drawCircle(x2, y2, 10f * density, pointFill)
                    }
                    "recorded" -> {
                        asMapList(action["segments"])
                            .sortedBy { segmentStartMillis(it) }
                            .forEach { segment ->
                            val points = asMapList(segment["points"])
                                .sortedBy { (it["t"] as? Number)?.toLong() ?: 0L }
                            if (points.isEmpty()) return@forEach
                            val path = Path()
                            points.forEachIndexed { index, point ->
                                val x = (((point["x"] as? Number)?.toFloat() ?: 0.5f) * width)
                                val y = (((point["y"] as? Number)?.toFloat() ?: 0.5f) * height)
                                if (index == 0) {
                                    path.moveTo(x, y)
                                } else {
                                    path.lineTo(x, y)
                                }
                            }
                            canvas.drawPath(path, stroke)
                        }
                    }
                }
            }
        }
        try {
            windowManager?.addView(overlay, lp)
            gesturePreviewOverlay = overlay
            handler.postDelayed({
                if (gesturePreviewOverlay === overlay) {
                    clearGesturePreviewOverlay()
                } else {
                    try {
                        if (overlay.isAttachedToWindow) {
                            windowManager?.removeViewImmediate(overlay)
                        }
                    } catch (_: Exception) {
                    }
                }
                handler.postDelayed(onDone, 140)
            }, 220)
        } catch (_: Exception) {
            clearGesturePreviewOverlay()
            onDone()
        }
    }

    private fun performButtonTargetClick(target: ButtonMatchTarget, onDone: () -> Unit) {
        val node = target.accessibilityNode
        if (node != null) {
            try {
                if (node.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                    onDone()
                    return
                }
            } catch (_: Exception) {
            }
        }
        performButtonClick(target.bounds, onDone)
    }

    private fun performButtonClick(bounds: Rect, onDone: () -> Unit) {
        val path = Path().apply {
            moveTo(bounds.centerX().toFloat(), bounds.centerY().toFloat())
        }
        try {
            dispatchGestureWithRetry(
                GestureDescription.Builder()
                    .addStroke(GestureDescription.StrokeDescription(path, 0, 80))
                    .build(),
                onDone = onDone,
            )
        } catch (_: Exception) {
            onDone()
        }
    }

    private fun performLockScreenAction(runToken: Long = runSessionId, onDone: () -> Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
        }
        handler.postDelayed({
            if (runToken == Long.MIN_VALUE || isRunSessionActive(runToken)) onDone()
        }, 500)
    }

    private fun showScriptFailureNotice(action: Map<String, Any?>) {
        val text = action["buttonText"] as? String ?: "目标按钮"
        val intent = Intent(this, AlarmActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            putExtra("title", "脚本执行失败")
            putExtra("body", "没有识别到按钮：$text")
            putExtra("targetAppLabel", "当前应用")
        }
        try {
            startActivity(intent)
        } catch (_: Exception) {
        }
    }

    private fun performNavigationAction(navType: String, runToken: Long = runSessionId, onDone: () -> Unit) {
        val globalAction = when (navType) {
            "home" -> GLOBAL_ACTION_HOME
            "recents" -> GLOBAL_ACTION_RECENTS
            else -> GLOBAL_ACTION_BACK
        }
        handler.post {
            if (!isRunSessionActive(runToken)) return@post
            val success = performGlobalAction(globalAction)
            if (!success) {
                if (navType == "home") {
                    launchHomeFallback()
                }
                handler.postDelayed({ performGlobalAction(globalAction) }, 250)
            }
            handler.postDelayed({
                if (isRunSessionActive(runToken)) onDone()
            }, if (navType == "recents") 900L else 650L)
        }
    }

    private fun launchHomeFallback() {
        try {
            val intent = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
        } catch (_: Exception) {
        }
    }

    private fun performGestureAction(action: Map<String, Any?>, runToken: Long = runSessionId, onDone: () -> Unit) {
        val (screenWidth, screenHeight) = screenSize()
        val width = screenWidth.coerceAtLeast(1).toFloat()
        val height = screenHeight.coerceAtLeast(1).toFloat()
        val actionType = action["type"] as? String ?: "swipe"

        val gestureBuilder = GestureDescription.Builder()
        val hasStroke = if (actionType == "recorded") {
            addRecordedStrokes(gestureBuilder, action, width, height)
        } else {
            val duration = ((action["duration"] as? Number)?.toLong() ?: 300L).coerceAtLeast(50L)
            val path = Path()
            if (actionType == "click") {
                val x = ((action["x1"] as? Number)?.toFloat() ?: 0.5f) * width
                val y = ((action["y1"] as? Number)?.toFloat() ?: 0.5f) * height
                path.moveTo(x, y)
            } else {
                val x1 = ((action["x1"] as? Number)?.toFloat() ?: 0.5f) * width
                val y1 = ((action["y1"] as? Number)?.toFloat() ?: 0.7f) * height
                val x2 = ((action["x2"] as? Number)?.toFloat() ?: 0.5f) * width
                val y2 = ((action["y2"] as? Number)?.toFloat() ?: 0.3f) * height
                path.moveTo(x1, y1)
                path.lineTo(x2, y2)
            }
            gestureBuilder.addStroke(GestureDescription.StrokeDescription(path, 0, duration))
            true
        }

        if (!hasStroke) {
            if (isRunSessionActive(runToken)) onDone()
            return
        }

        try {
            dispatchGestureWithRetry(
                gestureBuilder.build(),
                runToken = runToken,
                onDone = {
                    handler.postDelayed({
                        if (isRunSessionActive(runToken)) onDone()
                    }, 100)
                },
            )
        } catch (_: Exception) {
            if (isRunSessionActive(runToken)) onDone()
        }
    }

    private fun dispatchGestureWithRetry(
        gesture: GestureDescription,
        runToken: Long = runSessionId,
        retriesRemaining: Int = 3,
        retryDelayMillis: Long = 120L,
        onDone: () -> Unit,
    ) {
        val started = try {
            dispatchGesture(
                gesture,
                object : GestureResultCallback() {
                    override fun onCompleted(gestureDescription: GestureDescription?) {
                        if (isRunSessionActive(runToken)) onDone()
                    }

                    override fun onCancelled(gestureDescription: GestureDescription?) {
                        if (!isRunSessionActive(runToken)) return
                        if (retriesRemaining > 0) {
                            handler.postDelayed({
                                dispatchGestureWithRetry(
                                    gesture = gesture,
                                    runToken = runToken,
                                    retriesRemaining = retriesRemaining - 1,
                                    retryDelayMillis = retryDelayMillis,
                                    onDone = onDone,
                                )
                            }, retryDelayMillis)
                        } else {
                            onDone()
                        }
                    }
                },
                null,
            )
        } catch (_: Exception) {
            false
        }
        if (!started) {
            if (!isRunSessionActive(runToken)) return
            if (retriesRemaining > 0) {
                handler.postDelayed({
                    dispatchGestureWithRetry(
                        gesture = gesture,
                        runToken = runToken,
                        retriesRemaining = retriesRemaining - 1,
                        retryDelayMillis = retryDelayMillis,
                        onDone = onDone,
                    )
                }, retryDelayMillis)
            } else {
                if (isRunSessionActive(runToken)) onDone()
            }
        }
    }

    private fun replayRecordedSegment(segment: RecordedSegment, onDone: () -> Unit = {}) {
        if (segment.points.isEmpty()) {
            onDone()
            return
        }
        val (screenWidth, screenHeight) = screenSize()
        val path = Path()
        segment.points.forEachIndexed { index, point ->
            val x = point.x.coerceIn(0f, 1f) * screenWidth
            val y = point.y.coerceIn(0f, 1f) * screenHeight
            if (index == 0) {
                path.moveTo(x, y)
            } else {
                path.lineTo(x, y)
            }
        }
        if (segment.points.size == 1) {
            val point = segment.points.first()
            path.lineTo(
                (point.x.coerceIn(0f, 1f) * screenWidth) + 0.1f,
                point.y.coerceIn(0f, 1f) * screenHeight,
            )
        }
        val duration = segment.duration.coerceAtLeast(80L)
        val gesture = try {
            GestureDescription.Builder()
                .addStroke(GestureDescription.StrokeDescription(path, 0, duration))
                .build()
        } catch (_: Exception) {
            onDone()
            return
        }
        dispatchRecordingReplayGesture(gesture, retriesRemaining = 2, retryDelayMillis = 180L, onDone = onDone)
    }

    private fun dispatchRecordingReplayGesture(
        gesture: GestureDescription,
        retriesRemaining: Int,
        retryDelayMillis: Long,
        onDone: () -> Unit,
    ) {
        val started = try {
            dispatchGesture(
                gesture,
                object : GestureResultCallback() {
                    override fun onCompleted(gestureDescription: GestureDescription?) {
                        onDone()
                    }

                    override fun onCancelled(gestureDescription: GestureDescription?) {
                        if (retriesRemaining > 0) {
                            handler.postDelayed({
                                dispatchRecordingReplayGesture(
                                    gesture = gesture,
                                    retriesRemaining = retriesRemaining - 1,
                                    retryDelayMillis = retryDelayMillis,
                                    onDone = onDone,
                                )
                            }, retryDelayMillis)
                        } else {
                            onDone()
                        }
                    }
                },
                null,
            )
        } catch (_: Exception) {
            false
        }
        if (!started) {
            if (retriesRemaining > 0) {
                handler.postDelayed({
                    dispatchRecordingReplayGesture(
                        gesture = gesture,
                        retriesRemaining = retriesRemaining - 1,
                        retryDelayMillis = retryDelayMillis,
                        onDone = onDone,
                    )
                }, retryDelayMillis)
            } else {
                onDone()
            }
        }
    }

    private fun addRecordedStrokes(
        builder: GestureDescription.Builder,
        action: Map<String, Any?>,
        width: Float,
        height: Float,
    ): Boolean {
        val segments = asMapList(action["segments"])
            .sortedBy { segmentStartMillis(it) }
            .take(20)
        if (segments.isEmpty()) return false

        var added = false
        segments.forEach { segment ->
            val points = asMapList(segment["points"])
                .sortedBy { (it["t"] as? Number)?.toLong() ?: 0L }
            if (points.isEmpty()) return@forEach

            val path = Path()
            points.forEachIndexed { index, point ->
                val x = ((point["x"] as? Number)?.toFloat() ?: 0.5f) * width
                val y = ((point["y"] as? Number)?.toFloat() ?: 0.5f) * height
                if (index == 0) {
                    path.moveTo(x, y)
                } else {
                    path.lineTo(x, y)
                }
            }

            val start = segmentStartMillis(segment)
            val duration = segmentDurationMillis(segment, start)
            try {
                builder.addStroke(GestureDescription.StrokeDescription(path, start, duration))
                added = true
            } catch (_: Exception) {
                // Ignore only the invalid segment; later segments may still be usable.
            }
        }
        return added
    }

    private fun segmentStartMillis(segment: Map<String, Any?>): Long {
        val points = asMapList(segment["points"])
        val pointStart = points.minOfOrNull { (it["t"] as? Number)?.toLong() ?: Long.MAX_VALUE }
            ?.takeIf { it != Long.MAX_VALUE }
        return (pointStart ?: ((segment["start"] as? Number)?.toLong() ?: 0L)).coerceAtLeast(0L)
    }

    private fun segmentDurationMillis(segment: Map<String, Any?>, start: Long = segmentStartMillis(segment)): Long {
        val points = asMapList(segment["points"])
        val pointEnd = points.maxOfOrNull { (it["t"] as? Number)?.toLong() ?: Long.MIN_VALUE }
            ?.takeIf { it != Long.MIN_VALUE }
        val rawDuration = if (pointEnd != null) {
            (pointEnd - start).coerceAtLeast(50L)
        } else {
            ((segment["duration"] as? Number)?.toLong() ?: 80L).coerceAtLeast(50L)
        }
        return rawDuration.coerceAtLeast(50L)
    }

    private fun showPickerOverlay(pickerType: String) {
        if (pickerOverlay != null) removePickerOverlay()
        if (pickerType == "record") {
            showRecordingOverlay()
            return
        }
        if (pickerType == "unlockRecord") {
            showUnlockRecordIntroOverlay()
            return
        }
        if (pickerType == "clickSteps") {
            showClickStepsOverlay()
            return
        }
        if (pickerType == "buttonDetect") {
            showButtonDetectOverlay()
            return
        }
        if (pickerType == "imageButtonDetect") {
            showImageButtonDetectOverlay()
            return
        }

        pickerMode = pickerType
        pickerData.clear()

        val lp = fullScreenOverlayParams()

        val container = FrameLayout(this).apply {
            setBackgroundColor(0x22000000)
        }

        if (pickerType == "click") {
            val marker = createPickerMarker("点击", 0xFF2196F3.toInt())
            container.addView(marker, FrameLayout.LayoutParams(dp(72), dp(72)))
            setupDraggableMarker(marker, 0.5f, 0.5f) { x, y ->
                pickerData["x1"] = x
                pickerData["y1"] = y
            }
        } else {
            val startMarker = createPickerMarker("起点", 0xFF4CAF50.toInt())
            val endMarker = createPickerMarker("终点", 0xFFF44336.toInt())
            container.addView(startMarker, FrameLayout.LayoutParams(dp(72), dp(72)))
            container.addView(endMarker, FrameLayout.LayoutParams(dp(72), dp(72)))
            setupDraggableMarker(startMarker, 0.5f, 0.42f) { x, y ->
                pickerData["x1"] = x
                pickerData["y1"] = y
            }
            setupDraggableMarker(endMarker, 0.5f, 0.62f) { x, y ->
                pickerData["x2"] = x
                pickerData["y2"] = y
            }
        }

        container.addView(createPickerControls(), FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            dp(52),
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            topMargin = dp(36)
        })

        try {
            windowManager?.addView(container, lp)
            pickerOverlay = container
        } catch (_: Exception) {
            pickerMode = null
            publishPickerResult(mapOf("cancelled" to true))
        }
    }

    private fun createPickerControls(): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(dp(8), dp(6), dp(8), dp(6))
            background = roundedBackground(0xDD151A1E.toInt(), dp(24).toFloat(), 0x55FFFFFF)
        }
        row.addView(menuButton("保存位置", 0xFF4CAF50.toInt()) {
            finishPositionPicker()
        }, LinearLayout.LayoutParams(dp(92), dp(40)).apply {
            marginEnd = dp(8)
        })
        row.addView(menuButton("取消", 0xFFFF8A80.toInt()) {
            removePickerOverlay()
            publishPickerResult(mapOf("cancelled" to true))
        }, LinearLayout.LayoutParams(dp(72), dp(40)))
        return row
    }

    private fun finishPositionPicker() {
        val mode = pickerMode ?: return
        val (screenWidth, screenHeight) = screenSize()
        val result = mutableMapOf<String, Any?>(
            "type" to mode,
            "screenWidth" to screenWidth,
            "screenHeight" to screenHeight
        )
        pickerData.forEach { (key, value) ->
            result[key] = value.toDouble()
        }
        publishPickerResult(result)
        removePickerOverlay()
    }

    private fun publishPickerResult(result: Map<String, Any?>) {
        val nativeCallback = nativePickerResult
        if (nativeCallback != null) {
            nativePickerResult = null
            nativeCallback(result)
            return
        }
        onPickerResult?.invoke(result)
    }

    private fun showUnlockRecordIntroOverlay() {
        pickerMode = "unlockRecord"
        showCenteredPickerMessage(
            title = "锁屏执行",
            message = "如果你要在锁屏状态下执行任务，需要先录制一次解锁脚本。录制过程会记录你点亮屏幕后滑动、输入密码直到进入桌面的手势。",
            primaryText = "继续",
            secondaryText = "取消",
            onPrimary = { showUnlockRecordReadyOverlay() },
            onSecondary = {
                removePickerOverlay()
                publishPickerResult(mapOf("cancelled" to true))
            },
        )
    }

    private fun showUnlockRecordReadyOverlay() {
        showCenteredPickerMessage(
            title = "开始录制",
            message = "准备好后点击开始录制。下一步会让你锁屏，然后点亮手机并录制解锁手势。",
            primaryText = "开始录制",
            secondaryText = "取消",
            onPrimary = { showUnlockRecordLockOverlay() },
            onSecondary = {
                removePickerOverlay()
                publishPickerResult(mapOf("cancelled" to true))
            },
        )
    }

    private fun showUnlockRecordLockOverlay() {
        showCenteredPickerMessage(
            title = "锁屏录制",
            message = "点击锁屏后手机会熄屏。之后你点亮手机，会看到录制手势按钮。",
            primaryText = "锁屏",
            secondaryText = "取消",
            onPrimary = {
                showUnlockRecordStepOverlay()
                performLockScreenAction {}
            },
            onSecondary = {
                removePickerOverlay()
                publishPickerResult(mapOf("cancelled" to true))
            },
        )
    }

    private fun showUnlockRecordStepOverlay() {
        unlockRecordWaitingForRecord = true
        showCenteredPickerMessage(
            title = "步骤",
            message = "点亮手机后点击录制手势，然后完成滑动解锁和密码输入。进入桌面后会自动结束录制。",
            primaryText = "录制手势",
            secondaryText = "取消",
            onPrimary = {
                unlockRecordWaitingForRecord = false
                detachPickerOverlayView()
                startUnlockMotionRecording()
            },
            onSecondary = {
                unlockRecordWaitingForRecord = false
                removePickerOverlay()
                publishPickerResult(mapOf("cancelled" to true))
            },
        )
    }

    private fun showCenteredPickerMessage(
        title: String,
        message: String,
        primaryText: String,
        secondaryText: String,
        onPrimary: () -> Unit,
        onSecondary: () -> Unit,
    ) {
        removePickerOverlay()
        val lp = fullScreenOverlayParams(focusable = true)
        val root = FrameLayout(this).apply {
            setBackgroundColor(0x55000000)
            isClickable = true
            isFocusable = true
        }
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(16), dp(18), dp(16))
            background = roundedBackground(0xF21F252B.toInt(), dp(18).toFloat(), 0x44FFFFFF)
        }
        panel.addView(TextView(this).apply {
            text = title
            textSize = 17f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
        })
        panel.addView(TextView(this).apply {
            text = message
            textSize = 13f
            setTextColor(0xFFD6DEE4.toInt())
            setPadding(0, dp(10), 0, dp(14))
        })
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
        }
        row.addView(menuButton(secondaryText, 0xFFFF8A80.toInt(), onSecondary), LinearLayout.LayoutParams(0, dp(42), 1f).apply {
            marginEnd = dp(10)
        })
        row.addView(menuButton(primaryText, 0xFF4CAF50.toInt(), onPrimary), LinearLayout.LayoutParams(0, dp(42), 1f))
        panel.addView(row)
        root.addView(panel, FrameLayout.LayoutParams((resources.displayMetrics.widthPixels - dp(48)).coerceAtMost(dp(420)), FrameLayout.LayoutParams.WRAP_CONTENT).apply {
            gravity = Gravity.CENTER
        })
        try {
            windowManager?.addView(root, lp)
            pickerOverlay = root
        } catch (_: Exception) {
            publishPickerResult(mapOf("cancelled" to true))
        }
    }

    private fun showRecordingOverlay(autoStart: Boolean = false, autoStopOnHome: Boolean = false) {
        detachPickerOverlayView()
        pickerMode = if (autoStopOnHome) "unlockRecordCapture" else "recorded"
        val lp = fullScreenOverlayParams()

        lateinit var container: FrameLayout
        lateinit var surface: RecordingSurface
        container = FrameLayout(this).apply {
            setBackgroundColor(if (autoStopOnHome) Color.TRANSPARENT else 0x33000000)
        }
        surface = RecordingSurface(
            context = this,
            drawEnabled = !autoStopOnHome,
            onSegmentFinished = { segment ->
                if (autoStopOnHome) {
                    handler.postDelayed({ replayRecordedSegment(segment) }, 90)
                } else {
                    detachPickerOverlayView()
                    handler.postDelayed({
                        replayRecordedSegment(segment) {
                            handler.postDelayed({
                                if (pickerMode == "recorded" &&
                                    activeRecordingSurface === surface &&
                                    pickerOverlay == null
                                ) {
                                    try {
                                        windowManager?.addView(container, lp)
                                        pickerOverlay = container
                                    } catch (_: Exception) {
                                    }
                                }
                            }, 120L)
                        }
                    }, 180L)
                }
            },
        )
        activeRecordingSurface = surface
        activeRecordingAutoStopOnHome = autoStopOnHome
        unlockRecordFinalizing = false
        container.addView(surface, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
        ))

        val controls = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(dp(6), dp(5), dp(6), dp(5))
            background = roundedBackground(0xDD151A1E.toInt(), dp(24).toFloat(), 0x55FFFFFF)
        }
        val recordButton = menuButton("开始录制", 0xFFFF4444.toInt()) {}
        val cancelButton = menuButton("取消", 0xFF607D8B.toInt()) {
            removePickerOverlay()
            publishPickerResult(mapOf("cancelled" to true))
        }
        var recording = autoStart
        val timer = object : Runnable {
            override fun run() {
                if (!recording) return
                recordButton.text = if (autoStopOnHome) {
                    "录制 ${formatElapsed(surface.elapsedMillis())}"
                } else {
                    "保存 ${formatElapsed(surface.elapsedMillis())}"
                }
                handler.postDelayed(this, 200)
            }
        }
        recordButton.setOnClickListener {
            if (!recording) {
                recording = true
                surface.startRecording()
                recordButton.text = if (autoStopOnHome) "录制 00:00" else "保存 00:00"
                handler.post(timer)
            } else {
                if (autoStopOnHome) return@setOnClickListener
                if (!surface.hasGesture()) {
                    recordButton.text = "请先触摸屏幕"
                    handler.postDelayed({
                        if (recording) {
                            recordButton.text = "保存 ${formatElapsed(surface.elapsedMillis())}"
                        }
                    }, 900)
                    return@setOnClickListener
                }
                recording = false
                publishPickerResult(surface.exportResult())
                removePickerOverlay()
            }
        }
        controls.addView(recordButton, LinearLayout.LayoutParams(if (autoStopOnHome) dp(104) else dp(126), dp(38)).apply {
            marginEnd = dp(8)
        })
        controls.addView(cancelButton, LinearLayout.LayoutParams(dp(64), dp(38)))
        container.addView(controls, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            dp(48),
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            topMargin = dp(12)
        })

        try {
            windowManager?.addView(container, lp)
            pickerOverlay = container
            if (autoStart) {
                surface.startRecording()
                recordButton.text = "录制 00:00"
                handler.post(timer)
            }
        } catch (_: Exception) {
            pickerMode = null
            activeRecordingSurface = null
            activeRecordingAutoStopOnHome = false
            publishPickerResult(mapOf("cancelled" to true))
        }
    }

    private fun startUnlockMotionRecording() {
        removePickerOverlay()
        pickerMode = "unlockMotionRecord"
        unlockRecordFinalizing = false
        unlockMotionTrailSegments.clear()
        unlockMotionRecorder = MotionEventRecorder().apply { startRecording() }
        unlockMotionStartedAt = SystemClock.elapsedRealtime()
        ensureUnlockMotionTrailOverlay()
        ensureUnlockMotionCaptureOverlay()
        showUnlockMotionControl()
        startUnlockMotionTicker()
    }

    private fun ensureUnlockMotionCaptureOverlay() {
        if (unlockMotionCaptureOverlay != null) {
            attachUnlockMotionCaptureOverlay()
            return
        }
        unlockMotionCaptureOverlay = object : View(this) {
            override fun onTouchEvent(event: MotionEvent): Boolean {
                val recorder = unlockMotionRecorder ?: return true
                val location = IntArray(2)
                getLocationOnScreen(location)
                val (screenWidth, screenHeight) = screenSize()
                val segment = recorder.onMotionEvent(
                    event = event,
                    screenWidth = screenWidth,
                    screenHeight = screenHeight,
                    offsetX = location[0].toFloat(),
                    offsetY = location[1].toFloat(),
                )
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> detachUnlockMotionControl()
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                        if (segment != null) {
                            handleUnlockMotionSegment(segment)
                        } else if (unlockMotionRecorder != null && !unlockRecordFinalizing) {
                            attachUnlockMotionControl()
                        }
                    }
                }
                return true
            }
        }
        attachUnlockMotionCaptureOverlay()
    }

    private fun attachUnlockMotionCaptureOverlay() {
        val view = unlockMotionCaptureOverlay ?: return
        if (unlockMotionCaptureVisible) return
        val lp = fullScreenOverlayParams().apply {
            flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
        }
        try {
            windowManager?.addView(view, lp)
            unlockMotionCaptureVisible = true
        } catch (_: Exception) {
            unlockMotionCaptureVisible = false
        }
    }

    private fun detachUnlockMotionCaptureOverlay() {
        val view = unlockMotionCaptureOverlay ?: return
        if (!unlockMotionCaptureVisible) return
        try {
            windowManager?.removeView(view)
        } catch (_: Exception) {
        }
        unlockMotionCaptureVisible = false
    }

    private fun removeUnlockMotionCaptureOverlay() {
        detachUnlockMotionCaptureOverlay()
        unlockMotionCaptureOverlay = null
    }

    private fun handleUnlockMotionSegment(segment: RecordedSegment) {
        showUnlockMotionTrail(segment)
        detachUnlockMotionControl()
        detachUnlockMotionCaptureOverlay()
        handler.postDelayed({
            replayRecordedSegment(segment) {
                handler.postDelayed({
                    if (unlockMotionRecorder != null && !unlockRecordFinalizing) {
                        attachUnlockMotionCaptureOverlay()
                        attachUnlockMotionControl()
                    }
                }, 120L)
            }
        }, 180L)
    }

    private fun showUnlockMotionControl() {
        if (unlockMotionControl != null) {
            attachUnlockMotionControl()
            return
        }
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8), dp(5), dp(8), dp(5))
            background = roundedBackground(0xDD151A1E.toInt(), dp(18).toFloat(), 0x55FFFFFF)
        }
        val status = TextView(this).apply {
            text = "录制 00:00:00"
            textSize = 11f
            setTextColor(Color.WHITE)
            includeFontPadding = false
            typeface = Typeface.MONOSPACE
            minWidth = dp(112)
        }
        unlockMotionStatusView = status
        root.addView(status, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            dp(32),
        ).apply {
            marginEnd = dp(8)
        })
        root.addView(menuButton("结束", 0xFF4CAF50.toInt()) {
            stopUnlockMotionRecording(cancelled = false)
        }, LinearLayout.LayoutParams(dp(58), dp(34)).apply {
            marginEnd = dp(8)
        })
        root.addView(menuButton("取消", 0xFFFF8A80.toInt()) {
            stopUnlockMotionRecording(cancelled = true)
        }, LinearLayout.LayoutParams(dp(58), dp(34)))

        unlockMotionControl = root
        unlockMotionControlParams = baseOverlayParams().apply {
            flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
            width = WindowManager.LayoutParams.WRAP_CONTENT
            height = WindowManager.LayoutParams.WRAP_CONTENT
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            x = 0
            y = dp(12)
        }
        attachUnlockMotionControl()
    }

    private fun attachUnlockMotionControl() {
        val view = unlockMotionControl ?: return
        val params = unlockMotionControlParams ?: return
        if (unlockMotionControlVisible) return
        updateUnlockMotionStatus()
        try {
            windowManager?.addView(view, params)
            unlockMotionControlVisible = true
        } catch (_: Exception) {
            unlockMotionControlVisible = false
        }
    }

    private fun detachUnlockMotionControl() {
        val view = unlockMotionControl ?: return
        if (!unlockMotionControlVisible) return
        try {
            windowManager?.removeView(view)
        } catch (_: Exception) {
        }
        unlockMotionControlVisible = false
    }

    private fun stopUnlockMotionRecording(cancelled: Boolean) {
        stopUnlockMotionTicker()
        removeUnlockMotionCaptureOverlay()
        detachUnlockMotionControl()
        removeUnlockMotionTrailOverlay()
        unlockMotionControl = null
        unlockMotionControlParams = null
        unlockMotionStatusView = null
        val recorder = unlockMotionRecorder
        unlockMotionRecorder = null
        pickerMode = null
        unlockRecordFinalizing = false
        if (cancelled || recorder == null || !recorder.hasGesture()) {
            publishPickerResult(mapOf("cancelled" to true))
            return
        }
        val result = recorder.exportResult()
        showCenteredPickerMessage(
            title = "保存解锁脚本",
            message = "已经检测到进入桌面，是否保存这次锁屏解锁录制？",
            primaryText = "保存",
            secondaryText = "取消",
            onPrimary = {
                removePickerOverlay()
                publishPickerResult(result)
            },
            onSecondary = {
                removePickerOverlay()
                publishPickerResult(mapOf("cancelled" to true))
            },
        )
    }

    private fun startUnlockMotionTicker() {
        stopUnlockMotionTicker()
        val ticker = object : Runnable {
            override fun run() {
                if (unlockMotionRecorder == null || unlockMotionStartedAt == 0L) return
                updateUnlockMotionStatus()
                handler.postDelayed(this, 50)
            }
        }
        unlockMotionTicker = ticker
        handler.post(ticker)
    }

    private fun updateUnlockMotionStatus() {
        val started = unlockMotionStartedAt
        if (started == 0L) return
        unlockMotionStatusView?.let { statusView ->
            statusView.text =
                "录制 ${formatElapsedTenths((SystemClock.elapsedRealtime() - started).coerceAtLeast(0L))}"
            statusView.requestLayout()
            statusView.invalidate()
        }
    }

    private fun stopUnlockMotionTicker() {
        unlockMotionTicker?.let { handler.removeCallbacks(it) }
        unlockMotionTicker = null
        unlockMotionStartedAt = 0L
    }

    private fun ensureUnlockMotionTrailOverlay() {
        if (unlockMotionTrailOverlay != null) {
            attachUnlockMotionTrailOverlay()
            return
        }
        unlockMotionTrailOverlay = object : View(this) {
            private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = 0xFF40C4FF.toInt()
                style = Paint.Style.STROKE
                strokeWidth = 4f * resources.displayMetrics.density
                strokeCap = Paint.Cap.ROUND
                strokeJoin = Paint.Join.ROUND
            }
            private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = 0xFF40C4FF.toInt()
                style = Paint.Style.FILL
            }
            private val number = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.WHITE
                textAlign = Paint.Align.CENTER
                textSize = 11f * resources.displayMetrics.scaledDensity
                typeface = Typeface.DEFAULT_BOLD
            }

            override fun onDraw(canvas: Canvas) {
                super.onDraw(canvas)
                val location = IntArray(2)
                getLocationOnScreen(location)
                val (screenWidth, screenHeight) = screenSize()
                val widthScale = screenWidth.coerceAtLeast(1).toFloat()
                val heightScale = screenHeight.coerceAtLeast(1).toFloat()
                unlockMotionTrailSegments.forEachIndexed { index, segment ->
                    if (segment.points.isEmpty()) return@forEachIndexed
                    val path = Path()
                    segment.points.forEachIndexed { pointIndex, item ->
                        val x = item.x * widthScale - location[0]
                        val y = item.y * heightScale - location[1]
                        if (pointIndex == 0) path.moveTo(x, y) else path.lineTo(x, y)
                    }
                    canvas.drawPath(path, stroke)
                    val first = segment.points.first()
                    val cx = first.x * widthScale - location[0]
                    val cy = first.y * heightScale - location[1]
                    val radius = 10f * resources.displayMetrics.density
                    canvas.drawCircle(cx, cy, radius, fill)
                    val baseline = cy - (number.descent() + number.ascent()) / 2
                    canvas.drawText("${index + 1}", cx, baseline, number)
                }
            }
        }
        attachUnlockMotionTrailOverlay()
    }

    private fun attachUnlockMotionTrailOverlay() {
        val view = unlockMotionTrailOverlay ?: return
        if (unlockMotionTrailVisible) {
            view.invalidate()
            return
        }
        val lp = fullScreenOverlayParams().apply {
            flags = flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        }
        try {
            windowManager?.addView(view, lp)
            unlockMotionTrailVisible = true
        } catch (_: Exception) {
            unlockMotionTrailVisible = false
        }
    }

    private fun removeUnlockMotionTrailOverlay() {
        val view = unlockMotionTrailOverlay
        if (view != null && unlockMotionTrailVisible) {
            try {
                windowManager?.removeView(view)
            } catch (_: Exception) {
            }
        }
        unlockMotionTrailOverlay = null
        unlockMotionTrailVisible = false
        unlockMotionTrailSegments.clear()
    }

    private fun showClickStepsOverlay() {
        pickerMode = "clickSteps"
        val lp = fullScreenOverlayParams()

        lateinit var container: FrameLayout
        lateinit var surface: ClickStepSurface
        container = FrameLayout(this).apply {
            setBackgroundColor(0x22000000)
        }
        surface = ClickStepSurface(this) { point ->
            val segment = RecordedSegment(
                start = 0L,
                duration = 80L,
                points = mutableListOf(RecordedPoint(point.x, point.y, 0L)),
            )
            detachPickerOverlayView()
            handler.postDelayed({
                replayRecordedSegment(segment) {
                    handler.postDelayed({
                        if (pickerMode == "clickSteps" && pickerOverlay == null) {
                            try {
                                windowManager?.addView(container, lp)
                                pickerOverlay = container
                            } catch (_: Exception) {
                            }
                        }
                    }, 120L)
                }
            }, 160L)
        }
        container.addView(surface, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
        ))

        val controls = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(dp(8), dp(6), dp(8), dp(6))
            background = roundedBackground(0xDD151A1E.toInt(), dp(24).toFloat(), 0x55FFFFFF)
        }
        val saveButton = menuButton("保存", 0xFF4CAF50.toInt()) {
            if (!surface.hasPoints()) {
                return@menuButton
            }
            publishPickerResult(
                mapOf(
                    "type" to "clickSteps",
                    "points" to surface.exportPoints(),
                ),
            )
            removePickerOverlay()
        }
        val deleteButton = menuButton("删除", 0xFFFFB74D.toInt()) {
            surface.deleteSelectedOrLast()
        }
        val cancelButton = menuButton("取消", 0xFFFF8A80.toInt()) {
            publishPickerResult(mapOf("cancelled" to true))
            removePickerOverlay()
        }
        controls.addView(saveButton, LinearLayout.LayoutParams(dp(72), dp(40)).apply {
            marginEnd = dp(8)
        })
        controls.addView(deleteButton, LinearLayout.LayoutParams(dp(72), dp(40)).apply {
            marginEnd = dp(8)
        })
        controls.addView(cancelButton, LinearLayout.LayoutParams(dp(72), dp(40)))
        container.addView(controls, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            dp(52),
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            topMargin = dp(36)
        })

        try {
            windowManager?.addView(container, lp)
            pickerOverlay = container
        } catch (_: Exception) {
            pickerMode = null
            publishPickerResult(mapOf("cancelled" to true))
        }
    }

    private fun showButtonDetectOverlay() {
        pickerMode = "buttonDetect"
        val nodes = collectButtonNodes(rootInActiveWindow)
        val lp = fullScreenOverlayParams()

        val container = FrameLayout(this).apply {
            setBackgroundColor(Color.TRANSPARENT)
        }
        val (screenWidth, screenHeight) = screenSize()
        val surface = ButtonDetectSurface(this, nodes) { node ->
            publishPickerResult(node.toResult(screenWidth, screenHeight))
            removePickerOverlay()
        }
        container.addView(surface, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
        ))

        val controls = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(dp(8), dp(6), dp(8), dp(6))
            background = roundedBackground(0xDD151A1E.toInt(), dp(24).toFloat(), 0x55FFFFFF)
        }
        controls.addView(TextView(this).apply {
            text = "点击红框按钮"
            textSize = 12f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
        }, LinearLayout.LayoutParams(dp(118), dp(40)).apply {
            marginEnd = dp(8)
        })
        controls.addView(menuButton("取消", 0xFFFF8A80.toInt()) {
            publishPickerResult(mapOf("cancelled" to true))
            removePickerOverlay()
        }, LinearLayout.LayoutParams(dp(72), dp(40)))
        container.addView(controls, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            dp(52),
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            topMargin = dp(36)
        })

        try {
            windowManager?.addView(container, lp)
            pickerOverlay = container
        } catch (_: Exception) {
            pickerMode = null
            publishPickerResult(mapOf("cancelled" to true))
        }
    }

    private fun showImageButtonDetectOverlay() {
        pickerMode = "imageButtonDetect"
        showImageTemplateSelectOverlay()
    }

    private fun showImageTemplateSelectOverlay() {
        detachPickerOverlayView()
        pickerMode = "imageButtonDetect"
        val lp = fullScreenOverlayParams()
        val container = FrameLayout(this).apply {
            setBackgroundColor(0x11000000)
        }
        val surface = ImageTemplateSelectSurface(this)
        container.addView(surface, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
        ))
        val controls = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(dp(8), dp(6), dp(8), dp(6))
            background = roundedBackground(0xDD151A1E.toInt(), dp(24).toFloat(), 0x55FFFFFF)
        }
        controls.addView(TextView(this).apply {
            text = "拖动框选图片"
            textSize = 12f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
        }, LinearLayout.LayoutParams(dp(118), dp(40)).apply {
            marginEnd = dp(8)
        })
        controls.addView(menuButton("保存", 0xFF4CAF50.toInt()) {
            val rect = surface.selectedScreenRect()
            if (rect == null || rect.width() < dp(12) || rect.height() < dp(12)) {
                return@menuButton
            }
            showLoadingPickerOverlay("正在处理截图...")
            handler.postDelayed({
                captureScreenBitmap(
                    onSuccess = { bitmap ->
                        val result = buildImageTemplateResult(bitmap, rect)
                        bitmap.recycle()
                        removePickerOverlay()
                        publishPickerResult(result ?: mapOf("cancelled" to true))
                    },
                    onFailure = { 
                        removePickerOverlay()
                        publishPickerResult(mapOf("cancelled" to true)) 
                    },
                )
            }, 200L)
        }, LinearLayout.LayoutParams(dp(72), dp(40)).apply {
            marginEnd = dp(8)
        })
        controls.addView(menuButton("取消", 0xFFFF8A80.toInt()) {
            publishPickerResult(mapOf("cancelled" to true))
            removePickerOverlay()
        }, LinearLayout.LayoutParams(dp(72), dp(40)))
        container.addView(controls, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            dp(52),
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            topMargin = dp(36)
        })
        try {
            windowManager?.addView(container, lp)
            pickerOverlay = container
        } catch (_: Exception) {
            pickerMode = null
            publishPickerResult(mapOf("cancelled" to true))
        }
    }

    private fun showLoadingPickerOverlay(message: String) {
        detachPickerOverlayView()
        val lp = fullScreenOverlayParams()
        val container = FrameLayout(this).apply {
            setBackgroundColor(Color.TRANSPARENT)
        }
        container.addView(TextView(this).apply {
            text = message
            textSize = 14f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            background = roundedBackground(0xDD151A1E.toInt(), dp(24).toFloat(), 0x55FFFFFF)
            setPadding(dp(18), dp(10), dp(18), dp(10))
        }, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            dp(52),
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            topMargin = dp(36)
        })
        try {
            windowManager?.addView(container, lp)
            pickerOverlay = container
        } catch (_: Exception) {
            pickerOverlay = null
        }
    }

    private fun showOcrTextDetectOverlay(nodes: List<OcrTextInfo>) {
        detachPickerOverlayView()
        pickerMode = "imageButtonDetect"
        val lp = WindowManager.LayoutParams().apply {
            type = overlayType()
            format = PixelFormat.TRANSLUCENT
            flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
            width = WindowManager.LayoutParams.MATCH_PARENT
            height = WindowManager.LayoutParams.MATCH_PARENT
        }
        val container = FrameLayout(this).apply {
            setBackgroundColor(Color.TRANSPARENT)
        }
        val (screenWidth, screenHeight) = screenSize()
        val surface = OcrTextDetectSurface(this, nodes) { node ->
            publishPickerResult(node.toResult(screenWidth, screenHeight))
            removePickerOverlay()
        }
        container.addView(surface, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
        ))
        val controls = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(dp(8), dp(6), dp(8), dp(6))
            background = roundedBackground(0xDD151A1E.toInt(), dp(24).toFloat(), 0x55FFFFFF)
        }
        controls.addView(TextView(this).apply {
            text = if (nodes.isEmpty()) "未识别到文字" else "点击文字红框"
            textSize = 12f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
        }, LinearLayout.LayoutParams(dp(118), dp(40)).apply {
            marginEnd = dp(8)
        })
        controls.addView(menuButton("取消", 0xFFFF8A80.toInt()) {
            publishPickerResult(mapOf("cancelled" to true))
            removePickerOverlay()
        }, LinearLayout.LayoutParams(dp(72), dp(40)))
        container.addView(controls, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            dp(52),
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            topMargin = dp(36)
        })
        try {
            windowManager?.addView(container, lp)
            pickerOverlay = container
        } catch (_: Exception) {
            pickerMode = null
            publishPickerResult(mapOf("cancelled" to true))
        }
    }

    private fun recognizeScreenText(
        onSuccess: (List<OcrTextInfo>) -> Unit,
        onFailure: () -> Unit,
    ) {
        captureScreenBitmap(
            onSuccess = { bitmap -> recognizeScreenTextFromBitmap(bitmap, onSuccess, onFailure) },
            onFailure = onFailure,
        )
    }

    private fun recognizeScreenTextForMotto(
        region: Map<String, Any?>?,
        onSuccess: (List<OcrTextInfo>) -> Unit,
        onFailure: () -> Unit,
    ) {
        captureScreenBitmap(
            onSuccess = { bitmap ->
                val rect = normalizedRegionToRect(region, bitmap.width, bitmap.height)
                if (rect == null) {
                    recognizeScreenTextFromBitmap(bitmap, onSuccess, onFailure)
                    return@captureScreenBitmap
                }
                val crop = try {
                    Bitmap.createBitmap(bitmap, rect.left, rect.top, rect.width(), rect.height())
                } catch (_: Exception) {
                    bitmap.recycle()
                    onFailure()
                    return@captureScreenBitmap
                }
                bitmap.recycle()
                recognizeScreenTextFromBitmap(
                    crop,
                    onSuccess = { nodes ->
                        onSuccess(nodes.map { it.offset(rect.left, rect.top) })
                    },
                    onFailure = onFailure,
                )
            },
            onFailure = onFailure,
        )
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
        return if (rect.width() >= dp(12) && rect.height() >= dp(12)) rect else null
    }

    private fun captureScreenBitmap(
        onSuccess: (Bitmap) -> Unit,
        onFailure: () -> Unit,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            onFailure()
            return
        }
        try {
            takeScreenshot(
                Display.DEFAULT_DISPLAY,
                mainExecutor,
                object : TakeScreenshotCallback {
                    override fun onSuccess(screenshot: ScreenshotResult) {
                        val bitmap = try {
                            val hardwareBitmap = Bitmap.wrapHardwareBuffer(
                                screenshot.hardwareBuffer,
                                screenshot.colorSpace,
                            )
                            val copy = hardwareBitmap?.copy(Bitmap.Config.ARGB_8888, false)
                            screenshot.hardwareBuffer.close()
                            copy
                        } catch (_: Exception) {
                            try {
                                screenshot.hardwareBuffer.close()
                            } catch (_: Exception) {
                            }
                            null
                        }
                        if (bitmap == null) {
                            onFailure()
                            return
                        }
                        onSuccess(bitmap)
                    }

                    override fun onFailure(errorCode: Int) {
                        onFailure()
                    }
                },
            )
        } catch (_: Exception) {
            onFailure()
        }
    }

    private fun buildImageTemplateResult(bitmap: Bitmap, rect: Rect): Map<String, Any?>? {
        val safe = Rect(
            rect.left.coerceIn(0, bitmap.width - 1),
            rect.top.coerceIn(0, bitmap.height - 1),
            rect.right.coerceIn(1, bitmap.width),
            rect.bottom.coerceIn(1, bitmap.height),
        )
        if (safe.width() < 4 || safe.height() < 4) return null
        val crop = try {
            Bitmap.createBitmap(bitmap, safe.left, safe.top, safe.width(), safe.height())
        } catch (_: Exception) {
            return null
        }
        val out = ByteArrayOutputStream()
        crop.compress(Bitmap.CompressFormat.PNG, 100, out)
        crop.recycle()
        val (screenWidth, screenHeight) = screenSize()
        val encoded = Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
        return mapOf(
            "type" to "buttonRecognize",
            "source" to "imageTemplate",
            "buttonText" to "图片区域",
            "buttonId" to "",
            "buttonDescription" to "图片区域 ${safe.width()}x${safe.height()}",
            "templateImage" to encoded,
            "templateWidth" to safe.width(),
            "templateHeight" to safe.height(),
            "matchMode" to "exact",
            "regionMode" to "full",
            "region" to mapOf(
                "left" to (safe.left.toDouble() / screenWidth.coerceAtLeast(1)),
                "top" to (safe.top.toDouble() / screenHeight.coerceAtLeast(1)),
                "right" to (safe.right.toDouble() / screenWidth.coerceAtLeast(1)),
                "bottom" to (safe.bottom.toDouble() / screenHeight.coerceAtLeast(1)),
            ),
            "bounds" to mapOf(
                "left" to (safe.left.toDouble() / screenWidth.coerceAtLeast(1)),
                "top" to (safe.top.toDouble() / screenHeight.coerceAtLeast(1)),
                "right" to (safe.right.toDouble() / screenWidth.coerceAtLeast(1)),
                "bottom" to (safe.bottom.toDouble() / screenHeight.coerceAtLeast(1)),
            ),
            "successMode" to "defaultClick",
            "retryCount" to 3,
            "retryWaitMillis" to 800,
            "retrySuccessMode" to "defaultClick",
            "failAction" to "notify",
        )
    }

    private fun findBestTemplateMatch(
        screen: Bitmap,
        template: Bitmap,
        region: Rect?,
        savedBounds: Rect?,
    ): ButtonMatchTarget? {
        val search = region ?: Rect(0, 0, screen.width, screen.height)
        val tplW = template.width
        val tplH = template.height
        if (tplW <= 0 || tplH <= 0 || search.width() < tplW || search.height() < tplH) {
            return null
        }
        val stepX = kotlin.math.max(3, tplW / 8)
        val stepY = kotlin.math.max(3, tplH / 8)
        val samplesX = 12
        val samplesY = 12
        val templateSamples = mutableListOf<IntArray>()
        for (sy in 0 until samplesY) {
            for (sx in 0 until samplesX) {
                val tx = ((sx + 0.5f) * tplW / samplesX).toInt().coerceIn(0, tplW - 1)
                val ty = ((sy + 0.5f) * tplH / samplesY).toInt().coerceIn(0, tplH - 1)
                val c = template.getPixel(tx, ty)
                templateSamples.add(intArrayOf(Color.red(c), Color.green(c), Color.blue(c), tx, ty))
            }
        }
        val coarseCandidates = mutableListOf<Pair<Double, Rect>>()

        fun addCandidate(score: Double, rect: Rect) {
            coarseCandidates.add(score to rect)
            coarseCandidates.sortBy { it.first }
            if (coarseCandidates.size > 8) {
                coarseCandidates.removeAt(coarseCandidates.lastIndex)
            }
        }

        var y = search.top.coerceAtLeast(0)
        while (y <= (search.bottom - tplH).coerceAtMost(screen.height - tplH)) {
            var x = search.left.coerceAtLeast(0)
            while (x <= (search.right - tplW).coerceAtMost(screen.width - tplW)) {
                var diff = 0.0
                templateSamples.forEach { sample ->
                    val c = screen.getPixel(x + sample[3], y + sample[4])
                    diff += abs(Color.red(c) - sample[0])
                    diff += abs(Color.green(c) - sample[1])
                    diff += abs(Color.blue(c) - sample[2])
                }
                val score = diff / (templateSamples.size * 3.0 * 255.0)
                addCandidate(score, Rect(x, y, x + tplW, y + tplH))
                x += stepX
            }
            y += stepY
        }

        var bestScore = Double.MAX_VALUE
        var bestRect: Rect? = null
        val refineRadiusX = kotlin.math.max(2, stepX / 2)
        val refineRadiusY = kotlin.math.max(2, stepY / 2)
        coarseCandidates.forEach { (_, candidate) ->
            val minY = (candidate.top - refineRadiusY).coerceAtLeast(search.top).coerceAtLeast(0)
            val maxY = (candidate.top + refineRadiusY)
                .coerceAtMost(search.bottom - tplH)
                .coerceAtMost(screen.height - tplH)
            val minX = (candidate.left - refineRadiusX).coerceAtLeast(search.left).coerceAtLeast(0)
            val maxX = (candidate.left + refineRadiusX)
                .coerceAtMost(search.right - tplW)
                .coerceAtMost(screen.width - tplW)
            var fy = minY
            while (fy <= maxY) {
                var fx = minX
                while (fx <= maxX) {
                    val score = templateDifferenceScore(screen, template, fx, fy)
                    val candidateRect = Rect(fx, fy, fx + tplW, fy + tplH)
                    val distancePenalty = if (savedBounds == null) {
                        0.0
                    } else {
                        centerDistanceSquared(savedBounds, candidateRect).toDouble() /
                            ((screen.width * screen.width + screen.height * screen.height).coerceAtLeast(1).toDouble()) * 0.35
                    }
                    val overlapBonus = if (savedBounds == null) {
                        0.0
                    } else {
                        overlapArea(savedBounds, candidateRect).toDouble() /
                            (savedBounds.width().coerceAtLeast(1) * savedBounds.height().coerceAtLeast(1)).toDouble()
                    }
                    val finalScore = score + distancePenalty - (overlapBonus * 0.18)
                    if (finalScore < bestScore) {
                        bestScore = finalScore
                        bestRect = candidateRect
                        if (bestScore == 0.0) {
                            return ButtonMatchTarget(bestRect!!)
                        }
                    }
                    fx += 2
                }
                fy += 2
            }
        }
        return if (bestScore <= 0.06) bestRect?.let { ButtonMatchTarget(it) } else null
    }

    private fun templateDifferenceScore(screen: Bitmap, template: Bitmap, left: Int, top: Int): Double {
        val targetSamples = 6400.0
        val area = (template.width * template.height).coerceAtLeast(1).toDouble()
        val stride = kotlin.math.max(1, kotlin.math.ceil(kotlin.math.sqrt(area / targetSamples)).toInt())
        var diff = 0.0
        var count = 0
        var y = 0
        while (y < template.height) {
            var x = 0
            while (x < template.width) {
                val a = template.getPixel(x, y)
                val b = screen.getPixel(left + x, top + y)
                val dr = abs(Color.red(a) - Color.red(b))
                val dg = abs(Color.green(a) - Color.green(b))
                val db = abs(Color.blue(a) - Color.blue(b))
                val luminanceA = (Color.red(a) * 0.299 + Color.green(a) * 0.587 + Color.blue(a) * 0.114)
                val luminanceB = (Color.red(b) * 0.299 + Color.green(b) * 0.587 + Color.blue(b) * 0.114)
                val dl = abs(luminanceA - luminanceB)
                diff += dr + dg + db + dl
                count += 1
                x += stride
            }
            y += stride
        }
        return diff / (count.coerceAtLeast(1) * 4.0 * 255.0)
    }

    private fun recognizeScreenTextFromBitmap(
        bitmap: Bitmap,
        onSuccess: (List<OcrTextInfo>) -> Unit,
        onFailure: () -> Unit,
    ) {
        val recognizer = TextRecognition.getClient(
            ChineseTextRecognizerOptions.Builder().build(),
        )
        val enhancedBitmap = preprocessOcrBitmap(bitmap)
        val collected = linkedMapOf<String, OcrTextInfo>()

        fun collect(result: com.google.mlkit.vision.text.Text) {
            result.textBlocks.forEach { block ->
                block.lines.forEach { line ->
                    val rect = line.boundingBox ?: return@forEach
                    val value = line.text.trim()
                    if (value.isNotBlank() && rect.width() > dp(8) && rect.height() > dp(8)) {
                        val key = "${rect.flattenToString()}|$value"
                        collected[key] = OcrTextInfo(rect, value)
                    }
                }
            }
        }

        recognizer.process(InputImage.fromBitmap(bitmap, 0))
            .addOnSuccessListener { original ->
                collect(original)
                recognizer.process(InputImage.fromBitmap(enhancedBitmap, 0))
                    .addOnSuccessListener { enhanced ->
                        collect(enhanced)
                        onSuccess(collected.values.toList())
                    }
                    .addOnFailureListener {
                        if (collected.isNotEmpty()) {
                            onSuccess(collected.values.toList())
                        } else {
                            onFailure()
                        }
                    }
                    .addOnCompleteListener {
                        enhancedBitmap.recycle()
                        bitmap.recycle()
                    }
            }
            .addOnFailureListener {
                recognizer.process(InputImage.fromBitmap(enhancedBitmap, 0))
                    .addOnSuccessListener { enhanced ->
                        collect(enhanced)
                        onSuccess(collected.values.toList())
                    }
                    .addOnFailureListener { onFailure() }
                    .addOnCompleteListener {
                        enhancedBitmap.recycle()
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
                0f, 0f, contrast, 0f, translate,
                0f, 0f, 0f, 1f, 0f,
            ),
        )
        matrix.postConcat(contrastMatrix)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            colorFilter = ColorMatrixColorFilter(matrix)
        }
        canvas.drawColor(Color.WHITE)
        canvas.drawBitmap(source, 0f, 0f, paint)

        for (x in 0 until output.width step 2) {
            for (y in 0 until output.height step 2) {
                val pixel = output.getPixel(x, y)
                val luminance = (Color.red(pixel) + Color.green(pixel) + Color.blue(pixel)) / 3
                val bw = if (luminance > 168) 255 else 0
                output.setPixel(x, y, Color.rgb(bw, bw, bw))
                if (x + 1 < output.width) output.setPixel(x + 1, y, Color.rgb(bw, bw, bw))
                if (y + 1 < output.height) output.setPixel(x, y + 1, Color.rgb(bw, bw, bw))
                if (x + 1 < output.width && y + 1 < output.height) {
                    output.setPixel(x + 1, y + 1, Color.rgb(bw, bw, bw))
                }
            }
        }
        return output
    }

    private fun collectButtonNodes(root: AccessibilityNodeInfo?): List<ButtonNodeInfo> {
        if (root == null) return emptyList()
        val out = mutableListOf<ButtonNodeInfo>()
        val seen = mutableSetOf<String>()

        fun collectNodeText(node: AccessibilityNodeInfo?, depth: Int = 0): String {
            if (node == null || depth > 3) return ""
            val parts = mutableListOf<String>()
            node.text?.toString()?.trim()?.takeIf { it.isNotBlank() }?.let(parts::add)
            node.contentDescription?.toString()?.trim()?.takeIf { it.isNotBlank() }?.let(parts::add)
            for (index in 0 until node.childCount) {
                val childText = collectNodeText(node.getChild(index), depth + 1)
                if (childText.isNotBlank()) {
                    parts.add(childText)
                }
            }
            return parts.distinct().joinToString(" ")
        }

        fun nearestViewId(node: AccessibilityNodeInfo?): String {
            var current = node
            repeat(4) {
                val id = current?.viewIdResourceName?.trim().orEmpty()
                if (id.isNotBlank()) return id
                current = current?.parent
            }
            return ""
        }

        fun nearestClickableNode(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
            var current = node
            repeat(5) {
                if (current?.isClickable == true) return current
                current = current?.parent
            }
            return null
        }

        fun visit(node: AccessibilityNodeInfo?) {
            if (node == null) return
            val clickableNode = nearestClickableNode(node)
            val actionableNode = clickableNode ?: node
            val rect = Rect()
            actionableNode.getBoundsInScreen(rect)
            val text = collectNodeText(node)
            val description = node.contentDescription?.toString().orEmpty()
            val viewId = nearestViewId(actionableNode)
            val className = actionableNode.className?.toString().orEmpty()
            val looksLikeButton = actionableNode.isClickable ||
                className.contains("Button", ignoreCase = true) ||
                className.contains("ImageView", ignoreCase = true) ||
                className.contains("TextView", ignoreCase = true) && (text.isNotBlank() || description.isNotBlank())
            if (actionableNode.isVisibleToUser &&
                looksLikeButton &&
                rect.width() > dp(16) &&
                rect.height() > dp(16) &&
                rect.left >= 0 &&
                rect.top >= 0
            ) {
                val key = "${rect.flattenToString()}|$text|$description|$viewId"
                if (seen.add(key)) {
                    out.add(
                        ButtonNodeInfo(
                            bounds = Rect(rect),
                            text = text,
                            viewId = viewId,
                            description = description,
                            className = className,
                            accessibilityNode = try {
                                AccessibilityNodeInfo.obtain(actionableNode)
                            } catch (_: Exception) {
                                null
                            },
                        ),
                    )
                }
            }
            for (index in 0 until node.childCount) {
                visit(node.getChild(index))
            }
        }

        visit(root)
        return out.sortedWith(compareBy<ButtonNodeInfo> { it.bounds.top }.thenBy { it.bounds.left })
    }

    private fun createPickerMarker(label: String, color: Int): View {
        return FrameLayout(this).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(color and 0x88FFFFFF.toInt())
                setStroke(dp(2), color)
            }
            addView(TextView(context).apply {
                text = label
                setTextColor(Color.WHITE)
                textSize = 11f
                gravity = Gravity.CENTER
            }, FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ))
        }
    }

    private fun setupDraggableMarker(
        view: View,
        initialX: Float,
        initialY: Float,
        onPosChanged: (Float, Float) -> Unit,
    ) {
        val dm = resources.displayMetrics
        view.setOnTouchListener { v, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> true
                MotionEvent.ACTION_MOVE -> {
                    v.x = event.rawX - v.width / 2f
                    v.y = event.rawY - v.height / 2f
                    onPosChanged(
                        (event.rawX / dm.widthPixels).coerceIn(0f, 1f),
                        (event.rawY / dm.heightPixels).coerceIn(0f, 1f),
                    )
                    true
                }
                else -> true
            }
        }
        handler.post {
            view.x = initialX * dm.widthPixels - view.width / 2f
            view.y = initialY * dm.heightPixels - view.height / 2f
            onPosChanged(initialX, initialY)
        }
    }

    private fun removePickerOverlay() {
        detachPickerOverlayView()
        removeUnlockMotionCaptureOverlay()
        detachUnlockMotionControl()
        removeUnlockMotionTrailOverlay()
        unlockMotionControl = null
        unlockMotionControlParams = null
        unlockMotionStatusView = null
        unlockMotionRecorder = null
        stopUnlockMotionTicker()
        pickerMode = null
        activeRecordingSurface = null
        activeRecordingAutoStopOnHome = false
        unlockRecordWaitingForRecord = false
        unlockRecordFinalizing = false
    }

    private fun detachPickerOverlayView() {
        val overlay = pickerOverlay ?: return
        pickerOverlay = null
        try {
            if (overlay.isAttachedToWindow) {
                windowManager?.removeViewImmediate(overlay)
            } else {
                windowManager?.removeView(overlay)
            }
        } catch (_: Exception) {
            try {
                windowManager?.removeView(overlay)
            } catch (_: Exception) {
            }
        }
    }

    private fun removeChooserOverlay() {
        val overlay = chooserOverlay ?: return
        chooserOverlay = null
        try {
            if (overlay.isAttachedToWindow) {
                windowManager?.removeViewImmediate(overlay)
            } else {
                windowManager?.removeView(overlay)
            }
        } catch (_: Exception) {
            try {
                windowManager?.removeView(overlay)
            } catch (_: Exception) {
            }
        }
    }

    private fun removeReminderOverlay() {
        reminderAutoOpenRunnable?.let(handler::removeCallbacks)
        reminderAutoOpenRunnable = null
        val overlay = reminderOverlay ?: return
        reminderOverlay = null
        try {
            if (overlay.isAttachedToWindow) {
                windowManager?.removeViewImmediate(overlay)
            } else {
                windowManager?.removeView(overlay)
            }
        } catch (_: Exception) {
            try {
                windowManager?.removeView(overlay)
            } catch (_: Exception) {
            }
        }
    }

    private fun removeFloatingWindow() {
        floatingView?.let {
            try {
                windowManager?.removeView(it)
            } catch (_: Exception) {
            }
            floatingView = null
        }
        startMenuButton = null
        pauseMenuButton = null
        endMenuButton = null
        statusPrimaryView = null
        statusSecondaryView = null
        statusLoopView = null
        statusStepView = null
        statusTimeView = null
        statusWaitView = null
        collapsedMenuButton = null
    }

    private fun closeAutomationMenu() {
        stopScriptRun()
        destroyFlutterAutomationOverlay()
        removeChooserOverlay()
        removeReminderOverlay()
        removeFloatingWindow()
        collapsed = false
    }

    private fun showAlarmReminderOverlayInternal(intent: Intent) {
        removeReminderOverlay()
        val root = LayoutInflater.from(this).inflate(R.layout.activity_alarm, null)
        val title = intent.getStringExtra("title") ?: "任务提醒"
        val body = intent.getStringExtra("body") ?: "你的任务现在需要完成。"
        val targetAppLabel = intent.getStringExtra("targetAppLabel") ?: "目标应用"
        val autoOpenDelaySeconds = intent.getIntExtra("autoOpenDelaySeconds", 0).coerceAtLeast(0)
        val preConfigName = intent.getStringExtra("preGestureConfigName")
        val configName = intent.getStringExtra("gestureConfigName")
        root.findViewById<TextView>(R.id.alarmTitle)?.text = title
        root.findViewById<TextView>(R.id.alarmBody)?.text = body
        root.findViewById<TextView>(R.id.alarmHint)?.text = if (autoOpenDelaySeconds > 0) {
            "提醒已触发，${autoOpenDelaySeconds} 秒后自动打开 $targetAppLabel。"
        } else if (!preConfigName.isNullOrBlank()) {
            "亮屏未锁时先执行前置脚本：$preConfigName，然后再打开 $targetAppLabel。"
        } else if (configName.isNullOrBlank()) {
            "提醒已触发，点击下方按钮打开 $targetAppLabel。"
        } else {
            "绑定配置：$configName，点击下方按钮打开 $targetAppLabel。"
        }
        root.findViewById<TextView>(R.id.openTaskButton)?.apply {
            text = "打开$targetAppLabel"
            setOnClickListener {
                launchReminderTask(intent)
            }
        }
        root.findViewById<TextView>(R.id.dismissButton)?.setOnClickListener {
            dismissReminder(intent.getIntExtra("notificationId", 0))
        }
        val params = fullScreenOverlayParams(focusable = true)
        try {
            windowManager?.addView(root, params)
            reminderOverlay = root
            if (autoOpenDelaySeconds > 0) {
                reminderAutoOpenRunnable = Runnable {
                    if (reminderOverlay === root) {
                        launchReminderTask(intent)
                    }
                }.also {
                    handler.postDelayed(it, autoOpenDelaySeconds * 1000L)
                }
            }
        } catch (_: Exception) {
            reminderOverlay = null
            reminderAutoOpenRunnable = null
        }
    }

    private fun dismissReminder(notificationId: Int) {
        reminderAutoOpenRunnable?.let(handler::removeCallbacks)
        reminderAutoOpenRunnable = null
        removeReminderOverlay()
        if (notificationId != 0) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.cancel(notificationId)
        }
    }

    private fun launchReminderTask(intent: Intent) {
        reminderAutoOpenRunnable?.let(handler::removeCallbacks)
        reminderAutoOpenRunnable = null
        val taskId = intent.getStringExtra("taskId").orEmpty()
        val targetAppPackage = intent.getStringExtra("targetAppPackage")
        val targetAppLabel = intent.getStringExtra("targetAppLabel") ?: "目标应用"
        val preConfigName = intent.getStringExtra("preGestureConfigName")
        val configName = intent.getStringExtra("gestureConfigName")
        val preActions = parseActionsJson(intent.getStringExtra("preGestureActionsJson"))
        val actions = parseActionsJson(intent.getStringExtra("gestureActionsJson"))
        val preLoopCount = intent.getIntExtra("preGestureLoopCount", 1).coerceAtLeast(1)
        val preLoopIntervalMillis =
            intent.getIntExtra("preGestureLoopIntervalMillis", 0).coerceAtLeast(0)
        val loopCount = intent.getIntExtra("gestureLoopCount", 1).coerceAtLeast(1)
        val loopIntervalMillis =
            intent.getIntExtra("gestureLoopIntervalMillis", 0).coerceAtLeast(0)
        val autoOpenDelaySeconds = intent.getIntExtra("autoOpenDelaySeconds", 0).coerceAtLeast(0)
        val autoCompleteDelaySeconds = intent.getIntExtra("autoCompleteDelaySeconds", 0).coerceAtLeast(0)
        val notificationId = intent.getIntExtra("notificationId", 0)
        if (autoCompleteDelaySeconds > 0 && taskId.isNotBlank()) {
            AlarmLaunchStore.setPendingAutoComplete(
                this,
                taskId,
                System.currentTimeMillis() + autoCompleteDelaySeconds * 1000L,
            )
        }
        if (taskId.isNotBlank()) {
            AlarmLaunchStore.setPendingTaskId(this, taskId)
            // Clear stale pending-open marker from previous reminders.
            AlarmLaunchStore.consumePendingOpenTaskId(this)
        }
        if (!targetAppPackage.isNullOrBlank()) {
            val opened = openAppAndRunConfig(
                context = this,
                packageName = targetAppPackage,
                packageLabel = targetAppLabel,
                preConfigName = preConfigName,
                preActions = preActions,
                preLoopCount = preLoopCount,
                preLoopIntervalMillis = preLoopIntervalMillis,
                configName = configName,
                actions = actions,
                loopCount = loopCount,
                loopIntervalMillis = loopIntervalMillis,
                delaySeconds = autoOpenDelaySeconds,
            )
            if (opened) {
                dismissReminder(notificationId)
                return
            }
        }
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            if (taskId.isNotBlank()) {
                putExtra("taskId", taskId)
                if (!targetAppPackage.isNullOrBlank()) {
                    AlarmLaunchStore.setPendingOpenTaskId(this@AutoSwipeService, taskId)
                    putExtra("openTaskId", taskId)
                }
            }
        }
        startActivity(launchIntent)
        dismissReminder(notificationId)
    }

    private fun updateStatusText() {
        val button = startMenuButton
        val primary = statusPrimaryView
        val secondary = statusSecondaryView
        if (isRunning) {
            val elapsed = (SystemClock.uptimeMillis() - runStartedAt).coerceAtLeast(0L)
            val totalLoops = loopCount.coerceAtLeast(1)
            val loopIndex = if (infiniteLoop) {
                max(1, ((elapsed / (estimateActionsMillis(runtimeActions.drop(loopStartIndex)).coerceAtLeast(1) + loopIntervalMillis.coerceAtLeast(0L))) + 1).toInt())
            } else {
                (totalLoops - remainingLoops + 1).coerceIn(1, totalLoops)
            }
            val stepIndex = (currentActionIndex + 1).coerceIn(1, runtimeActions.size.coerceAtLeast(1))
            val totalSteps = runtimeActions.size.coerceAtLeast(1)
            val waitLeft = if (currentWaitUntilMillis > 0L) {
                (currentWaitUntilMillis - SystemClock.uptimeMillis()).coerceAtLeast(0L)
            } else {
                0L
            }
            button?.contentDescription =
                if (infiniteLoop) {
                    "停止，${formatShortElapsed(elapsed)}/无限"
                } else {
                    "停止，${formatShortElapsed(elapsed)}/${formatShortElapsed(runTotalMillis)}"
                }
            
            statusLoopView?.text = if (infiniteLoop) "轮次 ${loopIndex}/∞" else "轮次 ${loopIndex}/${totalLoops}"
            statusTimeView?.text = formatLongElapsed(elapsed)
            statusStepView?.text = "步骤 ${stepIndex}/${totalSteps}"
            statusWaitView?.text = if (waitLeft > 0L) "等待 ${formatPreciseWait(waitLeft)}" else "就绪"

            // Keep these for backward compatibility if any other part uses them
            primary?.text =
                "${if (isPaused) "暂停" else "执行"} 轮 ${if (infiniteLoop) "$loopIndex/∞" else "$loopIndex/$totalLoops"}  步 ${stepIndex}/${totalSteps}  ${formatLongElapsed(elapsed)}"
            secondary?.text =
                if (waitLeft > 0L) "等待 ${formatPreciseWait(waitLeft)}" else if (infiniteLoop) "总时长 持续执行" else "总时长 ${formatShortElapsed(runTotalMillis)}"
            
            pauseMenuButton?.setImageResource(if (isPaused) R.drawable.ic_overlay_play else R.drawable.ic_overlay_pause)
            pauseMenuButton?.contentDescription = if (isPaused) "继续" else "暂停"
        } else {
            button?.setImageResource(R.drawable.ic_overlay_play)
            button?.contentDescription = "启动"
            primary?.text = "待命"
            secondary?.text = "未执行"
            statusLoopView?.text = "待命"
            statusTimeView?.text = "00:00:00"
            statusStepView?.text = "未执行"
            statusWaitView?.text = "-"
            pauseMenuButton?.setImageResource(R.drawable.ic_overlay_pause)
            pauseMenuButton?.contentDescription = "暂停"
        }
    }

    private fun formatLongElapsed(milliseconds: Long): String {
        val totalSeconds = (milliseconds / 1000).coerceAtLeast(0L)
        val hours = totalSeconds / 3600
        val minutes = (totalSeconds % 3600) / 60
        val seconds = totalSeconds % 60
        return String.format(Locale.getDefault(), "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private fun formatPreciseWait(milliseconds: Long): String {
        return if (milliseconds >= 1000L) {
            val seconds = milliseconds / 1000.0
            if (milliseconds % 1000L == 0L) {
                "${seconds.toInt()}秒"
            } else {
                String.format(Locale.getDefault(), "%.1f秒", seconds)
            }
        } else {
            "${milliseconds}毫秒"
        }
    }

    private fun roundedBackground(color: Int, radius: Float, strokeColor: Int): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = radius
            setColor(color)
            setStroke(dp(1), strokeColor)
        }
    }

    private fun sideRoundedBackground(color: Int, radius: Float, strokeColor: Int, isRightSide: Boolean): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            // corners: [topLeft, topLeft, topRight, topRight, bottomRight, bottomRight, bottomLeft, bottomLeft]
            cornerRadii = if (isRightSide) {
                // 靠右：左边圆角，右边直角
                floatArrayOf(radius, radius, 0f, 0f, 0f, 0f, radius, radius)
            } else {
                // 靠左：右边圆角，左边直角
                floatArrayOf(0f, 0f, radius, radius, radius, radius, 0f, 0f)
            }
            setColor(color)
            setStroke(dp(1), strokeColor)
        }
    }

    private fun mapToJson(map: Map<String, Any?>): JSONObject {
        val obj = JSONObject()
        map.forEach { (key, value) ->
            obj.put(key, toJsonValue(value))
        }
        return obj
    }

    private fun toJsonValue(value: Any?): Any? {
        return when (value) {
            null -> JSONObject.NULL
            is Map<*, *> -> mapToJson(normalizeMap(value))
            is List<*> -> JSONArray().apply {
                value.forEach { put(toJsonValue(it)) }
            }
            else -> value
        }
    }

    private fun asMapList(value: Any?): List<Map<String, Any?>> {
        return (value as? List<*>)?.mapNotNull { item ->
            (item as? Map<*, *>)?.let(::normalizeMap)
        } ?: emptyList()
    }

    private fun estimateActionsDurationLabel(actions: List<Map<String, Any?>>): String {
        val (minMillis, maxMillis) = estimateActionsMillisRange(actions)
        return if (minMillis == maxMillis) {
            formatDurationLabel(minMillis)
        } else {
            "${formatDurationLabel(minMillis)}-${formatDurationLabel(maxMillis)}"
        }
    }

    private fun estimateActionsMillisRange(actions: List<Map<String, Any?>>): Pair<Long, Long> {
        var minMillis = 0L
        var maxMillis = 0L
        actions.forEach { action ->
            val (actionMin, actionMax) = estimateActionMillisRange(action)
            minMillis += actionMin
            maxMillis += actionMax
        }
        return minMillis to maxMillis
    }

    private fun estimateActionMillisRange(action: Map<String, Any?>): Pair<Long, Long> {
        return when (action["type"] as? String ?: "swipe") {
            "click" -> {
                val millis = ((action["duration"] as? Number)?.toLong() ?: 50L) + 100L
                millis to millis
            }
            "swipe" -> {
                val millis = ((action["duration"] as? Number)?.toLong() ?: 400L) + 100L
                millis to millis
            }
            "recorded" -> {
                val millis = ((action["duration"] as? Number)?.toLong() ?: 0L) + 100L
                millis to millis
            }
            "nav" -> {
                val millis = if (action["navType"] == "recents") 900L else 650L
                millis to millis
            }
            "wait" -> {
                if (isRandomWait(action)) {
                    val rawMin = waitMinMillis(action)
                    val rawMax = waitMaxMillis(action)
                    kotlin.math.min(rawMin, rawMax) to kotlin.math.max(rawMin, rawMax)
                } else {
                    val millis = resolveWaitMillis(action)
                    millis to millis
                }
            }
            "launchApp" -> 1000L to 1000L
            "buttonRecognize" -> {
                val retryCount = ((action["retryCount"] as? Number)?.toLong() ?: 3L).coerceIn(0L, 20L)
                val retryWait = ((action["retryWaitMillis"] as? Number)?.toLong() ?: 800L).coerceIn(0L, 10_000_000L)
                val retryMillis = estimateActionsMillis(asMapList(action["retryActions"])) + retryWait
                300L to (300L + retryMillis * retryCount)
            }
            "lockScreen" -> 500L to 500L
            else -> 0L to 0L
        }
    }

    private fun estimateActionsMillis(actions: List<Map<String, Any?>>): Long {
        return actions.sumOf { action ->
            when (action["type"] as? String ?: "swipe") {
                "click" -> ((action["duration"] as? Number)?.toLong() ?: 50L) + 100L
                "swipe" -> ((action["duration"] as? Number)?.toLong() ?: 400L) + 100L
                "recorded" -> ((action["duration"] as? Number)?.toLong() ?: 0L) + 100L
                "nav" -> if (action["navType"] == "recents") 900L else 650L
                "wait" -> resolveWaitMillis(action)
                "launchApp" -> 1000L
                "buttonRecognize" -> estimateActionMillisRange(action).second
                "lockScreen" -> 500L
                else -> 0L
            }
        }
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density + 0.5f).toInt()
    }

    private fun formatElapsed(milliseconds: Long): String {
        val totalSeconds = milliseconds / 1000
        val minutes = totalSeconds / 60
        val seconds = totalSeconds % 60
        return "${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}"
    }

    private fun formatElapsedTenths(milliseconds: Long): String {
        val totalCentiseconds = milliseconds / 10
        val totalSeconds = totalCentiseconds / 100
        val minutes = totalSeconds / 60
        val seconds = totalSeconds % 60
        val centiseconds = totalCentiseconds % 100
        return "${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}:${centiseconds.toString().padStart(2, '0')}"
    }

    private fun formatDurationLabel(milliseconds: Long): String {
        val millis = milliseconds.coerceAtLeast(0L)
        if (millis < 1000L) {
            return "${millis}毫秒"
        }
        if (millis < 60_000L) {
            return if (millis % 1000L == 0L) {
                "${millis / 1000L}秒"
            } else {
                "${String.format(Locale.US, "%.1f", millis / 1000.0)}秒"
            }
        }
        val minutes = millis / 60_000L
        val seconds = (millis % 60_000L) / 1000L
        return if (seconds == 0L) "${minutes}分钟" else "${minutes}分${seconds}秒"
    }

    private fun formatWaitDuration(milliseconds: Long): String {
        return formatDurationLabel(milliseconds)
    }

    private fun formatShortElapsed(milliseconds: Long): String {
        val seconds = (milliseconds / 1000).coerceAtLeast(0L)
        return if (seconds < 60) {
            "${seconds}s"
        } else {
            "${seconds / 60}m${seconds % 60}s"
        }
    }

    override fun onUnbind(intent: Intent?): Boolean {
        removeFloatingWindow()
        destroyFlutterAutomationOverlay()
        removeChooserOverlay()
        removeReminderOverlay()
        removePickerOverlay()
        instance = null
        return super.onUnbind(intent)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (unlockMotionRecorder != null && !unlockRecordFinalizing) {
            val packageName = event?.packageName?.toString().orEmpty()
            if (packageName.isNotBlank() && isHomePackage(packageName) && !isDeviceLocked(this)) {
                unlockRecordFinalizing = true
                handler.postDelayed({
                    stopUnlockMotionRecording(cancelled = false)
                }, 350)
            }
            return
        }
        if (activeRecordingAutoStopOnHome && !unlockRecordFinalizing) {
            val packageName = event?.packageName?.toString().orEmpty()
            if (packageName.isNotBlank() && isHomePackage(packageName)) {
                finishUnlockRecordingForHome()
            }
        }
    }

    override fun onMotionEvent(event: MotionEvent) {
        if (unlockMotionCaptureOverlay != null) return
        val recorder = unlockMotionRecorder ?: return
        val (screenWidth, screenHeight) = screenSize()
        val finishedSegment = recorder.onMotionEvent(
            event = event,
            screenWidth = screenWidth,
            screenHeight = screenHeight,
            useRawCoordinates = true,
        )
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> detachUnlockMotionControl()
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> handler.postDelayed({
                if (finishedSegment != null) {
                    showUnlockMotionTrail(finishedSegment)
                }
                if (unlockMotionRecorder != null && !unlockRecordFinalizing) {
                    attachUnlockMotionControl()
                }
            }, 90)
        }
    }
    override fun onInterrupt() {}

    private fun showUnlockMotionTrail(segment: RecordedSegment) {
        if (segment.points.isEmpty()) return
        unlockMotionTrailSegments.add(segment)
        ensureUnlockMotionTrailOverlay()
        unlockMotionTrailOverlay?.invalidate()
    }

    private fun isHomePackage(packageName: String): Boolean {
        val intent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
        }
        val resolved = packageManager.queryIntentActivities(intent, 0)
        return resolved.any { it.activityInfo?.packageName == packageName }
    }

    private fun finishUnlockRecordingForHome() {
        val surface = activeRecordingSurface ?: return
        if (!surface.hasGesture()) return
        unlockRecordFinalizing = true
        val result = surface.exportResult()
        showCenteredPickerMessage(
            title = "保存解锁脚本",
            message = "已经检测到进入桌面，是否保存这次锁屏解锁录制？",
            primaryText = "保存",
            secondaryText = "取消",
            onPrimary = {
                publishPickerResult(result)
                removePickerOverlay()
            },
            onSecondary = {
                removePickerOverlay()
                publishPickerResult(mapOf("cancelled" to true))
            },
        )
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        val newNightModeMask = newConfig.uiMode and Configuration.UI_MODE_NIGHT_MASK
        if (newNightModeMask == lastNightModeMask) {
            return
        }
        lastNightModeMask = newNightModeMask
        updateFlutterOverlayTheme()
        if (floatingView != null) {
            showFloatingWindow(expanded = !collapsed, attachToRightEdge = collapsedEdgeRight)
        }
    }

    private data class RecordedPoint(val x: Float, val y: Float, val t: Long)

    private data class RecordedSegment(
        val start: Long,
        var duration: Long = 80L,
        val points: MutableList<RecordedPoint> = mutableListOf(),
    )

    private class MotionEventRecorder {
        private val segments = mutableListOf<RecordedSegment>()
        private var currentSegment: RecordedSegment? = null
        private var recording = false
        private var startedAt = 0L
        private var recordingScreenWidth = 0
        private var recordingScreenHeight = 0

        fun startRecording() {
            segments.clear()
            currentSegment = null
            recording = true
            startedAt = SystemClock.uptimeMillis()
            recordingScreenWidth = 0
            recordingScreenHeight = 0
        }

        fun onMotionEvent(
            event: MotionEvent,
            screenWidth: Int,
            screenHeight: Int,
            offsetX: Float = 0f,
            offsetY: Float = 0f,
            useRawCoordinates: Boolean = false,
        ): RecordedSegment? {
            if (!recording) return null
            val width = screenWidth.coerceAtLeast(1).toFloat()
            val height = screenHeight.coerceAtLeast(1).toFloat()
            if (recordingScreenWidth <= 0) {
                recordingScreenWidth = width.toInt()
            }
            if (recordingScreenHeight <= 0) {
                recordingScreenHeight = height.toInt()
            }
            fun currentX(): Float = if (useRawCoordinates) event.rawX else event.x + offsetX
            fun currentY(): Float = if (useRawCoordinates) event.rawY else event.y + offsetY
            fun historicalX(index: Int): Float =
                if (useRawCoordinates) event.getHistoricalX(index) else event.getHistoricalX(index) + offsetX
            fun historicalY(index: Int): Float =
                if (useRawCoordinates) event.getHistoricalY(index) else event.getHistoricalY(index) + offsetY
            return when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    val start = (event.eventTime - startedAt).coerceAtLeast(0L)
                    currentSegment = RecordedSegment(start = start).also {
                        segments.add(it)
                    }
                    appendPoint(currentX(), currentY(), event.eventTime, width, height)
                    null
                }
                MotionEvent.ACTION_MOVE -> {
                    for (index in 0 until event.historySize) {
                        appendPoint(
                            historicalX(index),
                            historicalY(index),
                            event.getHistoricalEventTime(index),
                            width,
                            height,
                        )
                    }
                    appendPoint(currentX(), currentY(), event.eventTime, width, height)
                    null
                }
                MotionEvent.ACTION_UP -> {
                    appendPoint(currentX(), currentY(), event.eventTime, width, height)
                    finishCurrentSegment(event.eventTime)
                }
                MotionEvent.ACTION_CANCEL -> {
                    finishCurrentSegment(event.eventTime)
                }
                else -> null
            }
        }

        fun hasGesture(): Boolean {
            return segments.any { it.points.isNotEmpty() } ||
                (currentSegment?.points?.isNotEmpty() == true)
        }

        fun exportResult(): Map<String, Any?> {
            finishCurrentSegment(SystemClock.uptimeMillis())
            recording = false
            val duration = max(
                SystemClock.uptimeMillis() - startedAt,
                segments.maxOfOrNull { it.start + it.duration } ?: 0L,
            )
            return mapOf(
                "type" to "recorded",
                "duration" to duration,
                "screenWidth" to recordingScreenWidth.coerceAtLeast(1),
                "screenHeight" to recordingScreenHeight.coerceAtLeast(1),
                "segments" to segments.filter { it.points.isNotEmpty() }.map { segment ->
                    mapOf(
                        "start" to segment.start,
                        "duration" to segment.duration.coerceAtLeast(50L),
                        "points" to segment.points.map { point ->
                            mapOf(
                                "x" to point.x.toDouble(),
                                "y" to point.y.toDouble(),
                                "t" to point.t,
                            )
                        },
                    )
                },
            )
        }

        private fun appendPoint(
            x: Float,
            y: Float,
            eventTime: Long,
            width: Float,
            height: Float,
        ) {
            val segment = currentSegment ?: return
            val normalizedX = (x / width).coerceIn(0f, 1f)
            val normalizedY = (y / height).coerceIn(0f, 1f)
            val t = (eventTime - startedAt).coerceAtLeast(0L)
            val last = segment.points.lastOrNull()
            if (last != null &&
                abs(normalizedX - last.x) < 0.002f &&
                abs(normalizedY - last.y) < 0.002f &&
                t - last.t < 16L
            ) {
                return
            }
            segment.points.add(RecordedPoint(normalizedX, normalizedY, t))
        }

        private fun finishCurrentSegment(eventTime: Long): RecordedSegment? {
            val segment = currentSegment ?: return null
            val end = (eventTime - startedAt).coerceAtLeast(segment.start + 50L)
            segment.duration = (end - segment.start).coerceAtLeast(50L)
            currentSegment = null
            return RecordedSegment(
                start = segment.start,
                duration = segment.duration,
                points = segment.points.toMutableList(),
            )
        }
    }

    private data class StepPoint(var x: Float, var y: Float, var t: Long = 0L)

    private data class ButtonMatchTarget(
        val bounds: Rect,
        val accessibilityNode: AccessibilityNodeInfo? = null,
    )

    private data class ButtonNodeInfo(
        val bounds: Rect,
        val text: String,
        val viewId: String,
        val description: String,
        val className: String,
        val accessibilityNode: AccessibilityNodeInfo? = null,
    ) {
        fun toResult(screenWidth: Int, screenHeight: Int): Map<String, Any?> {
            return mapOf(
                "type" to "buttonRecognize",
                "source" to "accessibility",
                "buttonText" to text,
                "buttonId" to viewId,
                "buttonDescription" to description,
                "className" to className,
                "matchMode" to "exact",
                "regionMode" to "full",
                "region" to mapOf(
                    "left" to (bounds.left.toDouble() / screenWidth.coerceAtLeast(1)),
                    "top" to (bounds.top.toDouble() / screenHeight.coerceAtLeast(1)),
                    "right" to (bounds.right.toDouble() / screenWidth.coerceAtLeast(1)),
                    "bottom" to (bounds.bottom.toDouble() / screenHeight.coerceAtLeast(1)),
                ),
                "successMode" to "defaultClick",
                "retryCount" to 3,
                "retryWaitMillis" to 800,
                "retrySuccessMode" to "defaultClick",
                "failAction" to "notify",
                "bounds" to mapOf(
                    "left" to (bounds.left.toDouble() / screenWidth.coerceAtLeast(1)),
                    "top" to (bounds.top.toDouble() / screenHeight.coerceAtLeast(1)),
                    "right" to (bounds.right.toDouble() / screenWidth.coerceAtLeast(1)),
                    "bottom" to (bounds.bottom.toDouble() / screenHeight.coerceAtLeast(1)),
                ),
            )
        }
    }

    private data class OcrTextInfo(
        val bounds: Rect,
        val text: String,
    ) {
        fun offset(dx: Int, dy: Int): OcrTextInfo {
            return copy(bounds = Rect(bounds).apply { offset(dx, dy) })
        }

        fun toTextResult(screenWidth: Int, screenHeight: Int): Map<String, Any?> {
            return mapOf(
                "text" to text,
                "bounds" to mapOf(
                    "left" to (bounds.left.toDouble() / screenWidth.coerceAtLeast(1)),
                    "top" to (bounds.top.toDouble() / screenHeight.coerceAtLeast(1)),
                    "right" to (bounds.right.toDouble() / screenWidth.coerceAtLeast(1)),
                    "bottom" to (bounds.bottom.toDouble() / screenHeight.coerceAtLeast(1)),
                ),
            )
        }

        fun toResult(screenWidth: Int, screenHeight: Int): Map<String, Any?> {
            return mapOf(
                "type" to "buttonRecognize",
                "source" to "imageText",
                "buttonText" to text,
                "buttonId" to "",
                "buttonDescription" to text,
                "matchMode" to "exact",
                "regionMode" to "full",
                "region" to mapOf(
                    "left" to (bounds.left.toDouble() / screenWidth.coerceAtLeast(1)),
                    "top" to (bounds.top.toDouble() / screenHeight.coerceAtLeast(1)),
                    "right" to (bounds.right.toDouble() / screenWidth.coerceAtLeast(1)),
                    "bottom" to (bounds.bottom.toDouble() / screenHeight.coerceAtLeast(1)),
                ),
                "successMode" to "defaultClick",
                "retryCount" to 3,
                "retryWaitMillis" to 800,
                "retrySuccessMode" to "defaultClick",
                "failAction" to "notify",
                "bounds" to mapOf(
                    "left" to (bounds.left.toDouble() / screenWidth.coerceAtLeast(1)),
                    "top" to (bounds.top.toDouble() / screenHeight.coerceAtLeast(1)),
                    "right" to (bounds.right.toDouble() / screenWidth.coerceAtLeast(1)),
                    "bottom" to (bounds.bottom.toDouble() / screenHeight.coerceAtLeast(1)),
                ),
            )
        }
    }

    private class ImageTemplateSelectSurface(context: Context) : View(context) {
        private val rectPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xFFFF3B30.toInt()
            strokeWidth = 3f * resources.displayMetrics.density
            style = Paint.Style.STROKE
        }
        private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0x22FF3B30
            style = Paint.Style.FILL
        }
        private var startX = 0f
        private var startY = 0f
        private var currentX = 0f
        private var currentY = 0f
        private var hasSelection = false

        fun selectedScreenRect(): Rect? {
            if (!hasSelection) return null
            val location = IntArray(2)
            getLocationOnScreen(location)
            val left = kotlin.math.min(startX, currentX).toInt() + location[0]
            val top = kotlin.math.min(startY, currentY).toInt() + location[1]
            val right = kotlin.math.max(startX, currentX).toInt() + location[0]
            val bottom = kotlin.math.max(startY, currentY).toInt() + location[1]
            return Rect(left, top, right, bottom)
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startX = event.x
                    startY = event.y
                    currentX = event.x
                    currentY = event.y
                    hasSelection = true
                    invalidate()
                }
                MotionEvent.ACTION_MOVE, MotionEvent.ACTION_UP -> {
                    currentX = event.x
                    currentY = event.y
                    invalidate()
                }
                MotionEvent.ACTION_CANCEL -> {
                    hasSelection = false
                    invalidate()
                }
            }
            return true
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            if (!hasSelection) return
            val rect = Rect(
                kotlin.math.min(startX, currentX).toInt(),
                kotlin.math.min(startY, currentY).toInt(),
                kotlin.math.max(startX, currentX).toInt(),
                kotlin.math.max(startY, currentY).toInt(),
            )
            canvas.drawRect(rect, fillPaint)
            canvas.drawRect(rect, rectPaint)
        }
    }

    private class ButtonDetectSurface(
        context: Context,
        private val nodes: List<ButtonNodeInfo>,
        private val onSelect: (ButtonNodeInfo) -> Unit,
    ) : View(context) {
        private val density = resources.displayMetrics.density
        private val rectPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xFFFF3B30.toInt()
            strokeWidth = 2.5f * density
            style = Paint.Style.STROKE
        }
        private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0x22FF3B30
            style = Paint.Style.FILL
        }
        private val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = 11f * density
            style = Paint.Style.FILL
        }
        private val labelBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xCCFF3B30.toInt()
            style = Paint.Style.FILL
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            if (event.actionMasked == MotionEvent.ACTION_UP) {
                val selected = nodes
                    .filter { localRect(it.bounds).contains(event.x.toInt(), event.y.toInt()) }
                    .minByOrNull { it.bounds.width() * it.bounds.height() }
                if (selected != null) {
                    onSelect(selected)
                }
                return true
            }
            return true
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            nodes.forEachIndexed { index, node ->
                val rect = localRect(node.bounds)
                canvas.drawRect(rect, fillPaint)
                canvas.drawRect(rect, rectPaint)
                val label = (node.text.ifBlank { node.description }.ifBlank { "${index + 1}" }).take(12)
                val labelWidth = labelPaint.measureText(label) + 10f * density
                val top = (rect.top - 20f * density).coerceAtLeast(0f)
                canvas.drawRect(
                    rect.left.toFloat(),
                    top,
                    rect.left + labelWidth,
                    top + 18f * density,
                    labelBgPaint,
                )
                canvas.drawText(label, rect.left + 5f * density, top + 13f * density, labelPaint)
            }
        }

        private fun localRect(screenRect: Rect): Rect {
            val location = IntArray(2)
            getLocationOnScreen(location)
            return Rect(screenRect).apply {
                offset(-location[0], -location[1])
            }
        }
    }

    private class OcrTextDetectSurface(
        context: Context,
        private val nodes: List<OcrTextInfo>,
        private val onSelect: (OcrTextInfo) -> Unit,
    ) : View(context) {
        private val density = resources.displayMetrics.density
        private val rectPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xFFFF3B30.toInt()
            strokeWidth = 2.5f * density
            style = Paint.Style.STROKE
        }
        private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0x22FF3B30
            style = Paint.Style.FILL
        }
        private val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = 11f * density
            style = Paint.Style.FILL
        }
        private val labelBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xCCFF3B30.toInt()
            style = Paint.Style.FILL
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            if (event.actionMasked == MotionEvent.ACTION_UP) {
                val selected = nodes.firstOrNull {
                    localRect(it.bounds).contains(event.x.toInt(), event.y.toInt())
                }
                if (selected != null) {
                    onSelect(selected)
                }
                return true
            }
            return true
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            nodes.forEachIndexed { index, node ->
                val rect = localRect(node.bounds)
                canvas.drawRect(rect, fillPaint)
                canvas.drawRect(rect, rectPaint)
                val label = node.text.ifBlank { "${index + 1}" }.take(12)
                val labelWidth = labelPaint.measureText(label) + 10f * density
                val top = (rect.top - 20f * density).coerceAtLeast(0f)
                canvas.drawRect(rect.left.toFloat(), top, rect.left + labelWidth, top + 18f * density, labelBgPaint)
                canvas.drawText(label, rect.left + 5f * density, top + 13f * density, labelPaint)
            }
        }

        private fun localRect(screenRect: Rect): Rect {
            val location = IntArray(2)
            getLocationOnScreen(location)
            return Rect(screenRect).apply {
                offset(-location[0], -location[1])
            }
        }
    }

    private class ClickStepSurface(
        context: Context,
        private val onNewPoint: (StepPoint) -> Unit,
    ) : View(context) {
        private val points = mutableListOf<StepPoint>()
        private var selectedIndex = -1
        private var downIndex = -1
        private val startedAt = SystemClock.uptimeMillis()

        private val density = resources.displayMetrics.density
        private val circleRadius = 18f * density
        private val selectedRadius = 22f * density
        private val hitRadius = 34f * density

        private val circlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xFF4A90E2.toInt()
            style = Paint.Style.FILL
        }
        private val selectedPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xFFFFB74D.toInt()
            style = Paint.Style.FILL
        }
        private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            strokeWidth = 2f * density
            style = Paint.Style.STROKE
        }
        private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textAlign = Paint.Align.CENTER
            textSize = 14f * density
            typeface = android.graphics.Typeface.DEFAULT_BOLD
        }

        fun hasPoints(): Boolean = points.isNotEmpty()

        fun exportPoints(): List<Map<String, Double>> {
            return points.map { point ->
                mapOf(
                    "x" to point.x.toDouble(),
                    "y" to point.y.toDouble(),
                    "t" to point.t.toDouble(),
                )
            }
        }

        fun deleteSelectedOrLast() {
            if (points.isEmpty()) return
            val index = if (selectedIndex in points.indices) selectedIndex else points.lastIndex
            points.removeAt(index)
            selectedIndex = when {
                points.isEmpty() -> -1
                index <= points.lastIndex -> index
                else -> points.lastIndex
            }
            invalidate()
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            if (width <= 0 || height <= 0) return true
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downIndex = findPoint(event.x, event.y)
                    selectedIndex = downIndex
                    invalidate()
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    if (downIndex >= 0) {
                        points[downIndex].x = (event.x / width).coerceIn(0f, 1f)
                        points[downIndex].y = (event.y / height).coerceIn(0f, 1f)
                        selectedIndex = downIndex
                        invalidate()
                    }
                    return true
                }
                MotionEvent.ACTION_UP -> {
                    if (downIndex >= 0) {
                        points[downIndex].x = (event.x / width).coerceIn(0f, 1f)
                        points[downIndex].y = (event.y / height).coerceIn(0f, 1f)
                        selectedIndex = downIndex
                    } else {
                        val point = StepPoint(
                            (event.x / width).coerceIn(0f, 1f),
                            (event.y / height).coerceIn(0f, 1f),
                            (event.eventTime - startedAt).coerceAtLeast(0L),
                        )
                        points.add(point)
                        selectedIndex = points.lastIndex
                        onNewPoint(point)
                    }
                    downIndex = -1
                    invalidate()
                    return true
                }
                MotionEvent.ACTION_CANCEL -> {
                    downIndex = -1
                    return true
                }
            }
            return true
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            points.forEachIndexed { index, point ->
                val x = point.x * width
                val y = point.y * height
                val radius = if (index == selectedIndex) selectedRadius else circleRadius
                canvas.drawCircle(x, y, radius, if (index == selectedIndex) selectedPaint else circlePaint)
                canvas.drawCircle(x, y, radius, strokePaint)
                val label = "${index + 1}"
                val baseline = y - (textPaint.ascent() + textPaint.descent()) / 2f
                canvas.drawText(label, x, baseline, textPaint)
            }
        }

        private fun findPoint(x: Float, y: Float): Int {
            for (index in points.indices.reversed()) {
                val point = points[index]
                val dx = x - point.x * width
                val dy = y - point.y * height
                if (dx * dx + dy * dy <= hitRadius * hitRadius) {
                    return index
                }
            }
            return -1
        }
    }

    private inner class RecordingSurface(
        context: Context,
        private val drawEnabled: Boolean = true,
        private val onSegmentFinished: ((RecordedSegment) -> Unit)? = null,
    ) : View(context) {
        private val segments = mutableListOf<RecordedSegment>()
        private var currentSegment: RecordedSegment? = null
        private var recording = false
        private var startedAt = 0L
        private var recordingScreenWidth = 0
        private var recordingScreenHeight = 0

        private val pathPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xFFFF4444.toInt()
            strokeWidth = 6f
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }

        private val pointPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xFFFFD166.toInt()
            style = Paint.Style.FILL
        }

        fun startRecording() {
            segments.clear()
            currentSegment = null
            recording = true
            startedAt = SystemClock.uptimeMillis()
            val (screenWidth, screenHeight) = screenSize()
            recordingScreenWidth = screenWidth.coerceAtLeast(1)
            recordingScreenHeight = screenHeight.coerceAtLeast(1)
            invalidate()
        }

        fun elapsedMillis(): Long {
            if (startedAt == 0L) return 0L
            return SystemClock.uptimeMillis() - startedAt
        }

        fun hasGesture(): Boolean {
            return segments.any { it.points.isNotEmpty() } ||
                (currentSegment?.points?.isNotEmpty() == true)
        }

        fun exportResult(): Map<String, Any?> {
            finishCurrentSegment(SystemClock.uptimeMillis())
            recording = false
            val duration = max(elapsedMillis(), segments.maxOfOrNull { it.start + it.duration } ?: 0L)
            return mapOf(
                "type" to "recorded",
                "duration" to duration,
                "screenWidth" to recordingScreenWidth.coerceAtLeast(1),
                "screenHeight" to recordingScreenHeight.coerceAtLeast(1),
                "segments" to segments.filter { it.points.isNotEmpty() }.map { segment ->
                    mapOf(
                        "start" to segment.start,
                        "duration" to segment.duration.coerceAtLeast(50L),
                        "points" to segment.points.map { point ->
                            mapOf(
                                "x" to point.x.toDouble(),
                                "y" to point.y.toDouble(),
                                "t" to point.t,
                            )
                        },
                    )
                },
            )
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            if (!recording || width <= 0 || height <= 0) {
                return true
            }
            val location = IntArray(2)
            getLocationOnScreen(location)
            val (screenWidth, screenHeight) = screenSize()
            recordingScreenWidth = screenWidth.coerceAtLeast(1)
            recordingScreenHeight = screenHeight.coerceAtLeast(1)
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    val start = (event.eventTime - startedAt).coerceAtLeast(0L)
                    currentSegment = RecordedSegment(start = start).also {
                        segments.add(it)
                    }
                    appendPoint(
                        event.x + location[0],
                        event.y + location[1],
                        event.eventTime,
                    )
                    invalidate()
                }
                MotionEvent.ACTION_MOVE -> {
                    for (index in 0 until event.historySize) {
                        appendPoint(
                            event.getHistoricalX(index) + location[0],
                            event.getHistoricalY(index) + location[1],
                            event.getHistoricalEventTime(index),
                        )
                    }
                    appendPoint(
                        event.x + location[0],
                        event.y + location[1],
                        event.eventTime,
                    )
                    invalidate()
                }
                MotionEvent.ACTION_UP -> {
                    appendPoint(
                        event.x + location[0],
                        event.y + location[1],
                        event.eventTime,
                    )
                    finishCurrentSegment(event.eventTime)
                    invalidate()
                }
                MotionEvent.ACTION_CANCEL -> {
                    finishCurrentSegment(event.eventTime)
                    invalidate()
                }
            }
            return true
        }

        override fun onDraw(canvas: Canvas) {
            if (!drawEnabled) return
            super.onDraw(canvas)
            val location = IntArray(2)
            getLocationOnScreen(location)
            val screenWidth = recordingScreenWidth.takeIf { it > 0 } ?: screenSize().first
            val screenHeight = recordingScreenHeight.takeIf { it > 0 } ?: screenSize().second
            val widthScale = screenWidth.coerceAtLeast(1).toFloat()
            val heightScale = screenHeight.coerceAtLeast(1).toFloat()
            segments.forEach { segment ->
                if (segment.points.isEmpty()) return@forEach
                val path = Path()
                segment.points.forEachIndexed { index, point ->
                    val x = point.x * widthScale - location[0]
                    val y = point.y * heightScale - location[1]
                    if (index == 0) {
                        path.moveTo(x, y)
                    } else {
                        path.lineTo(x, y)
                    }
                }
                canvas.drawPath(path, pathPaint)
                val first = segment.points.first()
                canvas.drawCircle(
                    first.x * widthScale - location[0],
                    first.y * heightScale - location[1],
                    8f,
                    pointPaint,
                )
            }
        }

        private fun appendPoint(x: Float, y: Float, eventTime: Long) {
            val segment = currentSegment ?: return
            val normalizedX = (x / recordingScreenWidth.coerceAtLeast(1).toFloat()).coerceIn(0f, 1f)
            val normalizedY = (y / recordingScreenHeight.coerceAtLeast(1).toFloat()).coerceIn(0f, 1f)
            val t = (eventTime - startedAt).coerceAtLeast(0L)
            val last = segment.points.lastOrNull()
            if (last != null &&
                abs(normalizedX - last.x) < 0.002f &&
                abs(normalizedY - last.y) < 0.002f &&
                t - last.t < 16L
            ) {
                return
            }
            segment.points.add(RecordedPoint(normalizedX, normalizedY, t))
        }

        private fun finishCurrentSegment(eventTime: Long) {
            val segment = currentSegment ?: return
            val end = (eventTime - startedAt).coerceAtLeast(segment.start + 50L)
            segment.duration = (end - segment.start).coerceAtLeast(50L)
            onSegmentFinished?.invoke(
                RecordedSegment(
                    start = segment.start,
                    duration = segment.duration,
                    points = segment.points.toMutableList(),
                ),
            )
            currentSegment = null
        }
    }
}
