package com.example.flutter_application_1.screenhelper

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.RectF
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.WindowManager
import android.view.animation.LinearInterpolator

/** 全螢幕、不攔截觸控的高亮框：在目標元件外畫一圈脈動的綠色圓角框。 */
class HighlightOverlay(private val ctx: Context, private val wm: WindowManager) {
    private companion object { const val AUTO_HIDE_MS = 10_000L }

    private val density = ctx.resources.displayMetrics.density
    private val main = Handler(Looper.getMainLooper())
    private val autoHide = Runnable { hide() }
    private var view: HighlightView? = null

    fun show(rect: Rect) {
        hide()
        val v = HighlightView(ctx, density, Rect(rect))
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        )
        if (runCatching { wm.addView(v, lp) }.isFailure) return
        view = v
        v.startPulse()
        main.postDelayed(autoHide, AUTO_HIDE_MS)
    }

    fun hide() {
        main.removeCallbacks(autoHide)
        view?.let {
            it.stopPulse()
            runCatching { wm.removeView(it) }
        }
        view = null
    }

    val isShowing: Boolean get() = view != null
}

private class HighlightView(
    context: Context,
    private val density: Float,
    private val screenRect: Rect,
) : View(context) {
    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 5 * density
        color = 0xFF59B294.toInt()
    }
    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = 0x2259B294
    }
    private val box = RectF()
    private val loc = IntArray(2)
    private var t = 0f
    private val animator = ValueAnimator.ofFloat(0f, 1f).apply {
        duration = 900
        interpolator = LinearInterpolator()
        repeatCount = ValueAnimator.INFINITE
        repeatMode = ValueAnimator.REVERSE
        addUpdateListener { t = it.animatedValue as Float; invalidate() }
    }

    fun startPulse() = animator.start()
    fun stopPulse() = animator.cancel()

    override fun onDraw(canvas: Canvas) {
        // 螢幕座標轉成這個 view 的座標。
        getLocationOnScreen(loc)
        val inflate = 8 * density + t * 4 * density
        box.set(
            (screenRect.left - loc[0]) - inflate,
            (screenRect.top - loc[1]) - inflate,
            (screenRect.right - loc[0]) + inflate,
            (screenRect.bottom - loc[1]) + inflate,
        )
        val r = 16 * density
        strokePaint.alpha = (255 * (0.55f + 0.45f * (1f - t))).toInt()
        canvas.drawRoundRect(box, r, r, fillPaint)
        canvas.drawRoundRect(box, r, r, strokePaint)
    }
}
