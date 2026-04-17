package com.zilv.clock

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.util.Random
import kotlin.math.abs
import kotlin.math.max

class AutoSwipeService : AccessibilityService() {

    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var floatingLayoutParams: WindowManager.LayoutParams? = null
    private var chooserOverlay: View? = null
    private var pickerOverlay: View? = null
    private var startMenuButton: TextView? = null

    private var isRunning = false
    private var minSeconds = 0
    private var maxSeconds = 0
    private var scriptName: String? = null
    private var collapsed = false
    private var selectedConfigIndex = -1

    private val gestureActions = mutableListOf<Map<String, Any?>>()
    private val availableConfigs = mutableListOf<Map<String, Any?>>()
    private val pickerData: MutableMap<String, Float> = mutableMapOf()
    private var pickerMode: String? = null

    private val handler = Handler(Looper.getMainLooper())
    private val random = Random()

    companion object {
        var instance: AutoSwipeService? = null
        var onPickerResult: ((Map<String, Any?>) -> Unit)? = null

        fun updateConfig(
            min: Int,
            max: Int,
            actions: List<Map<String, Any?>>,
            name: String? = null,
        ) {
            instance?.apply {
                handler.removeCallbacksAndMessages(null)
                isRunning = false
                minSeconds = min
                maxSeconds = max
                scriptName = name
                gestureActions.clear()
                gestureActions.addAll(actions.map(::normalizeMap))
                updateStatusText()

                if (min == 0 && max == 0 && gestureActions.isNotEmpty()) {
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

        private fun normalizeMap(map: Map<*, *>): Map<String, Any?> {
            return map.entries.associate { entry -> entry.key.toString() to entry.value }
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
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
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
            width = WindowManager.LayoutParams.WRAP_CONTENT
            height = WindowManager.LayoutParams.WRAP_CONTENT
            gravity = Gravity.TOP or Gravity.START
            x = floatingLayoutParams?.x ?: 100
            y = floatingLayoutParams?.y ?: 120
        }
    }

    private fun showFloatingWindow(expanded: Boolean): Boolean {
        removeFloatingWindow()
        removeChooserOverlay()
        collapsed = !expanded

        val layoutParams = baseOverlayParams()
        val root = if (expanded) createExpandedMenu(layoutParams) else createCollapsedMenu(layoutParams)

        return try {
            windowManager?.addView(root, layoutParams)
            floatingView = root
            floatingLayoutParams = layoutParams
            updateStatusText()
            true
        } catch (_: Exception) {
            floatingView = null
            floatingLayoutParams = null
            false
        }
    }

    private fun createExpandedMenu(layoutParams: WindowManager.LayoutParams): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8), dp(6), dp(8), dp(6))
            background = roundedBackground(0xDD151A1E.toInt(), dp(28).toFloat(), 0x55FFFFFF)
        }

        val configButton = menuButton("配置", 0xFF7ED8C3.toInt()) {
            openFlutterCommand("open_configs")
        }
        startMenuButton = menuButton("启动", 0xFF8EB8FF.toInt()) {
            if (isRunning) {
                stopScriptRun()
            } else {
                showConfigChooser()
            }
        }
        val recordButton = menuButton("录制", 0xFFFFB989.toInt()) {
            openFlutterCommand("new_config")
        }
        val closeButton = menuButton("关闭", 0xFFFF8A80.toInt()) {
            closeAutomationMenu()
        }
        val foldButton = menuButton("折叠", 0xFFE8A8FF.toInt()) {
            showFloatingWindow(expanded = false)
        }

