import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ★ 2026-07-22 第十一輪：原生高優先級通知備援。
///
/// 背景：`flutter_callkit_incoming` 在 MIUI 被殺死的背景 isolate 中，原生 CallKit
/// 通知會**靜默建立失敗**（`showCallkitIncoming` 射後不理，Dart 端無從得知），
/// 導致 FCM 已送達卻沒有任何來電畫面。這裡用標準 Android notification builder
/// （`flutter_local_notifications`，成熟穩定、不經 CallKit 的 RemoteViews 自訂通知）
/// 發一則 heads-up 高優先級來電通知作為備援，與 CallKit 平行、共用 callId。
///
/// 兩個 isolate（主 + 背景 FCM handler）都會用到，故做成頂層函式 + 惰性初始化。
class LocalCallNotification {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// 固定通知 ID：同一時間只會有一通來電，用固定 ID 便於 cancel。
  static const int callNotificationId = 8801;
  static const String _channelId = 'uban_incoming_call_backup';
  static const String _channelName = '來電通知（備援）';
  static const String _channelDesc = 'App 被系統關閉時，確保仍能收到視訊來電通知';

  static Future<void> _ensureInit() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onTap,
      onDidReceiveBackgroundNotificationResponse:
          notificationBackgroundTapHandler,
    );
    // 建立高優先級 channel（Android 8+）
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );
    _initialized = true;
  }

  /// 顯示來電備援通知。與 CallKit 平行呼叫；MIUI 被殺死時這條較可靠。
  static Future<void> show(Map<String, dynamic> data) async {
    if (kIsWeb) return;
    try {
      await _ensureInit();
      final callerName =
          (data['callerName'] ?? data['senderName'] ?? '有人來電').toString();
      final payload = jsonEncode({
        'roomId': (data['roomId'] ?? '').toString(),
        'senderId': (data['senderId'] ?? '').toString(),
        'callId': (data['callId'] ?? '').toString(),
        'issuedAt': (data['issuedAt'] ?? '').toString(),
        'expiresAt': (data['expiresAt'] ?? '').toString(),
        'senderRole': (data['role'] ?? '').toString(),
      });
      final androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.call,
        fullScreenIntent: true, // 需 USE_FULL_SCREEN_INTENT 權限（Android 14+ 引導開啟）
        ongoing: true,
        autoCancel: false,
        visibility: NotificationVisibility.public,
        ticker: '視訊來電',
      );
      await _plugin.show(
        callNotificationId,
        '📞 視訊來電',
        '$callerName 正在呼叫您，點擊接聽',
        NotificationDetails(android: androidDetails),
        payload: payload,
      );
      debugPrint('🔔 [LocalNotif] 已發送來電備援通知 (callId=${data['callId']})');
    } catch (e) {
      debugPrint('⚠️ [LocalNotif] 發送來電備援通知失敗: $e');
    }
  }

  /// 取消來電備援通知（cancel-call / 接聽 / 拒接時呼叫）。
  static Future<void> cancel() async {
    if (kIsWeb) return;
    try {
      await _ensureInit();
      await _plugin.cancel(callNotificationId);
    } catch (e) {
      debugPrint('⚠️ [LocalNotif] 取消來電備援通知失敗: $e');
    }
  }

  /// 前景點擊：把來電資料寫入 pendingAcceptedCall prefs，交由 main() / 頁面 listener 接手導航。
  static void _onTap(NotificationResponse response) {
    _persistTapAsAccepted(response.payload);
  }
}

/// 背景 isolate 點擊 handler（必須是頂層 + vm:entry-point）。
@pragma('vm:entry-point')
void notificationBackgroundTapHandler(NotificationResponse response) {
  _persistTapAsAccepted(response.payload);
}

/// 點擊備援通知 = 接聽：寫入 pendingAcceptedCall，冷啟動時 main() 兜底導向 ElderScreen。
Future<void> _persistTapAsAccepted(String? payload) async {
  if (payload == null || payload.isEmpty) return;
  try {
    final Map<String, dynamic> data = jsonDecode(payload);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'pendingAcceptedCall',
      jsonEncode({
        'roomId': (data['roomId'] ?? '').toString(),
        'senderId': (data['senderId'] ?? '').toString(),
        'callId': (data['callId'] ?? '').toString(),
        'issuedAt': (data['issuedAt'] ?? '').toString(),
        'expiresAt': (data['expiresAt'] ?? '').toString(),
        'senderRole': (data['senderRole'] ?? '').toString(),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }),
    );
    debugPrint('✅ [LocalNotif] 點擊接聽 → 已寫入 pendingAcceptedCall (callId=${data['callId']})');
  } catch (e) {
    debugPrint('⚠️ [LocalNotif] 處理通知點擊失敗: $e');
  }
}
