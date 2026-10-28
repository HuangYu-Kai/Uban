package com.example.flutter_application_1.screenhelper

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.annotation.SuppressLint
import android.animation.ValueAnimator
import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.os.Bundle
import androidx.core.content.ContextCompat
import com.example.flutter_application_1.R
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.RectF
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
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
 * 手機小幫手（跨 App 求助浮鈕）v2。
 *
 * 長輩按下浮鈕或對小嘎說話時，才截圖並抓畫面元件清單，送後端分析，
 * 結果以高亮框、說明卡片與語音呈現。v2 新增三件事：
 * 1. 帶步驟：語音提問會變成「目標」，每做完一步（偵測到點擊或換頁）自動再看一次畫面、給下一步；
 * 2. 幫我按：小嘎有把握時由服務代為點擊目標（ACTION_CLICK，不行再用手勢點座標）；
 * 3. 問家人：把問題與畫面送給家屬，由家屬回覆。
 *
 * 用 TYPE_ACCESSIBILITY_OVERLAY，不需要 SYSTEM_ALERT_WINDOW；
 * 截圖用 takeScreenshot()（API 30+），不會像 MediaProjection 每次跳同意視窗。
 */
class ScreenHelperService : AccessibilityService() {

    companion object {
        private const val TAG = "ScreenHelper"

        /** 服務連線中的實例；快速設定磚用它判斷服務是否開著、並切換浮鈕。 */
        @Volatile
        var instance: ScreenHelperService? = null

        const val PREFS = "screen_helper"
        const val KEY_BALL_VISIBLE = "ball_visible"

        /** 除錯用廣播（只在 debuggable 版本註冊），讓 adb 能不動手指就驅動整個流程。 */
        const val ACTION_DEBUG = "com.example.flutter_application_1.SH_DEBUG"

        // 截圖解析度與 JPEG 品質：由 bench_screen_helper.py 量測決定。
        // W540/Q55 對比原本的 W720/Q60：12 個案例準確度相當，run0 p50 由 2237ms 降到 1898ms（約快 15%）。
        private const val SHOT_WIDTH = 540
        private const val SHOT_QUALITY = 55

        private const val BUTTON_DP = 56
        // 與 ic_uban_ball.png 的圓角一致（原圖圓角約為邊長的 31%），陰影輪廓才不會露出方角。
        private const val CORNER_DP = 17
        private const val MAX_NODES = 80
        private const val WAIT_MS = 12_000L
        private const val AUTH_TEXT = "請先打開 Uban 登入一次，我才能幫您看喔。"
        private const val MIC_FAIL_TEXT = "我沒聽清楚，可以再按一次麥克風喔"
        private const val TOO_MANY_STEPS_TEXT = "步驟有點多，要不要請家人幫忙看一下？"
        private const val NEXT_STEP_TEXT = "我看一下下一步…"
        private const val DEFAULT_FAMILY_QUESTION = "這個畫面我不太會用"
        private const val FAMILY_PREVIEW_SPEECH = "要把這個畫面一起傳給家人嗎？"
        private const val FAMILY_TEXT_ONLY_SPEECH = "好，我把問題傳給家人"
        private const val FAMILY_PREVIEW_TEXT = "要把這個畫面一起傳給家人嗎？畫面上的對話或照片家人也會看到"
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

        /** 暖機最短間隔：模型閒置太久會被 Ollama 卸載，但太頻繁暖機只是浪費後端。 */
        private const val WARM_INTERVAL_MS = 10 * 60_000L

        /** 手指按下時預抓的元件清單，多久內還算新鮮、可以直接拿來送。 */
        private const val NODES_CACHE_MS = 1_500L

        /** 偵測到換頁後，等畫面「最後一次變動」過了這麼久才再分析。 */
        private const val SETTLE_MS = 700L

        /** 從偵測到換頁起算，最多等這麼久，免得動畫不斷的畫面永遠等不到穩定。 */
        private const val SETTLE_CAP_MS = 2_500L

        /** 我們自己的浮層（卡片、按鈕、高亮框）會產生事件，操作後這段時間內的事件一律不算。 */
        private const val OWN_EVENT_GUARD_MS = 600L

        /** 帶步驟時，這麼久沒有任何進展就自動結束任務。 */
        private const val TASK_IDLE_MS = 90_000L
        private const val MAX_STEPS = 8
        private const val SYSTEM_UI_PKG = "com.android.systemui"
    }

    /**
     * 單次請求的耗時紀錄，所有時間都是「距離觸發時」的毫秒數（-1＝沒發生）。
     * 集中成一行 SH_TIMING 輸出，給 bench_screen_helper.py 解析。
     */
    private class Timing(val id: Int, val mode: String, val t0: Long) {
        @Volatile var nodes = -1L
        @Volatile var shot = -1L
        @Volatile var sent = -1L
        @Volatile var resp = -1L
        @Volatile var audio = -1L
        @Volatile var server = -1
        @Volatile var ok = false
        var logged = false
        fun since() = SystemClock.uptimeMillis() - t0
    }

    /** 某一刻的畫面元件清單，連同 id→節點對照（給「幫我按」用）。 */
    private class NodeSnapshot(
        val nodes: JSONArray,
        val byId: Map<Int, AccessibilityNodeInfo>,
        val pkg: String,
        val at: Long,
    )

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
    private var warmExecutor: ExecutorService? = null
    private var recognizer: SpeechRecognizer? = null