        listOf(configButton, startMenuButton, recordButton, closeButton, foldButton).forEach { button ->
            row.addView(
                button,
                LinearLayout.LayoutParams(dp(58), dp(42)).apply {
                    marginStart = dp(3)
                    marginEnd = dp(3)
                },
            )
        }
        attachDrag(row, layoutParams)
        return row
    }

    private fun createCollapsedMenu(layoutParams: WindowManager.LayoutParams): View {
        val bubble = TextView(this).apply {
            text = "展开"
            textSize = 13f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            background = roundedBackground(0xDD151A1E.toInt(), dp(24).toFloat(), 0x66FFFFFF)
            setOnClickListener { showFloatingWindow(expanded = true) }
        }
        attachDrag(bubble, layoutParams)
        return FrameLayout(this).apply {
            addView(bubble, FrameLayout.LayoutParams(dp(64), dp(48)))
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

    private fun attachDrag(view: View, layoutParams: WindowManager.LayoutParams) {
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
                        floatingView?.let { windowManager?.updateViewLayout(it, layoutParams) }
                        repositionChooser()
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (moving) {
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

    private fun showConfigChooser() {
        removeChooserOverlay()
        val layoutParams = baseOverlayParams().apply {
            width = dp(280)
            height = WindowManager.LayoutParams.WRAP_CONTENT
            x = floatingLayoutParams?.x ?: x
            y = (floatingLayoutParams?.y ?: y) + dp(60)
        }

        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(12), dp(14), dp(12))
            background = roundedBackground(0xF21F252B.toInt(), dp(18).toFloat(), 0x44FFFFFF)
        }
        panel.addView(TextView(this).apply {
            text = "选择配置"
            textSize = 15f
            setTextColor(Color.WHITE)
            setPadding(0, 0, 0, dp(8))
        })

        if (availableConfigs.isEmpty()) {
            panel.addView(TextView(this).apply {
                text = "还没有配置"
                textSize = 13f
                setTextColor(0xFFB8C0C8.toInt())
                setPadding(0, dp(12), 0, dp(12))
            })
            panel.addView(menuButton("新建配置", 0xFF7ED8C3.toInt()) {
                removeChooserOverlay()
                openFlutterCommand("new_config")
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(44)))
        } else {
            val list = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
            }
            availableConfigs.forEachIndexed { index, config ->
                val name = config["name"] as? String ?: "未命名配置"
                val actionCount = asMapList(config["actions"]).size
                val row = TextView(this).apply {
                    text = if (index == selectedConfigIndex) {
                        "$name  ·  $actionCount 个动作  ·  已选"
                    } else {
                        "$name  ·  $actionCount 个动作"
                    }
                    textSize = 13f
                    setTextColor(Color.WHITE)
                    setPadding(dp(10), dp(9), dp(10), dp(9))
                    background = roundedBackground(
                        if (index == selectedConfigIndex) 0x553D7BFF else 0x22111111,
                        dp(12).toFloat(),
                        if (index == selectedConfigIndex) 0x888EB8FF.toInt() else 0x22FFFFFF,
                    )
                    setOnClickListener {
                        selectedConfigIndex = index
                        showConfigChooser()
                    }
                }
                list.addView(
                    row,
                    LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    ).apply {
                        bottomMargin = dp(6)
                    },
                )
            }

            panel.addView(ScrollView(this).apply {
                addView(list)
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(180)))
            panel.addView(menuButton("播放", 0xFF4CAF50.toInt()) {
                val selected = availableConfigs.getOrNull(selectedConfigIndex)
                if (selected != null) {
                    removeChooserOverlay()
                    startConfig(selected)
                }
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(44)).apply {
                topMargin = dp(8)
            })
        }

        try {
            windowManager?.addView(panel, layoutParams)
            chooserOverlay = panel
        } catch (_: Exception) {
            chooserOverlay = null
        }
    }

    private fun repositionChooser() {
        val chooser = chooserOverlay ?: return
        val params = chooser.layoutParams as? WindowManager.LayoutParams ?: return
        params.x = floatingLayoutParams?.x ?: params.x
        params.y = (floatingLayoutParams?.y ?: params.y) + dp(60)
        windowManager?.updateViewLayout(chooser, params)
    }

    private fun startConfig(config: Map<String, Any?>) {
        val actions = asMapList(config["actions"])
        if (actions.isEmpty()) {
            return
        }
        handler.removeCallbacksAndMessages(null)
        minSeconds = 0
        maxSeconds = 0
        scriptName = config["name"] as? String ?: "配置"
        gestureActions.clear()
        gestureActions.addAll(actions)
        startScriptRun()
    }

    private fun startScriptRun() {
        if (gestureActions.isEmpty()) {
            return
        }
        isRunning = true
        updateStatusText()
        executeActionIndex(0)
    }

    private fun stopScriptRun() {
        isRunning = false
        handler.removeCallbacksAndMessages(null)
        updateStatusText()
    }

    private fun executeActionIndex(index: Int) {
        if (!isRunning) return

        if (index >= gestureActions.size) {
            if (minSeconds > 0 || maxSeconds > 0) {
                val delay = if (maxSeconds > minSeconds) {
                    (random.nextInt(maxSeconds - minSeconds + 1) + minSeconds) * 1000L
                } else {
                    minSeconds * 1000L
                }
                handler.postDelayed({ executeActionIndex(0) }, delay)
            } else {
                isRunning = false
                updateStatusText()
            }
            return
        }

        val action = gestureActions[index]
        when (action["type"] as? String ?: "swipe") {
            "swipe", "click", "recorded" -> {
                performGestureAction(action) {
                    executeActionIndex(index + 1)
                }
            }
            "nav" -> {
                val navType = action["navType"] as? String ?: "back"
                val globalAction = when (navType) {
                    "home" -> GLOBAL_ACTION_HOME
                    "recents" -> GLOBAL_ACTION_RECENTS
                    else -> GLOBAL_ACTION_BACK
                }
                performGlobalAction(globalAction)
                handler.postDelayed({ executeActionIndex(index + 1) }, 500)
            }
            "wait" -> {
                val seconds = (action["seconds"] as? Number)?.toInt() ?: 1
                handler.postDelayed({ executeActionIndex(index + 1) }, seconds * 1000L)
            }
            "launchApp" -> {
                val packageName = action["packageName"] as? String
                if (packageName != null) {
                    packageManager.getLaunchIntentForPackage(packageName)?.let { intent ->
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                    }
                }
                handler.postDelayed({ executeActionIndex(index + 1) }, 1000)
            }
            else -> executeActionIndex(index + 1)
        }
    }

    private fun performGestureAction(action: Map<String, Any?>, onDone: () -> Unit) {
        val dm = resources.displayMetrics
        val width = dm.widthPixels.toFloat()
        val height = dm.heightPixels.toFloat()
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
            onDone()
            return
        }

        try {
            dispatchGesture(gestureBuilder.build(), object : GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    handler.postDelayed({ onDone() }, 100)
                }

                override fun onCancelled(gestureDescription: GestureDescription?) {
                    handler.postDelayed({ onDone() }, 100)
                }
            }, null)
        } catch (_: Exception) {
            onDone()
        }
    }

    private fun addRecordedStrokes(
        builder: GestureDescription.Builder,
        action: Map<String, Any?>,
        width: Float,
        height: Float,
    ): Boolean {
        val segments = asMapList(action["segments"]).take(20)
        if (segments.isEmpty()) return false

        var added = false
        segments.forEach { segment ->
            val points = asMapList(segment["points"])
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

            val start = ((segment["start"] as? Number)?.toLong() ?: 0L).coerceAtLeast(0L)
            val duration = ((segment["duration"] as? Number)?.toLong() ?: 80L).coerceAtLeast(50L)
            try {
                builder.addStroke(GestureDescription.StrokeDescription(path, start, duration))
                added = true
            } catch (_: Exception) {
                // Ignore only the invalid segment; later segments may still be usable.
            }
        }
        return added
    }

    private fun showPickerOverlay(pickerType: String) {
        if (pickerOverlay != null) removePickerOverlay()
        if (pickerType == "record") {
            showRecordingOverlay()
            return
        }

        pickerMode = pickerType
        pickerData.clear()

        val lp = WindowManager.LayoutParams().apply {
            type = overlayType()
            format = PixelFormat.TRANSLUCENT
            flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
            width = WindowManager.LayoutParams.MATCH_PARENT
            height = WindowManager.LayoutParams.MATCH_PARENT
        }

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
            onPickerResult?.invoke(mapOf("cancelled" to true))
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
            onPickerResult?.invoke(mapOf("cancelled" to true))
            removePickerOverlay()
        }, LinearLayout.LayoutParams(dp(72), dp(40)))
        return row
    }

    private fun finishPositionPicker() {
        val mode = pickerMode ?: return
        val result = mutableMapOf<String, Any?>("type" to mode)
        result.putAll(pickerData)
        onPickerResult?.invoke(result)
        removePickerOverlay()
    }

    private fun showRecordingOverlay() {
        pickerMode = "recorded"
        val lp = WindowManager.LayoutParams().apply {
            type = overlayType()
            format = PixelFormat.TRANSLUCENT
            flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
            width = WindowManager.LayoutParams.MATCH_PARENT
            height = WindowManager.LayoutParams.MATCH_PARENT
        }

        val container = FrameLayout(this).apply {
            setBackgroundColor(0x33000000)
        }
        val surface = RecordingSurface(this)
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
        val recordButton = menuButton("开始录制", 0xFFFF4444.toInt()) {}
        val cancelButton = menuButton("取消", 0xFF607D8B.toInt()) {
            onPickerResult?.invoke(mapOf("cancelled" to true))
            removePickerOverlay()
        }
        var recording = false
        val timer = object : Runnable {
            override fun run() {
                if (!recording) return
                recordButton.text = "保存 ${formatElapsed(surface.elapsedMillis())}"
                handler.postDelayed(this, 200)
            }
        }
        recordButton.setOnClickListener {
            if (!recording) {
                recording = true
                surface.startRecording()
                recordButton.text = "保存 00:00"
                handler.post(timer)
            } else {
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
                onPickerResult?.invoke(surface.exportResult())
                removePickerOverlay()
            }
        }
        controls.addView(recordButton, LinearLayout.LayoutParams(dp(126), dp(40)).apply {
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
            onPickerResult?.invoke(mapOf("cancelled" to true))
        }
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
        pickerOverlay?.let {
            try {
                windowManager?.removeView(it)
            } catch (_: Exception) {
            }
            pickerOverlay = null
        }
        pickerMode = null
    }

    private fun removeChooserOverlay() {
        chooserOverlay?.let {
            try {
                windowManager?.removeView(it)
            } catch (_: Exception) {
            }
            chooserOverlay = null
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
    }

    private fun closeAutomationMenu() {
        stopScriptRun()
        removeChooserOverlay()
        removeFloatingWindow()
        collapsed = false
    }

    private fun updateStatusText() {
        startMenuButton?.text = when {
            isRunning -> "停止"
            scriptName != null -> "启动"
            else -> "启动"
        }
    }

    private fun openFlutterCommand(command: String) {
        removeChooserOverlay()
        if (!collapsed) {
            showFloatingWindow(expanded = false)
        }
        AlarmLaunchStore.setPendingOverlayCommand(this, command)
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra("overlayCommand", command)
        }
        startActivity(intent)
    }

    private fun roundedBackground(color: Int, radius: Float, strokeColor: Int): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = radius
            setColor(color)
            setStroke(dp(1), strokeColor)
        }
    }

    private fun asMapList(value: Any?): List<Map<String, Any?>> {
        return (value as? List<*>)?.mapNotNull { item ->
            (item as? Map<*, *>)?.let(::normalizeMap)
        } ?: emptyList()
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

    override fun onUnbind(intent: Intent?): Boolean {
        removeFloatingWindow()
        removeChooserOverlay()
        removePickerOverlay()
        instance = null
        return super.onUnbind(intent)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}

    private data class RecordedPoint(val x: Float, val y: Float, val t: Long)

    private data class RecordedSegment(
        val start: Long,
        var duration: Long = 80L,
        val points: MutableList<RecordedPoint> = mutableListOf(),
    )

    private class RecordingSurface(context: Context) : View(context) {
        private val segments = mutableListOf<RecordedSegment>()
        private var currentSegment: RecordedSegment? = null
        private var recording = false
        private var startedAt = 0L

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
                "segments" to segments.filter { it.points.isNotEmpty() }.map { segment ->
                    mapOf(
                        "start" to segment.start,
                        "duration" to segment.duration.coerceAtLeast(50L),
                        "points" to segment.points.map { point ->
                            mapOf("x" to point.x, "y" to point.y, "t" to point.t)
                        },
                    )
                },
            )
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            if (!recording || width <= 0 || height <= 0) {
                return true
            }
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    val start = (event.eventTime - startedAt).coerceAtLeast(0L)
                    currentSegment = RecordedSegment(start = start).also {
                        segments.add(it)
                    }
                    appendPoint(event.x, event.y, event.eventTime)
                    invalidate()
                }
                MotionEvent.ACTION_MOVE -> {
                    for (index in 0 until event.historySize) {
                        appendPoint(
                            event.getHistoricalX(index),
                            event.getHistoricalY(index),
                            event.getHistoricalEventTime(index),
                        )
                    }
                    appendPoint(event.x, event.y, event.eventTime)
                    invalidate()
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    appendPoint(event.x, event.y, event.eventTime)
                    finishCurrentSegment(event.eventTime)
                    invalidate()
                }
            }
            return true
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            segments.forEach { segment ->
                if (segment.points.isEmpty()) return@forEach
                val path = Path()
                segment.points.forEachIndexed { index, point ->
                    val x = point.x * width
                    val y = point.y * height
                    if (index == 0) {
                        path.moveTo(x, y)
                    } else {
                        path.lineTo(x, y)
                    }
                }
                canvas.drawPath(path, pathPaint)
                val first = segment.points.first()
                canvas.drawCircle(first.x * width, first.y * height, 8f, pointPaint)
            }
        }

        private fun appendPoint(x: Float, y: Float, eventTime: Long) {
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

        private fun finishCurrentSegment(eventTime: Long) {
            val segment = currentSegment ?: return
            val end = (eventTime - startedAt).coerceAtLeast(segment.start + 50L)
            segment.duration = (end - segment.start).coerceAtLeast(50L)
            currentSegment = null
        }
    }
}
