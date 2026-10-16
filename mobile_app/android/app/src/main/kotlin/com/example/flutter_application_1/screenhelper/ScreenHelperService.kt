package com.example.flutter_application_1.screenhelper

import android.accessibilityservice.AccessibilityService
import android.annotation.SuppressLint
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.RectF
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import android.widget.Toast
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import kotlin.math.abs

/**
 * 手機小幫手（跨 App 求助浮鈕）— Day 1 風險驗證版。
 *
 * 只驗證三件事：無障礙服務能在展示機開啟、浮動按鈕能疊在任何 App 上、
 * 按下去能截圖並抓到畫面元件清單。截圖存到
 * `/sdcard/Android/data/com.example.flutter_application_1/files/screen_helper/`，
 * 元件清單印到 logcat（tag = ScreenHelper）。後端呼叫、畫框與語音是 Day 3 的事。
 *
 * 用 TYPE_ACCESSIBILITY_OVERLAY，不需要 SYSTEM_ALERT_WINDOW；
 * 截圖用 takeScreenshot()（API 30+），不會像 MediaProjection 每次跳同意視窗。
 */
class ScreenHelperService : AccessibilityService() {

    companion object {
        private const val TAG = "ScreenHelper"
        private const val BUTTON_DP = 56
        private const val CORNER_DP = 14
        private const val MAX_NODES = 80
        private const val SHOT_WIDTH = 720
        private const val IDLE_ALPHA = 0.4f
        private const val ACTIVE_ALPHA = 1f
        private const val IDLE_DELAY_MS = 3000L
        private const val FADE_MS = 250L
    }

    private val main = Handler(Looper.getMainLooper())
    private val idleFade = Runnable { fadeToIdle() }
    private var windowManager: WindowManager? = null
    private var button: FrameLayout? = null
    private var spinner: SpinnerRing? = null
    private var params: WindowManager.LayoutParams? = null
    private var busy = false

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.i(TAG, "service connected, sdk=${Build.VERSION.SDK_INT}")
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        addFloatingButton()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    override fun onDestroy() {
        main.removeCallbacks(idleFade)
        spinner?.stop()
        spinner = null
        button?.let { runCatching { windowManager?.removeView(it) } }
        button = null
        super.onDestroy()
    }

    // ── 浮動按鈕 ────────────────────────────────────────────────

