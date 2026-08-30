// lib/services/session_manager.dart
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../globals.dart';
import 'api_service.dart';
import 'signaling.dart';

/// ★ 2026-08-10 第二十輪（需求 1、5）：全專案唯一的 session 釋放入口。
///
/// 過去有四份互相分歧的登出實作，沒有一份會斷開 Signaling、
/// 也沒有一份通知後端註銷 FCM token，導致「登出後仍收得到來電推播」、
/// 「重開 App 直接進入被綁死的帳號」、「監控機退出後再也綁不回去」。
/// 任何新的登出／退出流程都必須走這裡，不得再自行 remove 鍵位。
class SessionManager {
  /// 所有與「身分／帳號／裝置角色」有關的 prefs 鍵位——**基礎層**：
  /// 不論一般登出或強制解綁，一律清除。
  /// 新增鍵位時務必同步加進來，否則就會再度出現 session 綁死；
  /// 除非新鍵跟 [_quickLoginKeys] 一樣，語意是「記住上一位登入者以便快速登回」
  /// 而非「目前是誰登入」，才歸進那份清單——不確定就放這裡，寧可多清也不要漏清。
  static const List<String> _sessionKeys = [
    'user_role', 'saved_role',
    'caregiver_id', 'caregiver_name',
    'user_id', 'user_name',
    'saved_id', 'saved_device_name', 'saved_is_cctv',
    'access_token',
    'elder_room_id',
    'selected_elder_id', 'selected_elder_name',
    'pending_accepted_call', 'pending_call_room', 'pending_call_id',
  ];

  /// ★ 2026-08-25（本輪）：快速登入記憶鍵——**第二層**，獨立於 [_sessionKeys]。
  /// 護欄 **G24**：`last_elder_id` / `last_elder_name` / `last_elder_room_id` /
  /// `last_elder_device_role` 這組鍵刻意在**一般登出時保留**，好讓長輩在
  /// `elder_tabs/elder_profile_tab.dart::_handleLogout`（自己按「切換身分／登出」）
  /// 之後，還能在 `elder_pairing_display_screen.dart::_quickLoginSameElder`
  /// 一鍵登回同一長輩、不必重新走配對流程；該函式的回退邏輯正是讀這組鍵
  /// 還原 `caregiver_id`／`user_role`／`device_role_$room`／`saved_is_cctv`。
  /// 只有家屬端遠端 `force-logout`（強制解綁——這台裝置的授權已被收回，
  /// 不該再讓人一鍵登回）才連同清除。
  /// 是否保留由 [releaseSession] 的 [preserveQuickLogin] 參數決定，
  /// **預設 `false`（清除，等同過去「全清」的行為）**：新呼叫點忘記帶這個
  /// 參數時，寧可失敗成「乾淨的已登出」，也不要失敗成「殘留綁死的 session」。
  static const List<String> _quickLoginKeys = [
    'last_elder_id', 'last_elder_name', 'last_elder_room_id', 'last_elder_device_role',
  ];

  /// ★ 2026-08-11 第二十二輪（需求 8）：**實際在用**的待處理來電鍵位。
  ///
  /// 上面 `_sessionKeys` 裡那三個 `pending_*` 是 snake_case，但全專案真正讀寫的是
  /// `main.dart` / `splash_screen.dart` 寫入的 **camelCase** 版本
  /// （`pendingAcceptedCall` / `pendingRingCallData` / `pendingRingCall`）——
  /// 也就是說，過去登出／退出監控時這三個鍵**從來沒有被清掉**。
  /// 殘留的 `pendingAcceptedCall` 會在下一次冷啟動被 `main()` 讀出來重建來電，
  /// 是「從監視機跳回長輩端後，按接聽沒反應／房間對不上」的其中一條來源
  /// （另一條是孤兒 socket，見 `signaling.dart::_disposeSocket`）。
  ///
  /// 刻意**不併進** `_sessionKeys`：`releaseIfBound()` 用 `_sessionKeys` 判斷
  /// 「這台裝置是否還綁著身分」，把來電鍵混進去會讓「沒登入但殘留一則舊來電」
  /// 的裝置被誤判成有 session。兩者語意不同，必須分開。
  static const List<String> _pendingCallKeys = [
    'pendingAcceptedCall', 'pendingRingCallData', 'pendingRingCall',
  ];

