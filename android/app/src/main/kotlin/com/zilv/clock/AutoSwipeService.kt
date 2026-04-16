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
    private var intervalSeconds = 30
    private var useRandom = false
    
    private val handler = Handler(Looper.getMainLooper())
    private val random = Random()

    companion object {
        var instance: AutoSwipeService? = null
        
        fun updateConfig(interval: Int, randomMode: Boolean) {
            instance?.apply {
                intervalSeconds = interval
                useRandom = randomMode
            }
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        showFloatingWindow()
    }

    override fun onUnbind(intent: Intent?): Boolean {
        removeFloatingWindow()
        instance = null
        return super.onUnbind(intent)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}

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
            // 这里我们用代码创建一个简单的圆形按钮，实际项目中建议用 XML
            val inner = FrameLayout(context)
            inner.setBackgroundResource(android.R.drawable.presence_online) // 绿色小球
            val text = TextView(context).apply {
                text = "自动\n滑屏"
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
                        // 如果位移很小，视为点击
                        if (Math.abs(event.rawX - initialTouchX) < 10 && Math.abs(event.rawY - initialTouchY) < 10) {
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

    private fun toggleRunning() {
        isRunning = !isRunning
        val inner = (floatingView as FrameLayout).getChildAt(0)
        if (isRunning) {
            inner.setBackgroundResource(android.R.drawable.presence_busy) // 红色小球表示运行中
            startAutoSwipe()
        } else {
            inner.setBackgroundResource(android.R.drawable.presence_online)
            handler.removeCallbacksAndMessages(null)
        }
    }

    private fun startAutoSwipe() {
        if (!isRunning) return

        var delay = intervalSeconds * 1000L
        if (useRandom) {
            val factor = 0.8 + random.nextDouble() * 0.4
            delay = (delay * factor).toLong()
        }

        handler.postDelayed({
            if (isRunning) {
                performSwipe()
                startAutoSwipe() // 递归循环
            }
        }, delay)
    }

    private fun performSwipe() {
        val dm = resources.displayMetrics
        val width = dm.widthPixels
        val height = dm.heightPixels

        val path = Path().apply {
            moveTo(width / 2f, height * 0.8f)
            lineTo(width / 2f, height * 0.2f)
        }

        val gestureBuilder = GestureDescription.Builder()
        gestureBuilder.addStroke(GestureDescription.StrokeDescription(path, 0, 300))
        dispatchGesture(gestureBuilder.build(), null, null)
    }

    private fun removeFloatingWindow() {
        floatingView?.let {
            windowManager?.removeView(it)
            floatingView = null
        }
    }
}
