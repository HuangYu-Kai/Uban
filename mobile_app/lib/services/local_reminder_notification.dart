import 'dart:convert';
import 'dart:ui' show DartPluginRegistrant;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'elder_reminder_manager.dart';

/// ⏰ 長輩端排程提醒的本機高優先級通知管理器
///
/// ★ 第四十九輪（item 1）：使用者要求排程提醒的推播「權限要與系統鬧鐘相同，
///   並要有語音發聲（比照緊急警報）」。本檔案因此比照 `cctv_alert_notification.dart`
///   （跌倒警報，同樣的「鬧鐘級」需求）做兩項升級：
///   1. `AudioAttributesUsage.alarm`：讓通知聲音改走 Android 的「鬧鐘」音訊軌，
///      而非預設的「通知」音訊軌——手機開啟勿擾模式時，系統預設仍會放行鬧鐘音軌
///      （使用者需自行在 DND 設定關閉「鬧鐘」例外才會被擋），這與真正的系統鬧鐘
///      鈴聲繞過勿擾模式是同一個機制，且**不需要任何額外的使用者授權**即可生效。
///   2. `FlutterTts` 語音朗讀：直接在本函式內朗讀提醒內容，不依賴呼叫端是否能
///      顯示 `ElderReminderDialog`——這一點很關鍵：`services/firebase_bg_handler.dart`
///      的 FCM 背景 isolate（App 被殺死時收到伺服器推播）只會呼叫本函式，*不會*
///      呼叫 `ElderReminderManager.handleIncomingReminder`，也就沒有機會顯示彈窗。
///      若語音只綁在彈窗的 `initState`（原本的做法），這個「長輩可能錯過」的
///      核心情境反而是唯一完全沒有語音的路徑。詳見 [showReminderNotification]
///      內的說明與 `elder_reminder_manager.dart` 的 `speak` 參數説明（避免雙重朗讀）。
///
///   ⚠️ 本輪**沒有**加入 `setBypassDnd`（channel 層級的勿擾繞過，需要使用者額外
///   到系統設定頁授予「通知政策存取」權限，且 Android channel 建立後不可變，
///   必須比照 `cctv_alert_notification.dart` 用原生雙 channel id 動態切換）。
///   原因：`cctv_alert_notification.dart` 的作法之所以能生效，是因為
///   `family_settings_view.dart` 有一個對應的「勿擾模式例外」設定入口讓使用者
///   去授權；但那個入口只存在於**家屬端**，且該權限是「每一支手機各自的
///   App 安裝」各自獨立的系統權限，家屬手機上授權完全不會影響長輩手機。
///   長輩端目前沒有對應的授權入口，若貿然做兩個 channel 版本，長輩手機上永遠
///   會落在「未授權」那一版，等於白做——因此本輪只做**不需要額外授權就能生效**
///   的 `AudioAttributesUsage.alarm`，`setBypassDnd` 留待另外評估是否要在長輩端
///   新增一個對應的授權引導畫面後再做（否則就是半套）。
class LocalReminderNotification {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static FlutterTts? _tts;

  // ★ 第四十九輪：channel id 加上 `_v2` 版本後綴。Android 的 NotificationChannel
  //   一旦建立就不可變——已安裝過舊版 App 的裝置上，`uban_schedule_reminder` 這個
  //   channel 早已用舊設定（無 `audioAttributesUsage`、`category: reminder`）建立
  //   完成，之後再對同一個 id 呼叫 `createNotificationChannel` 傳新設定，系統會
  //   直接忽略、新設定不會生效（與 `cctv_alert_notification.dart` 檔頭註解說明的
  //   限制完全相同）。改用新 id 才能讓這些裝置實際拿到鬧鐘級音訊屬性；舊 id 的
  //   channel 留著不刪也無妨，只是不會再有新通知送往那裡。
  static const String channelId = 'uban_schedule_reminder_v2';
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
        // ★ 第四十九輪：鬧鐘音訊軌，見檔頭說明。
        audioAttributesUsage: AudioAttributesUsage.alarm,
      );
      await androidPlugin.createNotificationChannel(channel);
    }
    _initialized = true;
  }

  /// 顯示排程提醒通知（支援背景 FCM Isolate 與前景安全調用）
  ///
  /// [elderName]：可選。有值時朗讀「XXX您好，現在是…」的個人化開場白；
  /// 省略時（例如 `firebase_bg_handler.dart` 的背景 FCM 路徑目前尚未在 payload
  /// 帶長輩姓名）改用不含稱呼的通用句子，仍會朗讀，只是少一句招呼。
  static Future<void> showReminderNotification({
    required int id,
    required String title,
    required String timeStr,
    String? note,
    String? category,
    String? elderName,
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
        // ★ 第四十九輪：high → max，並改用 alarm 分類＋鬧鐘音訊軌＋鎖屏公開顯示，
        //   比照 `cctv_alert_notification.dart` 的鬧鐘級設定（唯一差異是這裡不做
        //   channel 層級的 bypassDnd，見檔頭說明）。
        priority: Priority.max,
        ticker: displayTitle,
        styleInformation: BigTextStyleInformation(
          bodyText,
          contentTitle: displayTitle,
          summaryText: 'Uban 守護排程',
        ),
        fullScreenIntent: true,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
        playSound: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
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

    // ★ 第四十九輪：語音朗讀獨立一個 try/catch，理由與 `_plugin.show` 分開
    //   完全一致於本專案既有慣例（見 `cctv_alert_notification.dart` 各步驟
    //   互不影響的寫法）——就算 TTS 引擎在某些裝置上初始化失敗，也不能讓通知
    //   本身（上面已經送出）被視為失敗，兩者是獨立的呈現管道。
    await _speakReminder(title: title, timeStr: timeStr, note: note, elderName: elderName);
  }

  /// 朗讀提醒內容。獨立成方法供 [showReminderNotification] 呼叫，
  /// 也讓「文字怎麼組」只有一處，不會日後改一邊漏改另一邊。
  static Future<void> _speakReminder({
    required String title,
    required String timeStr,
    String? note,
    String? elderName,
  }) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();
      _tts ??= FlutterTts();
      await _tts!.setLanguage('zh-TW');
      await _tts!.setPitch(1.0);
      await _tts!.setSpeechRate(0.5);
      final String noteSuffix = (note != null && note.isNotEmpty) ? note : '';
      final String greeting =
          (elderName != null && elderName.isNotEmpty) ? '$elderName您好，' : '';
      await _tts!.speak('$greeting現在是$timeStr，提醒您「$title」喔！$noteSuffix');
    } catch (e) {
      debugPrint('⚠️ [LocalReminderNotification] 語音朗讀失敗: $e');
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