  /// 釋放目前裝置上綁定的 session：
  /// 1. 盡力通知後端註銷 FCM token（[notifyBackend] 為 false 時跳過）
  /// 2. 中斷 Signaling（一律用 forceDisconnect()，不可用 disconnect()）
  /// 3. 清掉所有 session 相關 prefs 鍵位（含動態的 device_role_* 鍵）；
  ///    [preserveQuickLogin] 為 true 時保留 [_quickLoginKeys]（見該常數註解、護欄 G24）
  /// 4. 重置全域角色變數 appRole
  ///
  /// 每個步驟各自 try/catch，任何一步失敗都不能擋住後面的清理——
  /// 釋放 session 是「盡量做乾淨」而不是「全有全無」的操作。
  ///
  /// ★ 2026-08-25：新增 [preserveQuickLogin]，**預設 `false`**
  /// （維持既有行為＝全清，等同強制解綁的效果）。
  /// ★ [本輪]：目前共三個呼叫點傳 `true`——
  /// `elder_tabs/elder_profile_tab.dart::_handleLogout`（長輩自己按「登出」）、
  /// `elder_screen.dart::_exitCCTVMode`（長輩自己按「退出並重置」，語意等同
  /// 主動登出，見護欄 G125）、以及 [releaseIfBound] 內部呼叫（它只是這兩者
  /// 收尾導航到身分選擇頁後的安全閥，不是獨立的政策決定，理由見該函式註解）。
  /// 其餘呼叫點（家屬遠端強制解綁 `main.dart::handleForceLogout`——注意它走的是
  /// 自己一份完整的手動清單、不經過本函式也不經過 [releaseIfBound]；監控機被
  /// 家屬移除 `elder_screen.dart::onMonitorRemoved`；家屬端自己登出等）一律用
  /// 預設值——語意上都是「這台裝置／這個身分的授權已被收回」，不該保留快速
  /// 登入記憶。
  static Future<void> releaseSession({
    bool notifyBackend = true,
    bool preserveQuickLogin = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // 步驟 1：讀取通知後端所需資訊，並嘗試呼叫後端釋放 session（含註銷 FCM token）。
    // ★ 2026-08-17 第二十五輪（需求 4）：兩個 await 都補上 .timeout()。原本沒有逾時，
    //   若 getToken() 或 ApiService.releaseSession() 卡住不動（不是拋例外、是真的
    //   HANG 住），外層 try/catch 攔不到「掛住」，步驟 2～4（斷開 Signaling、清 prefs、
    //   重置 appRole）就永遠排不到——這正是「退出並重置」後裝置仍綁死在舊身分的根因。
    //   步驟 2～4 是「清理本機狀態」，無論如何都必須執行，絕不能被通知後端這一步卡死。
    if (notifyBackend) {
      try {
        String? fcmToken = prefs.getString('fcm_token');
        fcmToken ??= await FirebaseMessaging.instance
            .getToken()
            .timeout(const Duration(seconds: 5));

        if (fcmToken != null) {
          final int? userId = prefs.getInt('caregiver_id');
          final String? roomId = prefs.getString('elder_room_id');
          await ApiService.releaseSession(
            fcmToken: fcmToken,
            userId: userId,
            roomId: roomId,
          ).timeout(const Duration(seconds: 5));
        }
      } catch (e) {
        debugPrint('⚠️ [SessionManager] 通知後端釋放 session 失敗（忽略，繼續清理本機狀態）: $e');
      }
    }

    // 步驟 2：中斷 Signaling —— 一律用 forceDisconnect()，不可用 disconnect()
    //   （disconnect() 會失去 FCM 接收能力，是本專案的硬性護欄）。
    try {
      Signaling().clearSession();
      Signaling().forceDisconnect();
    } catch (e) {
      debugPrint('⚠️ [SessionManager] Signaling 釋放失敗（忽略，繼續清理本機狀態）: $e');
    }

    // 步驟 3：清除所有 session 相關 prefs 鍵位。
    //   絕不可用 prefs.clear()，那會連字體大小、通知偏好、wake_word_enabled
    //   等與帳號無關的設定一併洗掉。
    try {
      for (final key in _sessionKeys) {
        await prefs.remove(key);
      }
      // ★ 2026-08-25（本輪）：preserveQuickLogin 為 true 時保留這 4 個鍵，
      //   讓長輩登出後還能「快速登入同一長輩」；預設（false）仍然全清，
      //   等同過去「強制解綁」的效果，見護欄 G24。
      if (!preserveQuickLogin) {
        for (final key in _quickLoginKeys) {
          await prefs.remove(key);
        }
      }
      // ★ 2026-08-11 第二十二輪（需求 8）：連同 camelCase 的待處理來電鍵一起清。
      for (final key in _pendingCallKeys) {
        await prefs.remove(key);
      }
      final deviceRoleKeys =
          prefs.getKeys().where((k) => k.startsWith('device_role_')).toList();
      for (final key in deviceRoleKeys) {
        await prefs.remove(key);
      }
    } catch (e) {
      debugPrint('⚠️ [SessionManager] 清除 prefs 鍵位失敗: $e');
    }

    // 步驟 4：重置全域角色變數（globals.dart 的 appRole），避免殘留舊角色
    //   讓下一次判斷（例如 splash_screen 的還原邏輯）誤判。
    try {
      appRole = null;
      // ★ 2026-08-11 第二十二輪（需求 8）：prefs 清掉了，記憶體裡的 notifier 也要清。
      //   `pendingAcceptedCall` 是 ValueNotifier，各畫面的 listener 直接讀它的 value，
      //   不會回頭再讀 prefs；不歸零的話，退出監控後回到長輩主畫面的瞬間，
      //   舊的 pending 會被 listener 當成新來電消費掉（房間／角色都是上一輪的）。
      pendingAcceptedCall.value = null;
    } catch (e) {
      debugPrint('⚠️ [SessionManager] 重置 appRole 失敗: $e');
    }
  }

  /// 供身分選擇頁使用：只在「確實殘留 session」時才釋放，避免每次冷啟動都白跑。
  /// ⚠️ 判斷「要不要動手」時刻意只看 [_sessionKeys]，**不要**併入
  /// [_quickLoginKeys]——長輩登出後保留的 last_elder_* 屬於「未登入但記得
  /// 上一位」，不是「還綁著」，不該被算進殘留 session 的偵測條件。
  ///
  /// ★ [本輪]：真的動手清理時改傳 `preserveQuickLogin: true`（原本沿用
  /// [releaseSession] 預設值 `false`）。
  /// **原因**：本函式是「這台裝置疑似還殘留綁定痕跡」的安全閥，唯一目的是
  /// 避免使用者停在身分選擇頁仍收得到上一個帳號的來電、或重開 App 直接跳回
  /// 被綁死的帳號——它的職責是清乾淨「目前綁著誰」，**不是**決定「要不要記得
  /// 上一位長輩以便快速登回」。那個決定屬於呼叫端的政策，且早在導航到本畫面
  /// 之前就已經明確做過一次：長輩自己登出
  /// （`elder_tabs/elder_profile_tab.dart::_handleLogout`）與退出監控並重置
  /// （`elder_screen.dart::_exitCCTVMode`）都特地傳 `preserveQuickLogin: true`
  /// 保留 last_elder_*（護欄 G24／G125），做完才 `pushAndRemoveUntil` 到這個
  /// 畫面。若本函式偵測到任何殘留 `_sessionKeys`／`device_role_*`（不論成因
  /// ——包含尚未涵蓋到的邊界情況）就用預設參數再呼叫一次 [releaseSession]，
  /// 等於讓一個「不知道上游已經做過決定」的安全閥去覆蓋上游的保留，保留形同
  /// 虛設（使用者回報「登出轉監控設備、再轉回長輩通訊帳號後找不到快速登入」
  /// 正是這個機制造成，見 `CLAUDE_call-monitor.md` §7 G125）。安全閥該做的是
  /// 「補做上游可能漏做的清理」，不是「重新決定一次跟上游政策無關的清理範圍」。
  /// 🚫 這個改動**不影響**家屬端遠端強制解綁必須連 last_elder_* 一併清除的
  /// 保證：那條路徑（`main.dart::handleForceLogout`）走的是自己一份完整的
  /// 手動清單，本來就不呼叫本函式，見該處實作。
  static Future<bool> releaseIfBound() async {
    final prefs = await SharedPreferences.getInstance();
    final bool hasSessionKey = _sessionKeys.any((k) => prefs.containsKey(k));
    final bool hasDeviceRoleKey =
        prefs.getKeys().any((k) => k.startsWith('device_role_'));

    if (hasSessionKey || hasDeviceRoleKey) {
      // preserveQuickLogin: true —— 理由見上方函式註解：本函式是安全閥，
      // 不是政策決定者，不可覆蓋呼叫端已經做出的保留決定。
      await releaseSession(preserveQuickLogin: true);
      return true;
    }
    return false;
  }
}
