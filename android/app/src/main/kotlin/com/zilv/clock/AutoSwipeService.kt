package com.zilv.clock

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Context
import android.content.Intent
import android.graphics.Path
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.FrameLayout
import android.widget.TextView
import java.util.Random

class AutoSwipeService : AccessibilityService() {

    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var isRunning = false
    private var minSeconds = 0
    private var maxSeconds = 0
    private var scriptName: String? = null
    
    private var gestureActions = mutableListOf<Map<String, Any>>()
    
    private val handler = Handler(Looper.getMainLooper())
    private val random = Random()

    private var pickerMode: String? = null // "click" or "swipe"
    private var pickerOverlay: View? = null
    private var pickerData: MutableMap<String, Float> = mutableMapOf()

    companion object {
        var instance: AutoSwipeService? = null
        var onPickerResult: ((Map<String, Any>) -> Unit)? = null
        
        fun updateConfig(min: Int, max: Int, actions: List<Map<String, Any>>, name: String? = null) {
            instance?.apply {
                handler.removeCallbacksAndMessages(null)
                minSeconds = min
                maxSeconds = max
                scriptName = name
                gestureActions.clear()
                gestureActions.addAll(actions)
                updateStatusText()
                
                if (min == 0 && max == 0 && actions.isNotEmpty()) {
                    if (!isRunning) toggleRunning() else startScriptExecution()
                }
            }
        }

        fun enterPickerMode(type: String) {
            instance?.showPickerOverlay(type)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        if (gestureActions.isEmpty()) {
            gestureActions.add(mapOf(
                "type" to "swipe",
                "x1" to 0.5f, "y1" to 0.7f,
                "x2" to 0.5f, "y2" to 0.3f,
                "duration" to 400
            ))
        }
        showFloatingWindow()
    }

    private fun showPickerOverlay(pickerType: String) {
        if (pickerOverlay != null) removePickerOverlay()
        pickerMode = pickerType
        pickerData.clear()

        val lp = WindowManager.LayoutParams().apply {
            type = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }
            format = PixelFormat.TRANSLUCENT
            flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
            width = WindowManager.LayoutParams.MATCH_PARENT
            height = WindowManager.LayoutParams.MATCH_PARENT
        }

        val container = FrameLayout(this)
        
        if (pickerType == "click") {
            val marker = createPickerMarker("点我", 0xFF2196F3.toInt())
            val mlp = FrameLayout.LayoutParams(150, 150).apply {
                gravity = Gravity.CENTER
            }
            container.addView(marker, mlp)
            
            setupDraggableMarker(marker) { x, y ->
                pickerData["x1"] = x
                pickerData["y1"] = y
            }
        } else {
            val startMarker = createPickerMarker("起点", 0xFF4CAF50.toInt())
            val endMarker = createPickerMarker("终点", 0xFFF44336.toInt())
            
            container.addView(startMarker, FrameLayout.LayoutParams(150, 150).apply { 
                gravity = Gravity.CENTER
                topMargin = -200
            })
            container.addView(endMarker, FrameLayout.LayoutParams(150, 150).apply { 
                gravity = Gravity.CENTER
                topMargin = 200
            })

            setupDraggableMarker(startMarker) { x, y ->
                pickerData["x1"] = x
                pickerData["y1"] = y
            }
            setupDraggableMarker(endMarker) { x, y ->
                pickerData["x2"] = x
                pickerData["y2"] = y
            }
        }

        windowManager?.addView(container, lp)
        pickerOverlay = container
        updateStatusText()
    }

    private fun createPickerMarker(label: String, color: Int): View {
        return FrameLayout(this).apply {
            val shape = android.graphics.drawable.GradientDrawable().apply {
                shape = android.graphics.drawable.GradientDrawable.OVAL
                setColor(color and 0x88FFFFFF.toInt())
                setStroke(5, color)
            }
            background = shape
            addView(TextView(context).apply {
                text = label
                setTextColor(0xFFFFFFFF.toInt())
                textSize = 10f
                gravity = Gravity.CENTER
            }, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        }
    }

    private fun setupDraggableMarker(view: View, onPosChanged: (Float, Float) -> Unit) {
        val dm = resources.displayMetrics
        view.setOnTouchListener { v, event ->
            when (event.action) {
                MotionEvent.ACTION_MOVE -> {
                    v.x = event.rawX - v.width / 2f
                    v.y = event.rawY - v.height / 2f
                    onPosChanged(event.rawX / dm.widthPixels, event.rawY / dm.heightPixels)
                    true
                }
                else -> true
            }
        }
        handler.post {
            onPosChanged(0.5f, 0.5f)
        }
    }

    private fun removePickerOverlay() {
        pickerOverlay?.let {
            windowManager?.removeView(it)
            pickerOverlay = null
        }
        pickerMode = null
        updateStatusText()
    }

    private fun updateStatusText() {
        val inner = (floatingView as? FrameLayout)?.getChildAt(0)
        val statusText = inner?.findViewById<TextView>(1001)
        if (statusText != null) {
            if (pickerMode != null) {
                statusText.text = "✔ 保存位置"
                val shape = android.graphics.drawable.GradientDrawable().apply {
                    shape = android.graphics.drawable.GradientDrawable.RECTANGLE
                    cornerRadius = 60f
                    setColor(0xAA4CAF50.toInt()) 
                    setStroke(2, 0xFFFFFFFF.toInt())
                }
                inner.background = shape
            } else if (isRunning) {
                statusText.text = "■ 停止"
            } else {
                statusText.text = if (scriptName != null) "▶ $scriptName" else "▶ 开始"
            }
        }
    }

    private fun toggleRunning() {
        if (pickerMode != null) {
            val result = mutableMapOf<String, Any>("type" to pickerMode!!)
            result.putAll(pickerData)
            onPickerResult?.invoke(result)
            removePickerOverlay()
            return
        }

        isRunning = !isRunning
        val inner = (floatingView as? FrameLayout)?.getChildAt(0)
        if (inner != null) {
            if (isRunning) {
                val shape = android.graphics.drawable.GradientDrawable().apply {
                    shape = android.graphics.drawable.GradientDrawable.RECTANGLE
                    cornerRadius = 60f
                    setColor(0xAAFF4444.toInt())
                    setStroke(2, 0xFFFFFFFF.toInt())
                }
                inner.background = shape
                startScriptExecution()
            } else {
                val shape = android.graphics.drawable.GradientDrawable().apply {
                    shape = android.graphics.drawable.GradientDrawable.RECTANGLE
                    cornerRadius = 60f
                    setColor(0xAA000000.toInt())
                    setStroke(2, 0xFFFFFFFF.toInt())
                }
                inner.background = shape
                handler.removeCallbacksAndMessages(null)
            }
        }
        updateStatusText()
    }

    private fun startScriptExecution() {
        if (!isRunning) return
        executeActionIndex(0)
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
                handler.postDelayed({ startScriptExecution() }, delay)
            } else {
                toggleRunning()
            }
            return
        }

