package com.example.flutter_application_1.screenhelper

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Outline
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
import android.view.ViewOutlineProvider
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

/** 「問家人」預覽畫面上長輩的選擇。 */
enum class FamilyChoice { WITH_IMAGE, TEXT_ONLY, CANCEL }

/**
 * 小嘎的說明卡片：顯示文字，並提供大按鈕。
 * 第一排固定「問小嘎」「知道了」；第二排「幫我按」（只在小嘎能代按時出現）與「問家人」。
 * 長輩手指不靈光，按鈕一律 ≥56dp 高、字 ≥20sp。
 */
class HelperPanel(
    private val ctx: Context,
    private val wm: WindowManager,
    private val onAsk: () -> Unit,
    private val onDismiss: () -> Unit,
    private val onTap: () -> Unit,
    private val onFamily: () -> Unit,
    private val onFamilyChoice: (FamilyChoice) -> Unit,
) {
    private companion object {
        const val AUTO_HIDE_MS = 25_000L
        const val DEFAULT_TITLE = "小嘎"
    }

    private val density = ctx.resources.displayMetrics.density
    private val main = Handler(Looper.getMainLooper())
    private val autoHide = Runnable { onDismiss() }
    private var card: LinearLayout? = null
    private var titleView: TextView? = null
    private var messageView: TextView? = null
    private var tapButton: Button? = null
    private var familyButton: Button? = null
    private var row1: LinearLayout? = null
    private var row2: LinearLayout? = null
    private var previewBox: LinearLayout? = null
    private var previewImage: ImageView? = null
    private var previewBitmap: Bitmap? = null
    private var lp: WindowManager.LayoutParams? = null

    /**
     * true＝帶步驟、正在等長輩操作下一步：卡片不自動收起，
     * 否則長輩看一眼手機找按鈕的空檔，任務就被自動結束了。
     */
    private var persistent = false

    val isShowing: Boolean get() = card != null

    private fun dp(v: Int) = (v * density).toInt()

    /**
     * 顯示（或更新）卡片。
     * @param title 標題；帶步驟時是「小嘎・第 N 步」。
     * @param canTap 是否顯示「👆 幫我按」；呼叫端要自己確認有高亮目標且非敏感畫面。
     * @param showFamily 是否顯示「👨‍👩‍👧 問家人」；登入失效時不顯示（家人也幫不上）。
     * @param keepOpen 是否停用自動收起（等待下一步時為 true）。
     */
    fun show(
        text: String,
        targetRect: Rect?,
        title: String = DEFAULT_TITLE,
        canTap: Boolean = false,
        showFamily: Boolean = true,
        keepOpen: Boolean = false,
    ) {
        place(targetRect)
        setPreviewMode(false)
        titleView?.text = title
        applyButtons(canTap, showFamily)
        persistent = keepOpen
        setText(text)
        card?.let { runCatching { wm.updateViewLayout(it, lp) } }
    }

    /**
     * 「問家人」前的預覽：先讓長輩看到「會被傳出去的畫面」再決定要不要附圖。
     * 預覽期間不自動收起，免得長輩讀字讀到一半卡片就消失、也沒有送出任何東西。
     */
    fun showFamilyPreview(text: String, jpeg: ByteArray, targetRect: Rect?) {
        place(targetRect)
        titleView?.text = DEFAULT_TITLE
        previewBitmap?.recycle()
        previewBitmap = runCatching { BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size) }.getOrNull()
        previewImage?.setImageBitmap(previewBitmap)
        previewImage?.visibility = if (previewBitmap != null) View.VISIBLE else View.GONE
        setPreviewMode(true)
        persistent = true
        setText(text)
        card?.let { runCatching { wm.updateViewLayout(it, lp) } }
    }

    /** 放卡片：目標在下半部就放上面，反之放下面，免得蓋住要按的東西。 */
    private fun place(targetRect: Rect?) {
        val screen = ctx.resources.displayMetrics
        val top = targetRect != null && targetRect.centerY() > screen.heightPixels / 2
        if (card == null) build(screen.widthPixels)
        lp?.apply {
            gravity = (if (top) Gravity.TOP else Gravity.BOTTOM) or Gravity.CENTER_HORIZONTAL
            y = dp(if (top) 48 else 24)
        }
    }

    /** 預覽模式只留縮圖與三個選項；一般模式是問小嘎／知道了／幫我按／問家人。 */
    private fun setPreviewMode(preview: Boolean) {
        previewBox?.visibility = if (preview) View.VISIBLE else View.GONE
        row1?.visibility = if (preview) View.GONE else View.VISIBLE
        if (preview) row2?.visibility = View.GONE
        if (!preview) {
            previewImage?.setImageDrawable(null)
            previewBitmap?.recycle()
            previewBitmap = null
        }
    }

    /** 只換文字；沿用目前的按鈕與標題。 */
    fun setText(text: String) {
        val mv = messageView ?: return  // 卡片不在就不排自動收起，免得空轉呼叫 onDismiss
        mv.text = text
        main.removeCallbacks(autoHide)
        if (!persistent) main.postDelayed(autoHide, AUTO_HIDE_MS)
    }

    fun hide() {
        main.removeCallbacks(autoHide)
        card?.let { runCatching { wm.removeView(it) } }
        card = null
        titleView = null
        messageView = null
        tapButton = null
        familyButton = null
        row1 = null
        row2 = null
        previewBox = null
        previewImage = null
        previewBitmap?.recycle()
        previewBitmap = null
        lp = null
        persistent = false
    }

    /** 第二排的版面：沒有「幫我按」時「問家人」佔滿整排；兩顆都沒有就整排收起。 */
    private fun applyButtons(canTap: Boolean, showFamily: Boolean) {
        val tap = tapButton ?: return
        val family = familyButton ?: return
        tap.visibility = if (canTap) View.VISIBLE else View.GONE
        family.visibility = if (showFamily) View.VISIBLE else View.GONE
        row2?.visibility = if (canTap || showFamily) View.VISIBLE else View.GONE
        (tap.layoutParams as? LinearLayout.LayoutParams)?.rightMargin = if (showFamily) dp(6) else 0
        (family.layoutParams as? LinearLayout.LayoutParams)?.leftMargin = if (canTap) dp(6) else 0
        tap.requestLayout()
        family.requestLayout()
    }

    private fun build(screenW: Int) {
        val title = TextView(ctx).apply {
            text = DEFAULT_TITLE
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
        val tap = button("👆 幫我按", filled = true) { onTap() }
        val family = button("👨‍👩‍👧 問家人", filled = false) { onFamily() }
        val r1 = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            addView(ask, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                rightMargin = dp(6)
            })
            addView(ok, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                leftMargin = dp(6)
            })
        }
        val r2 = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            addView(tap, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            addView(family, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        }
        val img = ImageView(ctx).apply {
            adjustViewBounds = true
            scaleType = ImageView.ScaleType.FIT_CENTER
            maxHeight = dp(200)
            // 縮圖圓角，跟卡片風格一致。
            outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(v: View, outline: Outline) {
                    outline.setRoundRect(0, 0, v.width, v.height, dp(12).toFloat())
                }
            }
            clipToOutline = true
        }
        val withImage = button("連畫面一起傳", filled = true) { onFamilyChoice(FamilyChoice.WITH_IMAGE) }
        val textOnly = button("只傳問題", filled = false) { onFamilyChoice(FamilyChoice.TEXT_ONLY) }
        val choiceRow = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            addView(withImage, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                rightMargin = dp(6)
            })
            addView(textOnly, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                leftMargin = dp(6)
            })
        }
        val cancel = TextView(ctx).apply {
            text = "取消"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            setTextColor(0xFF666666.toInt())
            gravity = Gravity.CENTER
            minHeight = dp(48)
            setOnClickListener { onFamilyChoice(FamilyChoice.CANCEL) }
        }
        val pBox = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            visibility = View.GONE
            addView(img, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                bottomMargin = dp(12)
            })
            addView(choiceRow)
            addView(cancel, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(4) })
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
            addView(r1)
            addView(pBox)
            addView(r2, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(10) })
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
        titleView = title
        messageView = msg
        tapButton = tap
        familyButton = family
        row1 = r1
        row2 = r2
        previewBox = pBox
        previewImage = img
        lp = params
        applyButtons(canTap = false, showFamily = true)
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
