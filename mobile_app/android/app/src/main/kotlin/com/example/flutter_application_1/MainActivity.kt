package com.example.flutter_application_1

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "com.example.app/bring_to_front"

    // ★ issue 3：來電（尤其鎖屏/螢幕關閉）時，讓 Activity 顯示在鎖定畫面之上並點亮螢幕。
    // ★ 2026-08-05 第十八輪（需求 4）：過去無條件呼叫 requestDismissKeyguard +
    //   FLAG_DISMISS_KEYGUARD，在有設定 PIN / 圖形 / 指紋等安全鎖的裝置上會強制彈出
    //   解鎖畫面，使用者必須先解鎖才能進入通話——這正是「無法跳過螢幕鎖」的成因。
    //   改為比照 LINE 的作法：靠 setShowWhenLocked(true) 讓通話畫面直接蓋在鎖定畫面
    //   之上、不主動解鎖；只有裝置「沒有」設定安全鎖（單純滑動鎖）時才呼叫
    //   requestDismissKeyguard 把它收起來，體驗較好。
    private fun showOverLockScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        @Suppress("DEPRECATION")
        window.addFlags(
            android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
        )
        try {
            val powerManager = getSystemService(android.content.Context.POWER_SERVICE) as android.os.PowerManager
            val wakeLock = powerManager.newWakeLock(
                android.os.PowerManager.SCREEN_BRIGHT_WAKE_LOCK or android.os.PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "Uban:EmergencyWakeLock"
            )
            wakeLock.acquire(10000L)
        } catch (e: Exception) {
            e.printStackTrace()
        }
        try {
            val keyguardManager = getSystemService(android.content.Context.KEYGUARD_SERVICE) as android.app.KeyguardManager
            // ★ 只有裝置「沒有」設定安全鎖（isKeyguardSecure == false）時才主動收起
            //   keyguard；已設定 PIN/圖形/指紋的裝置一律不呼叫，讓通話畫面直接顯示在
            //   鎖定畫面之上，避免強迫使用者先解鎖才能接聽。
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !keyguardManager.isKeyguardSecure) {
                keyguardManager.requestDismissKeyguard(this, null)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    // ★ 2026-08-05 第十八輪（需求 4）：通話結束後還原鎖屏行為。
    //   不還原的話，setShowWhenLocked(true) 會讓 APP 永久蓋在鎖定畫面之上，
    //   使用者按電源鍵後仍能直接看到 APP 內容（體驗與隱私都不對）。
    private fun restoreLockScreen() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(false)
                setTurnScreenOn(false)
            }
            @Suppress("DEPRECATION")
            window.clearFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun forceBringToFront() {
        showOverLockScreen()
        // ★ issue 1：launchMode 已改為 singleTask，且 Manifest 移除了
        //   taskAffinity=""，此處不再需要 FLAG_ACTIVITY_NEW_TASK。
        //   從前景 Activity context 重新喚醒既有實例（觸發 onNewIntent），
        //   避免與背景 FCM isolate 啟動的 Intent 各自建立新 Task / 新 Flutter engine。
        val intent = android.content.Intent(context, MainActivity::class.java)
        intent.addFlags(android.content.Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        intent.addFlags(android.content.Intent.FLAG_ACTIVITY_SINGLE_TOP)
        context.startActivity(intent)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        showOverLockScreen()
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        // ★ 當 APP 已在背景，被 AndroidIntent 喚醒時，重新觸發鎖屏覆蓋
        showOverLockScreen()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // ★ signaling.dart / main.dart 透過此 MethodChannel 呼叫 bringToFront，
        //   先前沒有原生實作導致接聽後無法把既有 Activity 帶到前景（只能靠 AndroidIntent 冷啟動）。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "bringToFront" -> {
                        forceBringToFront()
                        result.success(true)
                    }
                    "showOverLockScreen" -> {
                        showOverLockScreen()
                        result.success(true)
                    }
                    "restoreLockScreen" -> {
                        restoreLockScreen()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
