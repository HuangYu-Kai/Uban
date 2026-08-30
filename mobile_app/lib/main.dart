import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_line_sdk/flutter_line_sdk.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:app_links/app_links.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'network/http_overrides_stub.dart'
    if (dart.library.io) 'network/http_overrides_io.dart';

// Screens
import 'theme/app_theme.dart';
import 'screens/video_call_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/elder_home_screen.dart';
import 'screens/identification_screen.dart';

// Utils & Globals
import 'globals.dart';
import 'services/signaling.dart' as sig;
import 'services/api_service.dart';
import 'services/video_call_permission_service.dart';
import 'services/local_call_notification.dart';
// ★ 2026-08-05 第十七輪：YOLO／測試跌倒警報的高優先級通知（與來電備援 channel 分開）
import 'services/cctv_alert_notification.dart';
// ★ 2026-08-12 第二十三輪：緊急通話提示音的全域單一擁有者（救護車雙音）
import 'services/emergency_tone.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final StreamController<String> callKitDeclineStream =
    StreamController<String>.broadcast();

bool _supportsCallKit() {
  return !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
}

bool _isExpiredCallPayload(Map<String, dynamic> data) {
  final int now = DateTime.now().millisecondsSinceEpoch;
  final int? expiresAt = int.tryParse('${data['expiresAt'] ?? ''}');
  if (expiresAt != null && now > expiresAt) return true;
  final int? issuedAt = int.tryParse('${data['issuedAt'] ?? ''}');
  if (issuedAt != null && (now - issuedAt) > kCallValidityMs) return true;
  return false;
}

/// ★ 2026-08-05 第十六輪：由「來電payload 的發起方角色」反推本機角色。
///
/// 根因：整條來電鏈（BG handler 的 `role == 'elder'` 分支、FCM 前景守門、
/// `_setupSignalingListener` 的 `appRole != 'elder'`）全部只看本機 prefs 的
/// `user_role ?? saved_role`，而這兩個鍵由**不同畫面**寫入且語意不一致：
///   - `login_screen` 寫 `user_role='family'`
///   - `role_selection_screen` 只寫 `saved_role`（從不寫 `user_role`）
/// 因為 `user_role` 優先，一台曾登入過家屬、之後改當長輩的手機會永遠停在
/// `appRole='family'` → 家屬打來時 `senderRole('family') == appRole('family')`
/// 被判為角色反轉而丟棄，且 BG handler 也不會走長輩的 CallKit 分支
/// → 家屬→長輩在 APP 內/背景/被殺死**三態全滅**；
/// 而長輩→家屬完全不受影響（長輩撥出時 `role: 'elder'` 是明確傳入的，
/// 不讀 prefs）—— 正是回報的「不對稱失效」。
///
/// 通話只可能是 elder↔family，所以 payload 的 `role` 一旦有值就是權威：
/// 對方是 family → 我方必為 elder，反之亦然。prefs 僅作為 payload 缺角色時的退路。
String? _deriveMyRoleFromCall(dynamic senderRoleRaw, String? localRole) {
  final String senderRole = (senderRoleRaw ?? '').toString().trim();
  if (senderRole == 'family') return 'elder';
  if (senderRole == 'elder') return 'family';
  return localRole;
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  // ★ 背景 handler 在獨立 isolate 運行，必須先初始化 Firebase
  try {
    // Check if Firebase is already initialized to avoid conflicts
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
      debugPrint('🔥 [BG] Firebase initialized in background handler');
    } else {
      debugPrint('🔥 [BG] Using existing Firebase app in background handler');
    }
  } catch (e, stackTrace) {
    debugPrint('❌ [BG] Firebase initialization failed: $e');
    debugPrint('📍 Stack trace: $stackTrace');
    // Continue processing even if Firebase init fails - we might still be able to show notifications
  }

  try {
    debugPrint("📩 Background message received: ${message.data}");

    var type = message.data['type'];
    // ★ 2026-07-22 monitor-wakeup 正規化（長輩被殺死收不到來電根因修復）：
    //   後端依 deviceMode 決定 FCM type，若本機的 token 在後端殘留一列
    //   deviceMode='monitor'（曾當過監控機的殘留列），來電會被送成 'monitor-wakeup'，
    //   而本 handler 只放行 call-request/emergency-call/cancel-call → 被靜默丟棄 → 不響。
    //   這裡用本機權威旗標 saved_is_cctv 判斷：若本機其實是通訊機（非 CCTV），
    //   把 monitor-wakeup 還原成 call-request，確保通訊機被殺死時仍會響鈴。
    if (type == 'monitor-wakeup') {
      try {
        final prefs = await SharedPreferences.getInstance();
        final isCctv = prefs.getBool('saved_is_cctv') ?? false;
        if (!isCctv) {
          debugPrint('🔧 [BG] 本機為通訊機，將 monitor-wakeup 正規化為 call-request');
          type = 'call-request';
          message.data['type'] = 'call-request';
        }
      } catch (_) {}
    }
    // ★ 2026-08-05 第十七輪：YOLO／測試跌倒警報。必須放在下方的型別白名單**之前**，
    //   否則會被那道 `type != ...` 的過濾直接丟掉（白名單本身不動，避免影響來電路徑）。
    //   背景 isolate 不做 TTS（在裸 isolate 不可靠），改由 fullScreenIntent 通知
    //   點亮螢幕並發聲；使用者打開 App 後由前景路徑（family_main_screen）朗讀。
    //   這裡完全不碰任何來電去重狀態（lastProcessedCallId / pendingAcceptedCall），
    //   警報與來電是兩條互不相干的通路，混用共用 token 必然造成來電被吃掉。
    if (type == 'cctv-alert') {
      debugPrint('🚨 [BG] 收到 CCTV 警報，顯示高優先級通知');
      try {
        await CctvAlertNotification.show(message.data);
      } catch (e) {
        debugPrint('⚠️ [BG] 跌倒警報通知失敗: $e');
      }
      return;
    }

    if (type != 'call-request' && type != 'emergency-call' && type != 'cancel-call' && type != 'force-logout') {
      debugPrint('⚠️ [BG] Ignoring message of type: $type');
      return;
    }

    if ((type == 'call-request' || type == 'emergency-call') &&
        _isExpiredCallPayload(message.data)) {
      debugPrint('⏰ [BG] Ignoring expired call payload: ${message.data['callId']}');
      return;
    }

    // ★ issue 4/5 fix: cancel-call FCM → dismiss CallKit immediately
    if (type == 'cancel-call') {
      debugPrint('🔕 [BG] Remote canceled call, dismissing CallKit...');
      // ★ 2026-07-22 第十一輪 Fix 1：endAllCalls 在 MIUI 被殺死背景 isolate 會拋
      //   PlatformException(content is null)，必須 try-catch，否則會中斷後續清理。
      try {
        await FlutterCallkitIncoming.endAllCalls();
      } catch (e) {
        debugPrint('⚠️ [BG] endAllCalls 失敗（不影響後續）: $e');
      }
      // ★ 第十一輪 Fix 3：一併取消原生備援通知。
      await LocalCallNotification.cancel();
      // ★ 2026-07-22 第八輪 Fix 2C：取消來電時清除背景預寫的陳舊狀態，
      //   避免冷啟動 main() 讀到 pendingRingCallData 誤重建 pending。
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('pendingAcceptedCall');
        await prefs.remove('pendingRingCallData');
        await prefs.remove('pendingRingCall');
      } catch (_) {}
      return;
    }

    // ★ 2026-07-30 第十四輪：force-logout 在背景 handler 中清除所有 session 鍵，
    //   讓下次冷啟動時 Splash → main() 看到空 prefs → 跳轉到 IdentificationScreen。
    //   背景 handler 無法導航（獨立 isolate），只能清 prefs；導航由冷啟動路徑接手。
    if (type == 'force-logout') {
      debugPrint('🚪 [BG] 收到 force-logout，清除背景 session 鍵');
      try {
        final bgPrefs = await SharedPreferences.getInstance();
        const keysToRemove = [
          'caregiver_id', 'caregiver_name', 'user_role', 'saved_role',
          'saved_id', 'saved_device_name', 'saved_is_cctv', 'elder_room_id',
          'access_token',
          'last_elder_id', 'last_elder_name', 'last_elder_room_id', 'last_elder_device_role',
          'pendingAcceptedCall', 'pendingRingCallData', 'pendingRingCall',
        ];
        for (final key in keysToRemove) { await bgPrefs.remove(key); }
        final deviceRoleKeys = bgPrefs.getKeys().where((k) => k.startsWith('device_role_')).toList();
        for (final key in deviceRoleKeys) { await bgPrefs.remove(key); }
        debugPrint('🚪 [BG] force-logout 清除完成（${keysToRemove.length + deviceRoleKeys.length} 鍵）');
      } catch (e) {
        debugPrint('❌ [BG] force-logout 清除失敗: $e');
      }
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final myId = prefs.getInt('caregiver_id');
      final callerUserIdRaw = (message.data['callerUserId'] ?? '').toString();
      if (callerUserIdRaw.isNotEmpty && myId != null && myId.toString() == callerUserIdRaw) {
        debugPrint("🙅 [BG] 略過自己發起的來電 (callerUserId=$callerUserIdRaw == me=$myId)");
        return;
      }

      // ★ 2026-08-05 第十六輪：不再直接採信本機 prefs 的角色。
      //   payload 的發起方角色是權威（通話只可能 elder↔family），prefs 只作退路。
      //   詳見 _deriveMyRoleFromCall 的註解——本機 user_role 殘留 'family' 會讓
      //   下方 `role == 'elder'` 的長輩 CallKit 分支永遠不成立，來電整條消失。
      //   刻意**不**把推導結果寫回 prefs：裝置身分會決定冷啟動導航，
      //   在背景 isolate 改寫身分的爆炸半徑過大，此處只用於本通來電的分支判斷。
      final localRole = prefs.getString('user_role') ?? prefs.getString('saved_role');
      final role = _deriveMyRoleFromCall(message.data['role'], localRole);
      if (role != localRole) {
        debugPrint("🧭 [BG] 本機 prefs 角色為 $localRole，依 payload 發起方角色"
            "(${message.data['role']}) 推導本機應為 $role（prefs 未同步，本通依推導結果處理）");
      }
      final roomId = (message.data['roomId'] ?? '').toString();
      final senderId = (message.data['senderId'] ?? '').toString();
      final callId = (message.data['callId'] ?? '').toString();
      final callerName = (message.data['callerName'] ?? message.data['senderName'] ?? '有人來電').toString();

      if (role == 'elder' && type == 'emergency-call') {
        debugPrint("🚨 [BG] Emergency call for elder, saving pending call and waking app");

        final pendingCall = jsonEncode({
          'roomId': roomId,
          'senderId': senderId,
          'callId': callId,
          'isEmergency': true,
          // ★ 2026-07-27 第十三輪：補上發起方角色與有效期，與 call-request 路徑對齊，
          //   供消費端（splash / elder_home_screen）防角色反轉驗證（護欄 #16）。
          'senderRole': (message.data['role'] ?? 'family').toString(),
          'issuedAt': (message.data['issuedAt'] ?? '').toString(),
          'expiresAt': (message.data['expiresAt'] ?? '').toString(),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        await prefs.setString('pendingAcceptedCall', pendingCall);

        // ★ 直接發送 Intent 啟動應用程式，喚醒裝置並進入視訊房間
        try {
          if (defaultTargetPlatform == TargetPlatform.android) {
            final AndroidIntent intent = AndroidIntent(
              action: 'android.intent.action.MAIN',
              package: 'com.example.flutter_application_1',
              componentName: 'com.example.flutter_application_1.MainActivity',
              flags: <int>[
                0x10000000, // FLAG_ACTIVITY_NEW_TASK
                0x00020000, // FLAG_ACTIVITY_REORDER_TO_FRONT
                0x20000000, // FLAG_ACTIVITY_SINGLE_TOP
              ],
            );
            await intent.launch();
          }
        } catch (e, stackTrace) {
          debugPrint('❌ [BG] AndroidIntent error: $e');
          debugPrint('📍 Stack trace: $stackTrace');
        }
        return;
      }

     if (role == 'elder' && type == 'call-request') {
       // ★ 2026-07-20 第七輪修復：在顯示 CallKit *之前*預先寫入 pendingRingCallData，
       //   確保 APP 被系統強制殺死後，冷啟動時 main() 有 fallback 資料可用。
       //   即使 BG isolate 的 CallKit Accept listener 寫入失敗（小米/OPPO 嚴格背景
       //   IO 限制），pendingRingCallData 已在收到 FCM 時寫入，不會遺失。
       try {
         final prefs = await SharedPreferences.getInstance();
         await prefs.setString('pendingRingCallData', jsonEncode({
           'roomId': roomId,
           'senderId': senderId,
           'callId': callId,
           'issuedAt': (message.data['issuedAt'] ?? '').toString(),
           'expiresAt': (message.data['expiresAt'] ?? '').toString(),
           'callerName': callerName,
           'senderRole': (message.data['role'] ?? '').toString(),
           // ★ Fix E：透傳是否為視訊通話，false = 純語音（電話），預設 true。
           'isVideoCall': (message.data['isVideoCall'] ?? 'true').toString(),
           'isAccepted': false,
           'timestamp': DateTime.now().millisecondsSinceEpoch,
         }));
       } catch (e) {
         debugPrint('⚠️ [BG] 寫入 pendingRingCallData 失敗: $e');
       }
       // ★ 2026-07-27 第十三輪：長輩端一般來電回歸 CallKit 全螢幕來電 UI。
       //   先前改成只發 LocalCallNotification（樸素 heads-up）造成兩個問題：
       //   (1) 來電樣式不是期望的 CallKit UI；
       //   (2) 備援通知的點擊 payload 在 APP 被殺死時無人消費，冷啟動只進主畫面。
       //   CallKit 已有完整的冷啟動接聽鏈路（BG isolate 寫 prefs → main() → Splash）。
       //   備援通知改由 _showFullScreenCallkit 內部在「CallKit 確實沒建立」時才補發。
       await _showFullScreenCallkit(message.data);
       return;
     }

      // ★ issue 14：家屬端在背景／螢幕關閉時收到長輩的「一般」來電，
      // 不應強制把 App 帶到前景，只顯示來電通知，由使用者主動點擊接聽。
      if (role != 'elder' && type == 'call-request') {
        // ★ 2026-07-20 第七輪修復：同長輩端，預寫 pendingRingCallData。
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('pendingRingCallData', jsonEncode({
            'roomId': roomId,
            'senderId': senderId,
            'callId': callId,
            'issuedAt': (message.data['issuedAt'] ?? '').toString(),
            'expiresAt': (message.data['expiresAt'] ?? '').toString(),
            'callerName': callerName,
            'senderRole': (message.data['role'] ?? '').toString(),
            // ★ Fix E：透傳是否為視訊通話，false = 純語音（電話），預設 true。
            'isVideoCall': (message.data['isVideoCall'] ?? 'true').toString(),
            'isAccepted': false,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          }));
        } catch (e) {
          debugPrint('⚠️ [BG] 寫入 pendingRingCallData 失敗: $e');
        }
        // ★ 2026-07-27 第十三輪：家屬端一般來電同樣回歸 CallKit（與長輩端一致）。
        await _showFullScreenCallkit(message.data);
        return;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [BG] Error in SharedPreferences processing: $e');
      debugPrint('📍 Stack trace: $stackTrace');
      // Continue to show notification even if prefs processing fails
    }

    // 其餘情況（能落到這裡的只剩「家屬端收到緊急來電」——elder+emergency-call、
    // elder+call-request、!elder+call-request 三種組合都已在上面提前 return）。
    // ★ 2026-08-24（使用者裁定）：「強制開啟」（AndroidIntent 直接把 App 拉到前景）
    //   只允許用於長輩端，絕不可用於家屬端——家屬手機無故被拉到前台，對任何懂技術的
    //   使用者而言都像是惡意軟體行為；長輩端保留這個行為，是因為身處困境的長輩必須
    //   能被聯繫到，不能只靠當事人自行手動解鎖、開啟 App。因此這裡移除了 AndroidIntent
    //   強制喚醒，只保留下面的來電響鈴畫面（CallKit 全螢幕來電通知）——使用者已明確
    //   將「來電響鈴畫面」列為刻意保留的例外，不受本次變更影響。
    // 🔁 若日後要把家屬端的緊急來電也降級成一般被動通知（不再彈全螢幕來電畫面），
    //   要改的就是下面這一行 _showFullScreenCallkit(...)。
    await _showFullScreenCallkit(message.data);
  } catch (e, stackTrace) {
    debugPrint('❌ [BG] Unexpected error in firebaseMessagingBackgroundHandler: $e');
    debugPrint('📍 Stack trace: $stackTrace');
    // Ensure we don't silently fail - still try to show a basic notification if possible
    try {
      await _showFullScreenCallkit(message.data);
    } catch (e2) {
      debugPrint('❌ [BG] Failed to show CallKit notification: $e2');
    }
  }
}

