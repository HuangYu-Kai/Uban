import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart' show WidgetsFlutterBinding, debugPrint;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_intent_plus/android_intent.dart';

import '../globals.dart';
import 'api_service.dart';
import 'local_call_notification.dart';
import 'cctv_alert_notification.dart';
import 'local_reminder_notification.dart';

/// 檢查當前平台是否支援 CallKit
bool supportsCallKit() {
  return !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
}

/// 判斷來電 payload 是否已過期
bool isExpiredCallPayload(Map<String, dynamic> data) {
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
/// `user_role ?? saved_role`，而這兩個鍵由不同畫面寫入且語意不一致：
///   - `login_screen` 寫 `user_role='family'`
///   - `role_selection_screen` 只寫 `saved_role`（從不寫 `user_role`）
/// 通話只可能是 elder↔family，所以 payload 的 `role` 一旦有值就是權威：
/// 對方是 family → 我方必為 elder，反之亦然。prefs 僅作為 payload 缺角色時的退路。
String? deriveMyRoleFromCall(dynamic senderRoleRaw, String? localRole) {
  final String senderRole = (senderRoleRaw ?? '').toString().trim();
  if (senderRole == 'family') return 'elder';
  if (senderRole == 'elder') return 'family';
  return localRole;
}

/// ★ 第四十輪（item 4）：取消來電時清除待處理通話 prefs 的共用邏輯。
Future<void> clearPendingCallPrefsOnCancel() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pendingAcceptedCall');
    await prefs.remove('pendingRingCallData');
    await prefs.remove('pendingRingCall');
  } catch (_) {}
}