    @SuppressLint("ClickableViewAccessibility")
    private fun addFloatingButton() {
        val density = resources.displayMetrics.density
        val size = (BUTTON_DP * density).toInt()
        val ring = SpinnerRing(this, density)
        val view = FrameLayout(this).apply {
            contentDescription = "手機小幫手"
            elevation = 8 * density
            // 陰影輪廓要與圓角方塊一致。
            outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(v: View, outline: Outline) {
                    outline.setRoundRect(0, 0, v.width, v.height, CORNER_DP * density)
                }
            }
            clipToOutline = false
            addView(
                AssistiveBall(context, density),
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT,
                ),
            )
            addView(
                ring,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT,
                ),
            )
        }
        spinner = ring
        val lp = WindowManager.LayoutParams(
            size, size,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = resources.displayMetrics.widthPixels - size - (8 * density).toInt()
            y = resources.displayMetrics.heightPixels / 2
        }

        // 拖曳與點擊共用同一個 touch listener：移動超過 touchSlop 就當拖曳。
        val slop = 12 * density
        var downX = 0f; var downY = 0f; var startX = 0; var startY = 0; var dragging = false
        view.setOnTouchListener { _, e ->
            when (e.action) {
                MotionEvent.ACTION_DOWN -> {
                    downX = e.rawX; downY = e.rawY; startX = lp.x; startY = lp.y; dragging = false
                    main.removeCallbacks(idleFade)
                    view.animate().alpha(ACTIVE_ALPHA).setDuration(150).start()
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = e.rawX - downX; val dy = e.rawY - downY
                    if (dragging || abs(dx) > slop || abs(dy) > slop) {
                        dragging = true
                        lp.x = startX + dx.toInt(); lp.y = startY + dy.toInt()
                        windowManager?.updateViewLayout(view, lp)
                    }
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (dragging) snapToEdge(view, lp)
                    else if (e.action == MotionEvent.ACTION_UP) onHelpPressed()
                    scheduleIdle()
                    true
                }
                else -> false
            }
        }
        windowManager?.addView(view, lp)
        button = view
        params = lp
        scheduleIdle()
    }

    /** 閒置一段時間後淡成半透明；處理中不淡出。 */
    private fun scheduleIdle() {
        main.removeCallbacks(idleFade)
        if (!busy) main.postDelayed(idleFade, IDLE_DELAY_MS)
    }

    private fun fadeToIdle() {
        if (busy) return
        button?.animate()?.alpha(IDLE_ALPHA)?.setDuration(FADE_MS)?.start()
    }

    private fun snapToEdge(view: FrameLayout, lp: WindowManager.LayoutParams) {
        val margin = (8 * resources.displayMetrics.density).toInt()
        val screenW = resources.displayMetrics.widthPixels
        lp.x = if (lp.x + view.width / 2 < screenW / 2) margin else screenW - view.width - margin
        windowManager?.updateViewLayout(view, lp)
    }

    // ── 按下求助 ────────────────────────────────────────────────

    private fun onHelpPressed() {
        if (busy) return
        busy = true
        val pkg = rootInActiveWindow?.packageName?.toString() ?: "?"
        val nodes = collectNodes()
        Log.i(TAG, "pressed on package=$pkg, nodes=${nodes.length()}")
        // logcat 單行有長度上限，逐筆印。
        for (i in 0 until nodes.length()) Log.i(TAG, "node ${nodes.getJSONObject(i)}")

        // 截圖前先藏起按鈕，避免它出現在截圖裡擋住畫面。
        button?.visibility = View.INVISIBLE
        main.postDelayed({ capture(pkg, nodes.length()) }, 150)
    }

    private fun capture(pkg: String, nodeCount: Int) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            showThinking()
            finish("這支手機版本太舊，無法截圖（元件 $nodeCount 個）")
            return
        }
        takeScreenshot(
            android.view.Display.DEFAULT_DISPLAY,
            mainExecutor,
            object : TakeScreenshotCallback {
                override fun onSuccess(result: ScreenshotResult) {
                    showThinking()
                    val file = runCatching { saveShot(result) }
                        .onFailure { Log.e(TAG, "save failed", it) }
                        .getOrNull()
                    finish(
                        if (file != null) "截圖成功（$pkg，元件 $nodeCount 個）"
                        else "截圖存檔失敗（元件 $nodeCount 個）"
                    )
                    file?.let { Log.i(TAG, "screenshot saved: ${it.absolutePath} (${it.length() / 1024} KB)") }
                }

                override fun onFailure(errorCode: Int) {
                    showThinking()
                    // 5 = SECURE_WINDOW（銀行、支付等禁止截圖的畫面）；3 = 間隔太短。
                    Log.w(TAG, "screenshot failed, errorCode=$errorCode")
                    finish("截圖失敗（代碼 $errorCode），元件 $nodeCount 個")
                }
            },
        )
    }

    private fun saveShot(result: ScreenshotResult): File {
        val hw = Bitmap.wrapHardwareBuffer(result.hardwareBuffer, result.colorSpace)
            ?: error("wrapHardwareBuffer returned null")
        val soft = hw.copy(Bitmap.Config.ARGB_8888, false)
        hw.recycle()
        result.hardwareBuffer.close()
        val scaled = if (soft.width > SHOT_WIDTH) {
            Bitmap.createScaledBitmap(soft, SHOT_WIDTH, soft.height * SHOT_WIDTH / soft.width, true)
        } else soft
        val dir = File(getExternalFilesDir(null), "screen_helper").apply { mkdirs() }
        val file = File(dir, "shot_${System.currentTimeMillis()}.jpg")
        FileOutputStream(file).use { scaled.compress(Bitmap.CompressFormat.JPEG, 60, it) }
        if (scaled !== soft) scaled.recycle()
        soft.recycle()
        return file
    }

    /** 截圖拍完後按鈕重新出現並轉圈，表示小嘎正在處理。 */
    private fun showThinking() {
        main.removeCallbacks(idleFade)
        button?.apply {
            visibility = View.VISIBLE
            animate().cancel()
            alpha = ACTIVE_ALPHA
        }
        spinner?.start()
    }

    private fun finish(message: String) {
        spinner?.stop()
        button?.visibility = View.VISIBLE
        Toast.makeText(this, message, Toast.LENGTH_LONG).show()
        busy = false
        scheduleIdle()
    }

    // ── 元件清單 ────────────────────────────────────────────────

    /** 走訪目前 App 的畫面，收集「看得到且有文字或可點」的元件，給之後送 AI 用。 */
    private fun collectNodes(): JSONArray {
        val out = JSONArray()
        val root = rootInActiveWindow ?: return out
        val stack = ArrayDeque<AccessibilityNodeInfo>().apply { add(root) }
        val rect = Rect()
        while (stack.isNotEmpty() && out.length() < MAX_NODES) {
            val node = stack.removeLast()
            for (i in node.childCount - 1 downTo 0) node.getChild(i)?.let { stack.add(it) }
            if (!node.isVisibleToUser) continue
            val label = labelOf(node)
            if (label.isEmpty() && !node.isClickable) continue
            node.getBoundsInScreen(rect)
            if (rect.width() <= 0 || rect.height() <= 0) continue
            out.put(JSONObject().apply {
                put("id", out.length() + 1)
                put("text", label)
                put("clickable", node.isClickable)
                put("bounds", JSONArray(listOf(rect.left, rect.top, rect.right, rect.bottom)))
            })
        }
        return out
    }

    /** 元件自己的文字／描述；可點但沒字的容器（例如卡片）就拼接子元件的字。 */
    private fun labelOf(node: AccessibilityNodeInfo): String {
        val own = listOfNotNull(node.text, node.contentDescription)
            .joinToString(" ") { it.toString().trim() }.trim()
        if (own.isNotEmpty() || !node.isClickable) return own.take(60)
        val parts = mutableListOf<String>()
        for (i in 0 until node.childCount) {
            val c = node.getChild(i) ?: continue
            listOfNotNull(c.text, c.contentDescription).forEach { parts.add(it.toString().trim()) }
        }
        return parts.filter { it.isNotEmpty() }.joinToString(" ").take(60)
    }
}