/// ★ 在背景/鎖屏顯示全螢幕 CallKit 來電（issue 2 & 3 的核心修復）。
///   接聽/拒絕事件由 [_MyAppState._setupCallKitListener] 透過 extra 內的 roomId/senderId/callId 接手。
Future<void> _showFullScreenCallkit(Map<String, dynamic> data) async {
  if (kIsWeb) return;
  final callerName =
      (data['callerName'] ?? data['senderName'] ?? '有人來電').toString();
  final roomId = (data['roomId'] ?? '').toString();
  final senderId = (data['senderId'] ?? '').toString();
  final callId = (data['callId'] ??
          DateTime.now().millisecondsSinceEpoch.toString())
      .toString();
  final issuedAt = (data['issuedAt'] ?? '').toString();
  final expiresAt = (data['expiresAt'] ?? '').toString();
  final senderRole = (data['role'] ?? '').toString();
  // ★ Fix E：是否為視訊通話，false = 純語音（電話），預設 true。
  //   緊急通話路徑從不帶此欄位，會自然預設為 true（維持強制視訊）。
  final isVideoCall = (data['isVideoCall'] ?? 'true').toString();
  final isEmergency = data['type'] == 'emergency-call';

  final params = CallKitParams(
    id: callId,
    nameCaller: callerName,
    appName: 'Uban',
    handle: isEmergency ? '🚨 緊急視訊通話' : '📞 視訊通話',
    type: 1,
    duration: 45000,
    textAccept: '✓ 接聽',
    textDecline: '✕ 拒絕',
    missedCallNotification: const NotificationParams(
      showNotification: true,
      isShowCallback: false,
      subtitle: '未接來電',
    ),
    extra: <String, dynamic>{
      'roomId': roomId,
      'senderId': senderId,
      'callId': callId,
      'issuedAt': issuedAt,
      'expiresAt': expiresAt,
      // ★ 2026-07-22 第八輪 Fix 3：透傳發起方角色，供接聽消費端驗證防角色反轉。
      'senderRole': senderRole,
      // ★ Fix E：透傳是否為視訊通話，供接聽消費端決定進房時鏡頭預設狀態。
      'isVideoCall': isVideoCall,
    },
    android: const AndroidParams(
      isCustomNotification: true,
      isShowLogo: false,
      ringtonePath: 'system_ringtone_default',
      backgroundColor: '#1a472a',
      actionColor: '#4CAF50',
      textColor: '#ffffff',
      incomingCallNotificationChannelName: 'Uban_Incoming_Call',
      isShowFullLockedScreen: true, // ★ 鎖定畫面全螢幕顯示
    ),
    ios: const IOSParams(
      handleType: 'generic',
      supportsVideo: true,
    ),
  );

  // ★ 2026-07-22 第十一輪 Fix 1：showCallkitIncoming 補 try-catch + log。
  //   它 Dart 端是「射後不理」（原生 sendBroadcast 後立即 success），正常不會拋錯，
  //   但仍包起來以防原生 platform channel 在某些 MIUI 版本同步拋 content-is-null。
  try {
    await FlutterCallkitIncoming.showCallkitIncoming(params);
    debugPrint('📲 [CallKit] showCallkitIncoming 已呼叫 (callId=$callId)');
  } catch (e) {
    debugPrint('⚠️ [CallKit] showCallkitIncoming 失敗（將依賴原生備援通知）: $e');
  }

  // ★ 2026-07-18 修復：APP 被殺死時，主 isolate 不存在，_setupCallKitListener
  //   收不到 CallKit 的拒接/逾時事件 → 拒接訊號永遠送不出去，發起方持續等待。
  //   這裡在背景 isolate 註冊短命 listener，攔到拒接/逾時就走無狀態 HTTP
  //   /api/call/decline 通知後端廣播 cancel-call（含 FCM），讓發起方即時停止等待。
  //   若使用者是「接聽」，則不處理（交由冷啟動後的正常流程接手）。
  //
  // ★ 2026-08-12 第二十三輪（需求 1「長輩端在 APP 外拒絕按鈕沒有用，只能按接受」）：
  //   上面這個 listener 從第四輪就存在，但**幾乎沒生效過**。原因不在 listener 本身，
  //   而在它的壽命：`_showFullScreenCallkit` 一 return，FCM 背景 handler 的 Future 就
  //   完成 → Android 端 `FlutterFirebaseMessagingBackgroundService` 的 `latch` 放行 →
  //   JobIntentService 收工 → 背景 FlutterEngine 被銷毀。使用者是在**幾秒後**才按下
  //   按鈕的，那時 `bgSub` 早就跟著 isolate 一起消失了。
  //
  //   「接受」看起來有效、「拒絕」看起來無效，正是這個 bug 的指紋：
  //   接受由 CallKit **原生層**直接拉起 MainActivity（完全不需要 Dart），
  //   拒絕卻只有 Dart 這一條路（要送 declineCall 給發起方、要清三個 prefs 鍵）。
  //
  //   修法：用一個 Completer 把背景 handler 的 Future 壓住，直到
  //   接聽／拒接／逾時／通話結束任一發生（或 50 秒上限）才放行。
  //
  //   ⚠️ 已知取捨（**刻意接受**，不要「修掉」）：FCM 背景 handler 在 Android 是
  //   **序列**執行的，保活期間後續 FCM（例如發起方按取消的 `cancel-call`）會排隊等待。
  //   最壞情況是發起方取消後、被叫端仍響到 CallKit 自己的 45 秒 `duration` 逾時為止。
  //   這在第二十二輪需求 10 已訂下的「來電最多等 1 分鐘」預算之內，
  //   而換來的是「拒接從 100% 失效變成可用」，且逾時事件終於送得到發起方
  //   （第二十三輪需求 3 的雙端逾時對話框，在被殺死情境下就靠這條）。
  StreamSubscription<CallEvent?>? bgSub;
  final Completer<void> bgDecision = Completer<void>();
  void releaseBgHold(String why) {
    if (!bgDecision.isCompleted) {
      debugPrint('🏁 [BG-CallKit] 結束背景保活（$why）');
      bgDecision.complete();
    }
  }

  if (senderId.isNotEmpty && roomId.isNotEmpty) {
    bgSub = FlutterCallkitIncoming.onEvent.listen((CallEvent? e) async {
      if (e == null) return;
      if (e.event == Event.actionCallDecline ||
          e.event == Event.actionCallTimeout) {
        debugPrint('🔕 [BG-CallKit] ${e.event} → HTTP declineCall (call=$callId)');
        await LocalCallNotification.cancel(); // ★ 第十一輪：拒接時關備援通知
        await ApiService.declineCall(
          roomId: roomId,
          senderId: senderId,
          callId: callId,
        );
        // ★ 2026-07-22 修復（第八輪 Issue 2）：BG isolate 拒接時清除所有陳舊狀態，
        //   避免下次冷啟動 main() 讀到 pendingRingCallData 誤重建 pending，
        //   或 pendingAcceptedCall 殘留導致角色反轉（接收方變發起方）。
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('pendingAcceptedCall');
          await prefs.remove('pendingRingCallData');
          await prefs.remove('pendingRingCall');
        } catch (_) {}
        await bgSub?.cancel();
        releaseBgHold('使用者拒接／響鈴逾時');
      } else if (e.event == Event.actionCallAccept) {
        // ★ 2026-07-19 第六輪：冷啟動時主 isolate 的 _setupCallKitListener 可能
        //   還沒註冊就錯過 accept 事件。背景 isolate 在此把接聽資料寫入
        //   SharedPreferences 的 pendingAcceptedCall——main() 冷啟動時會讀取
        //   這個 key 並在 Splash 之前設定 pendingAcceptedCall.value，
        //   確保「殺死狀態接聽」一定能導向視訊房間。
        // ★ 2026-07-20 第七輪：同時更新 pendingRingCallData 的 isAccepted flag，
        //   作為 main() 冷啟動時的雙重備援（即使 pendingAcceptedCall 寫入失敗，
        //   pendingRingCallData 已在收到 FCM 時預寫，main() 可用它重建 pending）。
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('pendingAcceptedCall', jsonEncode({
            'roomId': roomId,
            'senderId': senderId,
            'callId': callId,
            'issuedAt': issuedAt,
            'expiresAt': expiresAt,
            'senderRole': senderRole,
            'isVideoCall': isVideoCall, // ★ Fix E
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          }));
          debugPrint('✅ [BG-CallKit] accept → 已寫入 pendingAcceptedCall 至 prefs (call=$callId)');
          // 更新 pendingRingCallData isAccepted flag 作為備援
          await prefs.setString('pendingRingCallData', jsonEncode({
            'roomId': roomId,
            'senderId': senderId,
            'callId': callId,
            'issuedAt': issuedAt,
            'expiresAt': expiresAt,
            'callerName': callerName,
            'senderRole': senderRole,
            'isVideoCall': isVideoCall, // ★ Fix E
            'isAccepted': true,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          }));
        } catch (err) {
          debugPrint('⚠️ [BG-CallKit] 寫入 pendingAcceptedCall 失敗: $err');
        }
        await LocalCallNotification.cancel(); // ★ 第十一輪：接聽時關備援通知
        await bgSub?.cancel();
        releaseBgHold('使用者接聽');
      } else if (e.event == Event.actionCallEnded) {
        // ★ 2026-08-12 第二十三輪：通話被原生層／`endAllCalls()` 結束（例如發起方取消）。
        //   這裡不再送 declineCall——結束方已經知道了，重複送只會製造多重拒絕訊息
        //   （第八輪護欄 #14 的單通路原則）。只要放行保活即可。
        await bgSub?.cancel();
        releaseBgHold('CallKit 通話已結束');
      }
    });
  } else {
    releaseBgHold('缺 roomId/senderId，沒有可等待的事件');
  }

  // ★ 被殺死狀態可靠性修復：CallKit 在部分裝置會靜默建立失敗，
  //   若未補備援通知就會變成「完全沒來電彈窗」。
  //   這裡維持互斥：只有偵測到 CallKit 未建立時才補一則本地來電通知。
  if (!isEmergency) {
    // ★ 2026-08-02 第十四輪：單次 900ms 取樣容易誤判（CallKit 原生建立是非同步的），
    //   長輩機因此常落到備援的樸素樣式。改為輪詢。
    bool callkitAlive = false;
    for (int i = 0; i < 8; i++) { // 8 × 250ms = 最多 2.0s
      await Future.delayed(const Duration(milliseconds: 250));
      try {
        final activeCalls = await FlutterCallkitIncoming.activeCalls();
        if (activeCalls is List && activeCalls.isNotEmpty) {
          callkitAlive = true;
          break;
        }
      } catch (_) {}
    }

    if (callkitAlive) {
      debugPrint('✅ [BG-CallKit] CallKit 已建立，不發備援通知');
      await LocalCallNotification.cancel();
    } else {
      debugPrint('⚠️ [BG-CallKit] CallKit 未建立，補發備援通知');
      await LocalCallNotification.show(data);
      // 二段確認：CallKit 可能較慢才建立；事後出現就撤掉備援，避免雙重通知。
      for (int i = 0; i < 6; i++) { // 6 × 250ms = 最多 1.5s
        await Future.delayed(const Duration(milliseconds: 250));
        try {
          final activeCalls = await FlutterCallkitIncoming.activeCalls();
          if (activeCalls is List && activeCalls.isNotEmpty) {
            debugPrint('✅ [BG-CallKit] CallKit 事後建立成功，撤銷備援通知');
            await LocalCallNotification.cancel();
            break;
          }
        } catch (_) {}
      }
    }
  }

  // ★ 2026-08-12 第二十三輪（需求 1）：背景保活。
  //   **必須放在最後**——上面的備援探測本身就會 await 最多 3.5 秒，
  //   把保活擺前面會讓「CallKit 沒建立時補發備援通知」整整晚 50 秒才執行，
  //   等於把第十三輪護欄 #22 的互斥備援機制廢掉。
  if (!bgDecision.isCompleted) {
    debugPrint('⏳ [BG-CallKit] 保持背景 isolate 存活以接住拒接／接聽事件（最多 50s）');
    try {
      await bgDecision.future.timeout(const Duration(seconds: 50));
    } on TimeoutException {
      debugPrint('⌛ [BG-CallKit] 背景保活達 50s 上限，放行（使用者未操作）');
    } catch (e) {
      debugPrint('⚠️ [BG-CallKit] 背景保活等待異常（忽略）: $e');
    }
    try {
      await bgSub?.cancel();
    } catch (_) {}
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ★ 2026-08-11 第二十一輪（需求 4）：整段開機初始化包上「總逾時」。
  //
  //   `runApp()` 原本在 try/catch **之外**，所以只有「例外」不會擋住它——
  //   但 Dart 的 try/catch **攔不到卡住**。`Firebase.initializeApp()`、
  //   `requestPermission()`（會等系統權限對話框）、`LineSDK.setup()`、
  //   `SharedPreferences` 這些 platform channel 只要有一個不回來，
  //   `runApp()` 就永遠不會被呼叫 → 停在系統的原生啟動畫面（純白、沒有任何
  //   動畫、也不可能跳轉），而且每次重開都一樣。這正是使用者回報的症狀。
  //
  //   `.timeout()` 不會取消底層工作，只是讓等待方先走：UI 一定會起來，
  //   初始化則在背景自己完成（Firebase 晚幾秒 ready 也不影響已註冊的
  //   background handler）。個別高風險 await 另外再各自設較短的逾時。
  try {
    await _bootstrap().timeout(const Duration(seconds: 10));
  } catch (e) {
    debugPrint('⚠️ [Main] 開機初始化未在 10 秒內完成（逾時或例外），仍繼續啟動 UI: $e');
  }

  runApp(const MyApp());
}

