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
  /// 所有與「身分／帳號／裝置角色」有關的 prefs 鍵位。
  /// 新增鍵位時務必同步加進來，否則就會再度出現 session 綁死。
  static const List<String> _sessionKeys = [
    'user_role', 'saved_role',
    'caregiver_id', 'caregiver_name',
    'user_id', 'user_name',
    'saved_id', 'saved_device_name', 'saved_is_cctv',
    'access_token',
    'elder_room_id',
    'last_elder_id', 'last_elder_name', 'last_elder_room_id', 'last_elder_device_role',
    'selected_elder_id', 'selected_elder_name',
    'pending_accepted_call', 'pending_call_room', 'pending_call_id',
  ];

  /// 釋放目前裝置上綁定的 session：
  /// 1. 盡力通知後端註銷 FCM token（[notifyBackend] 為 false 時跳過）
  /// 2. 中斷 Signaling（一律用 forceDisconnect()，不可用 disconnect()）
  /// 3. 清掉所有 session 相關 prefs 鍵位（含動態的 device_role_* 鍵）
  /// 4. 重置全域角色變數 appRole
  ///
  /// 每個步驟各自 try/catch，任何一步失敗都不能擋住後面的清理——
  /// 釋放 session 是「盡量做乾淨」而不是「全有全無」的操作。
  static Future<void> releaseSession({bool notifyBackend = true}) async {
    final prefs = await SharedPreferences.getInstance();

    // 步驟 1：讀取通知後端所需資訊，並嘗試呼叫後端釋放 session（含註銷 FCM token）。
    if (notifyBackend) {
      try {
        String? fcmToken = prefs.getString('fcm_token');
        fcmToken ??= await FirebaseMessaging.instance.getToken();

        if (fcmToken != null) {
          final int? userId = prefs.getInt('caregiver_id');
          final String? roomId = prefs.getString('elder_room_id');
          await ApiService.releaseSession(
            fcmToken: fcmToken,
            userId: userId,
            roomId: roomId,
          );
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
    } catch (e) {
      debugPrint('⚠️ [SessionManager] 重置 appRole 失敗: $e');
    }
  }

  /// 供身分選擇頁使用：只在「確實殘留 session」時才釋放，避免每次冷啟動都白跑。
  static Future<bool> releaseIfBound() async {
    final prefs = await SharedPreferences.getInstance();
    final bool hasSessionKey = _sessionKeys.any((k) => prefs.containsKey(k));
    final bool hasDeviceRoleKey =
        prefs.getKeys().any((k) => k.startsWith('device_role_'));

    if (hasSessionKey || hasDeviceRoleKey) {
      await releaseSession();
      return true;
    }
    return false;
  }
}
