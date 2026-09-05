import 'dart:convert';
import 'dart:ui' show DartPluginRegistrant;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'elder_reminder_manager.dart';

/// ⏰ 長輩端排程提醒的本機高優先級通知管理器
class LocalReminderNotification {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const String channelId = 'uban_schedule_reminder';
  static const String channelName = '排程提醒';
  static const String channelDesc = '子女為長輩設定的健康用藥與生活排程提醒';

  static Future<void> _ensureInit() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        debugPrint('⏰ [LocalReminderNotification] Notification tapped: ${details.payload}');
        if (details.payload != null && details.payload!.isNotEmpty) {
          try {
            final data = jsonDecode(details.payload!);
            if (data is Map<String, dynamic>) {
              ElderReminderManager.instance.handleIncomingReminder(data, force: true);
            }
          } catch (_) {}
        }
      },
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      const channel = AndroidNotificationChannel(
        channelId,
        channelName,
        description: channelDesc,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );
      await androidPlugin.createNotificationChannel(channel);
    }
    _initialized = true;
  }

  /// 顯示排程提醒通知（支援背景 FCM Isolate 與前景安全調用）
  static Future<void> showReminderNotification({
    required int id,
    required String title,
    required String timeStr,
    String? note,
    String? category,
  }) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();
      await _ensureInit();

      String categoryIcon = '⏰';
      switch (category) {
        case 'medication':
          categoryIcon = '💊';
          break;
        case 'water':
          categoryIcon = '💧';
          break;
        case 'exercise':
          categoryIcon = '🚶';
          break;
        case 'hospital':
          categoryIcon = '🏥';
          break;
        default:
          categoryIcon = '⏰';
      }

      final displayTitle = '$categoryIcon 排程提醒：$title';
      final bodyText = (note != null && note.isNotEmpty)
          ? '$timeStr - $note'
          : '$timeStr 提醒事項，記得完成喔！';

      final androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDesc,
        importance: Importance.max,
        priority: Priority.high,
        ticker: displayTitle,
        styleInformation: BigTextStyleInformation(
          bodyText,
          contentTitle: displayTitle,
          summaryText: 'Uban 守護排程',
        ),
        fullScreenIntent: true,
        category: AndroidNotificationCategory.reminder,
        playSound: true,
        enableVibration: true,
      );

      final platformDetails = NotificationDetails(android: androidDetails);
      final payloadData = jsonEncode({
        'id': id,
        'title': title,
        'time_str': timeStr,
        'note': note ?? '',
        'category': category ?? 'custom',
      });
      await _plugin.show(
        id,
        displayTitle,
        bodyText,
        platformDetails,
        payload: payloadData,
      );
      debugPrint('⏰ [LocalReminderNotification] 通知發送成功: ID=$id, $displayTitle');
    } catch (e) {
      debugPrint('⚠️ [LocalReminderNotification] 顯示通知失敗: $e');
    }
  }

  /// 取消指定提醒通知
  static Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id);
    } catch (_) {}
  }

  /// 冷啟動時若點擊通知啟動 App，讀取並清除點擊的通知 payload
  static Future<Map<String, dynamic>?> consumeLaunchPayload() async {
    try {
      await _ensureInit();
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details != null && details.didNotificationLaunchApp) {
        final payload = details.notificationResponse?.payload;
        if (payload != null && payload.isNotEmpty) {
          final data = jsonDecode(payload);
          if (data is Map<String, dynamic>) {
            return data;
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ [LocalReminderNotification] consumeLaunchPayload 失敗: $e');
    }
    return null;
  }
}
