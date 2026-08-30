package com.example.flutter_application_1

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "com.example.app/bring_to_front"

    // ★ 跌倒警報 DND 繞過：查詢/導引授權設定頁、選擇 channel 用的第二條 MethodChannel。
    private val notificationPolicyChannel = "com.example.app/notification_policy"

    companion object {
        // 跌倒警報 channel 相關常數，詳見 ensureAlertChannel() 的完整說明。
        private const val ALERT_CHANNEL_NAME = "跌倒警報"
        private const val ALERT_CHANNEL_DESC = "YOLO 監視機偵測到疑似跌倒時的高優先級提醒"
        // 不具 bypassDnd 的版本（尚未取得「通知政策存取」權限時使用）。
        private const val ALERT_CHANNEL_ID_NORMAL = "uban_cctv_alert_v3"
        // 具 bypassDnd 的版本（已取得「通知政策存取」權限時使用）。
        private const val ALERT_CHANNEL_ID_DND = "uban_cctv_alert_v3_dnd"
        // 更舊版本遺留的 channel id，僅用於清除，讓舊安裝收斂到目前唯一存在的 channel。
        private val LEGACY_ALERT_CHANNEL_IDS = listOf("uban_cctv_alert", "uban_cctv_alert_v2")
    }

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

    /**
     * ★ issue 3（app 卡死在背景，需一鍵清除才殺得掉）／需求 3（鎖屏通話結束後
     * 不得再留在 App 任何畫面）共用的收尾動作。
     *
     * `finish()` 只會結束目前這個 Activity；本 App 是 `launchMode="singleTask"`
     * 且全程只有 `MainActivity` 一個 Activity，`finish()` 之後 Task 紀錄仍留在
     * Recents（顯示最後一幀畫面），必須額外呼叫 `finishAndRemoveTask()` 才會
     * 連 Task 一併從 Recents 移除、讓系統依正常規則回收行程。
     *
     * `isTaskRoot` 是防呆：只有當這個 Activity 是 Task 的根（本 App 目前恆
     * 成立）才動用會牽動整個 Task 的 `finishAndRemoveTask()`；理論上不成立時
     * （例如日後新增第二個 Activity）退回單純 `finish()`，不誤殺整個 Task。
     */
    private fun finishAndRemoveTaskCompat() {
        if (isTaskRoot) {
            finishAndRemoveTask()
        } else {
            super.finish()
        }
    }

    // ★ issue 9：使用者連續按返回鍵離開 App 時，走的是 Flutter 框架在 Navigator
    //   彈到底時自動觸發的 `SystemNavigator.pop()`（`pet_room_view.dart` 等畫面
    //   顯式呼叫的同一個平台方法也是同一條路），兩者最終都落到
    //   `Activity.finishAfterTransition()` → `finish()`。
    //   在這裡統一攔截 `finish()` 本身，讓「不管是哪條路徑觸發的結束」都改走
    //   `finishAndRemoveTaskCompat()`，不必逐一去改 Dart 端每個呼叫點（其中
    //   `pet_room_view.dart` 不在本次可改動範圍內）。
    //   單一 Activity 架構下，`finish()` 沒有任何合理情境需要「Activity 結束但
    //   Task 留著」，所以這裡不做額外條件判斷、對所有 `finish()` 呼叫一視同仁。
    override fun finish() {
        finishAndRemoveTaskCompat()
    }

    /**
     * ★ 需求 3：判斷「這個當下」keyguard 是否仍處於鎖定狀態。
     *
     * 用途：Dart 端（`video_call_screen.dart` / `elder_screen.dart`）在通話畫面
     * `initState()` 呼叫一次並記住結果，藉此分辨「這通電話是從鎖屏／背景喚醒
     * 才進來的」還是「使用者本來就已經在 App 裡」——只有前者才在通話結束時
     * 呼叫 [finishAndRemoveTaskCompat]。
     *
     * 對已設定 PIN／圖形／指紋等安全鎖的裝置，這個判斷相當可靠：
     * [showOverLockScreen] 只會把畫面「蓋上去」、不會主動解鎖（見該函式與
     * `CLAUDE_call-monitor.md` G49），所以即使通話畫面已經蓋在鎖定畫面之上，
     * `isKeyguardLocked` 仍會如實回報「鎖定中」。
     *
     * 已知誤差僅在**沒有**設定安全鎖的裝置：那類裝置 [showOverLockScreen] 會
     * 呼叫 `requestDismissKeyguard()` 主動收起 keyguard，若 Dart 端查詢的時間點
     * 晚於那次收起，可能讀到「未鎖定」而低估。這個誤差方向是安全的——頂多
     * 沒把 App 收掉，不會錯殺使用者正在使用中的畫面。
     */
    private fun isKeyguardLocked(): Boolean {
        return try {
            val keyguardManager = getSystemService(android.content.Context.KEYGUARD_SERVICE) as android.app.KeyguardManager
            keyguardManager.isKeyguardLocked
        } catch (e: Exception) {
            e.printStackTrace()
            false
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
        // ★ 冷啟動時就先依目前的 DND 授權狀態選好跌倒警報 channel（完整原理見
        //   ensureAlertChannel() 的說明），不等 Dart 端呼叫，確保第一時間發出的
        //   警報就用對 channel。
        ensureAlertChannel()
        super.onCreate(savedInstanceState)
    }

    override fun onResume() {
        super.onResume()
        // ★ 使用者可能剛從系統「請勿打擾存取權」設定頁授權完畢返回 APP；每次回到
        //   前景都重新判斷一次，讓授權後立刻切到 bypassDnd 的 channel，不必等下次
        //   冷啟動。（NotificationChannel 建立後不可變，這裡的「切換」實際上是刪舊
        //   建新，完整原理見 ensureAlertChannel() 的說明。）
        ensureAlertChannel()
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
                    "isKeyguardLocked" -> {
                        result.success(isKeyguardLocked())
                    }
                    "finishAndRemoveTask" -> {
                        finishAndRemoveTaskCompat()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // ★ 跌倒警報 DND 繞過：查詢授權狀態、導引使用者到系統設定頁、以及取得目前
        //   應該使用的 channel id，供 cctv_alert_notification.dart 使用。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notificationPolicyChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isDndAccessGranted" -> {
                        result.success(isDndAccessGranted())
                    }
                    "openDndAccessSettings" -> {
                        result.success(openDndAccessSettings())
                    }
                    "canUseFullScreenIntent" -> {
                        result.success(canUseFullScreenIntent())
                    }
                    "openFullScreenIntentSettings" -> {
                        result.success(openFullScreenIntentSettings())
                    }
                    "ensureAlertChannel" -> {
                        result.success(ensureAlertChannel())
                    }
                    "androidSdkInt" -> {
                        result.success(androidSdkInt())
                    }
                    "isMiuiFamily" -> {
                        result.success(isMiuiFamily())
                    }
                    "openOemPermissionEditor" -> {
                        result.success(openOemPermissionEditor())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * 是否已取得「通知政策存取」（Notification Policy Access）權限——
     * 這是勿擾模式（DND）例外清單的特殊存取權限。API 23（M）以下沒有這個概念，
     * 一律視為已授予。
     */
    private fun isDndAccessGranted(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                true
            } else {
                val notificationManager = getSystemService(android.content.Context.NOTIFICATION_SERVICE)
                    as android.app.NotificationManager
                notificationManager.isNotificationPolicyAccessGranted
            }
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    /**
     * 開啟系統「請勿打擾存取權」設定頁，讓使用者手動授權。
     * 這是特殊權限，Android 不提供 runtime permission 對話框可以直接跟使用者要。
     * 部分 OEM ROM 可能沒有對應頁面，找不到可處理的 Activity 時回傳 false，
     * 不讓 APP 崩潰。
     */
    private fun openDndAccessSettings(): Boolean {
        return try {
            val intent = android.content.Intent(
                android.provider.Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS
            )
            if (intent.resolveActivity(packageManager) != null) {
                startActivity(intent)
                true
            } else {
                false
            }
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    /**
     * 是否可使用全螢幕 Intent（fullScreenIntent）。Android 14（API 34）起這是
     * 另一項需要使用者手動授權的特殊權限；34 以下沿用舊行為，安裝時自動授予，
     * 直接回傳 true。
     */
    private fun canUseFullScreenIntent(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                val notificationManager = getSystemService(android.content.Context.NOTIFICATION_SERVICE)
                    as android.app.NotificationManager
                notificationManager.canUseFullScreenIntent()
            } else {
                true
            }
        } catch (e: Exception) {
            e.printStackTrace()
            true
        }
    }

    /**
     * 開啟系統「允許全螢幕通知」設定頁（僅 API 34+ 存在）。
     * 低於 34 直接回傳 false（沒有這個頁面）；找不到可處理的 Activity 一樣回傳
     * false 而非崩潰。
     */
    private fun openFullScreenIntentSettings(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                val intent = android.content.Intent(
                    android.provider.Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT
                )
                intent.data = android.net.Uri.parse("package:$packageName")
                if (intent.resolveActivity(packageManager) != null) {
                    startActivity(intent)
                    true
                } else {
                    false
                }
            } else {
                false
            }
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    /**
     * ★ 跌倒警報 DND 繞過 channel 選擇邏輯（整個機制成敗的關鍵，改動前務必讀完）。
     *
     * 這裡疊加了兩個 Android 平台限制：
     *
     * 1. `NotificationChannel.setBypassDnd(true)` 只有在 channel「建立當下」APP
     *    就已經持有「通知政策存取」權限時才會生效——建立時沒有權限、之後才去
     *    系統設定授權，這個 channel 的 bypassDnd 不會回溯生效。
     * 2. Android notification channel 一旦建立就不可變（immutable）——之後對同一個
     *    channel id 再呼叫 createNotificationChannel() 想更改音效、AudioAttributes
     *    或 bypassDnd，系統一律靜默忽略，不報錯也不生效。
     *
     * 兩者疊加代表「建立一次 channel、之後再翻旗標」這條路完全走不通。因此這裡
     * 改用「雙 channel id + 每次啟動/回前景都重新判斷」：依「當下」是否持有 DND
     * 存取權限，建立對應的 channel，並把另一個變體刪掉，確保系統裡永遠只存在
     * 一個跟目前授權狀態相符的 channel；同時清掉更舊版本（v1/v2）遺留的 channel
     * id，讓舊安裝收斂。
     *
     * 呼叫時機：onCreate（冷啟動）與 onResume（例如使用者從系統設定頁授權完返回
     * APP）都會呼叫，讓使用者一開完權限、回到 APP 就立刻拿到升級後的 channel，
     * 不必等 Dart 端觸發；Dart 端（cctv_alert_notification.dart）也會在自己的
     * 初始化流程主動呼叫一次，並用回傳值決定要對哪個 channel id 發通知。
     *
     * @return 目前實際存在、Dart 端應該拿去發通知的 channel id。
     */
    private fun ensureAlertChannel(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            // Android 8 以下沒有 notification channel 概念，回傳一個佔位 id 即可。
            return ALERT_CHANNEL_ID_NORMAL
        }
        return try {
            val notificationManager = getSystemService(android.content.Context.NOTIFICATION_SERVICE)
                as android.app.NotificationManager
            val hasDndAccess = try {
                notificationManager.isNotificationPolicyAccessGranted
            } catch (e: Exception) {
                e.printStackTrace()
                false
            }

            val activeId = if (hasDndAccess) ALERT_CHANNEL_ID_DND else ALERT_CHANNEL_ID_NORMAL
            val inactiveId = if (hasDndAccess) ALERT_CHANNEL_ID_NORMAL else ALERT_CHANNEL_ID_DND

            val audioAttributes = android.media.AudioAttributes.Builder()
                .setUsage(android.media.AudioAttributes.USAGE_ALARM)
                .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val soundUri = android.net.Uri.parse("android.resource://$packageName/raw/emergency_siren")

            val alertChannel = android.app.NotificationChannel(
                activeId,
                ALERT_CHANNEL_NAME,
                android.app.NotificationManager.IMPORTANCE_HIGH
            )
            alertChannel.description = ALERT_CHANNEL_DESC
            alertChannel.enableVibration(true)
            alertChannel.setSound(soundUri, audioAttributes)
            // hasDndAccess 為 true 時才會走到這裡把 activeId 設成 DND 版、傳 true，
            // 故「建立當下即持有權限」在這個分支恆成立。
            alertChannel.setBypassDnd(hasDndAccess)
            notificationManager.createNotificationChannel(alertChannel)

            // 刪掉另一個變體：留著不只是殘留設定項目，使用者也可能誤點到沒有
            // bypass 效果的那個、或在系統設定頁看到兩筆重複的「跌倒警報」。
            try {
                notificationManager.deleteNotificationChannel(inactiveId)
            } catch (e: Exception) {
                e.printStackTrace()
            }

            // 清掉 v1/v2 遺留的 channel id，讓舊安裝收斂到目前唯一存在的 channel。
            for (legacyId in LEGACY_ALERT_CHANNEL_IDS) {
                try {
                    notificationManager.deleteNotificationChannel(legacyId)
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }

            activeId
        } catch (e: Exception) {
            e.printStackTrace()
            ALERT_CHANNEL_ID_NORMAL
        }
    }

    /**
     * 回傳目前裝置的 Android API Level（`Build.VERSION.SDK_INT`）。
     *
     * 用途：[canUseFullScreenIntent] 在 API 34 以下恆回傳 true，但這個 true 有
     * 兩種完全不同的意義——34 以下是「這項權限根本不存在、系統自動授予」，
     * 34+ 才是「使用者真的手動到設定頁授予了」。Dart 端的設定頁光看
     * [canUseFullScreenIntent] 的布林值分不出這兩種情況，會在 API 34 以下的
     * 裝置上誤顯示「已授權」，因此額外把 SDK_INT 暴露出去，讓 UI 自己判斷
     * 「此系統版本不需要」。失敗時回傳 0，讓 Dart 端視為「未知」。
     */
    private fun androidSdkInt(): Int {
        return try {
            Build.VERSION.SDK_INT
        } catch (e: Exception) {
            e.printStackTrace()
            0
        }
    }

    /**
     * ★ 2026-08-20 新增：判斷目前裝置是否為小米家族 ROM（Xiaomi／Redmi／POCO，
     * 即 MIUI 或其後繼的 HyperOS）。用途：「鎖定螢幕顯示」「後台彈出介面」是這個
     * ROM 家族專有的權限頁面，AOSP 與其他 OEM 完全沒有對應設定；在非此家族的
     * 裝置上顯示引導只會造成困惑，因此需要先判斷。
     *
     * 兩路偵測，任一命中即視為 MIUI 家族：
     * 1. 機型層級：Build.MANUFACTURER / Build.BRAND 是否包含 xiaomi／redmi／poco。
     *    穩定、不會拋例外，但涵蓋不到「小米機身刷成其他 ROM」這類邊界情況。
     * 2. ROM 層級：反射讀取系統屬性 ro.miui.ui.version.name 是否非空。這是 MIUI
     *    實際安裝與否的直接證據，但屬於非公開 API，日後版本可能改變讀法或直接
     *    移除，因此整段包在自己的 try/catch 裡，讀不到就當作沒有這個訊號，
     *    不影響第一路的判斷結果。
     *
     * 整支函式保證不拋例外；任何一路讀取失敗都只讓那一路視為「未命中」，不會讓
     * 呼叫端收到例外或讓 APP 崩潰。
     */
    private fun isMiuiFamily(): Boolean {
        val brandHit = try {
            val manufacturer = Build.MANUFACTURER?.lowercase() ?: ""
            val brand = Build.BRAND?.lowercase() ?: ""
            listOf("xiaomi", "redmi", "poco").any {
                manufacturer.contains(it) || brand.contains(it)
            }
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }

        val romPropertyHit = try {
            val systemPropertiesClass = Class.forName("android.os.SystemProperties")
            val getMethod = systemPropertiesClass.getMethod("get", String::class.java)
            val miuiVersionName = getMethod.invoke(null, "ro.miui.ui.version.name") as? String
            miuiVersionName != null && miuiVersionName.isNotBlank()
        } catch (e: Exception) {
            // ro.miui.ui.version.name 是非公開系統屬性，讀不到（權限、版本差異、
            // 或根本不是 MIUI）都會走到這裡，吞掉例外即可，不影響 brandHit 那一路。
            false
        }

        return brandHit || romPropertyHit
    }

    /**
     * ★ 2026-08-20 新增：開啟 MIUI 的權限編輯頁，引導使用者手動開啟「鎖定螢幕
     * 顯示」與「後台彈出介面」——這兩項是 MIUI 專有 AppOps，沒有標準 runtime
     * permission 對話框可以直接跟使用者要，只能導去系統設定頁讓使用者自己開。
     *
     * 依序嘗試三層，每一層都先 resolveActivity 確認裝置上真的有 Activity 能接，
     * 才呼叫 startActivity，避免在沒有對應頁面的機型／未來版本上崩潰：
     * 1. MIUI 安全中心權限編輯器的明確 component——最精準，通常直接落在
     *    這個 APP 的權限清單頁。
     * 2. MIUI 權限編輯器的 action（miui.intent.action.APP_PERM_EDITOR）——部分
     *    MIUI／HyperOS 版本 component 名稱不同，改用 action 讓系統自己解析。
     * 3. 標準「應用程式詳情」設定頁（ACTION_APPLICATION_DETAILS_SETTINGS）——
     *    所有 Android 裝置都有，雖然不會直接落在「其他權限」頁，但至少能讓
     *    使用者從這裡繼續往下找，好過完全沒有反應。
     *
     * 這三個目標都是 OEM 私有或系統標準頁面，前兩層屬於非公開介面，未來 MIUI／
     * HyperOS 版本可能改名或移除，因此用「一層失敗就試下一層」寫死優先順序，
     * 而不是假設其中一定存在。
     *
     * @return true 只代表「成功啟動了某個 Activity」，不代表使用者真的完成了
     *         設定——這兩項權限本來就無法用程式驗證，呼叫端（Dart 側）不可把
     *         true 當成「已授權」，一律只能顯示「需手動確認」。
     */
    private fun openOemPermissionEditor(): Boolean {
        // 1. 明確 component：MIUI 安全中心的權限編輯器
        try {
            val intent = android.content.Intent()
            intent.component = android.content.ComponentName(
                "com.miui.securitycenter",
                "com.miui.permcenter.permissions.PermissionsEditorActivity"
            )
            intent.putExtra("extra_pkgname", packageName)
            if (intent.resolveActivity(packageManager) != null) {
                startActivity(intent)
                return true
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }

        // 2. MIUI 權限編輯器 action，讓系統自己解析對應的 Activity
        try {
            val intent = android.content.Intent("miui.intent.action.APP_PERM_EDITOR")
            intent.putExtra("extra_pkgname", packageName)
            if (intent.resolveActivity(packageManager) != null) {
                startActivity(intent)
                return true
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }

        // 3. Fallback：標準「應用程式詳情」設定頁，所有 ROM 都有
        return try {
            val intent = android.content.Intent(
                android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS
            )
            intent.data = android.net.Uri.parse("package:$packageName")
            if (intent.resolveActivity(packageManager) != null) {
                startActivity(intent)
                true
            } else {
                false
            }
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }
}
