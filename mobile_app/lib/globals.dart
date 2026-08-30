import 'package:flutter/material.dart';

ValueNotifier<Map<String, String?>?> pendingAcceptedCall = ValueNotifier(null);
bool isAppReady = false;
String? appRole;

/// ★ 全域媒體播放狀態通知：當有 YouTube / 新聞 / TTS 播放時設為 true，背景 WakeWord 語音喚醒暫停監聽，徹底防範 Android 語音焦點競爭跳針
ValueNotifier<bool> isMediaPlayingNotifier = ValueNotifier(false);

/// ★ 2026-08-10 第二十輪（需求 6）：長輩端「全時語音喚醒詞」總開關。
///
/// 使用者回報「打開 App 後麥克風與攝像頭不斷地開啟與關閉」。追下去的根因是
/// `elder_home_screen.dart` 的常駐 `SpeechToText` 監聽——它被設計成**永不停止**：
///   - `onError` → 600ms 後重啟
///   - `onStatus` 收到 `done` / `notListening` → 400ms 後重啟
///   - 5 秒週期的看門狗發現沒在聽 → 重啟
///   - 每一次 `didChangeAppLifecycleState`（含通知列下拉這種小事）→ 重啟
///   - 媒體播放結束 → 重啟
/// 每次重啟都是一次麥克風 acquire/release，系統的麥克風指示燈於是不停閃爍，
/// 而這個 App 的核心是「環繞長輩語音操作」，環境雜音又會不斷觸發誤判重啟。
///
/// 預設 **false（關閉）**，由長輩端設定頁的開關手動啟用。
/// 關閉時完全不初始化 STT、不請求麥克風權限、不啟動看門狗——
/// 不是「啟動後再停掉」，而是根本不開始。
///
/// 這個 notifier 讓設定頁的切換能即時生效，不必重開 App；
/// 持久化鍵位為 [kWakeWordEnabledKey]，屬於「與帳號無關的裝置偏好」，
/// 因此**刻意不列入** `SessionManager._sessionKeys`，登出不會被清掉。
ValueNotifier<bool> wakeWordEnabledNotifier = ValueNotifier(false);

/// [wakeWordEnabledNotifier] 的 SharedPreferences 鍵位。
const String kWakeWordEnabledKey = 'wake_word_enabled';

/// ★ 2026-07-18：來電有效期（毫秒）。與後端 socket_app.py 的 expires_at/FCM ttl
///   以及 CallKit `duration` 三者必須一致，否則會出現「通知還在響但接聽被判過期」。
/// ★ 2026-07-20：有效期 45s→120s，與後端 socket_app.py expires_at/FCM ttl 同步。
///   Android Doze/省電桶可能延遲 FCM 60-90 秒，45s ttl 會在 Doze 期間過期。
///   CallKit duration 保持 45s 不變（使用者接聽時間仍以 45s 為限）。
/// ★ 2026-08-11 第二十二輪（需求 10）：120s→**60s**。使用者明確要求
///   「發起端最多僅可等待 1 分鐘，逾時就關閉該次連線」，避免出現
///   「電話明明是 2、3 分鐘前撥的，現在才跳來電通知」。
///   後端 `socket_app.py` 的 `expires_at`（一般＋緊急皆為 issued_at + 60000）與
///   FCM `ttl=60s`（call-request / emergency-call / cancel-call）必須與此值一致。
///   **取捨**：Doze 延遲超過 60 秒的推播會被丟棄而不是遲到才響——這是使用者
///   明確選擇的取捨，**不要改回 120s**。
///   CallKit `duration` 仍維持 45s（響鈴時間 ≠ 推播有效期，兩者本就不同義）。
const int kCallValidityMs = 60000;

/// ★ 2026-07-19：SplashScreen 是否仍在畫面上（冷啟動導航進行中）。
///   冷啟動接聽來電時，SplashScreen 是 pendingAcceptedCall 的唯一導航擁有者；
///   main.dart 的全域兜底導航在此期間必須讓位，避免把 VideoCallScreen push 到
///   Splash 上後又被 Splash 的 pushReplacement 洗掉（家屬接聽後只進主畫面的 bug）。
bool splashActive = false;

