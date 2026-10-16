package com.example.flutter_application_1.screenhelper

import android.accessibilityservice.AccessibilityService
import android.annotation.SuppressLint
import android.animation.ValueAnimator
import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.os.Bundle
import androidx.core.content.ContextCompat
import com.example.flutter_application_1.R
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
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.abs

/**
 * 手機小幫手（跨 App 求助浮鈕）— Day 1 風險驗證版。
 *
 * 只驗證三件事：無障礙服務能在展示機開啟、浮動按鈕能疊在任何 App 上、
 * 按下去能截圖並抓到畫面元件清單。截圖改存記憶體 JPEG，
 * 連同元件清單送後端分析，結果以高亮框、說明卡片與語音呈現（Day 3）。
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
        private const val WAIT_MS = 12_000L
        private const val AUTH_TEXT = "請先打開 Uban 登入一次，我才能幫您看喔。"
        private const val MIC_FAIL_TEXT = "我沒聽清楚，可以再按一次麥克風喔"
        private val FILLER_IDS = intArrayOf(
            R.raw.filler_01, R.raw.filler_02, R.raw.filler_03, R.raw.filler_04,
            R.raw.filler_05, R.raw.filler_06, R.raw.filler_07, R.raw.filler_08,
            R.raw.filler_09, R.raw.filler_10, R.raw.filler_11, R.raw.filler_12,
        )
        private val WAIT_IDS = intArrayOf(R.raw.wait_01, R.raw.wait_02)
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

    private var audio: HelperAudio? = null
    private var highlight: HighlightOverlay? = null
    private var panel: HelperPanel? = null
    private var executor: ExecutorService? = null
    private var recognizer: SpeechRecognizer? = null

    private var requestId = 0          // 讓過期的回應失效
    private var listenToken = 0        // 讓過期的「播完提示音後開始聽」失效
    private var pressPkg = "?"         // 按下當下的前景 App
    private var lastNodes = JSONArray()
    private val waitRunnable = Runnable { audio?.playRaw(randomOf(WAIT_IDS)) }

    private fun randomOf(ids: IntArray) = ids[ids.indices.random()]

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.i(TAG, "service connected, sdk=${Build.VERSION.SDK_INT}")
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        windowManager = wm
        audio = HelperAudio(this)
        highlight = HighlightOverlay(this, wm)
        panel = HelperPanel(this, wm, onAsk = { startVoiceQuestion() }, onDismiss = { dismissAll() })
        executor = Executors.newSingleThreadExecutor()
        addFloatingButton()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        // 換了別的 App 視窗，長輩多半已經點了目標，把框收掉。自己的浮層不算。
        if (pkg != packageName && pkg != pressPkg && highlight?.isShowing == true) highlight?.hide()
    }

    override fun onInterrupt() {
        // 系統要求中斷回饋：停掉聲音、收起浮層，但服務仍在，物件保留。
        dismissAll()
        stopListening()
    }

    override fun onDestroy() {
        main.removeCallbacks(idleFade)
        main.removeCallbacks(waitRunnable)
        requestId++
        stopListening()
        panel?.hide(); panel = null
        highlight?.hide(); highlight = null
        audio?.release(); audio = null
        executor?.shutdownNow(); executor = null
        spinner?.stop()
        spinner = null
        button?.let { runCatching { windowManager?.removeView(it) } }
        button = null
        super.onDestroy()
    }

    /** 「知道了」：收起卡片、高亮框並停掉聲音。 */
    private fun dismissAll() {
        listenToken++
        panel?.hide()
        highlight?.hide()
        audio?.stopAll()
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
        // 正在聽或卡片還開著時再按，視為重新求助。
        stopListening()
        runFlow(null)
    }

    /** 完整流程：墊音 → 抓元件 → 截圖 → 送後端 → 顯示結果。question 為語音提問（可空）。 */
    private fun runFlow(question: String?) {
        busy = true
        val myId = ++requestId
        listenToken++
        // 截圖前先收掉卡片與高亮框，避免擋住或被拍進畫面。
        panel?.hide()
        highlight?.hide()
        audio?.stopAll()
        audio?.playRaw(randomOf(FILLER_IDS))

        pressPkg = rootInActiveWindow?.packageName?.toString() ?: "?"
        val nodes = collectNodes()
        lastNodes = nodes
        Log.i(TAG, "pressed on package=$pressPkg, nodes=${nodes.length()}, question=${question != null}")
        // logcat 單行有長度上限，逐筆印。
        for (i in 0 until nodes.length()) Log.i(TAG, "node ${nodes.getJSONObject(i)}")

        // 截圖前先藏起按鈕，避免它出現在截圖裡擋住畫面。
        button?.visibility = View.INVISIBLE
        val pkg = pressPkg
        main.postDelayed({
            capture { jpeg ->
                if (myId != requestId) return@capture
                showThinking()
                submit(myId, jpeg, nodes.toString(), pkg, question)
            }
        }, 150)
    }

    /** 背景送出請求；12 秒還沒回就播一句「再等等」。 */
    private fun submit(myId: Int, jpeg: ByteArray?, nodesJson: String, pkg: String, question: String?) {
        main.removeCallbacks(waitRunnable)
        main.postDelayed(waitRunnable, WAIT_MS)
        val ex = executor
        if (ex == null) { onResult(myId, HelperResult.NetworkError("no executor")); return }
        try {
            ex.execute {
                val r = HelperApi.analyze(applicationContext, jpeg, nodesJson, pkg, question)
                main.post { onResult(myId, r) }
            }
        } catch (e: Exception) {
            onResult(myId, HelperResult.NetworkError("rejected"))
        }
    }

    private fun onResult(myId: Int, r: HelperResult) {
        if (myId != requestId) return
        main.removeCallbacks(waitRunnable)
        finish()
        when (r) {
            is HelperResult.Success -> {
                val rect = r.nodeId?.let { rectOfNode(it) }
                Log.i(TAG, "result node=${r.nodeId} sensitive=${r.sensitive}")
                if (rect != null) highlight?.show(rect)
                panel?.show(r.speech, rect)
                audio?.speak(r.speech)
            }
            HelperResult.AuthMissing -> {
                panel?.show(AUTH_TEXT, null)
                audio?.speak(AUTH_TEXT)
            }
            is HelperResult.NetworkError -> {
                Log.w(TAG, "network error: ${r.reason}")
                panel?.show("網路好像有點慢，等一下再按我一次好嗎？", null)
                audio?.playRaw(R.raw.err_network)
            }
        }
    }

    /** 依本地元件清單的 id 取得螢幕座標。 */
    private fun rectOfNode(id: Int): Rect? {
        for (i in 0 until lastNodes.length()) {
            val o = lastNodes.getJSONObject(i)
            if (o.optInt("id") == id) {
                val b = o.getJSONArray("bounds")
                return Rect(b.getInt(0), b.getInt(1), b.getInt(2), b.getInt(3))
            }
        }
        return null
    }

    /** 截圖，成功給 JPEG bytes；失敗（例如禁止截圖的畫面）給 null，仍會只送元件清單。 */
    private fun capture(done: (ByteArray?) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) { done(null); return }
        takeScreenshot(
            android.view.Display.DEFAULT_DISPLAY,
            mainExecutor,
            object : TakeScreenshotCallback {
                override fun onSuccess(result: ScreenshotResult) {
                    val jpeg = runCatching { toJpeg(result) }
                        .onFailure { Log.e(TAG, "encode failed", it) }
                        .getOrNull()
                    Log.i(TAG, "screenshot ${(jpeg?.size ?: 0) / 1024} KB")
                    done(jpeg)
                }

                override fun onFailure(errorCode: Int) {
                    // 5 = SECURE_WINDOW（銀行、支付等禁止截圖的畫面）；3 = 間隔太短。
                    Log.w(TAG, "screenshot failed, errorCode=$errorCode")
                    done(null)
                }
            },
        )
    }

    private fun toJpeg(result: ScreenshotResult): ByteArray {
        val hw = Bitmap.wrapHardwareBuffer(result.hardwareBuffer, result.colorSpace)
            ?: error("wrapHardwareBuffer returned null")
        val soft = hw.copy(Bitmap.Config.ARGB_8888, false)
        hw.recycle()
        result.hardwareBuffer.close()
        val scaled = if (soft.width > SHOT_WIDTH) {
            Bitmap.createScaledBitmap(soft, SHOT_WIDTH, soft.height * SHOT_WIDTH / soft.width, true)
        } else soft
        val out = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.JPEG, 60, out)
        if (scaled !== soft) scaled.recycle()
        soft.recycle()
        return out.toByteArray()
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

    private fun finish() {
        spinner?.stop()
        button?.visibility = View.VISIBLE
        busy = false
        scheduleIdle()
    }

    // ── 語音提問 ────────────────────────────────────────────────

    private fun startVoiceQuestion() {
        if (busy) return
        val p = panel ?: return
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            p.setText("請到 Uban 的權限設定打開麥克風喔")
            return
        }
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            p.setText(MIC_FAIL_TEXT)
            return
        }
        audio?.stopAll()
        stopListening()
        p.setText("我在聽，請說…")
        val token = ++listenToken
        audio?.playRaw(R.raw.listen_prompt)
        // 等提示音播完才開始收音，避免錄到自己的聲音。
        audio?.runWhenIdle { if (token == listenToken) startListening() }
    }

    private fun startListening() {
        val sr = SpeechRecognizer.createSpeechRecognizer(this)
        recognizer = sr
        sr.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onPartialResults(partialResults: Bundle?) {}
            override fun onEvent(eventType: Int, params: Bundle?) {}

            override fun onError(error: Int) {
                Log.w(TAG, "recognizer error $error")
                stopListening()
                val msg = if (error == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS)
                    "請到 Uban 的權限設定打開麥克風喔" else MIC_FAIL_TEXT
                panel?.setText(msg)
            }

            override fun onResults(results: Bundle?) {
                val q = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    ?.firstOrNull()?.trim()
                stopListening()
                if (q.isNullOrEmpty()) { panel?.setText(MIC_FAIL_TEXT); return }
                Log.i(TAG, "heard: $q")
                panel?.setText("您說：「$q」")
                runFlow(q)
            }
        })
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, "zh-TW")
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }
        runCatching { sr.startListening(intent) }.onFailure {
            Log.w(TAG, "startListening failed", it)
            stopListening()
            panel?.setText(MIC_FAIL_TEXT)
        }
    }

    private fun stopListening() {
        listenToken++
        recognizer?.let { runCatching { it.cancel(); it.destroy() } }
        recognizer = null
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