        val action = gestureActions[index]
        val actionType = action["type"] as? String ?: "swipe"
        
        when (actionType) {
            "swipe", "click" -> {
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
                    val intent = packageManager.getLaunchIntentForPackage(packageName)
                    if (intent != null) {
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                    }
                }
                handler.postDelayed({ executeActionIndex(index + 1) }, 1000)
            }
            else -> executeActionIndex(index + 1)
        }
    }

    private fun performGestureAction(action: Map<String, Any>, onDone: () -> Unit) {
        val dm = resources.displayMetrics
        val width = dm.widthPixels.toFloat()
        val height = dm.heightPixels.toFloat()
        val actionType = action["type"] as? String ?: "swipe"
        val duration = ((action["duration"] as? Number)?.toLong() ?: 300L)

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

        val gestureBuilder = GestureDescription.Builder()
        gestureBuilder.addStroke(GestureDescription.StrokeDescription(path, 0, duration))
        
        try {
            dispatchGesture(gestureBuilder.build(), object : GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    handler.postDelayed({ onDone() }, 100)
                }
                override fun onCancelled(gestureDescription: GestureDescription?) {
                    handler.postDelayed({ onDone() }, 100)
                }
            }, null)
        } catch (e: Exception) {
            onDone()
        }
    }

    private fun showFloatingWindow() {
        val layoutParams = WindowManager.LayoutParams().apply {
            type = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }
            format = PixelFormat.TRANSLUCENT
            flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
            width = WindowManager.LayoutParams.WRAP_CONTENT
            height = WindowManager.LayoutParams.WRAP_CONTENT
            gravity = Gravity.TOP or Gravity.START
            x = 100
            y = 100
        }

        floatingView = FrameLayout(this).apply {
            val inner = FrameLayout(context).apply {
                val shape = android.graphics.drawable.GradientDrawable().apply {
                    shape = android.graphics.drawable.GradientDrawable.RECTANGLE
                    cornerRadius = 60f
                    setColor(0xAA000000.toInt())
                    setStroke(2, 0xFFFFFFFF.toInt())
                }
                background = shape
                setPadding(20, 10, 20, 10)
            }
            
            val text = TextView(context).apply {
                id = 1001
                text = "▶ 开始"
                textSize = 12f
                setTextColor(0xFFFFFFFF.toInt())
                gravity = Gravity.CENTER
            }
            inner.addView(text, FrameLayout.LayoutParams(160, 80))
            addView(inner)

            var initialX = 0
            var initialY = 0
            var initialTouchX = 0f
            var initialTouchY = 0f
            var isMoving = false

            setOnTouchListener { _, event ->
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = layoutParams.x
                        initialY = layoutParams.y
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        isMoving = false
                        true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = event.rawX - initialTouchX
                        val dy = event.rawY - initialTouchY
                        if (Math.abs(dx) > 10 || Math.abs(dy) > 10) {
                            isMoving = true
                            layoutParams.x = initialX + dx.toInt()
                            layoutParams.y = initialY + dy.toInt()
                            windowManager?.updateViewLayout(floatingView, layoutParams)
                        }
                        true
                    }
                    MotionEvent.ACTION_UP -> {
                        if (!isMoving) {
                            toggleRunning()
                        }
                        true
                    }
                    else -> false
                }
            }
        }
        windowManager?.addView(floatingView, layoutParams)
    }

    private fun removeFloatingWindow() {
        floatingView?.let {
            windowManager?.removeView(it)
            floatingView = null
        }
    }

    override fun onUnbind(intent: Intent?): Boolean {
        removeFloatingWindow()
        removePickerOverlay()
        instance = null
        return super.onUnbind(intent)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}
}