/// ★ issue 3/10：通話/監控畫面結束時的安全導航。
/// 若目前路由可以 pop（代表是從某個主畫面正常推入的），則直接返回；
/// 若無法 pop（例如冷啟動後直接被導向通話畫面，沒有上一頁），
/// 則導向呼叫端提供的 [fallbackScreen]（通常是長輩/家屬主畫面），
/// 並清空導航堆疊，避免出現黑屏或無回應畫面。
///
/// ★ 2026-08-23：補上「呼叫端路由是否仍是最上層」的防呆。
/// 通話結束／連線中斷是由多條互相獨立的回呼各自偵測（例如對方掛斷觸發
/// `onCallEnded`，WebRTC 連線隨即斷開又觸發 `onConnectionLost`，有時還會
/// 再加上 `onPeerConnectionFailed`），沒有任何集中判斷「這通電話是否已經
/// 處理過」，於是同一次掛斷可能讓兩、三個回呼都呼叫本函式。第一次呼叫已經
/// `pop()` 或 `pushAndRemoveUntil()` 把呼叫端的路由換掉，但 State 要到下一個
/// frame 才真正 dispose，第二次呼叫發生當下 `context.mounted` 仍讀得到
/// true，若不攔下就會在已經清空過一次的導航堆疊上再操作一次——這正是
/// 「畫面卡死、白屏或黑屏、完全無法操作」的成因。
/// `ModalRoute.of(context)?.isCurrent` 是比 `context.mounted` 更早失效的訊號：
/// `Navigator` 在 push/pop 當下就同步更新路由歷史（`isCurrent` 立刻反映），
/// 真正的 widget 卸載（連帶讓 `mounted` 變 false）則要等到下一次 build 才
/// 發生，因此能攔住「同一個 tick 內背靠背呼叫」這種光靠 `mounted` 檢查
/// 攔不住的情況。
/// 呼叫端若需要「本畫面只離開一次」更強的畫面內保證（涵蓋不經過
/// `safeNavigateBack` 的其他離場路徑），仍應自行加畫面內旗標——
/// 見 `elder_screen.dart::_navigatedAway`，兩層防線互補、不互相取代。
///
/// ★ 2026-08-24：回傳 `bool`——`true` 代表本次呼叫確實執行了導航（pop 或
/// push），`false` 代表因為上面的 `isCurrent` 防呆（或 `context` 已不在畫面
/// 上）而拒絕動作。**呼叫端的「已經離開」旗標必須鎖在這個回傳值上，不可在
/// 呼叫前就先鎖**：若先鎖、這裡又回傳 false，代表畫面其實哪裡都沒去，旗標
/// 卻已經鎖死，會擋住該畫面之後所有其他離場路徑——這正是「連線失敗」對話框
/// 曾經永久卡死的成因：對話框 `builder` 給的 context 在 `Navigator.pop` 之後
/// 已不是最上層路由，這裡因而回傳 false，但呼叫端在呼叫前就把旗標鎖住了，
/// 於是永遠沒有第二次機會離開畫面。
bool safeNavigateBack(BuildContext context, Widget fallbackScreen) {
  if (!context.mounted) return false;
  // ★ 2026-08-23：呼叫端自己的路由若已經不是最上層（代表已被另一個回呼
  //   搶先導航掉），視為重複呼叫，直接不做事；以下兩個分支的行為完全不變。
  if (ModalRoute.of(context)?.isCurrent != true) return false;
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop();
  } else {
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => fallbackScreen),
      (route) => false,
    );
  }
  return true;
}

/// ★ 2026-08-02 第十四輪：解析各通路傳來的 isVideoCall。
/// Socket 給 bool、FCM 經後端 `str()` 會變成 "True"/"False"（Python 首字大寫）、
/// prefs/CallKit extra 給字串——一律在此正規化。
/// **只有明確為 false 才判定為語音通話**，其餘（含 null、無法解析）一律 true（安全預設）。
bool parseIsVideoCall(dynamic raw) {
  if (raw == null) return true;
  if (raw is bool) return raw;
  return raw.toString().trim().toLowerCase() != 'false';
}