    private var requestId = 0          // 讓過期的回應失效
    private var listenToken = 0        // 讓過期的「播完提示音後開始聽」失效
    private var familyToken = 0        // 讓過期的「問家人」回應失效
    private var pressPkg = "?"         // 按下當下的前景 App
    private var snapshot: NodeSnapshot? = null    // 目前這輪請求使用的元件清單
    private var prefetched: NodeSnapshot? = null  // 手指按下時預抓的清單
    private val waitRunnable = Runnable { audio?.playRaw(randomOf(WAIT_IDS)) }

    // ── 帶步驟任務 ──
    private var goal: String? = null                       // 長輩一開始說的目標；單次求助為 null
    private val history = mutableListOf<Pair<String, String>>()  // (小嘎說的話, 指的元件文字)
    private var step = 0                                   // 目前顯示的是第幾步
    private var taskActive = false
    private val taskIdleRunnable = Runnable { onTaskIdle() }

    // ── 等待換頁 ──
    private var awaiting = false      // 已佈署：等長輩做完這一步
    private var triggered = false     // 已偵測到點擊／換頁，正在等畫面穩定
    private var awaitMode = "auto"    // 之後那次請求要記成哪種 mode（auto／tap）
    private var triggerAt = 0L
    private var ignoreEventsUntil = 0L
    private val settleRunnable = Runnable { onSettled() }

    // ── 最近一次結果（幫我按、問家人要用）──
    private var lastSpeech = ""
    private var lastSensitive = false
    private var lastNodeId: Int? = null
    private var lastRect: Rect? = null
    private var lastCanTap = false
    private var lastJpeg: ByteArray? = null     // 只留記憶體；dismissAll／送出成功就清掉
    private var familySending = false
    private var familyPreviewing = false        // 正在顯示「要不要附上畫面」的預覽卡

    private var timing: Timing? = null
    private var lastWarmAt = 0L

    private var userPresentReceiver: BroadcastReceiver? = null
    private var debugReceiver: BroadcastReceiver? = null