Future<void> _bootstrap() async {
  configureHttpOverrides();

  // ★ 音訊焦點共存設定：防止背景語音喚醒與音訊播放器搶奪 Audio Focus 造成播音中斷
  try {
    AudioPlayer.global.setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        stayAwake: true,
        contentType: AndroidContentType.music,
        usageType: AndroidUsageType.media,
        audioFocus: AndroidAudioFocus.none,
      ),
    ));
  } catch (e) {
    debugPrint('⚠️ [AudioContext Config Fail] $e');
  }

  // ★ 2026-08-11 第二十一輪（需求 4）：以下每個 await 都補上個別逾時。
  //   包在 try 裡**不等於**安全——try/catch 只攔例外，攔不到永遠不回來的
  //   platform channel；逾時才會把「卡住」轉成可被 catch 的例外。
  try {
    await dotenv.load(fileName: '.env').timeout(const Duration(seconds: 3));
  } catch (_) {}

  try {
    // Initialize date formatting
    await Future.wait([
      initializeDateFormatting('zh_TW', null),
      initializeDateFormatting('zh', null),
    ]).timeout(const Duration(seconds: 3));
    Intl.defaultLocale = 'zh_TW';
  } catch (e) {
    debugPrint('Intl initialization failed: $e');
  }

  try {
    // Bug 16: Ensure role is loaded at boot (Check both common keys)
    final prefs = await SharedPreferences.getInstance()
        .timeout(const Duration(seconds: 5));
    // ★ 2026-07-22：冷啟動時強制從磁碟刷新，確保讀到 BG isolate 最新寫入
    await prefs.reload().timeout(const Duration(seconds: 3));
    appRole = prefs.getString('user_role') ?? prefs.getString('saved_role');
    debugPrint("🚀 App Booting. Detected Role: $appRole");

    // ★ 2026-07-27 第十三輪：若本次冷啟動是「點擊備援來電通知」觸發的，
    //   payload 只會出現在 getNotificationAppLaunchDetails()（背景 tap handler
    //   在 APP 已終止時不保證被呼叫）。這裡先把它寫進 pendingAcceptedCall prefs，
    //   下面既有的讀取邏輯就能接手 → Splash → 視訊房間，與 CallKit 路徑一致。
    try {
      await LocalCallNotification.consumeLaunchPayload()
          .timeout(const Duration(seconds: 3));
      await prefs.reload().timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint("⚠️ [Main] consumeLaunchPayload 失敗: $e");
    }

    final pendingCallStr = prefs.getString('pendingAcceptedCall');
    if (pendingCallStr != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(pendingCallStr);
        // ★ issue 10：App 被滑掉重啟時，丟棄逾時（>60秒）未完成的待接聽通話，
        //   避免冷啟動後直接被導向一通早已結束/被拒絕的舊通話。
        // ★ 2026-08-11 第二十一輪（需求 4）：`timestamp` 缺漏一律視為「過期」。
        //   原本 `ts == null` 會退化成 `ageMs = 0`（永遠新鮮），任何一筆沒帶
        //   timestamp 的殘留資料就會**每次冷啟動都被重新載入**，把使用者永久
        //   鎖在「無動畫、不跳轉」的畫面上。修好寫入端（見 onEmergencyCall）之後，
        //   全專案所有寫入點都會帶 timestamp，因此「沒有 timestamp」等同於
        //   「舊版本殘留的髒資料」——這條同時也是既有裝置的自我修復路徑。
        final int? ts = int.tryParse('${decoded['timestamp'] ?? ''}');
        final int ageMs = ts != null
            ? DateTime.now().millisecondsSinceEpoch - ts
            : -1;
        if (ts == null || ageMs > 60000) {
          debugPrint("🗑️ [Main] Discarding stale pendingAcceptedCall "
              "(ts=$ts, age: ${ageMs}ms)");
          await prefs.remove('pendingAcceptedCall');
        } else {
          pendingAcceptedCall.value = decoded.map((key, value) => MapEntry(key, value?.toString()));
          debugPrint("🚨 [Main] Loaded pendingAcceptedCall from SharedPreferences: $pendingCallStr");
        }
        // ★ 2026-07-22：不在此處 remove，保留給 splash_screen 備援讀取。
        //   splash_screen._navigateToNext() 的最終防線會在消費後清除。
        // await prefs.remove('pendingAcceptedCall');
      } catch (e) {
        debugPrint("Error parsing pendingAcceptedCall: $e");
      }
    }

    // ★ 2026-07-20 第七輪：pendingRingCallData 備援。
    //   若 pendingAcceptedCall 未成功載入（BG isolate 的 CallKit Accept listener
    //   寫入失敗，或是冷啟動時主 isolate 尚未註冊 listener 就錯過事件），
    //   從 pendingRingCallData（在收到 FCM 時就預寫）重建。
    //   pendingRingCallData 含 isAccepted: true 代表使用者已按下接聽。
    if (pendingAcceptedCall.value == null) {
      final ringCallStr = prefs.getString('pendingRingCallData');
      if (ringCallStr != null) {
        try {
          final Map<String, dynamic> decoded = jsonDecode(ringCallStr);
          final bool isAccepted = decoded['isAccepted'] == true;
          final int? ts = int.tryParse('${decoded['timestamp'] ?? ''}');
          final int ageMs = ts != null
              ? DateTime.now().millisecondsSinceEpoch - ts
              : -1;
          // 超過有效期的舊資料直接丟棄
          // ★ 2026-08-11 第二十一輪（需求 4）：`timestamp` 缺漏同樣視為過期，
          //   理由與上方 pendingAcceptedCall 相同（避免不死的殘留資料）。
          // ★ 2026-08-11 第二十二輪（需求 10）：寫死的 120000 改用 kCallValidityMs
          //   （現為 60s），避免常數改了這裡卻沒跟著改而留下 2 分鐘的舊來電。
          if (ts == null || ageMs > kCallValidityMs) {
            debugPrint("🗑️ [Main] Discarding stale pendingRingCallData "
                "(ts=$ts, age: ${ageMs}ms)");
            await prefs.remove('pendingRingCallData');
          } else if (isAccepted) {
            pendingAcceptedCall.value = decoded.map((key, value) => MapEntry(key, value?.toString()));
            debugPrint("🚨 [Main] Fallback: reconstructed pendingAcceptedCall from pendingRingCallData (accepted)");
          } else {
            debugPrint("ℹ️ [Main] pendingRingCallData exists but isAccepted=false, keeping for fallback");
          }
          // ★ 2026-07-22：保留 pendingRingCallData 供 splash 備援，不在此處移除
          // await prefs.remove('pendingRingCallData');
        } catch (e) {
          debugPrint("Error parsing pendingRingCallData: $e");
        }
      }
    } else {
      // pendingAcceptedCall 已成功載入，保留 pendingRingCallData 供 splash 備援
      debugPrint("ℹ️ [Main] pendingAcceptedCall 已載入，保留 pendingRingCallData 供 splash 備援");
      // ★ 2026-07-22：不在 main 清掉
      // await prefs.remove('pendingRingCallData');
    }

    if (kIsWeb) {
      // On Web, skip initialization if FirebaseOptions is missing to prevent crash
      debugPrint("🌐 Web platform detected. Skipping Firebase if no options.");
    } else {
      await Firebase.initializeApp().timeout(const Duration(seconds: 6));
      // ★ 2026-07-18 修復：背景訊息 handler 必須在 Firebase 初始化後「立即」註冊，
      //   且獨立 try/catch。原本註冊在 LineSDK/Analytics 之後同一個 try 內，
      //   任一項噴錯就會導致 handler 沒註冊 → APP 被殺死時 FCM 無法喚醒 CallKit。
      try {
        FirebaseMessaging.onBackgroundMessage(
            _firebaseMessagingBackgroundHandler);
        debugPrint("🔔 FCM background handler registered");
        // ★ 2026-08-11 第二十一輪（需求 4）：`requestPermission()` 會等系統的
        //   通知權限對話框，使用者不點就不會回來 → 直接卡死 `runApp()`。
        //   移到 handler 註冊**之後**並加上逾時：權限對話框照常顯示、使用者
        //   慢慢點也沒關係，UI 不會被它綁架。
        await FirebaseMessaging.instance
            .requestPermission()
            .timeout(const Duration(seconds: 4));
      } catch (e) {
        debugPrint("⚠️ FCM background handler registration failed: $e");
      }

      // Initialize Firebase Analytics（非關鍵，失敗不影響來電）
      try {
        FirebaseAnalytics.instance.logAppOpen();
      } catch (e) {
        debugPrint("⚠️ Firebase Analytics initialization failed: $e");
      }

      // Initialize LINE SDK（非關鍵，失敗不影響來電）
      try {
        await LineSDK.instance
            .setup("2009500424")
            .timeout(const Duration(seconds: 4));
        debugPrint("🟢 LineSDK Initialized in main()");
      } catch (e) {
        debugPrint("⚠️ LineSDK initialization failed: $e");
      }
    }
  } catch (e) {
    debugPrint("⚠️ Firebase initialization failed or missing: $e");
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  // ★ 問題4修復：FCM 消息去重，防止 Socket.IO + FCM 重複通知
  final Map<String, int> _fcmCallIdCache = {}; // 記錄已處理的 callId 和時間戳
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  // ★ [本輪]：移機復原代碼的「待消費」暫存與其輪詢計時器。
  //   理由見 _scheduleRecoveryCodeFallback 的函式註解。
  String? _pendingRecoveryCode;
  Timer? _recoveryPollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    isAppReady = true; // ★ 標記 APP 已就緒，允許導航
    if (!kIsWeb) {
      _setupForegroundMessaging(); // ★ 新增：背景推播之外，前景也要監聽
      if (_supportsCallKit()) {
        _setupCallKitListener();
        _checkInitialCall(); // ★ 冷啟動檢查：是否有正在進行的 CallKit
      }
    }
    _setupSignalingListener();
    sig.Signaling().updateAppForeground(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = navigatorKey.currentContext;
      if (context != null) {
        VideoCallPermissionService.requestOnFirstUse(context);
      }
      
      // ★ Issue 8：請求懸浮視窗權限（讓來電通知覆蓋其他 APP）
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        Permission.systemAlertWindow.status.then((status) {
          if (!status.isGranted) {
            debugPrint("🔔 [Main] 請求懸浮視窗權限...");
            Permission.systemAlertWindow.request();
          }
        });
      }
    });
    
    // 延遲初始化 Deep Link，確保 Navigator 已就緒
    Future.delayed(const Duration(milliseconds: 1500), () {
      _initDeepLinks();
    });
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _recoveryPollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _initDeepLinks() async {
    // 檢查冷啟動傳入的連結
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }
    } catch (e) {
      debugPrint('Deep Link initialization failed: $e');
    }

    // 監聽熱啟動傳入的連結
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    }, onError: (err) {
      debugPrint('Deep Link Stream error: $err');
    });
  }

  void _handleDeepLink(Uri uri) {
    debugPrint('🔗 Caught Deep Link: $uri');
    // 支援 uban://recovery?code=xxx 或 HTTP(S) url
    if (uri.path == '/recovery' || uri.scheme == 'uban' && uri.host == 'recovery' || uri.path.contains('recovery')) {
      final code = uri.queryParameters['code'];
      if (code != null) {
        debugPrint('🔑 Extracted recovery code: $code');
        // ★ [本輪]：固定 300ms 延遲是跟 Splash 冷啟動導航的一場必輸賭局，
        //   改成等 splashActive 確定結束（且冷啟動全程沒出現待接聽來電）才
        //   消費，理由見 _scheduleRecoveryCodeFallback 的函式註解。
        _scheduleRecoveryCodeFallback(code);
      }
    }
  }

  /// ★ [本輪]：復原代碼必須等 Splash 冷啟動導航「塵埃落定」後才消費，不能賭
  /// 固定延遲。
  ///
  /// 舊版 `Future.delayed(300ms, () => _showRecoveryConfirmationDialog(code))`
  /// 賭的是「300ms 後 App 一定已經穩定顯示」，這個假設在冷啟動時不成立：
  /// Deep Link 本身要等 `initState` 排定的 1500ms 才開始處理（見
  /// `_initDeepLinks` 的呼叫點），而 `splash_screen.dart` 沒有待接聽來電時的
  /// 標準路徑光是開場動畫就至少 4000ms 才會第一次 `pushReplacement`／
  /// `pushAndRemoveUntil`——300ms 後對話框幾乎必定在 Splash 都還沒換頁時，
  /// 就用 `navigatorKey` 那個 root Navigator 彈出。Splash 稍後呼叫
  /// `_replaceWith`／`_navigateFamilyHome`／`_goNext` 時，
  /// `Navigator.pushReplacement` 換掉的是「這個 Navigator 當下最上層的
  /// route」——這時最上層是復原對話框、不是 Splash 自己的 route，於是對話框
  /// 被換頁悄悄打斷、Splash 的 route 反而留在底下沒被換掉，使用者看到的就是
  /// 「App 打開了，卡在身分選擇介面，復原流程什麼反應都沒有」。
  ///
  /// 改走與 `pendingAcceptedCall` 同一種「資料先存、確定性訊號才消費」模式，
  /// 比照既有的 `_scheduleAcceptedCallFallback` 輪詢 `splashActive`：
  /// `splashActive` 只會在 `SplashScreen.dispose()` 變 false，而 `dispose()`
  /// 只會在 Splash 完成一次 `pushReplacement`／`pushAndRemoveUntil`、新畫面
  /// 接手之後才觸發，所以「`splashActive == false`」是「Splash 整段導航（含
  /// 所有待接聽來電分支）已經跑完」的確定性訊號，不是又猜一個「這次應該夠長
  /// 了吧」的延遲。
  ///
  /// 🚨 絕對限制（不得違反）：輪詢期間只要**曾經**觀察到
  /// `pendingAcceptedCall.value != null`（不論一般來電或緊急通話，也不論到了
  /// 要顯示對話框那一刻它是否已被目的地畫面消費掉、變回 null），本次啟動就
  /// **完全放棄**彈出復原對話框、直接丟棄這份代碼——通話永遠優先，復原提示
  /// 留到「下一次啟動」使用者重新點一次連結即可。這裡不重試、不排隊：漏接一通
  /// 緊急來電遠比晚一點看到復原提示嚴重得多。
  void _scheduleRecoveryCodeFallback(String code) {
    _recoveryPollTimer?.cancel();
    _pendingRecoveryCode = code;
    const int maxTicks = 100; // 100 × 200ms = 20s，高於 Splash 15 秒導航看門狗上限
    int tick = 0;
    bool sawPendingCall = pendingAcceptedCall.value != null;
    _recoveryPollTimer =
        Timer.periodic(const Duration(milliseconds: 200), (timer) {
      tick++;
      // 代碼已被覆蓋（例如熱啟動時又收到一次同類連結），這一輪作廢。
      if (_pendingRecoveryCode != code) {
        timer.cancel();
        return;
      }
      if (pendingAcceptedCall.value != null) {
        sawPendingCall = true;
      }
      // Splash 仍在導航中，讓位等待——不論是否曾出現待接聽來電都不搶在它前面。
      if (splashActive && tick < maxTicks) {
        return;
      }
      timer.cancel();
      if (_pendingRecoveryCode != code) return;
      _pendingRecoveryCode = null;
      if (sawPendingCall || pendingAcceptedCall.value != null) {
        debugPrint(
            '⏸️ [Main] 本次冷啟動偵測到待接聽來電/緊急通話，放棄彈出復原對話框（見函式註解），下次啟動請重新點擊連結');
        return;
      }
      _showRecoveryConfirmationDialog(code);
    });
  }

  Widget _buildIllustration(String elderName, String familyName) {
    final elderInit = elderName.isNotEmpty ? elderName[0] : '長';
    final familyInit = familyName.isNotEmpty ? familyName[0] : '家';

    return Container(
      height: 120,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 裝飾性 bezier 連接點線
          Positioned.fill(
            child: CustomPaint(
              painter: ConnectionLinePainter(),
            ),
          ),
          
          // 裝飾用圓圈背景 (長輩側)
          Positioned(
            left: 50,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF59B294).withValues(alpha: 0.08),
              ),
            ),
          ),
          
          // 裝飾用圓圈背景 (家屬側)
          Positioned(
            right: 50,
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF7043).withValues(alpha: 0.08),
              ),
            ),
          ),
          
          // 長輩頭貼 (左)
          Positioned(
            left: 70,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF59B294), Color(0xFF2E7D78)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2E7D78).withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: Center(
                child: Text(
                  elderInit,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),

          // 子女頭貼 (右)
          Positioned(
            right: 70,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF8A65), Color(0xFFFF7043)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF7043).withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: Center(
                child: Text(
                  familyInit,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),

          // 自訂黃金鑰匙圖示 (中間偏上)
          Positioned(
            top: 20,
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CustomPaint(
                    painter: GoldenKeyPainter(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showRecoveryConfirmationDialog(String code) {
    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint('⚠️ Cannot show recovery dialog: navigatorKey.currentContext is null');
      return;
    }

    debugPrint('💬 Showing recovery dialog for code: $code');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        bool isLoading = true;
        bool isVerified = false;
        String? errorMsg;
        String elderName = '';
        String familyName = '';
        Map<String, dynamic>? verifiedData;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            void runVerification() async {
              try {
                final result = await ApiService.verifyRecoveryCode(code);
                if (!dialogContext.mounted) return;
                
                if (result['status'] == 'success' && result['data'] != null) {
                  setDialogState(() {
                    isLoading = false;
                    isVerified = true;
                    verifiedData = result['data'];
                    elderName = verifiedData!['elder_name'] ?? '長輩';
                    familyName = verifiedData!['family_name'] ?? '家人';
                  });
                } else {
                  setDialogState(() {
                    isLoading = false;
                    isVerified = false;
                    errorMsg = result['message'] ?? result['error'] ?? result['detail'] ?? '驗證失敗';
                  });
                }
              } catch (e) {
                if (!dialogContext.mounted) return;
                setDialogState(() {
                  isLoading = false;
                  isVerified = false;
                  errorMsg = '網路連線失敗: $e';
                });
              }
            }

            if (isLoading && errorMsg == null && !isVerified) {
              Future.microtask(() => runVerification());
            }

            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(32),
              ),
              elevation: 10,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: Container(
                  color: const Color(0xFFFFFDF9), // 溫馨象牙白
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isLoading) ...[
                        const SizedBox(height: 20),
                        const SizedBox(
                          width: 50,
                          height: 50,
                          child: CircularProgressIndicator(
                            color: Color(0xFFFF7043),
                            strokeWidth: 4,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          '正在安全地驗證登入金鑰...',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 16,
                            color: const Color(0xFF555555),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ] else if (errorMsg != null) ...[
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: SizedBox(
                              width: 32,
                              height: 32,
                              child: CustomPaint(
                                painter: CozyErrorPainter(),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '金鑰驗證失敗',
                          style: GoogleFonts.notoSansTc(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF991B1B),
                            fontSize: 22,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          errorMsg!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.notoSansTc(
                            fontSize: 15,
                            color: const Color(0xFF555555),
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF7043),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              '關閉',
                              style: GoogleFonts.notoSansTc(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ] else if (isVerified) ...[
                        _buildIllustration(elderName, familyName),
                        const SizedBox(height: 24),
                        Text(
                          '👵 「您好，請問是 $elderName 嗎？」',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.notoSansTc(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF2E7D78),
                            fontSize: 30,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '「家人 $familyName 正在幫您登入 Uban 系統。」',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.notoSansTc(
                            fontSize: 22,
                            color: const Color(0xFF4A4A4A),
                            height: 1.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              height: 64,
                              child: ElevatedButton(
                                onPressed: () async {
                                  setDialogState(() {
                                    isLoading = true;
                                  });
                                  
                                  try {
                                    final int elderUserId = verifiedData!['user_id'];
                                    final String name = verifiedData!['elder_name'] ?? '長輩';
                                    final String? elderIdUuid = verifiedData!['elder_id'];
                                    
                                    final prefs = await SharedPreferences.getInstance();
                                    await prefs.setInt('caregiver_id', elderUserId);
                                    await prefs.setString('caregiver_name', name);
                                    await prefs.setString('user_role', 'elder');
                                    if (elderIdUuid != null) {
                                      await prefs.setString('elder_room_id', elderIdUuid);
                                    }
                                    appRole = 'elder';

                                    if (navigatorKey.currentState != null) {
                                      navigatorKey.currentState!.pop();
                                      navigatorKey.currentState!.pushAndRemoveUntil(
                                        MaterialPageRoute(
                                          builder: (_) => ElderHomeScreen(
                                            userId: elderUserId,
                                            userName: name,
                                            roomId: elderIdUuid,
                                          ),
                                        ),
                                        (route) => false,
                                      );
                                    }
                                  } catch (e) {
                                    setDialogState(() {
                                      isLoading = false;
                                      errorMsg = '寫入登入狀態失敗: $e';
                                    });
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF59B294),
                                  foregroundColor: Colors.white,
                                  shadowColor: const Color(0xFF59B294).withValues(alpha: 0.3),
                                  elevation: 4,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                child: Text(
                                  '是的，這是我',
                                  style: GoogleFonts.notoSansTc(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 22,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: TextButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF888888),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: Text(
                                  '不是我',
                                  style: GoogleFonts.notoSansTc(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _checkPendingCallFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingCallStr = prefs.getString('pendingAcceptedCall');
      if (pendingCallStr != null) {
        final Map<String, dynamic> decoded = jsonDecode(pendingCallStr);
        debugPrint("🚨 [Main] Found pendingAcceptedCall in SharedPreferences on Resume: $pendingCallStr");
        await prefs.remove('pendingAcceptedCall');

        // ★ issue 10：忽略逾時（>60秒）的待接聽通話
        // ★ 2026-08-11 第二十一輪（需求 4）：`timestamp` 缺漏一律視為過期
        //   （與 main() 的兩處判斷對齊，理由見該處註解）。
        final int? ts = int.tryParse('${decoded['timestamp'] ?? ''}');
        final int ageMs = ts != null
            ? DateTime.now().millisecondsSinceEpoch - ts
            : -1;
        if (ts == null || ageMs > 60000) {
          debugPrint("🗑️ [Main] Discarding stale pendingAcceptedCall on resume "
              "(ts=$ts, age: ${ageMs}ms)");
          return;
        }

        // ★ 修復：檢查是否與 Signaling 中的 lastProcessedCallId 重複（問題 4）
        final String? callId = decoded['callId']?.toString();
        final String? lastId = sig.Signaling().lastProcessedCallId;
        if (callId != null && callId == lastId) {
          debugPrint("🗑️ [Main] Discarding duplicate pendingAcceptedCall (callId=$callId)");
          return;
        }

        // 更新 ValueNotifier，讓首頁 listener 接手
        pendingAcceptedCall.value = decoded.map((key, value) => MapEntry(key, value?.toString()));
      }
    } catch (e) {
      debugPrint("Error checking pending call on resume: $e");
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint(
          "☀️ [Main] App Resumed. Triggering self-healing reconnection...");
      sig.Signaling().updateAppForeground(true);
      sig.Signaling().reconnect();
      _checkPendingCallFromSharedPreferences();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      sig.Signaling().updateAppForeground(false);
    }
  }

  // ★ 情境 2 修復 + 2026-07-19 第六輪還原 + 2026-07-20 第七輪重試強化：
  //   冷啟動時 actionCallAccept 事件可能在 _setupCallKitListener 註冊「之前」
  //   就已發生（使用者在 APP 被殺死時按下接聽 → 系統啟動 APP → Dart 尚未註冊
  //   listener → 事件遺失）。此時 pendingAcceptedCall 永遠不會被設定，
  //   使用者只會看到開機動畫 → 主畫面（真機回報的問題2）。
  //
  //   補救：檢查 activeCalls() 中「已被使用者明確接聽」(isAccepted=true) 且
  //   未過期的通話，補設 pendingAcceptedCall。僅響鈴未接聽的通話
  //   (isAccepted=false) 一律不動，維持「必須明確點擊接聽」的安全性。
  //
  //   ★ 第七輪：native CallKit plugin 狀態更新為非同步，冷啟動時查詢
  //   activeCalls() 可能回傳 isAccepted=false 或空列表。加入最多 3 次重試
  //   （間隔 300ms）等待 native 層完成狀態同步。
  Future<void> _checkInitialCall() async {
    const int maxAttempts = 3;
    const int retryDelayMs = 300;

    bool foundAccepted = false;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      if (attempt > 0) {
        debugPrint("🔄 [Main] _checkInitialCall retry ${attempt}/${maxAttempts - 1}...");
        await Future.delayed(const Duration(milliseconds: retryDelayMs));
      }
      try {
        final activeCalls = await FlutterCallkitIncoming.activeCalls();
        if (activeCalls is! List || activeCalls.isEmpty) {
          if (attempt < maxAttempts - 1) continue; // 可能是 native 尚未初始化，重試
          return;
        }
        if (attempt == 0) {
          debugPrint("ℹ️ [Main] 偵測到 ${activeCalls.length} 筆進行中的 CallKit，檢查是否有已接聽事件...");
        }
        for (final call in activeCalls) {
          if (call is! Map) continue;
          final bool isAccepted = call['isAccepted'] == true;
          if (!isAccepted) {
            continue;
          }
          foundAccepted = true;
          final extra = call['extra'];
          if (extra is! Map) continue;
          final String roomId = (extra['roomId'] ?? '').toString();
          final String senderId = (extra['senderId'] ?? '').toString();
          final String? callId = extra['callId']?.toString();
          final String? issuedAt = extra['issuedAt']?.toString();
          final String? expiresAt = extra['expiresAt']?.toString();
          if (roomId.isEmpty || senderId.isEmpty) continue;

          // 過期驗證（與 actionCallAccept 相同標準）
          final int now = DateTime.now().millisecondsSinceEpoch;
          final int? exp = int.tryParse(expiresAt ?? '');
          final int? issued = int.tryParse(issuedAt ?? '');
          final bool isExpired = (exp != null && now > exp) ||
              (issued != null && (now - issued) > kCallValidityMs);
          if (isExpired) {
            debugPrint("⏰ [Main] _checkInitialCall: 已接聽通話已過期 (callId=$callId)，忽略並關閉");
            FlutterCallkitIncoming.endAllCalls();
            continue;
          }

          debugPrint("✅ [Main] _checkInitialCall: 偵測到冷啟動前已接聽的通話 (callId=$callId)，補設 pendingAcceptedCall");
          if (callId != null && callId.isNotEmpty) {
            sig.Signaling().lastProcessedCallId = callId;
            sig.Signaling().lastProcessedCallTime = now;
          }
          pendingAcceptedCall.value = <String, String?>{
            'roomId': roomId,
            'senderId': senderId,
            'callId': callId,
            'issuedAt': issuedAt,
            'expiresAt': expiresAt,
            'isVideoCall': extra['isVideoCall']?.toString(),
          };
          _scheduleAcceptedCallFallback(roomId, senderId, callId);
          return; // 找到已接聽通話，立即結束
        }

        if (!foundAccepted) {
          if (attempt < maxAttempts - 1) {
            debugPrint("ℹ️ [Main] _checkInitialCall: 尚無 isAccepted=true 的通話，等待 native 狀態同步...");
            continue; // 重試
          }
          debugPrint("ℹ️ [Main] _checkInitialCall: ${maxAttempts} 次嘗試後仍無已接聽通話，放棄");
        }
        return; // 所有重試已用完
      } catch (e) {
        debugPrint("⚠️ [Main] _checkInitialCall error (attempt $attempt): $e");
        if (attempt >= maxAttempts - 1) return;
      }
    }
    // ★ 2026-07-23：3 次快速重試後若仍未找到 isAccepted=true，
    //   啟動背景 Timer 持續輪詢（不阻塞 initState 返回）。
    //   冷啟動時使用者可能在 5-15 秒後才點接聽，900ms 遠不足以捕捉。
    //   此 Timer 在 splash 期間讓位給 splash 的主動輪詢；splash 結束後
    //   若仍未消費則由本 Timer 捕捉。
    if (!foundAccepted) {
      _scheduleExtendedActiveCallsPoll();
    }
  }

  /// ★ 2026-07-23 背景 Timer 輪詢 activeCalls()，不阻塞 initState。
  /// 每 1 秒一次、最多 15 次（15 秒）。找到 isAccepted=true 時設定
  /// pendingAcceptedCall.value，由 splash / 首頁 listener 接手導航。
  void _scheduleExtendedActiveCallsPoll() {
    const int maxTicks = 15;
    int tick = 0;
    Timer.periodic(const Duration(seconds: 1), (timer) async {
      tick++;
      // pending 已被消費則停止
      if (pendingAcceptedCall.value != null) {
        timer.cancel();
        return;
      }
      try {
        final activeCalls = await FlutterCallkitIncoming.activeCalls();
        if (activeCalls is! List || activeCalls.isEmpty) {
          if (tick >= maxTicks) timer.cancel();
          return;
        }
        for (final call in activeCalls) {
          if (call is! Map) continue;
          if (call['isAccepted'] != true) continue;
          final extra = call['extra'];
          if (extra is! Map) continue;
          final String roomId = (extra['roomId'] ?? '').toString();
          final String senderId = (extra['senderId'] ?? '').toString();
          final String? callId = extra['callId']?.toString();
          if (roomId.isEmpty || senderId.isEmpty) continue;

          final int now = DateTime.now().millisecondsSinceEpoch;
          final String? expStr = extra['expiresAt']?.toString();
          final String? issStr = extra['issuedAt']?.toString();
          final int? exp = int.tryParse(expStr ?? '');
          final int? issued = int.tryParse(issStr ?? '');
          if ((exp != null && now > exp) ||
              (issued != null && (now - issued) > kCallValidityMs)) {
            FlutterCallkitIncoming.endAllCalls();
            continue;
          }

          debugPrint(
              "🚨 [ExtendedPoll] 背景輪詢捕捉到已接聽 (callId=$callId)");
          if (callId != null && callId.isNotEmpty) {
            sig.Signaling().lastProcessedCallId = callId;
            sig.Signaling().lastProcessedCallTime = now;
          }
          pendingAcceptedCall.value = <String, String?>{
            'roomId': roomId,
            'senderId': senderId,
            'callId': callId,
            'issuedAt': issStr,
            'expiresAt': expStr,
            'isVideoCall': extra['isVideoCall']?.toString(),
          };
          timer.cancel();
          return;
        }
      } catch (_) {}
      if (tick >= maxTicks) timer.cancel();
    });
  }

  BuildContext? _activeCallDialogContext;
  String? _lastHandledEmergencyCallId;

  /// ★ 2026-08-04：force-logout 重入防護時間戳。
  ///   後端 unbind 會同時送 Socket 與 FCM 兩份 force-logout，兩條路徑各觸發一次
  ///   handleForceLogout()，兩次 pushAndRemoveUntil 疊加會在轉場途中清空路由 → 黑屏。
  ///   刻意採「時間戳比對」而非布林旗標：無論中途發生什麼異常，3 秒後必定自動失效，
  ///   不可能永久卡死（比照 lastProcessedCallId / lastProcessedCallTime 的既有慣用法）。
  static int _lastForceLogoutMs = 0;

  /// ★ 2026-08-02 第十四輪：只有「真正顯示來電 UI」的通路才可以宣告共用去重 token。
  ///   先前 FCM 前景路徑先寫 token 再 early return，導致隨後抵達的 Socket
  ///   call-request 被 signaling.dart 的 2 秒去重窗口丟棄 → 前景完全沒有來電 UI。
  void _claimCallDedupToken(String? callId, {dynamic isVideoCallRaw}) {
    if (callId == null || callId.isEmpty) return;
    sig.Signaling().lastProcessedCallId = callId;
    sig.Signaling().lastProcessedCallTime = DateTime.now().millisecondsSinceEpoch;
    // ★ 2026-08-02 第十四輪：FCM 前景備援接手時，Socket 從未寫過視訊/語音旗標，
    //   這裡補記，讓後續 _navigateToVideoCall 的 isVideoCallFor(callId) 查得到。
    //   isVideoCallRaw 為 null 時 parseIsVideoCall 回傳 true，即安全預設（視訊）。
    sig.Signaling().incomingCallIsVideoCallId = callId;
    sig.Signaling().incomingCallIsVideo = parseIsVideoCall(isVideoCallRaw);
  }

  void _setupForegroundMessaging() {
      // !!!!除非要更新視訊通話邏輯，否則禁止更動!!!!
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      debugPrint("📩 [Main] Foreground message received: ${message.data}");
      // ★ 2026-07-22 monitor-wakeup 正規化（同背景 handler）：本機若非 CCTV 通訊機，
      //   把後端因殘留 monitor token 誤送的 monitor-wakeup 還原成 call-request。
      if (message.data['type'] == 'monitor-wakeup') {
        try {
          final prefs = await SharedPreferences.getInstance();
          final isCctv = prefs.getBool('saved_is_cctv') ?? false;
          if (!isCctv) {
            debugPrint("🔧 [FCM-Fg] 本機為通訊機，將 monitor-wakeup 正規化為 call-request");
            message.data['type'] = 'call-request';
          }
        } catch (_) {}
      }
      // ★ 2026-08-05 第十七輪：YOLO／測試跌倒警報（前景 FCM）。
      //   APP 在前景時 Socket 的 'cctv-alert' 才是主通路（family_main_screen 會彈窗＋朗讀），
      //   這裡只補一則系統通知當備援，並且**絕對不碰**來電去重狀態
      //   （_claimCallDedupToken / lastProcessedCallId）——那條 token 只屬於來電通路。
      if (message.data['type'] == 'cctv-alert') {
        debugPrint("🚨 [FCM-Fg] 收到 CCTV 警報，補發系統通知");
        try {
          await CctvAlertNotification.show(message.data);
        } catch (e) {
          debugPrint("⚠️ [FCM-Fg] 跌倒警報通知失敗: $e");
        }
        return;
      }

      if (message.data['type'] == 'call-request' || message.data['type'] == 'emergency-call') {
        if (_isExpiredCallPayload(message.data)) {
          debugPrint("⏰ [FCM-Backup] 忽略過期來電 (callId=${message.data['callId']})");
          return;
        }
        final roomId = message.data['roomId'];
        final senderId = message.data['senderId'];
        final callId = message.data['callId'];
        final senderRole = message.data['role'];
        final isEmergency = message.data['type'] == 'emergency-call';

        // ★ 2026-08-05 第十六輪：原本用 `appRole == senderRole` 判角色反轉，
        //   但 appRole 來自可能過期的 prefs（user_role/saved_role 由不同畫面寫入、
        //   語意不一致）。長輩機殘留 user_role='family' 時，家屬來電會在這裡被
        //   誤判為「同角色」而丟棄 → 前景收不到來電。改用 payload 反推：
        //   payload 有角色時它就是權威，只有 payload 缺角色時才退回 appRole 比對，
        //   保留護欄 #16 對「自己的來電繞回自己」的防護。
        final myRole = _deriveMyRoleFromCall(senderRole, appRole);
        if (senderRole != null && myRole == senderRole) {
          debugPrint("📞 [FCM-Backup] Ignoring call-request: sender role ($senderRole) matches our role ($myRole, appRole=$appRole)");
          return;
        }

        // ★ issue 1：過濾「自己發起的來電」（callerUserId == 本機 caregiver_id）
        try {
          final prefs = await SharedPreferences.getInstance();
          final myId = prefs.getInt('caregiver_id');
          final callerUserId = int.tryParse('${message.data['callerUserId'] ?? ''}');
          if (myId != null && callerUserId != null && myId == callerUserId) {
            debugPrint("🙅 [FCM-Backup] 略過自己發起的來電 (callerUserId=$callerUserId == me=$myId)");
            return;
          }
        } catch (_) {}

        // ★ 問題4修復：與 Socket.IO 共享去重邏輯，防止 Socket.IO + FCM 重複通知
        final int currentTime = DateTime.now().millisecondsSinceEpoch;
        if (callId != null) {
          // 與 Signaling 共享相同的去重判斷
          if (callId == sig.Signaling().lastProcessedCallId && 
              (currentTime - sig.Signaling().lastProcessedCallTime) < 3000) {
            debugPrint("⚠️ [FCM-Backup] 忽略重複的 ${isEmergency ? '緊急' : ''}來電（CallId 已由 Socket 處理: $callId）");
            return;
          }
          if (_fcmCallIdCache.containsKey(callId)) {
            final lastProcessedTime = _fcmCallIdCache[callId] ?? 0;
            if ((currentTime - lastProcessedTime) < 3000) { // 3秒去重窗口
              debugPrint("⚠️ [FCM-Backup] 忽略重複的 ${isEmergency ? '緊急' : ''}來電（CallId 已在 3 秒內處理: $callId）");
              return;
            }
          }
          // 更新緩存
          _fcmCallIdCache[callId] = currentTime;
          // ★ 清理舊的快取（超過5秒的記錄）
          _fcmCallIdCache.removeWhere((key, value) => (currentTime - value) > 5000);
        }

        // ★ 2026-08-12 第二十三輪：長輩端的緊急通話**無條件自動接聽**，
        //   在此直接短路，不進下面的 dialog 路徑。
        //   刻意放在 `isResumed` 寬限期**之前**：寬限期存在的理由是「讓 Socket 先彈窗、
        //   避免同一通來電出現兩個來電 UI」，而緊急通話根本不彈窗，等 1.5 秒只會
        //   延後長輩進房。重複觸發由 _autoAcceptEmergencyCall 內的
        //   _lastHandledEmergencyCallId 去重，Socket 先到也不會做第二次。
        if (isEmergency && myRole == 'elder') {
          await _autoAcceptEmergencyCall(
            roomId: (roomId ?? '').toString(),
            senderId: (senderId ?? '').toString(),
            callId: callId?.toString(),
            senderRole: senderRole?.toString(),
            issuedAt: message.data['issuedAt']?.toString(),
            expiresAt: message.data['expiresAt']?.toString(),
            isVideoCallRaw: message.data['isVideoCall'],
            source: '-FCM',
          );
          return;
        }

        // ★ 2026-08-02 第十四輪：前景不再裸 return（那會讓 Socket 也被去重丟棄 →
        //   家屬端在 APP 內完全收不到來電）。改為給 Socket 1.5 秒寬限期；
        //   寬限期屆滿仍未被 Socket 處理，才由 FCM 備援補上 dialog。
        final isResumed = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
        if (isResumed) {
          debugPrint("⏳ [FCM-Backup] 前景狀態，讓 Socket 優先處理（1.5 秒寬限期）");
          Timer(const Duration(milliseconds: 1500), () {
            if (!mounted) return;
            // Socket 路徑已處理（signaling.dart 在呼叫 onCallRequest 之前就會寫入此 token）
            if (callId != null && callId == sig.Signaling().lastProcessedCallId) {
              debugPrint("ℹ️ [FCM-Backup] 寬限期內 Socket 已處理，不重複彈窗 (callId=$callId)");
              return;
            }
            if (_isExpiredCallPayload(message.data)) {
              debugPrint("⏰ [FCM-Backup] 寬限期屆滿但來電已過期，忽略 (callId=$callId)");
              return;
            }
            if (callId != null && sig.Signaling().isCallInvalidated(callId.toString())) {
              debugPrint("🔕 [FCM-Backup] 寬限期屆滿但來電已被取消/拒接，忽略 (callId=$callId)");
              return;
            }
            debugPrint("🔔 [FCM-Backup] 寬限期屆滿，Socket 未處理，由 FCM 備援彈窗 (callId=$callId)");
            _claimCallDedupToken(callId?.toString(), isVideoCallRaw: message.data['isVideoCall']);
            _showIncomingCallDialog(
              roomId,
              senderId,
              callId: callId,
              isEmergency: isEmergency,
              callerName: message.data['senderName'] ?? message.data['callerName'],
              senderRole: senderRole?.toString(),
            );
          });
          return;
        }

        debugPrint(
            "🔔 [FCM-Backup] ${isEmergency ? '緊急' : ''}Call Request from $senderId in room $roomId (ID: $callId)");
        // ★ 備援：FCM 用作備份，以防 Socket 連接不穩定時收不到來電
        _claimCallDedupToken(callId?.toString(), isVideoCallRaw: message.data['isVideoCall']);
        _showIncomingCallDialog(
          roomId,
          senderId,
          callId: callId,
          isEmergency: isEmergency,
          callerName: message.data['senderName'] ?? message.data['callerName'],
          senderRole: senderRole?.toString(),
        );
      }

      // ★ issue 4/5 fix: cancel-call FCM in foreground → dismiss in-app dialog and CallKit
      if (message.data['type'] == 'cancel-call') {
        debugPrint("🔕 [FCM-Fg] Remote canceled call, dismissing dialog...");
        // ★ 2026-07-22 第八輪 Fix 2C：標記此 callId 失效，防止延遲抵達的同一
        //   call-request（Socket 或 FCM）再次彈窗 → 避免「取消後又響」與角色反轉。
        final canceledCallId = (message.data['callId'] ?? '').toString();
        sig.Signaling().invalidateCallId(canceledCallId);
        if (_activeCallDialogContext != null) {
          if (Navigator.canPop(_activeCallDialogContext!)) {
            Navigator.pop(_activeCallDialogContext!);
          }
          _activeCallDialogContext = null;
        }
        // Also end any active CallKit（★ 第十一輪：try-catch 防 content-is-null 崩潰）
        try {
          FlutterCallkitIncoming.endAllCalls();
        } catch (e) {
          debugPrint('⚠️ [FCM-Fg] endAllCalls 失敗（不影響）: $e');
        }
        await LocalCallNotification.cancel(); // ★ 第十一輪：關備援通知
        // ★ 2026-08-12 第二十三輪：來電被對方取消時必須停掉緊急提示音，
        //   否則長輩端會出現「通話早就沒了、救護車聲還在響」（護欄 G77 可停止性）。
        unawaited(EmergencyTone.instance.stop());
        return;
      }

      // ★ 2026-07-30 第十四輪：FCM 前景 force-logout 處理。
      //   當長輩在前景（如 ElderHomeScreen）收到 FCM force-logout → 清除 session 並導航。
      if (message.data['type'] == 'force-logout') {
        debugPrint('🚪 [FCM-Fg] 收到 force-logout，執行 handleForceLogout');
        _MyAppState.handleForceLogout();
        return;
      }
    });
  }

  static Future<void> handleForceLogout() async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastForceLogoutMs < 3000) {
      debugPrint('🚪 [Main] force-logout 已於 ${nowMs - _lastForceLogoutMs}ms 前處理過，忽略重複觸發（防黑屏）');
      return;
    }
    _lastForceLogoutMs = nowMs;
    debugPrint('🚪 [Main] 執行 handleForceLogout：清除 session 並退回身分選擇介面');
    try {
      sig.Signaling().clearSession();
      sig.Signaling().forceDisconnect();

      final prefs = await SharedPreferences.getInstance();
      const keysToRemove = [
        'caregiver_id', 'caregiver_name', 'user_role', 'saved_role',
        'saved_id', 'saved_device_name', 'saved_is_cctv', 'elder_room_id',
        'access_token',
        'last_elder_id', 'last_elder_name', 'last_elder_room_id', 'last_elder_device_role',
        'pendingAcceptedCall', 'pendingRingCallData', 'pendingRingCall',
        'selected_elder_id', 'selected_elder_name', 'selected_elder_room_id',
      ];
      for (final key in keysToRemove) {
        await prefs.remove(key);
      }
      final devRoleKeys = prefs.getKeys().where((k) => k.startsWith('device_role_')).toList();
      for (final key in devRoleKeys) {
        await prefs.remove(key);
      }
      pendingAcceptedCall.value = null;
      appRole = null;

      if (navigatorKey.currentState != null) {
        // ★ 2026-08-23：目的地由 RoleSelectionScreen 改為 IdentificationScreen——
        //   後者才是現行系統入口（見 family_dashboard_screen.dart:8 的說明），
        //   RoleSelectionScreen 是已被取代的舊畫面。這裡同時也是
        //   force-logout 事件唯一的導航擁有者：elder_screen.dart 原本另外
        //   掛了一份重複的 force-logout 監聽，兩者幾乎同時觸發時會各自
        //   pushAndRemoveUntil 到不同畫面，在已經清空一次的堆疊上再操作
        //   一次 → 背景徹底死機（ANR）／白屏。已將該重複監聽移除，這裡
        //   經由全域 navigatorKey 執行、即使 ElderScreen 未掛載也能觸發。
        navigatorKey.currentState!.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const IdentificationScreen()),
          (route) => false,
        );
      }
      debugPrint('🚪 [Main] handleForceLogout 完成，已成功退回 IdentificationScreen');
    } catch (e) {
      debugPrint('❌ [Main] handleForceLogout 失敗: $e');
    }
  }

  void _setupSignalingListener() {
    // !!!!除非要更新視訊通話邏輯，否則禁止更動!!!!
    final s = sig.Signaling();

    // ★ 關鍵修復：只有家屬端才在這裡設定 onCallRequest / onEmergencyCall
    //   長輩端的 onCallRequest 由 ElderHomeScreen.initState() 負責設定，
    //   如果在這裡也設定，會覆蓋掉 ElderHomeScreen 的回調，導致長輩端收不到來電。
    if (appRole != 'elder') {
      s.onCallRequest = (roomId, senderId, callId, [senderName]) {
        _showIncomingCallDialog(
          roomId,
          senderId,
          callId: callId,
          isEmergency: false,
          callerName: senderName,
        );
      };
    }
    
    // ★ 緊急呼叫處理（家屬端與長輩端都需要）
    s.onEmergencyCall = (roomId, senderId, callId, [senderName]) {
      // ★ 2026-08-12 第二十三輪：`CallRequestCallback` 塞不下 role/issuedAt/expiresAt，
      //   由 signaling.dart 在觸發本回呼前寫入 lastEmergencyMeta（純資料欄位，非狀態旗標）。
      final Map<String, String> meta = s.lastEmergencyMeta;
      final String? senderRole = meta['role'];
      // ★ 2026-08-05 第十六輪：不用可能殘留錯誤的 appRole 判角色——payload 的
      //   發起方角色才是權威（通話只可能 elder↔family），appRole 只作退路。
      //   長輩機殘留 user_role='family' 時，舊的 `appRole == 'elder'` 永遠不成立，
      //   緊急通話會掉進 else 分支去彈「接聽／拒絕」——正是使用者回報的症狀。
      final String? myRole = _deriveMyRoleFromCall(senderRole, appRole);
      if (myRole == 'elder') {
        // ★ 2026-08-12 第二十三輪：改走統一的無條件自動接聽收斂點
        //   （去重、關 CallKit／備援通知／dialog、播救護車提示音、寫 pending 全在裡面）。
        unawaited(_autoAcceptEmergencyCall(
          roomId: roomId,
          senderId: senderId,
          callId: callId,
          senderRole: senderRole,
          issuedAt: meta['issuedAt'],
          expiresAt: meta['expiresAt'],
          source: '-Socket',
        ));
      } else {
        _showIncomingCallDialog(
          roomId,
          senderId,
          callId: callId,
          isEmergency: true,
          callerName: senderName,
          senderRole: senderRole,
        );
      }
    };

    // 對方取消來電
    s.onCancelCall = (roomId, senderId, callId, [senderName]) {
      // ★ 2026-08-12 第二十三輪：同 FCM 取消路徑，一併停掉緊急提示音（護欄 G77）。
      unawaited(EmergencyTone.instance.stop());
      if (_activeCallDialogContext != null) {
        debugPrint(
            "🔕 [Main] Remote canceled call. Dismissing global dialog...");
        if (Navigator.canPop(_activeCallDialogContext!)) {
          Navigator.pop(_activeCallDialogContext!);
        }
        _activeCallDialogContext = null;
      }
    };

    // ★ 2026-08-25（第三十三輪）：WebRTC Offer 的全域預設處理。
    //   這是「更專屬的畫面」尚未接手 onIncomingCall 時的**唯一**防線——長輩端
    //   停留在 ElderHomeScreen（尚未進 ElderScreen）、或 ElderScreen 剛掛載但
    //   _initElderMode() 還卡在等 FCM token（最多 5 秒）／媒體初始化那幾秒
    //   空窗（見 elder_screen.dart::_initElderMode 內 onIncomingCall 註冊時機
    //   的說明），凡是這段期間抵達的 offer 全部會落到這裡。
    //   舊版無條件 `return true`——不分角色、不分這通電話是否真的被同意過，
    //   只要 offer 送達就一律放行，等同「預設允許接聽」。這正是使用者回報
    //   「長輩端鎖定螢幕時收到一般來電，沒有經過任何人為操作就直接進入
    //   視訊房間」的可疑根因：offer 一送達，這個全域預設值就會讓它長驅直入，
    //   不管長輩端當下有沒有做過任何選擇。
    s.onIncomingCall = (callerId, callType) async {
      debugPrint(
          "📞 [Main] Global Incoming Offer from $callerId (Type: $callType).");
      // 緊急通話：G81 規定長輩端任何情況下都不得出現接聽／拒絕 UI，這裡與
      // elder_screen.dart::onIncomingCall 的判斷一致，無條件放行。
      if (callType == 'emergency') {
        return true;
      }
      // 長輩端的一般通話：lastProcessedCallId 是 signaling.dart 對「一般
      // 來電」唯一的去重／已知來電 token，只會在收到 call-request 時寫入
      // （見 signaling.dart :424-425）。若本機在這個 session 從未處理過任何
      // call-request，代表這通 offer 完全沒有對應到 ElderHomeScreen 的來電
      // 對話框、CallKit 或備援通知——沒有任何使用者互動的證據，不可比照舊版
      // 直接放行，否則就是「預設允許接聽」原地重現。
      // ★ 若 lastProcessedCallId 非空，代表本機確實處理過某次 call-request
      //   （很可能就是這一通），沿用既有假設放行——這與 signaling.dart 在
      //   onIncomingCall 為 null 時使用的 isKnownAcceptedCall 判斷是同一套
      //   標準，不會讓已經合法接聽（透過對話框、CallKit 或備援通知）的來電
      //   在這裡被誤擋，也就不會在「已同意但畫面剛好還沒準備好」的空窗期
      //   造成漏接或重複詢問。
      if (appRole == 'elder' &&
          (sig.Signaling().lastProcessedCallId?.isEmpty ?? true)) {
        debugPrint(
            "⚠️ [Main] 長輩端收到沒有對應 call-request 紀錄的一般來電 offer，拒絕（避免未經同意就進房）");
        try {
          sig.Signaling().sendCallBusy(callerId);
        } catch (e) {
          debugPrint("⚠️ [Main] sendCallBusy 失敗（忽略）: $e");
        }
        return false;
      }
      return true;
    };

    // ★ 2026-08-04：改用 Signaling 的 onForceLogout callback。
    //   舊寫法 `s.socket?.on('force-logout', ...)` 在 initState 執行時 socket 為 null，
    //   `?.` 短路使 handler 從未註冊；實際的 socket 監聽已移入
    //   signaling.dart::_registerSocketListeners()，該處保證在 socket 建立後執行。
    s.onForceLogout = () {
      debugPrint('🚪 [Main-Socket] 收到 force-logout，全域處理');
      _MyAppState.handleForceLogout();
    };
  }

  /// ★ 2026-08-12 第二十三輪：緊急通話**無條件自動接聽**的單一收斂點。
  ///
  /// 使用者要求：「緊急通話不需要經過長輩同意，無論長輩端在 APP 內或 APP 外還是
  /// 任何情況，只要家屬端撥打了緊急通話，就由不得長輩端設備接受或拒絕接聽，
  /// 而是直接打開視訊通話房間」。
  ///
  /// 緊急通話有四條互不相干的抵達路徑，先前只有兩條真的自動接聽：
  ///
  /// | 通路 | 舊行為 | 現在 |
  /// |------|--------|------|
  /// | Socket `emergency-call`（APP 存活） | 自動接聽 ✅ | 改走本函式 |
  /// | FCM 背景 isolate（APP 被殺死） | 寫 prefs ＋ Intent 喚醒 ✅ | 不變 |
  /// | **FCM 前景備援**（Socket 掉線／慢） | **彈出接聽／拒絕 dialog ❌** | 改走本函式 |
  /// | **`_showIncomingCallDialog` 最終防線** | **彈出 dialog ❌** | 改走本函式 |
  ///
  /// 後兩條就是「長輩端還看得到拒絕按鈕」的實際來源。
  ///
  /// ⚠️ 本函式**刻意不自己導航**：導航統一由 `elder_home_screen` / `splash_screen` /
  /// main.dart 全域兜底三處消費 `pendingAcceptedCall` 完成。插一條新的導航路徑會與
  /// 那三層兜底互相打架（第五／六輪就是被這種重複導航洗掉 route 而黑屏）。
  ///
  /// ⚠️ 背景 isolate **不可**呼叫本函式（plugin 實例不共用、提示音停不掉），
  /// 那條路維持既有的「寫 prefs ＋ AndroidIntent 喚醒 → 冷啟動」流程。
  Future<void> _autoAcceptEmergencyCall({
    required String roomId,
    required String senderId,
    String? callId,
    String? senderRole,
    String? issuedAt,
    String? expiresAt,
    dynamic isVideoCallRaw,
    String source = '',
  }) async {
    if (roomId.isEmpty || senderId.isEmpty) {
      debugPrint('⚠️ [Emergency$source] roomId/senderId 為空，無法自動接聽');
      return;
    }
    final String id = (callId ?? '').trim();
    if (id.isNotEmpty && id == _lastHandledEmergencyCallId) {
      debugPrint('⚠️ [Emergency$source] 忽略重複的緊急通話 (callId=$id)');
      return;
    }
    if (id.isNotEmpty) _lastHandledEmergencyCallId = id;
    debugPrint('🚨 [Emergency$source] 緊急通話無條件自動接聽 (callId=$id)');

    // ★ 2026-08-19 第二十九輪：喚醒被背景化／鎖屏的長輩畫面（Android 14+）。
    //   全專案唯一會點亮螢幕、蓋過鎖屏的機制是這個 MethodChannel
    //   （`MainActivity.forceBringToFront()` → `showOverLockScreen()`，見 G49）。
    //   本函式是緊急通話四條抵達通路（Socket／FCM 前景備援／`_showIncomingCallDialog`
    //   最終防線）的共同收斂點，過去從未呼叫過它——螢幕未開啟或被鎖屏時，即使下面
    //   成功寫入 `pendingAcceptedCall`、外部消費者也已把 `_isInCall` 之類的狀態
    //   轉為進行中，長輩實際看到的仍是黑屏或鎖定畫面，得靠使用者自己按電源鍵才會
    //   發現「原來已經自動接聽了」。放在去重 guard **之後**、其餘副作用之前，確保
    //   同一通緊急通話只喚醒一次。
    //   ⚠️ 與 `elder_screen.dart::_handleAcceptedCallFromBackground`（:433-439）用
    //   同一個 channel／method；此處刻意改用 `await` + `try/catch`，**不是**
    //   `_navigateToVideoCall`（:2258-2263）那個未 `await` 的舊寫法——`invokeMethod`
    //   的 `PlatformException` 是非同步丟出的，不 `await` 就接不到（同步 try/catch
    //   會變成 dead code，見 G49 與 `video_call_screen.dart::_goHomeAfterCall` 的
    //   `catchError` 註解）。這裡是「無條件自動接聽」的收斂點，失敗必須確實被吞掉
    //   並記錄，不可讓自動接聽流程中斷、也不可假裝有 catch 到卻其實沒有。
    try {
      const platform = MethodChannel('com.example.app/bring_to_front');
      await platform.invokeMethod('bringToFront');
    } catch (e) {
      debugPrint('⚠️ [Emergency$source] 喚醒畫面失敗（不影響自動接聽）: $e');
    }

    // 宣告共用去重 token，讓隨後抵達的另一條通路（Socket ↔ FCM）不再重複處理。
    _claimCallDedupToken(id.isEmpty ? null : id, isVideoCallRaw: isVideoCallRaw);

    // 關掉「可能已經跳出來」的來電 UI——緊急通話不給選擇，畫面上不該留下按鈕。
    if (_activeCallDialogContext != null) {
      try {
        if (Navigator.canPop(_activeCallDialogContext!)) {
          Navigator.pop(_activeCallDialogContext!);
        }
      } catch (e) {
        debugPrint('⚠️ [Emergency$source] 關閉來電 dialog 失敗（忽略）: $e');
      }
      _activeCallDialogContext = null;
    }
    // ★ 第十一輪：endAllCalls 在部分 MIUI 會拋 content-is-null，必須包 try-catch，
    //   否則整條自動接聽會在這裡中斷（護欄 G21）。
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (e) {
      debugPrint('⚠️ [Emergency$source] endAllCalls 失敗（不影響）: $e');
    }
    try {
      await LocalCallNotification.cancel();
    } catch (e) {
      debugPrint('⚠️ [Emergency$source] 關閉備援通知失敗（不影響）: $e');
    }

    // 提示音：監視機（CCTV）自動接聽必須完全靜音（護欄 G56）。
    bool isCctv = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      isCctv = prefs.getBool('saved_is_cctv') ?? false;
    } catch (_) {}
    if (!isCctv) {
      // 不 await：提示音是輔助，絕不可讓它延後進房（護欄 G77）。
      unawaited(EmergencyTone.instance.play());
    }

    final Map<String, dynamic> pendingCallData = <String, dynamic>{
      'roomId': roomId,
      'senderId': senderId,
      'callId': id,
      'isEmergency': true,
      // 護欄 G16：全鏈路帶發起方角色，供消費端防角色反轉。
      'senderRole':
          (senderRole == null || senderRole.isEmpty) ? 'family' : senderRole,
      // ★ 護欄 G22（第二十二輪改寫）：緊急通話的 Socket 與 FCM 兩條路都必須帶
      //   issuedAt/expiresAt。舊規則「緊急刻意不帶」已被推翻——不帶會讓這筆
      //   pendingAcceptedCall 永不過期，冷啟動反覆載入早已結束的通話（第二十一輪白屏）。
      //   後端未帶時退化為空字串，消費端視同「無有效期資訊」，行為與舊版相同。
      'issuedAt': issuedAt ?? '',
      'expiresAt': expiresAt ?? '',
      // 本機新鮮度（與有效期無關），第二十一輪的自癒路徑依賴它。
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pendingAcceptedCall', jsonEncode(pendingCallData));
    } catch (e) {
      debugPrint('⚠️ [Emergency$source] 寫入 pendingAcceptedCall 失敗: $e');
    }
    // 護欄：Map<String, dynamic> → Map<String, String?> 後才可指派給 ValueNotifier。
    pendingAcceptedCall.value =
        pendingCallData.map((key, value) => MapEntry(key, value?.toString()));
  }

  void _showIncomingCallDialog(String roomId, String senderId,
      {String? callId,
      bool isEmergency = false,
      String? callerName,
      String? senderRole}) {
    // ★ 2026-08-12 第二十三輪：長輩端緊急通話的**最終防線**。
    //   不管是哪條通路走到這裡，只要「本機是長輩端 ＋ 這是緊急通話」，
    //   就一律轉為無條件自動接聽，**永遠不顯示接聽／拒絕按鈕**。
    //   放在最前面（早於 _activeCallDialogContext 檢查）是刻意的：
    //   即使畫面上已經有一般來電的 dialog，緊急通話仍要壓過去。
    if (isEmergency && _deriveMyRoleFromCall(senderRole, appRole) == 'elder') {
      unawaited(_autoAcceptEmergencyCall(
        roomId: roomId,
        senderId: senderId,
        callId: callId,
        senderRole: senderRole,
        source: '-Dialog',
      ));
      return;
    }

    if (_activeCallDialogContext != null) {
      debugPrint("⚠️ [Main] Dialog already showing, skipping...");
      return;
    }

    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint(
          "⚠️ [Main] Cannot show dialog: navigatorKey.currentContext is NULL!");
      return;
    }

    final String callerLabel = callerName?.toString().trim().isNotEmpty == true
        ? callerName!.toString().trim()
        : ((appRole == 'elder') ? '您的家人' : '長輩');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) {
        _activeCallDialogContext = c;
        return AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isEmergency ? Colors.red.shade100 : Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isEmergency ? Icons.warning : Icons.phone_callback,
                  color: isEmergency ? Colors.red : Colors.green,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Text(isEmergency ? '🚨 緊急來電' : '📞 來電通知'),
            ],
          ),
          content: Text(
            '$callerLabel 正在呼叫您！',
            style: const TextStyle(fontSize: 18),
          ),
          backgroundColor: isEmergency ? Colors.red.shade50 : Colors.green.shade50,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          actions: [
            ElevatedButton.icon(
              onPressed: () {
                _activeCallDialogContext = null;
                Navigator.pop(c);
                sig.Signaling().sendCallBusy(senderId, callId: callId, room: roomId);
              },
              icon: const Icon(Icons.call_end),
              label: const Text('拒接', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                _activeCallDialogContext = null;
                Navigator.pop(c);
                _navigateToVideoCall(roomId, senderId, callId: callId);
              },
              icon: const Icon(Icons.videocam),
              label: const Text('接聽', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        );
      },
    ).then((_) {
      // ★ 2026-08-02 第十四輪：dialog 以任何方式關閉都要重置 guard，
      //   否則 _activeCallDialogContext 永久卡住 → 之後所有來電 dialog 都被擋。
      _activeCallDialogContext = null;
    });
  }

  void _setupCallKitListener() {
    // !!!!除非要更新視訊通話邏輯，否則禁止更動!!!!
    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) {
      if (event == null) return;

      final extra = event.body['extra'];
      if (extra == null || extra is! Map) return;
      final roomId = extra['roomId'] as String?;
      final senderId = extra['senderId'] as String?;
      final callId = extra['callId'] as String?;
      final issuedAt = extra['issuedAt']?.toString();
      final expiresAt = extra['expiresAt']?.toString();
      final senderRole = extra['senderRole']?.toString();
      final isVideoCall = extra['isVideoCall']?.toString(); // ★ Fix E

      if (roomId == null || senderId == null) return;

      if (event.event == Event.actionCallAccept) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final exp = int.tryParse(expiresAt ?? '');
        final issued = int.tryParse(issuedAt ?? '');
        final isExpired = (exp != null && now > exp) || (issued != null && (now - issued) > kCallValidityMs);
        if (isExpired) {
          debugPrint("⏰ [CallKit] Ignore expired accept (callId=$callId)");
          FlutterCallkitIncoming.endAllCalls();
          return;
        }
        // ★ 2026-08-26：接聽當下立刻蓋鎖屏，不等通話畫面 initState。
        //   舊行為：這裡只寫 pendingAcceptedCall，畫面真正蓋過鎖定畫面要等
        //   VideoCallScreen／ElderScreen 的 initState 呼叫 showOverLockScreen——
        //   也就是要等本 listener 導航、route 掛載完成之後，中間約有 2 秒空窗；
        //   緊急通話則是原生 onCreate/onNewIntent 早就蓋好（見 G49），兩者體驗
        //   不對稱。改成在這裡（Dart 能動手的最早時機）先蓋一次，通話畫面
        //   initState 那次呼叫**仍保留、不要刪**——`showOverLockScreen` 只是
        //   重設 window flag，冪等、呼叫兩次無副作用，且仍需覆蓋不經過本
        //   handler 的路徑（例如冷啟動 §4.8 兜底鏈）。
        //   位置：放在過期檢查「之後」——過期的接聽不該蓋鎖屏；放在
        //   pendingAcceptedCall 賦值「之前」——用不 await 的 `.catchError()`
        //   （`invokeMethod` 的 `PlatformException` 是非同步丟出的，同步例外
        //   本來就到不了這裡，因此原生端出錯絕不會擋住下面的賦值：漏接聽比
        //   鎖屏晚兩秒嚴重得多）。
        //   🚫 呼叫的是 `showOverLockScreen`，不是 `bringToFront`：本
        //   listener 長輩／家屬雙端共用，而「強制開啟」只准長輩端（CLAUDE.md
        //   3.1 第 13 條）。這裡只是讓使用者剛剛自己按下的接聽動作所開啟的
        //   畫面能蓋過鎖定畫面，不主動解鎖、也不啟動 App，不算強制開啟——
        //   不要加 `bringToFront` 或 `AndroidIntent` 進來。
        const MethodChannel('com.example.app/bring_to_front')
            .invokeMethod('showOverLockScreen')
            .catchError((e) {
          debugPrint('⚠️ [CallKit] showOverLockScreen 失敗: $e');
          return null;
        });
        if (callId != null && callId.isNotEmpty) {
          sig.Signaling().lastProcessedCallId = callId;
          sig.Signaling().lastProcessedCallTime = DateTime.now().millisecondsSinceEpoch;
        }
        // 優先讓首頁 listener 消費（可關閉既有 in-app 來電彈窗），
        // 若短時間內未被消費，再由全域導航兜底。
        pendingAcceptedCall.value = <String, String?>{
          'roomId': roomId,
          'senderId': senderId,
          'callId': callId,
          'issuedAt': issuedAt,
          'expiresAt': expiresAt,
          // ★ 2026-07-22 第八輪 Fix 3：帶上發起方角色，供消費端防角色反轉驗證。
          'senderRole': senderRole,
          'isVideoCall': isVideoCall, // ★ Fix E
        };
        // ★ 2026-07-19：全域兜底導航。
        //   冷啟動期間 SplashScreen 是 pendingAcceptedCall 的優先導航擁有者，
        //   全域兜底必須讓位，避免把 VideoCallScreen push 到 Splash 上後又被
        //   Splash 的 pushReplacement 洗掉（家屬接聽後只進主畫面的 bug）。
        //   但 Splash 有多條路徑「不消費 pending」（如 API 失敗回退），若用一次性
        //   350ms 兜底並在 splashActive 期間跳過，會造成永久漏接。因此改為輪詢：
        //   等 splashActive 結束（Splash 已完成導航）後再兜底；若 pending 已被
        //   Splash 消費（value==null）則自動跳過。
        _scheduleAcceptedCallFallback(roomId, senderId, callId);
      } else if (event.event == Event.actionCallDecline) {
        // Broadcast the decline event so that active dialogs in the app can close themselves
        callKitDeclineStream.add(roomId);

        // 僅關閉來電彈窗，不清空整個導航堆疊
        if (_activeCallDialogContext != null) {
          if (Navigator.canPop(_activeCallDialogContext!)) {
            Navigator.pop(_activeCallDialogContext!);
          }
          _activeCallDialogContext = null;
        }
        // ★ 2026-07-18：拒接統一走 _sendDeclineEvent（先 socket 後 HTTP 保底），
        //   確保背景/被殺死狀態下 Socket 未連線時仍能通知發起方停止等待。
        _sendDeclineEvent(roomId, senderId, callId: callId);
      } else if (event.event == Event.actionCallTimeout) {
        // ★ 2026-07-18：CallKit 響鈴逾時（無人接聽）等同拒接，需通知發起方停止等待，
        //   否則發起方只能苦等自身逾時。同樣走 _sendDeclineEvent 的 socket→HTTP 保底。
        debugPrint("⏰ [CallKit] 響鈴逾時未接聽 → 通知發起方 (callId=$callId)");
        if (_activeCallDialogContext != null) {
          if (Navigator.canPop(_activeCallDialogContext!)) {
            Navigator.pop(_activeCallDialogContext!);
          }
          _activeCallDialogContext = null;
        }
        _sendDeclineEvent(roomId, senderId, callId: callId);
      }
    });
  }

  /// ★ 2026-07-19：接聽後全域兜底導航（輪詢版）。
  /// 先讓 SplashScreen 有機會消費 pendingAcceptedCall（冷啟動優先擁有者）；
  /// 每 200ms 檢查一次，最多約 8 秒：
  ///   - pending 已被消費（value==null）→ 代表某頁面已接手，停止兜底；
  ///   - splashActive 已結束且 pending 仍在 → 由本兜底導向通話畫面；
  ///   - 逾時仍未消費 → 最後一次強制導航，避免漏接。
  void _scheduleAcceptedCallFallback(String roomId, String senderId, String? callId) {
    const int maxTicks = 40; // 40 × 200ms = 8s
    int tick = 0;
    Timer.periodic(const Duration(milliseconds: 200), (timer) {
      tick++;
      // 已被其他頁面（Splash / 首頁 listener）消費
      if (pendingAcceptedCall.value == null) {
        timer.cancel();
        return;
      }
      // Splash 仍在導航中，讓位等待
      if (splashActive && tick < maxTicks) {
        return;
      }
      // Splash 已結束或逾時 → 由全域兜底接手
      timer.cancel();
      if (pendingAcceptedCall.value != null) {
        _navigateToVideoCall(roomId, senderId, callId: callId);
      }
    });
  }

  void _sendDeclineEvent(String roomId, String senderId, {String? callId}) async {
    debugPrint(
        "❌ Call Declined from CallKit, sending call-busy to $senderId (callId: $callId)...");

    final prefs = await SharedPreferences.getInstance();
    // ★ 2026-07-22 修復：拒接時同步清除所有相關狀態，避免下次冷啟動誤導向這通已被拒絕的通話。
    await prefs.remove('pendingAcceptedCall');
    await prefs.remove('pendingRingCallData');
    await prefs.remove('pendingRingCall');
    pendingAcceptedCall.value = null;

    // ★ 2026-07-22 修復（第八輪 Issue 1）：原本 Socket 和 HTTP 兩路都發，
    //   後端的 on_call_busy 和 api_decline_call 各自廣播 call-busy + cancel-call，
    //   導致家屬端收到三重拒絕訊息。改為 if-else：Socket 在線時只走 Socket，
    //   離線時才走 HTTP。catch 區塊作為 Socket 失敗時的 HTTP 備援。
    try {
      if (sig.Signaling().socket?.connected == true) {
        sig.Signaling().sendCallBusy(senderId, callId: callId, room: roomId);
      } else {
        debugPrint('🔌 [Decline] Socket 離線，改用 HTTP declineCall');
        await ApiService.declineCall(
          roomId: roomId,
          senderId: senderId,
          callId: callId,
        );
      }
    } catch (e) {
      debugPrint('⚠️ [Decline] 主通路失敗 ($e)，走 HTTP 備援');
      await ApiService.declineCall(
        roomId: roomId,
        senderId: senderId,
        callId: callId,
      );
    }
  }

  void _navigateToVideoCall(String roomId, String senderId, {String? callId, bool isEmergency = false}) async {
    // !!!!除非要更新視訊通話邏輯，否則禁止更動!!!!
    // ★ Bug 16 解決方案：如果身分是長輩，絕對不可啟動 VideoCallScreen (那是給家屬用的)。
    // 我們僅儲存 pendingAcceptedCall，讓長輩主畫面 (ElderScreen) 啟動後去接手。
    final prefs = await SharedPreferences.getInstance();
    final String effectiveRole = appRole ?? prefs.getString('user_role') ?? prefs.getString('saved_role') ?? '';
    if (effectiveRole == 'elder') {
      // ★ issue 2/5：此通話可能已由 splash/ElderScreen 透過 SharedPreferences
      //   預先載入並消費過（lastProcessedCallId 已記錄）。此時若再次寫入
      //   pendingAcceptedCall，會在通話結束、回到 ElderHomeScreen 後被誤判為
      //   「新來電」而重新嘗試接聽一通早已結束的通話。
      if (callId != null &&
          callId.isNotEmpty &&
          callId == sig.Signaling().lastProcessedCallId) {
        debugPrint("ℹ️ [Main] 略過已處理過的來電 (callId=$callId)，不重複寫入 pendingAcceptedCall");
        return;
      }
      debugPrint(
          "📱 Elder role detected ($effectiveRole), skipping VideoCallScreen push and caching accepted call.");
      pendingAcceptedCall.value = <String, String?>{
        'roomId': roomId,
        'senderId': senderId,
        'callId': callId,
        'isEmergency': isEmergency.toString(),
      };

      // ★ 喚醒長輩 APP 並帶到最前台，這會觸發 ElderScreen 的 _checkPendingAcceptedCall
      try {
        const platform = MethodChannel('com.example.app/bring_to_front');
        platform.invokeMethod('bringToFront');
      } catch (e) {
        debugPrint("Failed to bring elder app to front: $e");
      }
      return;
    }

    if (navigatorKey.currentState != null && isAppReady) {
      // 只關閉來電彈窗，避免 popUntil 觸發 Splash 重新導向
      if (_activeCallDialogContext != null) {
        if (Navigator.canPop(_activeCallDialogContext!)) {
          Navigator.pop(_activeCallDialogContext!);
        }
        _activeCallDialogContext = null;
      }

      // ★ Fix E：優先採用 pendingAcceptedCall 攜帶的 isVideoCall（CallKit/FCM
      //   冷啟動路徑寫入），callId 不吻合或未攜帶該欄位時，退回 Signaling
      //   同一 isolate 內的快取（前景 Socket 直接接聽路徑，見 isVideoCallFor）。
      // ★ 2026-08-02 第十四輪修正：改用 parseIsVideoCall 正規化，相容後端
      //   str(bool) 產生的 "True"/"False"（Python 首字大寫）。
      final pendingMap = pendingAcceptedCall.value;
      final bool resolvedIsVideoCall = (pendingMap != null &&
              pendingMap['callId'] == callId &&
              pendingMap['isVideoCall'] != null)
          ? parseIsVideoCall(pendingMap['isVideoCall'])
          : sig.Signaling().isVideoCallFor(callId);

      Future.microtask(() {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (context) => VideoCallScreen(
              roomId: roomId,
              targetSocketId: senderId,
              isIncomingCall: true,
              callId: callId,
              isVideoCall: resolvedIsVideoCall,
            ),
          ),
        );
      });
    } else {
      // App is cold booting or navigator not ready. Save it for Dashboard/Elder screen to pick up.
      pendingAcceptedCall.value = {'roomId': roomId, 'senderId': senderId, 'callId': callId, 'isEmergency': isEmergency.toString()};
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey, // ★ 關鍵：必須綁定 navigatorKey，否則無法顯示彈窗或導航
      title: 'UBan',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(context),
      // ★★★ 還原為原始入口：SplashScreen ★★★
      home: const SplashScreen(),
      /*
      onGenerateRoute: (settings) {
        if (settings.name == '/family_home') {
          final args = settings.arguments as Map<String, dynamic>? ?? {};
          return MaterialPageRoute(
            builder: (context) => FamilyMainScreen(
              userId: args['user_id'] ?? 0,
              userName: args['user_name'] ?? '使用者',
            ),
          );
        }
        return null; // Let 'routes' handle it
      },
      routes: {
        '/login': (context) => const LoginScreen(),
        '/identification': (context) => const IdentificationScreen(),
      },
      */
    );
  }
}

class GoldenKeyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFF7043)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width * 0.5, size.height * 0.35);

    canvas.drawCircle(center, size.width * 0.22, paint);

    canvas.drawLine(
      center + Offset(0, size.width * 0.22),
      Offset(size.width * 0.5, size.height * 0.9),
      paint,
    );

    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.7),
      Offset(size.width * 0.75, size.height * 0.7),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.85),
      Offset(size.width * 0.7, size.height * 0.85),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ConnectionLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF59B294).withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final p0 = Offset(size.width * 0.32, size.height * 0.55);
    final p1 = Offset(size.width * 0.5, size.height * 0.15);
    final p2 = Offset(size.width * 0.68, size.height * 0.55);

    for (double t = 0; t <= 1.0; t += 0.05) {
      final x = (1 - t) * (1 - t) * p0.dx + 2 * (1 - t) * t * p1.dx + t * t * p2.dx;
      final y = (1 - t) * (1 - t) * p0.dy + 2 * (1 - t) * t * p1.dy + t * t * p2.dy;
      canvas.drawCircle(Offset(x, y), 2.5, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CozyErrorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(size.width * 0.3, size.height * 0.3),
      Offset(size.width * 0.7, size.height * 0.7),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.7, size.height * 0.3),
      Offset(size.width * 0.3, size.height * 0.7),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
