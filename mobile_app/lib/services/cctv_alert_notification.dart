import 'dart:ui' show Color, DartPluginRegistrant;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// ★ 2026-08-05 第十七輪：YOLO 跌倒警報的高優先級通知。
///
/// 結構完全比照 `local_call_notification.dart`（`_ensureInit()` + 高優先級 channel +
/// `show()` + `cancel()`），但用途不同：這裡沒有接聽/拒接動作，純粹是「強制點亮螢幕 +
/// 提醒家屬立即查看監視畫面」的一次性警報通知，因此**不加任何 action 按鈕**——
/// `local_call_notification.dart` 的動作按鈕曾因為跑在未初始化的裸 isolate 而整條
/// 失效（拒接鍵完全沒作用），修了一整輪才修好；這裡沒有按鈕邏輯要處理，不重蹈覆轍。
///
/// channel（`uban_cctv_alert`）與通知 id（`8811`）都與來電備援
/// （`uban_incoming_call_backup` / `8801`，見 `local_call_notification.dart`）分開，
/// 不可共用——來電備援 channel 是 CallKit 失敗時唯一的來電管道，共用會互相干擾。
class CctvAlertNotification {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// 固定通知 ID：同一時間只會有一則跌倒警報通知，用固定 ID 便於 cancel；
  /// 與來電備援的 8801 錯開，避免互相覆蓋。
  static const int alertNotificationId = 8811;
  static const String _channelId = 'uban_cctv_alert';
  static const String _channelName = '跌倒警報';
  static const String _channelDesc = 'YOLO 監視機偵測到疑似跌倒時的高優先級提醒';

  static Future<void> _ensureInit() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);
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

  /// 顯示跌倒警報通知。**會直接從 FCM 背景 isolate 呼叫**（見 C-6：
  /// `CctvAlertNotification.show(message.data)`），故比照
  /// `local_call_notification.dart::notificationBackgroundTapHandler` 的做法，
  /// 呼叫外部套件前先確保 binding 初始化，避免 MissingPluginException。
  ///
  /// [data] 直接吃 FCM 的 `message.data`（`Map<String, dynamic>`）。後端
  /// （`yolo_alert_dispatcher.py`）目前只送 `type/elderId/deviceId/alertType/
  /// alertId/confidence/timestamp`，沒有長輩名字欄位，故退回 `elderId`，
  /// 兩者皆缺時再退回「長輩」——不為此去改後端。
  static Future<void> show(Map<String, dynamic> data) async {
    if (kIsWeb) return;
    try {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();
    } catch (e) {
      debugPrint('⚠️ [CctvAlertNotif] 背景 isolate 初始化失敗: $e');
    }
    try {
      await _ensureInit();
      final String elderName =
          (data['elderName'] ?? data['elderId'] ?? '長輩').toString();
      final String body =
          '${elderName.isEmpty ? '長輩' : elderName} 可能跌倒，請立即查看監視畫面';
      final androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true, // 強制點亮螢幕的機制，需 USE_FULL_SCREEN_INTENT 權限
        ongoing: false,
        playSound: true,
        enableVibration: true,
        color: const Color(0xFFB91C1C),
      );
      await _plugin.show(
        alertNotificationId,
        '🚨 偵測到跌倒',
        body,
        NotificationDetails(android: androidDetails),
      );
      debugPrint('🔔 [CctvAlertNotif] 已發送跌倒警報通知 (alertId=${data['alertId']})');
    } catch (e) {
      debugPrint('⚠️ [CctvAlertNotif] 發送跌倒警報通知失敗: $e');
    }
  }

  /// 取消跌倒警報通知。
  static Future<void> cancel() async {
    if (kIsWeb) return;
    try {
      await _ensureInit();
      await _plugin.cancel(alertNotificationId);
    } catch (e) {
      debugPrint('⚠️ [CctvAlertNotif] 取消跌倒警報通知失敗: $e');
    }
  }
}