    private fun randomOf(ids: IntArray) = ids[ids.indices.random()]
    private fun now() = SystemClock.uptimeMillis()

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.i(TAG, "service connected, sdk=${Build.VERSION.SDK_INT}")
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        windowManager = wm
        audio = HelperAudio(this)
        highlight = HighlightOverlay(this, wm)
        // 卡片上的按鈕與我們的浮層同屬本 App，按下去的事件要先標記成「自己的」再處理。
        panel = HelperPanel(
            this, wm,
            onAsk = { markOwnAction(); startVoiceQuestion() },
            onDismiss = { markOwnAction(); dismissAll() },
            onTap = { tapForMe() },
            onFamily = { markOwnAction(); askFamily() },
            onFamilyChoice = { markOwnAction(); onFamilyChoice(it) },
        )
        executor = Executors.newSingleThreadExecutor()
        warmExecutor = Executors.newSingleThreadExecutor()
        addFloatingButton()
        instance = this
        applyBallVisibility(isBallVisible())
        ScreenHelperState.notifyChanged(this)
        registerReceivers()
        warmUp()
    }

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        ScreenHelperState.notifyChanged(this)
        return super.onUnbind(intent)
    }

    fun isBallVisible(): Boolean =
        getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean(KEY_BALL_VISIBLE, true)

    /** 顯示／隱藏浮鈕並記住選擇；任何執行緒都可呼叫。 */
    fun setBallVisible(visible: Boolean) {
        getSharedPreferences(PREFS, MODE_PRIVATE).edit().putBoolean(KEY_BALL_VISIBLE, visible).apply()
        ScreenHelperState.notifyChanged(this)
        if (Looper.myLooper() == Looper.getMainLooper()) applyBallVisibility(visible)
        else main.post { applyBallVisibility(visible) }
    }

    private fun applyBallVisibility(visible: Boolean) {
        if (visible) {
            button?.apply {
                visibility = View.VISIBLE
                alpha = ACTIVE_ALPHA
            }
            scheduleIdle()
            return
        }
        // 隱藏：讓進行中的請求作廢，並收掉所有浮層與聲音（dismissAll 會一併結束任務）。
        requestId++
        main.removeCallbacks(waitRunnable)
        finish()
        main.removeCallbacks(idleFade)
        stopListening()
        dismissAll()
        button?.visibility = View.GONE
    }

    // ── 無障礙事件 ──────────────────────────────────────────────

    /**
     * 事件處理必須極輕：TYPE_WINDOW_CONTENT_CHANGED 一秒可能上百次，
     * 所以沒有「正在等換頁」就第一行直接放掉，全程只做 O(1) 的比對與 Handler 排程。
     *
     * 帶步驟時的換頁偵測分兩段：
     * 1. 已佈署但未觸發：目標 App 的 TYPE_VIEW_CLICKED，或別的視窗的 TYPE_WINDOW_STATE_CHANGED，
     *    視為「長輩做了這一步」；
     * 2. 已觸發：之後每個 STATE／CONTENT 變動都把「畫面穩定」計時往後推 700ms，
     *    總等待上限 2.5 秒，時間到就自動進下一步。
     * 我們自己的浮層與目標 App 同套件時分不出來源，只能靠 ignoreEventsUntil 這個時間窗排除。
     */
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        val type = event.eventType
        if (type == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) {
            if (!awaiting || !triggered) return
            if (now() < ignoreEventsUntil) return
            val pkg = event.packageName?.toString() ?: return
            if (isExternalEvent(pkg)) scheduleSettle(now())
            return
        }
        if (type == AccessibilityEvent.TYPE_VIEW_CLICKED) {
            if (!awaiting || triggered) return
            if (now() < ignoreEventsUntil) return
            val pkg = event.packageName?.toString() ?: return
            // 點擊只認目標 App：別的視窗（通知列、輸入法）的點擊不代表長輩做了這一步。
            if (pkg == pressPkg) onTriggered(now())
            return
        }
        if (type != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        // 換了別的 App 視窗，長輩多半已經點了目標，把框收掉。自己的浮層不算。
        if (pkg != packageName && pkg != pressPkg && highlight?.isShowing == true) highlight?.hide()
        if (!awaiting || now() < ignoreEventsUntil || !isExternalEvent(pkg)) return
        if (!triggered) onTriggered(now()) else scheduleSettle(now())
    }

    /** 事件是否來自「使用者正在操作的畫面」：排除我們自己的浮層與系統列。 */
    private fun isExternalEvent(pkg: String): Boolean {
        if (pkg == packageName && pressPkg != packageName) return false
        if (pkg == SYSTEM_UI_PKG && pressPkg != SYSTEM_UI_PKG) return false
        return true
    }

    /** 把接下來 [ms] 內的事件當成自己的浮層造成的，不列入換頁判斷。 */
    private fun markOwnAction(ms: Long = OWN_EVENT_GUARD_MS) {
        ignoreEventsUntil = maxOf(ignoreEventsUntil, now() + ms)
    }

    /** 開始等長輩做完這一步。guard=true 時先忽略我們剛疊上去的卡片與高亮框所產生的事件。 */
    private fun armAwait(mode: String, guard: Boolean = true) {
        awaiting = true
        triggered = false
        awaitMode = mode
        main.removeCallbacks(settleRunnable)
        if (guard) markOwnAction()
    }

    private fun cancelAwait() {
        awaiting = false
        triggered = false
        main.removeCallbacks(settleRunnable)
    }

    /** 偵測到長輩做了動作（或我們代按了）：收起舊的框、提示在看下一步，並開始等畫面穩定。 */
    private fun onTriggered(at: Long) {
        triggered = true
        triggerAt = at
        bumpTaskIdle()
        highlight?.hide()
        panel?.show(NEXT_STEP_TEXT, null, stepTitle(history.size + 1), canTap = false, keepOpen = true)
        scheduleSettle(at)
    }

    /** 每次畫面又變動就把觸發時間往後推 700ms，但從觸發起算不超過 2.5 秒。 */
    private fun scheduleSettle(at: Long) {
        main.removeCallbacks(settleRunnable)
        val remainCap = triggerAt + SETTLE_CAP_MS - at
        main.postDelayed(settleRunnable, SETTLE_MS.coerceAtMost(remainCap).coerceAtLeast(0L))
    }

    private fun onSettled() {
        if (!awaiting || !triggered) return
        val mode = awaitMode
        cancelAwait()
        if (!taskActive || busy) return
        if (history.size >= MAX_STEPS) { tooManySteps(); return }
        runFlow(mode)
    }

    // ── 帶步驟任務 ──────────────────────────────────────────────

    private fun stepTitle(n: Int) = if (taskActive) "小嘎・第 $n 步" else "小嘎"

    /** 語音提問＝新目標：清掉舊歷史重新開始。 */
    private fun startTask(question: String, mode: String) {
        goal = question
        history.clear()
        step = 0
        taskActive = true
        bumpTaskIdle()
        runFlow(mode)
    }

    /** 結束任務但保留 goal：之後按「問家人」還要拿它當問題。 */
    private fun endTask() {
        taskActive = false
        cancelAwait()
        main.removeCallbacks(taskIdleRunnable)
    }

    private fun bumpTaskIdle() {
        main.removeCallbacks(taskIdleRunnable)
        if (taskActive) main.postDelayed(taskIdleRunnable, TASK_IDLE_MS)
    }

    private fun onTaskIdle() {
        if (!taskActive) return
        Log.i(TAG, "task idle timeout, end")
        dismissAll()
    }

    private fun tooManySteps() {
        endTask()
        highlight?.hide()
        lastSpeech = TOO_MANY_STEPS_TEXT
        lastRect = null
        lastCanTap = false
        panel?.show(TOO_MANY_STEPS_TEXT, null)
        audio?.speak(TOO_MANY_STEPS_TEXT)
    }

    override fun onInterrupt() {
        // 系統要求中斷回饋：停掉聲音、收起浮層，但服務仍在，物件保留。
        dismissAll()
        stopListening()
    }

    override fun onDestroy() {
        instance = null
        ScreenHelperState.notifyChanged(this)
        main.removeCallbacks(idleFade)
        main.removeCallbacks(waitRunnable)
        main.removeCallbacks(settleRunnable)
        main.removeCallbacks(taskIdleRunnable)
        requestId++
        familyToken++
        unregisterReceivers()
        stopListening()
        panel?.hide(); panel = null
        highlight?.hide(); highlight = null
        audio?.release(); audio = null
        executor?.shutdownNow(); executor = null
        warmExecutor?.shutdownNow(); warmExecutor = null
        lastJpeg = null; snapshot = null; prefetched = null
        spinner?.stop()
        spinner = null
        button?.let { runCatching { windowManager?.removeView(it) } }
        button = null
        super.onDestroy()
    }

    /** 「知道了」：結束任務、取消進行中的請求，收起卡片、高亮框並停掉聲音。 */
    private fun dismissAll() {
        listenToken++
        familyToken++
        familyPreviewing = false
        endTask()
        // 帶步驟時卡片在分析期間也看得到，按「知道了」要能讓進行中的請求作廢。
        if (busy) cancelInFlight()
        panel?.hide()
        highlight?.hide()
        audio?.stopAll()
        // 截圖與節點不留：JPEG 可能含個資，節點物件也不該跨次保留。
        lastJpeg = null
        snapshot = null
        prefetched = null
        lastRect = null
        lastCanTap = false
        markOwnAction()
    }

    /** 讓進行中的分析結果作廢並讓浮鈕恢復。 */
    private fun cancelInFlight() {
        ++requestId
        main.removeCallbacks(waitRunnable)
        finish()
    }

    // ── 暖機與廣播 ──────────────────────────────────────────────

    /**
     * 叫後端先載好模型。連線時與解鎖時各一次，10 分鐘內不重複；結果不重要所以忽略。
     * 另開一條執行緒，免得暖機最長 45 秒時把長輩的第一次求助卡在 analyze 前面排隊。
     */
    private fun warmUp() {
        val t = now()
        if (lastWarmAt != 0L && t - lastWarmAt < WARM_INTERVAL_MS) return
        if (HelperApi.token(this) == null) return  // 還沒登入就不算數，等登入後的下一次解鎖
        lastWarmAt = t
        val ex = warmExecutor ?: return
        runCatching { ex.execute { HelperApi.warm(applicationContext) } }
    }

    private fun registerReceivers() {
        unregisterReceivers()
        val present = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) { warmUp() }
        }
        userPresentReceiver = present
        val presentFilter = IntentFilter(Intent.ACTION_USER_PRESENT)
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(present, presentFilter, Context.RECEIVER_NOT_EXPORTED)
        else registerReceiver(present, presentFilter)

        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            val dbg = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent != null) handleDebug(intent)
                }
            }
            debugReceiver = dbg
            // 必須 EXPORTED，adb shell am broadcast 才送得進來；release 版完全不註冊。
            if (Build.VERSION.SDK_INT >= 33) registerReceiver(dbg, IntentFilter(ACTION_DEBUG), Context.RECEIVER_EXPORTED)
            else registerReceiver(dbg, IntentFilter(ACTION_DEBUG))
            Log.i(TAG, "SH_DEBUG receiver registered")
        }
    }

    private fun unregisterReceivers() {
        userPresentReceiver?.let { runCatching { unregisterReceiver(it) } }
        userPresentReceiver = null
        debugReceiver?.let { runCatching { unregisterReceiver(it) } }
        debugReceiver = null
    }

    /** 除錯廣播：extras q／press／tap／family／dismiss，各自等同於長輩的一個操作。 */
    private fun handleDebug(intent: Intent) {
        val keys = intent.extras?.keySet()?.joinToString { "$it=${intent.extras?.get(it)}" } ?: ""
        Log.i(TAG, "SH_DEBUG received $keys")
        intent.getStringExtra("q")?.takeIf { it.isNotBlank() }?.let { onQuestionHeard(it.trim(), "debug") }
        if (intent.getBooleanExtra("press", false)) onHelpPressed("debug")
        if (intent.getBooleanExtra("tap", false)) tapForMe()
        if (intent.getBooleanExtra("family", false)) askFamily()
        intent.getStringExtra("family_choice")?.let { c ->
            val choice = when (c) {
                "with_image" -> FamilyChoice.WITH_IMAGE
                "text_only" -> FamilyChoice.TEXT_ONLY
                "cancel" -> FamilyChoice.CANCEL
                else -> null
            }
            if (choice != null) onFamilyChoice(choice) else Log.w(TAG, "SH_DEBUG unknown family_choice=$c")
        }
        if (intent.getBooleanExtra("dismiss", false)) dismissAll()
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
                    markOwnAction()
                    // 趁手指還沒抬起，先把元件清單抓好；按下到放開的幾十毫秒就這樣省下來。
                    if (!busy) prefetchNodes()
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
                    markOwnAction()
                    if (dragging) snapToEdge(view, lp)
                    else if (e.action == MotionEvent.ACTION_UP) onHelpPressed("press")
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

    /**
     * 按浮鈕。沒有進行中的任務＝單次求助（不帶目標）；
     * 任務進行中按浮鈕＝「請現在就再看一次」，沿用目標與歷史，
     * 補救「長輩做完了但我們沒偵測到換頁」的情況。
     */
    private fun onHelpPressed(mode: String) {
        if (busy) return
        // 正在聽或卡片還開著時再按，視為重新求助。
        stopListening()
        if (!taskActive) {
            goal = null
            history.clear()
            step = 0
        }
        runFlow(mode)
    }

    /** 語音辨識出問題（或除錯廣播送來的 q）：開始一個新任務。 */
    private fun onQuestionHeard(q: String, mode: String) {
        if (busy) cancelInFlight()
        stopListening()
        panel?.setText("您說：「$q」")
        startTask(q, mode)
    }

    /**
     * 完整流程：墊音 → 抓元件 → 截圖 → 送後端 → 顯示結果。
     * 帶步驟時（taskActive）會附上 goal 與 history；自動進下一步（auto／tap）不播墊音，
     * 只轉圈與顯示卡片文字，免得每一步都吵。
     */
    private fun runFlow(mode: String) {
        busy = true
        val myId = ++requestId
        listenToken++
        val t = Timing(myId, mode, now())
        timing = t
        familyPreviewing = false
        cancelAwait()
        markOwnAction()
        val quiet = mode == "auto" || mode == "tap"
        // 截圖前先收掉卡片與高亮框，避免擋住或被拍進畫面。
        panel?.hide()
        highlight?.hide()
        audio?.stopAll()
        if (!quiet) {
            audio?.playRaw(randomOf(FILLER_IDS)) {
                Log.i(TAG, "SH_FILLER id=$myId t=${t.since()}")
            }
        }
        lastSpeech = ""
        lastSensitive = false
        lastNodeId = null
        lastRect = null
        lastCanTap = false

        val root = rootInActiveWindow
        val curPkg = root?.packageName?.toString() ?: "?"
        pressPkg = curPkg
        val cached = prefetched
        prefetched = null
        // 預抓的清單夠新、而且還在同一個 App 才直接用；否則重抓。
        val snap = if (cached != null && now() - cached.at < NODES_CACHE_MS && cached.pkg == curPkg) cached
        else collectNodes(root, curPkg)
        snapshot = snap
        t.nodes = t.since()
        val nodes = snap.nodes
        Log.i(TAG, "flow mode=$mode package=$pressPkg, nodes=${nodes.length()}, task=$taskActive")
        // logcat 單行有長度上限，逐筆印。
        for (i in 0 until nodes.length()) Log.d(TAG, "node ${nodes.getJSONObject(i)}")

        // 截圖前先藏起按鈕，避免它出現在截圖裡擋住畫面。
        button?.visibility = View.INVISIBLE
        main.postDelayed({
            capture { jpeg ->
                if (myId != requestId) return@capture
                lastJpeg = jpeg
                t.shot = t.since()
                showThinking()
                if (quiet) {
                    panel?.show(NEXT_STEP_TEXT, null, stepTitle(history.size + 1), canTap = false, keepOpen = true)
                }
                submit(myId, jpeg, nodes.toString(), curPkg, t)
            }
        }, 150)
    }

    /** 背景送出請求；12 秒還沒回就播一句「再等等」。 */
    private fun submit(myId: Int, jpeg: ByteArray?, nodesJson: String, pkg: String, t: Timing) {
        main.removeCallbacks(waitRunnable)
        main.postDelayed(waitRunnable, WAIT_MS)
        val ex = executor
        if (ex == null) { onResult(myId, HelperResult.NetworkError("no executor"), t); return }
        // 在主執行緒先把任務狀態拷貝出來，背景執行緒不碰會變動的欄位。
        val task = taskActive
        val goalArg = if (task) goal else null
        // 第一步把目標也當成問題送，讓不認得 goal 的舊後端行為與 v1 相同。
        val question = if (task && history.isEmpty()) goal else null
        val historyJson = if (task && history.isNotEmpty()) {
            JSONArray().apply {
                history.takeLast(MAX_STEPS).forEach { (speech, target) ->
                    put(JSONObject().put("speech", speech).put("target", target))
                }
            }.toString()
        } else null
        try {
            ex.execute {
                t.sent = t.since()
                val r = HelperApi.analyze(applicationContext, jpeg, nodesJson, pkg, question, goalArg, historyJson)
                main.post { onResult(myId, r, t) }
            }
        } catch (e: Exception) {
            onResult(myId, HelperResult.NetworkError("rejected"), t)
        }
    }

    private fun onResult(myId: Int, r: HelperResult, t: Timing) {
        if (myId != requestId) return
        main.removeCallbacks(waitRunnable)
        finish()
        t.resp = t.since()
        // 接下來要疊卡片與高亮框，它們產生的事件不能被當成換頁。
        markOwnAction()
        when (r) {
            is HelperResult.Success -> onSuccess(r, t)
            HelperResult.AuthMissing -> {
                endTask()
                showPlain(AUTH_TEXT, showFamily = false)
                audio?.speak(AUTH_TEXT) { logTiming(t) }
            }
            is HelperResult.NetworkError -> {
                Log.w(TAG, "network error: ${r.reason}")
                endTask()
                showPlain("網路好像有點慢，等一下再按我一次好嗎？", showFamily = true)
                audio?.playRaw(R.raw.err_network) { logTiming(t) }
            }
        }
    }

    /** 沒有高亮目標的一般訊息卡片，並同步記錄「最近結果」讓問家人能帶上。 */
    private fun showPlain(text: String, showFamily: Boolean) {
        lastSpeech = text
        lastRect = null
        lastCanTap = false
        highlight?.hide()
        panel?.show(text, null, showFamily = showFamily)
    }

    private fun onSuccess(r: HelperResult.Success, t: Timing) {
        t.ok = true
        t.server = r.serverMs
        var speech = r.speech
        val sensitive = r.sensitive
        var rect = if (sensitive) null else r.nodeId?.let { rectOfNode(it) }
        Log.i(TAG, "result node=${r.nodeId} sensitive=$sensitive done=${r.done} step=${r.step} canTap=${r.canTap}")

        if (sensitive) {
            // 付款、密碼畫面：不畫框、不代按，也不留截圖；任務到此為止，交給家人。
            lastJpeg = null
            endTask()
        } else if (taskActive) {
            val stepNo = if (r.step > 0) r.step else history.size + 1
            when {
                r.done -> { endTask(); rect = null }
                stepNo > MAX_STEPS -> { endTask(); rect = null; speech = TOO_MANY_STEPS_TEXT }
                else -> {
                    step = stepNo
                    history.add(r.speech to r.targetText)
                    bumpTaskIdle()
                }
            }
        }

        lastSpeech = speech
        lastSensitive = sensitive
        lastNodeId = if (rect != null) r.nodeId else null
        lastRect = rect
        lastCanTap = r.canTap && rect != null && !sensitive
        // 還在任務中且有框＝要等長輩做這一步：框與卡片都不自動消失。
        val waitStep = taskActive && rect != null
        rect?.let { highlight?.show(it, keepVisible = waitStep) }
        panel?.show(speech, rect, stepTitle(step), canTap = lastCanTap, keepOpen = waitStep)
        audio?.speak(speech) { logTiming(t) }
        if (waitStep) armAwait("auto")
    }

    /** 一行輸出整輪耗時，給 bench_screen_helper.py 解析；每個請求只印一次。 */
    private fun logTiming(t: Timing) {
        if (t.logged) return
        t.logged = true
        t.audio = t.since()
        Log.i(
            TAG,
            "SH_TIMING id=${t.id} mode=${t.mode} nodes=${t.nodes} shot=${t.shot} sent=${t.sent} " +
                "resp=${t.resp} audio=${t.audio} server=${t.server} ok=${t.ok}",
        )
    }

    /** 依本地元件清單的 id 取得螢幕座標。 */
    private fun rectOfNode(id: Int): Rect? {
        val nodes = snapshot?.nodes ?: return null
        for (i in 0 until nodes.length()) {
            val o = nodes.getJSONObject(i)
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
        scaled.compress(Bitmap.CompressFormat.JPEG, SHOT_QUALITY, out)
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

    // ── 幫我按 ──────────────────────────────────────────────────

    /**
     * 小嘎代按目前高亮的目標。先試節點的 ACTION_CLICK（最準，不受版面微調影響）；
     * 失敗（節點消失、不可點、位置已變）再用手勢點座標中心。
     * 點完後帶步驟就直接進入「等畫面穩定」——我們知道剛按過，不必再等長輩的點擊事件。
     */
    private fun tapForMe() {
        val rect = lastRect
        if (rect == null || !lastCanTap || lastSensitive || busy) {
            Log.w(TAG, "tap ignored: rect=${rect != null} canTap=$lastCanTap sensitive=$lastSensitive busy=$busy")
            return
        }
        val node = lastNodeId?.let { snapshot?.byId?.get(it) }
        val inTask = taskActive
        cancelAwait()
        listenToken++
        audio?.stopAll()
        // 先收掉浮層，免得手勢點到我們自己的卡片或高亮框。
        panel?.hide()
        highlight?.hide()
        lastRect = null
        lastCanTap = false
        main.postDelayed({
            // 先試節點點擊；不行再用手勢（點擊位置被浮鈕蓋住時，浮鈕會先暫時讓位）。
            if (clickNode(node, rect)) afterTap(true, rect, inTask)
            else gestureTap(rect) { ok -> afterTap(ok, rect, inTask) }
        }, 80)
    }

    private fun afterTap(ok: Boolean, rect: Rect, inTask: Boolean) {
        Log.i(TAG, "tap for me ok=$ok task=$inTask")
        if (!ok) {
            // 按不到：還原卡片與框，請長輩自己按，流程照舊等換頁。
            lastRect = rect
            lastCanTap = false
            highlight?.show(rect, keepVisible = inTask && taskActive)
            panel?.show("我按不到，請您按一下綠色框框的地方喔", rect, stepTitle(step), canTap = false,
                keepOpen = inTask && taskActive)
            if (inTask && taskActive) armAwait("auto")
            return
        }
        if (inTask && taskActive) {
            // 不呼叫 markOwnAction：按完之後的畫面變動正是我們要等的。
            armAwait("tap", guard = false)
            onTriggered(now())
        }
    }

    /**
     * 用手勢點 rect 中心。若浮鈕剛好蓋在那個位置，注入的觸控會被浮鈕的視窗攔走，
     * 所以先把浮鈕設成看不見、視窗也設成不可觸控，等手勢送出 300ms 後再恢復。
     * （只設 INVISIBLE 不夠：視窗本身仍會接收觸控。）
     */
    private fun gestureTap(rect: Rect, done: (Boolean) -> Unit) {
        val lp = params
        val v = button
        val covered = lp != null && v != null && v.visibility != View.GONE &&
            Rect(lp.x, lp.y, lp.x + v.width, lp.y + v.height).contains(rect.centerX(), rect.centerY())
        if (!covered || lp == null || v == null) { done(dispatchTap(rect)); return }
        v.visibility = View.INVISIBLE
        lp.flags = lp.flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        runCatching { windowManager?.updateViewLayout(v, lp) }
        // 等視窗旗標生效再送手勢。
        main.postDelayed({
            done(dispatchTap(rect))
            main.postDelayed({
                lp.flags = lp.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv()
                if (button === v) {
                    runCatching { windowManager?.updateViewLayout(v, lp) }
                    // 這 300ms 內若已開始新的請求，浮鈕的顯示交給 runFlow／finish 管。
                    if (!busy) v.visibility = View.VISIBLE
                }
            }, 300)
        }, 60)
    }

    /** 對節點（或它最近的可點擊祖先）送 ACTION_CLICK；節點失效或已移位就回 false。 */
    private fun clickNode(node: AccessibilityNodeInfo?, expected: Rect): Boolean {
        if (node == null) return false
        if (!runCatching { node.refresh() }.getOrDefault(false)) return false
        val bounds = Rect()
        node.getBoundsInScreen(bounds)
        // 畫面可能在等待期間變了：節點還在但已不在高亮框附近，就別亂按。
        if (!Rect.intersects(bounds, expected)) return false
        var cur: AccessibilityNodeInfo? = node
        var hops = 0
        while (cur != null && !cur.isClickable && hops < 4) { cur = cur.parent; hops++ }
        val target = cur?.takeIf { it.isClickable } ?: return false
        return runCatching { target.performAction(AccessibilityNodeInfo.ACTION_CLICK) }.getOrDefault(false)
    }

    private fun dispatchTap(rect: Rect): Boolean {
        val path = Path().apply { moveTo(rect.exactCenterX(), rect.exactCenterY()) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 50))
            .build()
        return runCatching { dispatchGesture(gesture, null, null) }.getOrDefault(false)
    }

    // ── 問家人 ──────────────────────────────────────────────────

    /**
     * 按「問家人」。有截圖且非敏感時，先出預覽卡讓長輩決定要不要附上畫面——
     * 畫面上可能有私人對話或照片，不能默默就傳出去。
     * 沒截圖或敏感畫面就直接只傳文字，卡片上明講「不會傳畫面」。
     */
    private fun askFamily() {
        if (familySending) return
        if (executor == null) return
        cancelAwait()  // 預覽期間不要被「偵測到換頁」自動打斷
        listenToken++
        audio?.stopAll()
        if (busy) {
            // 分析到一半就改問家人：結果作廢。（這時卡片狀態不完整，無法還原，所以直接結束任務。）
            endTask()
            cancelInFlight()
            highlight?.hide()
            lastRect = null
            lastCanTap = false
        }
        val jpeg = if (lastSensitive) null else lastJpeg
        if (jpeg != null) {
            familyPreviewing = true
            panel?.showFamilyPreview(FAMILY_PREVIEW_TEXT, jpeg, lastRect)
            audio?.speak(FAMILY_PREVIEW_SPEECH)  // 長輩不一定會讀卡片，念短句提醒要做選擇
            return
        }
        sendFamily(withImage = false)
    }

    /** 預覽卡上的三個選項。 */
    private fun onFamilyChoice(choice: FamilyChoice) {
        if (!familyPreviewing) {
            Log.w(TAG, "family choice ignored: not previewing")
            return
        }
        familyPreviewing = false
        when (choice) {
            FamilyChoice.WITH_IMAGE -> sendFamily(withImage = true)
            FamilyChoice.TEXT_ONLY -> sendFamily(withImage = false)
            FamilyChoice.CANCEL -> {
                // 回到按「問家人」之前的樣子；帶步驟且還有框就繼續等下一步。
                val rect = lastRect
                val waitStep = taskActive && rect != null
                panel?.show(
                    lastSpeech.ifEmpty { "好，需要的時候再按「問家人」喔" }, rect, stepTitle(step),
                    canTap = lastCanTap && rect != null, keepOpen = waitStep,
                )
                if (waitStep) armAwait("auto")
            }
        }
    }

    /** 實際送出。withImage=false 時 image 一律省略，但仍帶 helper_speech。 */
    private fun sendFamily(withImage: Boolean) {
        val ex = executor ?: return
        endTask()
        highlight?.hide()
        lastRect = null
        lastCanTap = false
        familySending = true
        val token = ++familyToken
        panel?.show(
            if (withImage) "正在把問題和畫面傳給家人…" else "正在傳給家人…（只會傳問題，不會傳畫面）",
            null, showFamily = false,
        )
        // 只傳文字時念一句讓長輩安心；附圖時預覽已經問過，不重複。
        if (!withImage) audio?.speak(FAMILY_TEXT_ONLY_SPEECH)

        val question = goal ?: DEFAULT_FAMILY_QUESTION
        val pkg = pressPkg
        val label = appLabelOf(pkg)
        val speech = lastSpeech
        val sensitive = lastSensitive
        val jpeg = if (withImage && !sensitive) lastJpeg else null
        try {
            ex.execute {
                val r = HelperApi.askFamily(applicationContext, question, pkg, label, speech, sensitive, jpeg)
                main.post { onFamilyResult(token, r) }
            }
        } catch (e: Exception) {
            onFamilyResult(token, FamilyResult.NetworkError("rejected"))
        }
    }

    private fun onFamilyResult(token: Int, r: FamilyResult) {
        familySending = false
        if (token != familyToken) return  // 送到一半長輩按了「知道了」
        markOwnAction()
        when (r) {
            is FamilyResult.Done -> {
                lastJpeg = null  // 已經送出，不再留著
                lastSpeech = r.message
                panel?.show(r.message, null, showFamily = false)
                audio?.speak(r.message)
            }
            FamilyResult.AuthMissing -> {
                showPlain(AUTH_TEXT, showFamily = false)
                audio?.speak(AUTH_TEXT)
            }
            is FamilyResult.NetworkError -> {
                Log.w(TAG, "ask family failed: ${r.reason}")
                // 截圖留著，網路好了可以再按一次「問家人」。
                panel?.show("網路好像有點慢，等一下再按「問家人」一次好嗎？", null, showFamily = true)
                audio?.playRaw(R.raw.err_network)
            }
        }
    }

    /** 給家人看的 App 名稱；查不到（套件可見性限制）就退回套件名。 */
    private fun appLabelOf(pkg: String): String =
        runCatching {
            packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
        }.getOrNull()?.takeIf { it.isNotBlank() } ?: pkg

    // ── 語音提問 ────────────────────────────────────────────────

    private fun startVoiceQuestion() {
        val p = panel ?: return
        // 長輩開口代表要改問新問題：不要在聽的時候被「偵測到換頁」自動打斷。
        cancelAwait()
        if (busy) cancelInFlight()  // 分析到一半也能直接改用問的：讓進行中的請求結果作廢。
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
        // 實機回報：先播完「您想做什麼呢」才收音，每次都要等。改成按下就打斷小嘎，
        // 隔 150ms（讓喇叭停乾淨、不錄到尾音）直接開始聽，提示改看卡片上的字。
        main.postDelayed({ if (token == listenToken) startListening() }, 150)
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
                onQuestionHeard(q, "voice")
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

    /** 手指按到浮鈕的瞬間先抓一份清單放著；runFlow 發現它還新鮮就直接用。 */
    private fun prefetchNodes() {
        val root = rootInActiveWindow ?: return
        prefetched = collectNodes(root, root.packageName?.toString() ?: "?")
    }

    /**
     * 走訪目前 App 的畫面，收集「看得到且有文字或可點」的元件，給之後送 AI 用；
     * 同時記下 id→節點，「幫我按」才能對同一個節點送 ACTION_CLICK。每次收集都產生新的快照，
     * 舊的整份丟掉（API 33+ 不需手動 recycle），不會跨請求累積。
     */
    private fun collectNodes(root: AccessibilityNodeInfo?, pkg: String): NodeSnapshot {
        val out = JSONArray()
        val byId = HashMap<Int, AccessibilityNodeInfo>()
        if (root != null) {
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
                val id = out.length() + 1
                byId[id] = node
                out.put(JSONObject().apply {
                    put("id", id)
                    put("text", label)
                    put("clickable", node.isClickable)
                    // 目前所在的分頁（例如底部導覽「首頁」）會是 selected，讓 AI 別叫人再去按它。
                    put("selected", node.isSelected || node.isChecked)
                    put("bounds", JSONArray(listOf(rect.left, rect.top, rect.right, rect.bottom)))
                })
            }
        }
        return NodeSnapshot(out, byId, pkg, now())
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

/**
 * 浮鈕本體：把 Uban 的 App 圖示（綠底圓角方塊＋白色人形抱愛心）縮放進 56dp，
 * 長輩一眼認得「這是 Uban 的小嘎」。圖檔本身已帶圓角與透明邊角，不需再裁切；
 * 圖檔載入失敗時退回純綠色圓角方塊。idle 半透明由外層 view 的 alpha 控制。
 */
private class AssistiveBall(context: Context, private val density: Float) : View(context) {
    private val icon: Bitmap? = BitmapFactory.decodeResource(resources, R.drawable.ic_uban_ball)
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private val fallback = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF59B294.toInt() }
    private val dst = RectF()

    override fun onDraw(canvas: Canvas) {
        dst.set(0f, 0f, width.toFloat(), height.toFloat())
        val bmp = icon
        if (bmp != null) {
            canvas.drawBitmap(bmp, null, dst, paint)
        } else {
            val r = 17 * density
            canvas.drawRoundRect(dst, r, r, fallback)
        }
    }
}

/**
 * 分析期間疊在按鈕上的旋轉弧線，表示「小嘎正在看」。預設隱藏。
 * 圖示底色就是 AppTheme.primary 的綠，原本的綠色弧線會融在上面看不見，
 * 所以改成白色弧線，底下再墊一圈半透明深綠加寬的弧線當陰影——
 * 白線在綠底上清楚，萬一遇到淺色背景也有深色邊撐住輪廓。
 */
private class SpinnerRing(context: Context, density: Float) : View(context) {
    private val stroke = 4 * density
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = stroke
        strokeCap = Paint.Cap.ROUND
        color = 0xFFFFFFFF.toInt()
    }
    private val shadow = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = stroke + 3 * density
        strokeCap = Paint.Cap.ROUND
        color = 0x66184F3F
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
        // 弧線貼著圖示內緣，避開中間的人形圖案。
        val inset = minOf(width, height) * 0.08f + stroke / 2 + 1
        oval.set(inset, inset, width - inset, height - inset)
        canvas.drawArc(oval, angle, 110f, false, shadow)
        canvas.drawArc(oval, angle, 110f, false, paint)
    }
}
