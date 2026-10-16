package com.example.flutter_application_1.screenhelper

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/** 小嘎的說明卡片：顯示文字，並提供「問小嘎」與「知道了」兩顆大按鈕。 */
class HelperPanel(
    private val ctx: Context,
    private val wm: WindowManager,
    private val onAsk: () -> Unit,
    private val onDismiss: () -> Unit,
) {
    private companion object { const val AUTO_HIDE_MS = 25_000L }

    private val density = ctx.resources.displayMetrics.density
    private val main = Handler(Looper.getMainLooper())
    private val autoHide = Runnable { onDismiss() }
    private var card: LinearLayout? = null
    private var messageView: TextView? = null
    private var lp: WindowManager.LayoutParams? = null

    val isShowing: Boolean get() = card != null

    private fun dp(v: Int) = (v * density).toInt()

    fun show(text: String, targetRect: Rect?) {
        val screen = ctx.resources.displayMetrics
        val top = targetRect != null && targetRect.centerY() > screen.heightPixels / 2
        if (card == null) build(screen.widthPixels)
        lp?.apply {
            gravity = (if (top) Gravity.TOP else Gravity.BOTTOM) or Gravity.CENTER_HORIZONTAL
            y = dp(if (top) 48 else 24)
        }
        setText(text)
        card?.let { runCatching { wm.updateViewLayout(it, lp) } }
    }

    fun setText(text: String) {
        messageView?.text = text
        main.removeCallbacks(autoHide)
        main.postDelayed(autoHide, AUTO_HIDE_MS)
    }

    fun hide() {
        main.removeCallbacks(autoHide)
        card?.let { runCatching { wm.removeView(it) } }
        card = null
        messageView = null
        lp = null
    }

    private fun build(screenW: Int) {
        val title = TextView(ctx).apply {
            text = "小嘎"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setTextColor(0xFF2E7D78.toInt())
            typeface = android.graphics.Typeface.DEFAULT_BOLD
        }
        val msg = TextView(ctx).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
            setTextColor(0xFF333333.toInt())
            maxLines = 6
            ellipsize = TextUtils.TruncateAt.END
            setLineSpacing(0f, 1.15f)
            setPadding(0, dp(8), 0, dp(16))
        }
        val ask = button("🎤 問小嘎", filled = true) { onAsk() }
        val ok = button("知道了", filled = false) { onDismiss() }
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            addView(ask, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                rightMargin = dp(6)
            })
            addView(ok, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                leftMargin = dp(6)
            })
        }
        val c = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(20), dp(20), dp(20))
            background = GradientDrawable().apply {
                setColor(Color.WHITE)
                cornerRadius = dp(20).toFloat()
            }
            elevation = 12 * density
            addView(title)
            addView(msg)
            addView(row)
        }
        val params = WindowManager.LayoutParams(
            screenW - dp(32),
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        )
        if (runCatching { wm.addView(c, params) }.isFailure) return
        card = c
        messageView = msg
        lp = params
    }

    private fun button(label: String, filled: Boolean, onClick: () -> Unit): Button =
        Button(ctx).apply {
            text = label
            isAllCaps = false
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
            minHeight = dp(56)
            minimumHeight = dp(56)
            stateListAnimator = null
            val green = 0xFF59B294.toInt()
            background = GradientDrawable().apply {
                cornerRadius = dp(16).toFloat()
                if (filled) setColor(green) else {
                    setColor(Color.WHITE)
                    setStroke(dp(2), green)
                }
            }
            setTextColor(if (filled) Color.WHITE else 0xFF2E7D78.toInt())
            setOnClickListener(View.OnClickListener { onClick() })
        }
}
