import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 💬 家屬端「爸媽問你一個問題」的本機通知
///
/// 為什麼需要這支：依專案硬規則 14，喚醒類 FCM 一律只送純 `data` payload、
/// 不帶 `notification` block（避免繞過前端的角色守門），因此系統不會自動
/// 彈通知——沒有這支消費端，家屬 App 關著時那則 FCM 會被靜默丟掉，
/// 子女要等自己打開 App 才看得到收件匣。
///
/// ⚠️ **刻意與 `CctvAlertNotification` 走不同的強度**：
/// 跌倒警報用 `Importance.max` ＋ 繞過勿擾 ＋ 專屬鈴聲，是因為攸關人身安全。
/// 但「爸媽問你這個按鈕怎麼用」用同樣的強度半夜把子女吵醒，只會讓他們把
/// 整個 App 的通知關掉——連真正的跌倒警報都一起收不到。
/// 所以這裡用 `Importance.defaultImportance`／`Priority.default`，
/// 不繞過勿擾、不 fullScreenIntent、不強制音量。
class ElderQuestionNotification {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const String channelId = 'uban_elder_question';
  static const String channelName = '長輩提問';
  static const String channelDesc = '長輩問小嘎、小嘎轉交給您回答的問題';

  static Future<void> _ensureInit() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      const channel = AndroidNotificationChannel(
        channelId,
        channelName,
        description: channelDesc,
        // 一般重要度：會出現在通知欄與鎖定畫面，但不會蓋屏、不會強制發聲。
        importance: Importance.defaultImportance,
        playSound: true,
        enableVibration: true,
      );
      await androidPlugin.createNotificationChannel(channel);
    }
    _initialized = true;
  }

  /// 顯示一則「長輩提問」通知。
  ///
  /// [data] 為 FCM 的純 data payload，欄位與
  /// `services/elder_question_dispatcher.py::_notify_family` 送出的鍵名一致，
  /// 兩邊必須同步修改，否則會靜默顯示成空白通知。
  static Future<void> show(Map<String, dynamic> data) async {
    try {
      // 背景 Isolate 需要自己註冊 plugin，否則 _plugin 呼叫會直接失敗。
      DartPluginRegistrant.ensureInitialized();
      await _ensureInit();

      final elderName = (data['elderName'] ?? '長輩').toString();
      final question = (data['question'] ?? '').toString().trim();
      final screenContext = (data['screenContext'] ?? '').toString().trim();
      final questionId =
          int.tryParse((data['questionId'] ?? '').toString()) ?? 0;

      if (question.isEmpty) {
        debugPrint('💬 [ElderQuestionNotification] question 為空，略過');
        return;
      }

      final body = screenContext.isEmpty
          ? question
          : '$question\n（當時在：$screenContext）';

      final androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDesc,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        // 問題可能較長，用 BigText 讓子女不必點開就看得完
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: '$elderName 問你一個問題',
        ),
        category: AndroidNotificationCategory.message,
        // 🚫 不設 fullScreenIntent、不設 audioAttributesUsage alarm、
        //    不 bypassDnd——這不是緊急事件，理由見類別註解。
      );

      await _plugin.show(
        // 用 questionId 當通知 id，同一則問題重送不會疊出多條通知。
        // questionId 為 0（解析失敗）時退回固定值，至少不會覆蓋別則。
        questionId > 0 ? questionId : 990001,
        '$elderName 問你一個問題',
        body,
        NotificationDetails(android: androidDetails),
      );
      debugPrint('💬 [ElderQuestionNotification] 已顯示提問通知 id=$questionId');
    } catch (e) {
      debugPrint('⚠️ [ElderQuestionNotification] 顯示失敗: $e');
    }
  }
}