/// ★ 在背景/鎖屏顯示全螢幕 CallKit 來電（issue 2 & 3 的核心修復）。
///   接聽/拒絕事件由 [_MyAppState._setupCallKitListener] 透過 extra 內的 roomId/senderId/callId 接手。
Future<void> showFullScreenCallkit(Map<String, dynamic> data) async {
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
      'senderRole': senderRole,
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
      isShowFullLockedScreen: true,
    ),
    ios: const IOSParams(
      handleType: 'generic',
      supportsVideo: true,
    ),
  );

  try {
    await FlutterCallkitIncoming.showCallkitIncoming(params);
    debugPrint('📲 [CallKit] showCallkitIncoming 已呼叫 (callId=$callId)');
  } catch (e) {
    debugPrint('⚠️ [CallKit] showCallkitIncoming 失敗（將依賴原生備援通知）: $e');
  }

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
        await LocalCallNotification.cancel();
        final bool declineOk = await ApiService.declineCall(
          roomId: roomId,
          senderId: senderId,
          callId: callId,
        );
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('pendingAcceptedCall');
          await prefs.remove('pendingRingCallData');
          await prefs.remove('pendingRingCall');
        } catch (_) {}
        if (e.event == Event.actionCallDecline) {
          try {
            await LocalCallNotification.showDeclineFeedback(success: declineOk);
          } catch (_) {}
        }
        await bgSub?.cancel();
        releaseBgHold('使用者拒接／響鈴逾時');
      } else if (e.event == Event.actionCallAccept) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('pendingAcceptedCall', jsonEncode({
            'roomId': roomId,
            'senderId': senderId,
            'callId': callId,
            'issuedAt': issuedAt,
            'expiresAt': expiresAt,
            'senderRole': senderRole,
            'isVideoCall': isVideoCall,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          }));
          debugPrint('✅ [BG-CallKit] accept → 已寫入 pendingAcceptedCall 至 prefs (call=$callId)');
          await prefs.setString('pendingRingCallData', jsonEncode({
            'roomId': roomId,
            'senderId': senderId,
            'callId': callId,
            'issuedAt': issuedAt,
            'expiresAt': expiresAt,
            'callerName': callerName,
            'senderRole': senderRole,
            'isVideoCall': isVideoCall,
            'isAccepted': true,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          }));
        } catch (err) {
          debugPrint('⚠️ [BG-CallKit] 寫入 pendingAcceptedCall 失敗: $err');
        }
        await LocalCallNotification.cancel();
        await bgSub?.cancel();
        releaseBgHold('使用者接聽');
      } else if (e.event == Event.actionCallEnded) {
        await bgSub?.cancel();
        releaseBgHold('CallKit 通話已結束');
      }
    });
  } else {
    releaseBgHold('缺 roomId/senderId，沒有可等待的事件');
  }

  if (!isEmergency) {
    bool callkitAlive = false;
    for (int i = 0; i < 8; i++) {
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
      for (int i = 0; i < 6; i++) {
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

/// Firebase 背景推播訊息處理函式 (需具備 @pragma('vm:entry-point'))
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
      debugPrint('🔥 [BG] Firebase initialized in background handler');
    } else {
      debugPrint('🔥 [BG] Using existing Firebase app in background handler');
    }
  } catch (e, stackTrace) {
    debugPrint('❌ [BG] Firebase initialization failed: $e');
    debugPrint('📍 Stack trace: $stackTrace');
  }

  try {
    debugPrint("📩 Background message received: ${message.data}");

    var type = message.data['type'];
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

    if (type == 'cctv-alert') {
      debugPrint('🚨 [BG] 收到 CCTV 警報，顯示高優先級通知');
      try {
        await CctvAlertNotification.show(message.data);
      } catch (e) {
        debugPrint('⚠️ [BG] 跌倒警報通知失敗: $e');
      }
      return;
    }

    if (type == 'reminder') {
      debugPrint('⏰ [BG] 收到排程提醒 FCM，顯示本機高優先級通知與彈窗');
      try {
        final int reminderId = int.tryParse(message.data['id']?.toString() ?? '') ?? 0;
        final String title = message.data['title']?.toString() ?? '排程提醒';
        final String timeStr = message.data['time_str']?.toString() ?? '';
        final String? note = message.data['note']?.toString();
        final String? category = message.data['category']?.toString();
        await LocalReminderNotification.showReminderNotification(
          id: reminderId,
          title: title,
          timeStr: timeStr,
          note: note,
          category: category,
        );
      } catch (e) {
        debugPrint('⚠️ [BG] 排程提醒通知失敗: $e');
      }
      return;
    }

    if (type != 'call-request' && type != 'emergency-call' && type != 'cancel-call' && type != 'force-logout') {
      debugPrint('⚠️ [BG] Ignoring message of type: $type');
      return;
    }

    if ((type == 'call-request' || type == 'emergency-call') &&
        isExpiredCallPayload(message.data)) {
      debugPrint('⏰ [BG] Ignoring expired call payload: ${message.data['callId']}');
      return;
    }

    if (type == 'cancel-call') {
      debugPrint('🔕 [BG] Remote canceled call, dismissing CallKit...');
      try {
        await FlutterCallkitIncoming.endAllCalls();
      } catch (e) {
        debugPrint('⚠️ [BG] endAllCalls 失敗（不影響後續）: $e');
      }
      await LocalCallNotification.cancel();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('pendingAcceptedCall');
        await prefs.remove('pendingRingCallData');
        await prefs.remove('pendingRingCall');
      } catch (_) {}
      return;
    }

    if (type == 'force-logout') {
      final reason = (message.data['reason'] ?? '').toString();
      debugPrint('🚪 [BG] 收到 force-logout，清除背景 session 鍵（reason=$reason）');
      try {
        final bgPrefs = await SharedPreferences.getInstance();
        const keysToRemove = [
          'caregiver_id', 'caregiver_name', 'user_role', 'saved_role',
          'saved_id', 'saved_device_name', 'saved_is_cctv', 'elder_room_id',
          'access_token',
          'pendingAcceptedCall', 'pendingRingCallData', 'pendingRingCall',
        ];
        for (final key in keysToRemove) { await bgPrefs.remove(key); }
        if (reason == 'elder-unbound') {
          const quickLoginKeys = [
            'last_elder_id', 'last_elder_name', 'last_elder_room_id', 'last_elder_device_role',
          ];
          for (final key in quickLoginKeys) { await bgPrefs.remove(key); }
        }
        final deviceRoleKeys = bgPrefs.getKeys().where((k) => k.startsWith('device_role_')).toList();
        for (final key in deviceRoleKeys) { await bgPrefs.remove(key); }
        debugPrint('🚪 [BG] force-logout 清除完成');
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

      final localRole = prefs.getString('user_role') ?? prefs.getString('saved_role');
      final role = deriveMyRoleFromCall(message.data['role'], localRole);
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
          'senderRole': (message.data['role'] ?? 'family').toString(),
          'issuedAt': (message.data['issuedAt'] ?? '').toString(),
          'expiresAt': (message.data['expiresAt'] ?? '').toString(),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        await prefs.setString('pendingAcceptedCall', pendingCall);

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
           'isVideoCall': (message.data['isVideoCall'] ?? 'true').toString(),
           'isAccepted': false,
           'timestamp': DateTime.now().millisecondsSinceEpoch,
         }));
       } catch (e) {
         debugPrint('⚠️ [BG] 寫入 pendingRingCallData 失敗: $e');
       }
       await showFullScreenCallkit(message.data);
       return;
     }

      if (role != 'elder' && type == 'call-request') {
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
            'isVideoCall': (message.data['isVideoCall'] ?? 'true').toString(),
            'isAccepted': false,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          }));
        } catch (e) {
          debugPrint('⚠️ [BG] 寫入 pendingRingCallData 失敗: $e');
        }
        await showFullScreenCallkit(message.data);
        return;
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [BG] Error in SharedPreferences processing: $e');
      debugPrint('📍 Stack trace: $stackTrace');
    }

    await showFullScreenCallkit(message.data);
  } catch (e, stackTrace) {
    debugPrint('❌ [BG] Unexpected error in firebaseMessagingBackgroundHandler: $e');
    debugPrint('📍 Stack trace: $stackTrace');
    try {
      await showFullScreenCallkit(message.data);
    } catch (e2) {
      debugPrint('❌ [BG] Failed to show CallKit notification: $e2');
    }
  }
}