/** 仿 iOS 輔助觸控的圓角方塊按鈕：idle 半透明、按下才完全顯示（透明度由外層控制）。 */
private class AssistiveBall(context: Context, private val density: Float) : View(context) {
    private val bg = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xCC1F1F1F.toInt() }
    private val c1 = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0x40FFFFFF }
    private val c2 = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0x80FFFFFF.toInt() }
    private val c3 = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFFFFFFFF.toInt() }
    private val rect = RectF()

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat()
        val h = height.toFloat()
        val r = 14 * density
        rect.set(0f, 0f, w, h)
        canvas.drawRoundRect(rect, r, r, bg)
        val cx = w / 2
        val cy = h / 2
        val size = minOf(w, h)
        canvas.drawCircle(cx, cy, size * 0.4f, c1)
        canvas.drawCircle(cx, cy, size * 0.3f, c2)
        canvas.drawCircle(cx, cy, size * 0.2f, c3)
    }
}

/** 分析期間疊在按鈕上的旋轉綠色弧線（AppTheme.primary），表示「小嘎正在看」。預設隱藏。 */
private class SpinnerRing(context: Context, density: Float) : View(context) {
    private val stroke = 4 * density
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = stroke
        strokeCap = Paint.Cap.ROUND
        color = 0xFF59B294.toInt()
    }
    private val oval = RectF()
    private var angle = 0f
    private val animator = ValueAnimator.ofFloat(0f, 360f).apply {
        duration = 900
        interpolator = LinearInterpolator()
        repeatCount = ValueAnimator.INFINITE
        addUpdateListener {
            angle = it.animatedValue as Float
            invalidate()
        }
    }

    init {
        visibility = GONE
    }

    fun start() {
        visibility = VISIBLE
        if (!animator.isRunning) animator.start()
    }

    fun stop() {
        animator.cancel()
        visibility = GONE
    }

    override fun onDraw(canvas: Canvas) {
        // 內縮後弧線剛好繞在 40% 那圈外面。
        val inset = minOf(width, height) * 0.08f + stroke / 2
        oval.set(inset, inset, width - inset, height - inset)
        canvas.drawArc(oval, angle, 100f, false, paint)
    }
}
