package com.zilv.clock

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Path
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import java.util.Random

class AutoSwipeService : AccessibilityService() {

    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var isRunning = false
    private var minSeconds = 30
    private var maxSeconds = 60
    
    // 手势动作列表：每个动作是一个 Map，包含 type (click/swipe), x1, y1, x2, y2, duration
    private var gestureActions = mutableListOf<Map<String, Any>>()
    
    private val handler = Handler(Looper.getMainLooper())
    private val random = Random()

    companion object {
        var instance: AutoSwipeService? = null
        
        fun updateConfig(min: Int, max: Int, actions: List<Map<String, Any>>) {
            instance?.apply {
                minSeconds = min
                maxSeconds = max
                gestureActions.clear()
                gestureActions.addAll(actions)
            }
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        // 默认初始化一个简单的向上滑动动作
        if (gestureActions.isEmpty()) {
            gestureActions.add(mapOf(
                "type" to "swipe",
                "x1" to 0.5f, "y1" to 0.8f,
                "x2" to 0.5f, "y2" to 0.2f,
                "duration" to 300
            ))
        }
        showFloatingWindow()
    }

    // ... (keep removeFloatingWindow, onUnbind, onAccessibilityEvent) ...

    private fun toggleRunning() {
        isRunning = !isRunning
        val inner = (floatingView as FrameLayout).getChildAt(0)
        val statusText = inner.findViewById<TextView>(1001)
        if (isRunning) {
            inner.setBackgroundResource(android.R.drawable.presence_busy) 
            statusText.text = "运行中"
            startAutoSwipe()
        } else {
            inner.setBackgroundResource(android.R.drawable.presence_online)
            statusText.text = "待命"
            handler.removeCallbacksAndMessages(null)
        }
    }

    private fun startAutoSwipe() {
        if (!isRunning) return

        // 随机产生下一次执行的等待时间
        val delay = if (maxSeconds > minSeconds) {
            (random.nextInt(maxSeconds - minSeconds + 1) + minSeconds) * 1000L
        } else {
            minSeconds * 1000L
        }

        handler.postDelayed({
            if (isRunning) {
                executeActions()
                startAutoSwipe()
            }
        }, delay)
    }

    private fun executeActions() {
        val dm = resources.displayMetrics
        val width = dm.widthPixels.toFloat()
        val height = dm.heightPixels.toFloat()

        val gestureBuilder = GestureDescription.Builder()
        
        var totalDelay = 0L
        for (action in gestureActions) {
            val type = action["type"] as? String ?: "swipe"
            val duration = (action["duration"] as? Int ?: 300).toLong()
            
            val path = Path()
            if (type == "click") {
                val x = (action["x1"] as Float) * width
                val y = (action["y1"] as Float) * height
                path.moveTo(x, y)
                gestureBuilder.addStroke(GestureDescription.StrokeDescription(path, totalDelay, 50))
            } else {
                val x1 = (action["x1"] as Float) * width
                val y1 = (action["y1"] as Float) * height
                val x2 = (action["x2"] as Float) * width
                val y2 = (action["y2"] as Float) * height
                path.moveTo(x1, y1)
                path.lineTo(x2, y2)
                gestureBuilder.addStroke(GestureDescription.StrokeDescription(path, totalDelay, duration))
            }
            totalDelay += duration + 100 // 动作之间留一点空隙
        }
        
        try {
            dispatchGesture(gestureBuilder.build(), null, null)
        } catch (e: Exception) {}
    }

    private fun showFloatingWindow() {
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        
        val layoutParams = WindowManager.LayoutParams().apply {
            type = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                WindowManager.LayoutParams.TYPE_PHONE
            }
            format = PixelFormat.TRANSLUCENT
            flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
            width = WindowManager.LayoutParams.WRAP_CONTENT
            height = WindowManager.LayoutParams.WRAP_CONTENT
            gravity = Gravity.TOP or Gravity.START
            x = 100
            y = 100
        }

        floatingView = FrameLayout(this).apply {
            val inner = FrameLayout(context)
            inner.setBackgroundResource(android.R.drawable.presence_online)
            val text = TextView(context).apply {
                id = 1001
                text = "待命"
                textSize = 10f
                setTextColor(0xFFFFFFFF.toInt())
                gravity = Gravity.CENTER
            }
            inner.addView(text, FrameLayout.LayoutParams(120, 120))
            addView(inner)

            var initialX = 0
            var initialY = 0
            var initialTouchX = 0f
            var initialTouchY = 0f

            setOnTouchListener { v, event ->
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = layoutParams.x
                        initialY = layoutParams.y
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        layoutParams.x = initialX + (event.rawX - initialTouchX).toInt()
                        layoutParams.y = initialY + (event.rawY - initialTouchY).toInt()
                        windowManager?.updateViewLayout(floatingView, layoutParams)
                        true
                    }
                    MotionEvent.ACTION_UP -> {
                        if (Math.abs(event.rawX - initialTouchX) < 15 && Math.abs(event.rawY - initialTouchY) < 15) {
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
        instance = null
        return super.onUnbind(intent)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}
}
