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
import android.graphics.Rect
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.text.InputType
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
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
    private var pickerOverlay: View? = null
    private var startMenuButton: TextView? = null

    private var isRunning = false
    private var minSeconds = 0
    private var maxSeconds = 0
    private var scriptName: String? = null
    private var collapsed = false
    private var selectedConfigIndex = -1

    private val gestureActions = mutableListOf<Map<String, Any?>>()
    private val runtimeActions = mutableListOf<Map<String, Any?>>()
    private val availableConfigs = mutableListOf<Map<String, Any?>>()
    private val floatingRecordActions = mutableListOf<Map<String, Any?>>()
    private var floatingRecordName = ""
    private val pickerData: MutableMap<String, Float> = mutableMapOf()
    private var pickerMode: String? = null
    private var nativePickerResult: ((Map<String, Any?>) -> Unit)? = null
    private var runStartedAt = 0L
    private var runTotalMillis = 0L
    private var playbackTicker: Runnable? = null
    private val defaultGestureBeforeWaitMillis = 300
    private val defaultGestureAfterWaitMillis = 800

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

        fun openAppAndRunConfig(
            context: Context,
            packageName: String,
            packageLabel: String,
            configName: String?,
            actions: List<Map<String, Any?>>,
            delaySeconds: Int = 5,
        ): Boolean {
            val launchIntent = context.packageManager.getLaunchIntentForPackage(packageName)
                ?: return false
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(launchIntent)

            val service = instance ?: return true
            service.handler.postDelayed({
                service.showFloatingWindow(expanded = false, attachToRightEdge = true)
                if (actions.isNotEmpty()) {
                    updateConfig(0, 0, actions, configName ?: packageLabel)
                }
            }, delaySeconds.coerceAtLeast(0) * 1000L)
            return true
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

    private fun showFloatingWindow(
        expanded: Boolean,
        attachToRightEdge: Boolean = false,
    ): Boolean {
        removeFloatingWindow()
        removeChooserOverlay()
        collapsed = !expanded

        val layoutParams = baseOverlayParams()
        val root = if (expanded) createExpandedMenu(layoutParams) else createCollapsedMenu(layoutParams)
        val shouldAttachRight = attachToRightEdge || !expanded
        clampOverlayPosition(root, layoutParams, attachRight = shouldAttachRight)

        return try {
            windowManager?.addView(root, layoutParams)
            floatingView = root
            floatingLayoutParams = layoutParams
            updateStatusText()
            handler.post {
                val params = floatingLayoutParams ?: return@post
                val view = floatingView ?: return@post
                clampOverlayPosition(view, params, attachRight = shouldAttachRight)
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
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(6), dp(5), dp(6), dp(5))
            background = roundedBackground(0xE6151A1E.toInt(), dp(22).toFloat(), 0x55FFFFFF)
        }

        val configButton = iconButton("⚙", "配置", 0xFF7ED8C3.toInt()) {
            openFlutterCommand("open_configs")
        }
        startMenuButton = iconButton("▶", "启动", 0xFF8EB8FF.toInt()) {
            if (isRunning) {
                stopScriptRun()
            } else {
                showConfigChooser()
            }
        }
        val recordButton = iconButton("●", "录制", 0xFFFFB989.toInt()) {
            showFloatingRecorder()
        }
        val closeButton = iconButton("×", "关闭", 0xFFFF8A80.toInt()) {
            closeAutomationMenu()
        }
        val foldButton = iconButton("›", "折叠", 0xFFE8A8FF.toInt()) {
            showFloatingWindow(expanded = false, attachToRightEdge = true)
        }

        listOf(configButton, startMenuButton, recordButton, closeButton, foldButton).forEach { button ->
            row.addView(
                button,
                LinearLayout.LayoutParams(dp(38), dp(38)).apply {
                    marginStart = dp(2)
                    marginEnd = dp(2)
                },
            )
        }
        attachDrag(row, layoutParams)
        return row
    }

    private fun createCollapsedMenu(layoutParams: WindowManager.LayoutParams): View {
        val bubble = TextView(this).apply {
            text = "‹"
            textSize = 28f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            contentDescription = "展开"
            background = roundedBackground(0xE6151A1E.toInt(), dp(18).toFloat(), 0x66FFFFFF)
            setOnClickListener { showFloatingWindow(expanded = true) }
        }
        attachDrag(bubble, layoutParams, stickToRight = true)
        return FrameLayout(this).apply {
            addView(bubble, FrameLayout.LayoutParams(dp(40), dp(48)))
        }
    }

    private fun iconButton(
        icon: String,
        description: String,
        color: Int,
        onClick: () -> Unit,
    ): TextView {
        return TextView(this).apply {
            text = icon
            textSize = 18f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            contentDescription = description
            background = roundedBackground(color and 0xCCFFFFFF.toInt(), dp(16).toFloat(), 0x33FFFFFF)
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
        stickToRight: Boolean = false,
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
                        clampOverlayPosition(root, layoutParams, attachRight = stickToRight)
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

    private fun clampOverlayPosition(
        view: View?,
        layoutParams: WindowManager.LayoutParams,
        attachRight: Boolean = false,
    ) {
        val dm = resources.displayMetrics
        val fallbackWidth = if (collapsed) dp(40) else dp(220)
        val fallbackHeight = if (collapsed) dp(48) else dp(48)
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
        val maxX = (dm.widthPixels - width).coerceAtLeast(0)
        val maxY = (dm.heightPixels - height).coerceAtLeast(0)
        layoutParams.x = if (attachRight) maxX else layoutParams.x.coerceIn(0, maxX)
        layoutParams.y = layoutParams.y.coerceIn(0, maxY)
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
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
            } else {
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
            }
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
            x = floatingLayoutParams?.x ?: x
            y = (floatingLayoutParams?.y ?: y) + dp(60)
            clampOverlayPosition(null, this)
        }
    }

    private fun addChooserPanel(view: View, layoutParams: WindowManager.LayoutParams) {
        try {
            windowManager?.addView(view, layoutParams)
            chooserOverlay = view
            handler.post {
                val chooser = chooserOverlay ?: return@post
                val params = chooser.layoutParams as? WindowManager.LayoutParams ?: return@post
                clampOverlayPosition(chooser, params)
                try {
                    windowManager?.updateViewLayout(chooser, params)
                } catch (_: Exception) {
                }
            }
        } catch (_: Exception) {
            chooserOverlay = null
        }
    }

    private fun showConfigChooser() {
        removeChooserOverlay()
        val layoutParams = floatingPanelParams(widthDp = 280)

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
                showFloatingRecorder()
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(44)))
        } else {
            val list = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
            }
            availableConfigs.forEachIndexed { index, config ->
                val name = config["name"] as? String ?: "未命名配置"
                val actions = asMapList(config["actions"])
                val actionCount = actions.size
                val duration = estimateActionsDurationLabel(actions)
                val row = TextView(this).apply {
                    text = if (index == selectedConfigIndex) {
                        "$name  ·  $actionCount 个动作 · 约 $duration  ·  已选"
                    } else {
                        "$name  ·  $actionCount 个动作 · 约 $duration"
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

        addChooserPanel(panel, layoutParams)
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
            val defaultMillis = ((current?.get("waitMillis") as? Number)?.toInt()
                ?: ((current?.get("seconds") as? Number)?.toInt()?.times(1000))
                ?: defaultGestureAfterWaitMillis).coerceIn(1, 10_000_000)
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
                        ?: defaultGestureAfterWaitMillis).coerceIn(1, 10_000_000)
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

    private fun showFloatingButtonEditor(seed: Map<String, Any?>, editIndex: Int? = null) {
        removeChooserOverlay()
        val layoutParams = floatingPanelParams(widthDp = 340, focusable = true)
        val panel = floatingPanel("按钮识别")
        val textInput = inputField(seed["buttonText"] as? String ?: "", "按钮文字", numberOnly = false)
        val idInput = inputField(seed["buttonId"] as? String ?: "", "按钮ID", numberOnly = false)
        val descInput = inputField(seed["buttonDescription"] as? String ?: "", "按钮描述", numberOnly = false)
        val retryInput = inputField(((seed["retryCount"] as? Number)?.toInt() ?: 3).toString(), "重试次数", numberOnly = true)
        val waitInput = inputField(((seed["retryWaitMillis"] as? Number)?.toInt() ?: 800).toString(), "重试等待毫秒", numberOnly = true)

        panel.addView(fieldLabel("识别方式"))
        panel.addView(TextView(this).apply {
            text = "保存时选择：完全相同 / 包含"
            textSize = 12f
            setTextColor(0xFFB8C0C8.toInt())
            setPadding(0, 0, 0, dp(8))
        })
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

        fun save(matchMode: String, failAction: String) {
            val action = mapOf(
                    "type" to "buttonRecognize",
                    "buttonText" to textInput.text?.toString()?.trim().orEmpty(),
                    "buttonId" to idInput.text?.toString()?.trim().orEmpty(),
                    "buttonDescription" to descInput.text?.toString()?.trim().orEmpty(),
                    "matchMode" to matchMode,
                    "regionMode" to "full",
                    "successMode" to "defaultClick",
                    "retryCount" to ((retryInput.text?.toString()?.trim()?.toIntOrNull() ?: 3).coerceIn(0, 20)),
                    "retryWaitMillis" to ((waitInput.text?.toString()?.trim()?.toIntOrNull() ?: 800).coerceIn(0, 10_000_000)),
                    "retrySuccessMode" to "defaultClick",
                    "failAction" to failAction,
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
        row.addView(menuButton("包含保存", 0xFF4CAF50.toInt()) {
            save("contains", "notify")
        }, LinearLayout.LayoutParams(0, dp(42), 1f))
        panel.addView(row)
        panel.addView(menuButton("完全相同保存", 0xFF8EB8FF.toInt()) {
            save("exact", "notify")
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(42)).apply {
            topMargin = dp(8)
        })
        panel.addView(menuButton("失败锁屏保存", 0xFFFF5252.toInt()) {
            save("contains", "lockScreen")
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(42)).apply {
            topMargin = dp(8)
        })

        addChooserPanel(panel, layoutParams)
    }

    private fun appendFloatingPickerResult(result: Map<String, Any?>) {
        appendGestureActionsWithBuffers(floatingActionsFromPickerResult(result))
    }

    private fun floatingActionsFromPickerResult(result: Map<String, Any?>): List<Map<String, Any?>> {
        return when (result["type"] as? String) {
            "clickSteps" -> {
                val points = result["points"] as? List<*> ?: emptyList<Any?>()
                points.mapNotNull { point ->
                    val map = point as? Map<*, *> ?: return@mapNotNull null
                    mapOf(
                        "type" to "click",
                        "x1" to ((map["x"] as? Number)?.toDouble() ?: 0.5),
                        "y1" to ((map["y"] as? Number)?.toDouble() ?: 0.5),
                        "duration" to 50,
                    )
                }
            }
            "recorded" -> {
                if (asMapList(result["segments"]).isNotEmpty()) {
                    listOf(normalizeMap(result))
                } else {
                    emptyList()
                }
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

    private fun appendGestureActionsWithBuffers(actions: List<Map<String, Any?>>) {
        actions.forEach { action ->
            floatingRecordActions.add(fixedMillisWaitAction(defaultGestureBeforeWaitMillis))
            floatingRecordActions.add(action)
            floatingRecordActions.add(fixedMillisWaitAction(defaultGestureAfterWaitMillis))
        }
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
                "识别“$text” · $mode · 失败重试 ${((action["retryCount"] as? Number)?.toInt() ?: 3)} 次"
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
        val chooser = chooserOverlay ?: return
        val params = chooser.layoutParams as? WindowManager.LayoutParams ?: return
        params.x = floatingLayoutParams?.x ?: params.x
        params.y = (floatingLayoutParams?.y ?: params.y) + dp(60)
        clampOverlayPosition(chooser, params)
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
        runtimeActions.clear()
        runtimeActions.addAll(gestureActions.map(::planRuntimeAction))
        runStartedAt = SystemClock.uptimeMillis()
        runTotalMillis = estimateActionsMillis(runtimeActions)
        isRunning = true
        updateStatusText()
        showFloatingWindow(expanded = false, attachToRightEdge = true)
        startPlaybackTicker()
        executeActionIndex(0)
    }

    private fun stopScriptRun() {
        isRunning = false
        handler.removeCallbacksAndMessages(null)
        playbackTicker = null
        runtimeActions.clear()
        updateStatusText()
    }

    private fun executeActionIndex(index: Int) {
        if (!isRunning) return

        if (index >= runtimeActions.size) {
            if (minSeconds > 0 || maxSeconds > 0) {
                val delay = if (maxSeconds > minSeconds) {
                    (random.nextInt(maxSeconds - minSeconds + 1) + minSeconds) * 1000L
                } else {
                    minSeconds * 1000L
                }
                handler.postDelayed({ executeActionIndex(0) }, delay)
            } else {
                isRunning = false
                playbackTicker = null
                runtimeActions.clear()
                updateStatusText()
            }
            return
        }

        val action = runtimeActions[index]
        when (action["type"] as? String ?: "swipe") {
            "swipe", "click", "recorded" -> {
                performGestureAction(action) {
                    executeActionIndex(index + 1)
                }
            }
            "nav" -> {
                val navType = action["navType"] as? String ?: "back"
                performNavigationAction(navType) {
                    executeActionIndex(index + 1)
                }
            }
            "wait" -> {
                val waitMillis = resolveWaitMillis(action)
                handler.postDelayed({ executeActionIndex(index + 1) }, waitMillis)
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
            "buttonRecognize" -> {
                performButtonRecognizeAction(action) {
                    executeActionIndex(index + 1)
                }
            }
            "lockScreen" -> {
                performLockScreenAction {
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

    private fun performButtonRecognizeAction(action: Map<String, Any?>, onDone: () -> Unit) {
        val retryCount = ((action["retryCount"] as? Number)?.toInt() ?: 3).coerceIn(0, 20)
        val retryWait = ((action["retryWaitMillis"] as? Number)?.toLong() ?: 800L).coerceIn(0L, 10_000_000L)
        val retryActions = asMapList(action["retryActions"])

        fun attempt(remaining: Int, afterRetry: Boolean) {
            val match = findMatchingButton(action)
            if (match != null) {
                val modeKey = if (afterRetry) "retrySuccessMode" else "successMode"
                val actionsKey = if (afterRetry) "retrySuccessActions" else "successActions"
                val mode = action[modeKey] as? String ?: "defaultClick"
                val customActions = asMapList(action[actionsKey])
                if (mode == "custom" && customActions.isNotEmpty()) {
                    executeInlineActions(customActions, onDone)
                } else {
                    performButtonClick(match) {
                        handler.postDelayed(onDone, 250)
                    }
                }
                return
            }

            if (remaining > 0) {
                executeInlineActions(retryActions) {
                    handler.postDelayed({ attempt(remaining - 1, afterRetry = true) }, retryWait)
                }
                return
            }

            when (action["failAction"] as? String ?: "notify") {
                "lockScreen" -> performLockScreenAction(onDone)
                "notify" -> {
                    showScriptFailureNotice(action)
                    onDone()
                }
                else -> onDone()
            }
        }

        attempt(retryCount, afterRetry = false)
    }

    private fun executeInlineActions(actions: List<Map<String, Any?>>, onDone: () -> Unit) {
        fun runAt(index: Int) {
            if (index >= actions.size) {
                onDone()
                return
            }
            val action = actions[index]
            when (action["type"] as? String ?: "swipe") {
                "swipe", "click", "recorded" -> performGestureAction(action) { runAt(index + 1) }
                "nav" -> performNavigationAction(action["navType"] as? String ?: "back") { runAt(index + 1) }
                "wait" -> handler.postDelayed({ runAt(index + 1) }, resolveWaitMillis(action))
                "launchApp" -> {
                    val packageName = action["packageName"] as? String
                    if (packageName != null) {
                        packageManager.getLaunchIntentForPackage(packageName)?.let { intent ->
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                        }
                    }
                    handler.postDelayed({ runAt(index + 1) }, 1000)
                }
                "lockScreen" -> performLockScreenAction { runAt(index + 1) }
                else -> runAt(index + 1)
            }
        }
        runAt(0)
    }

    private fun findMatchingButton(action: Map<String, Any?>): ButtonNodeInfo? {
        val nodes = collectButtonNodes(rootInActiveWindow)
        val targetText = ((action["buttonText"] as? String) ?: (action["text"] as? String) ?: "").trim()
        val targetId = ((action["buttonId"] as? String) ?: (action["viewId"] as? String) ?: "").trim()
        val targetDescription = ((action["buttonDescription"] as? String) ?: (action["description"] as? String) ?: "").trim()
        val exact = (action["matchMode"] as? String) == "exact"
        val region = actionRegionRect(action)
        return nodes.firstOrNull { node ->
            if (region != null && !Rect.intersects(region, node.bounds)) {
                return@firstOrNull false
            }
            val textMatched = targetText.isNotEmpty() &&
                textMatches(node.text.ifBlank { node.description }, targetText, exact)
            val idMatched = targetId.isNotEmpty() && textMatches(node.viewId, targetId, exact)
            val descriptionMatched = targetDescription.isNotEmpty() &&
                textMatches(node.description, targetDescription, exact)
            textMatched || idMatched || descriptionMatched
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

    private fun actionRegionRect(action: Map<String, Any?>): Rect? {
        if ((action["regionMode"] as? String ?: "full") != "custom") return null
        val region = normalizeMap(action["region"] as? Map<*, *> ?: return null)
        val dm = resources.displayMetrics
        val left = (((region["left"] as? Number)?.toFloat() ?: 0f) * dm.widthPixels).toInt()
        val top = (((region["top"] as? Number)?.toFloat() ?: 0f) * dm.heightPixels).toInt()
        val right = (((region["right"] as? Number)?.toFloat() ?: 1f) * dm.widthPixels).toInt()
        val bottom = (((region["bottom"] as? Number)?.toFloat() ?: 1f) * dm.heightPixels).toInt()
        return Rect(left, top, right, bottom)
    }

    private fun performButtonClick(node: ButtonNodeInfo, onDone: () -> Unit) {
        val path = Path().apply {
            moveTo(node.bounds.centerX().toFloat(), node.bounds.centerY().toFloat())
        }
        try {
            dispatchGesture(
                GestureDescription.Builder()
                    .addStroke(GestureDescription.StrokeDescription(path, 0, 80))
                    .build(),
                object : GestureResultCallback() {
                    override fun onCompleted(gestureDescription: GestureDescription?) {
                        onDone()
                    }

                    override fun onCancelled(gestureDescription: GestureDescription?) {
                        onDone()
                    }
                },
                null,
            )
        } catch (_: Exception) {
            onDone()
        }
    }

    private fun performLockScreenAction(onDone: () -> Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
        }
        handler.postDelayed(onDone, 500)
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

    private fun performNavigationAction(navType: String, onDone: () -> Unit) {
        val globalAction = when (navType) {
            "home" -> GLOBAL_ACTION_HOME
            "recents" -> GLOBAL_ACTION_RECENTS
            else -> GLOBAL_ACTION_BACK
        }
        handler.post {
            val success = performGlobalAction(globalAction)
            if (!success) {
                if (navType == "home") {
                    launchHomeFallback()
                }
                handler.postDelayed({ performGlobalAction(globalAction) }, 250)
            }
            handler.postDelayed({ onDone() }, if (navType == "recents") 900L else 650L)
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
        if (pickerType == "clickSteps") {
            showClickStepsOverlay()
            return
        }
        if (pickerType == "buttonDetect") {
            showButtonDetectOverlay()
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
            publishPickerResult(mapOf("cancelled" to true))
            removePickerOverlay()
        }, LinearLayout.LayoutParams(dp(72), dp(40)))
        return row
    }

    private fun finishPositionPicker() {
        val mode = pickerMode ?: return
        val result = mutableMapOf<String, Any?>("type" to mode)
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
            publishPickerResult(mapOf("cancelled" to true))
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
                publishPickerResult(surface.exportResult())
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
            publishPickerResult(mapOf("cancelled" to true))
        }
    }

    private fun showClickStepsOverlay() {
        pickerMode = "clickSteps"
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
        val surface = ClickStepSurface(this)
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
        val lp = WindowManager.LayoutParams().apply {
            type = overlayType()
            format = PixelFormat.TRANSLUCENT
            flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
            width = WindowManager.LayoutParams.MATCH_PARENT
            height = WindowManager.LayoutParams.MATCH_PARENT
        }

        val container = FrameLayout(this).apply {
            setBackgroundColor(0x11000000)
        }
        val surface = ButtonDetectSurface(this, nodes) { node ->
            publishPickerResult(node.toResult(resources.displayMetrics.widthPixels, resources.displayMetrics.heightPixels))
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

    private fun collectButtonNodes(root: AccessibilityNodeInfo?): List<ButtonNodeInfo> {
        if (root == null) return emptyList()
        val out = mutableListOf<ButtonNodeInfo>()
        val seen = mutableSetOf<String>()

        fun visit(node: AccessibilityNodeInfo?) {
            if (node == null) return
            val rect = Rect()
            node.getBoundsInScreen(rect)
            val text = node.text?.toString().orEmpty()
            val description = node.contentDescription?.toString().orEmpty()
            val viewId = node.viewIdResourceName.orEmpty()
            val className = node.className?.toString().orEmpty()
            val looksLikeButton = node.isClickable ||
                className.contains("Button", ignoreCase = true) ||
                className.contains("TextView", ignoreCase = true) && (text.isNotBlank() || description.isNotBlank())
            if (node.isVisibleToUser &&
                looksLikeButton &&
                rect.width() > dp(16) &&
                rect.height() > dp(16) &&
                rect.left >= 0 &&
                rect.top >= 0
            ) {
                val key = "${rect.flattenToString()}|$text|$description|$viewId"
                if (seen.add(key)) {
                    out.add(ButtonNodeInfo(rect, text, viewId, description, className))
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
        val button = startMenuButton ?: return
        if (isRunning) {
            val elapsed = (SystemClock.uptimeMillis() - runStartedAt).coerceAtLeast(0L)
            button.text = "■"
            button.contentDescription =
                "停止，${formatShortElapsed(elapsed)}/${formatShortElapsed(runTotalMillis)}"
        } else {
            button.text = "▶"
            button.contentDescription = "启动"
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

    private data class StepPoint(var x: Float, var y: Float)

    private data class ButtonNodeInfo(
        val bounds: Rect,
        val text: String,
        val viewId: String,
        val description: String,
        val className: String,
    ) {
        fun toResult(screenWidth: Int, screenHeight: Int): Map<String, Any?> {
            return mapOf(
                "type" to "buttonRecognize",
                "buttonText" to text,
                "buttonId" to viewId,
                "buttonDescription" to description,
                "className" to className,
                "matchMode" to "contains",
                "regionMode" to "full",
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
                val selected = nodes.firstOrNull {
                    it.bounds.contains(event.rawX.toInt(), event.rawY.toInt())
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
                canvas.drawRect(node.bounds, fillPaint)
                canvas.drawRect(node.bounds, rectPaint)
                val label = (node.text.ifBlank { node.description }.ifBlank { "${index + 1}" }).take(12)
                val labelWidth = labelPaint.measureText(label) + 10f * density
                val top = (node.bounds.top - 20f * density).coerceAtLeast(0f)
                canvas.drawRect(
                    node.bounds.left.toFloat(),
                    top,
                    node.bounds.left + labelWidth,
                    top + 18f * density,
                    labelBgPaint,
                )
                canvas.drawText(label, node.bounds.left + 5f * density, top + 13f * density, labelPaint)
            }
        }
    }

    private class ClickStepSurface(context: Context) : View(context) {
        private val points = mutableListOf<StepPoint>()
        private var selectedIndex = -1
        private var downIndex = -1

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
                mapOf("x" to point.x.toDouble(), "y" to point.y.toDouble())
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
                        points.add(
                            StepPoint(
                                (event.x / width).coerceIn(0f, 1f),
                                (event.y / height).coerceIn(0f, 1f),
                            ),
                        )
                        selectedIndex = points.lastIndex
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
