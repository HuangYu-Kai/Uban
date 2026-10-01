import 'dart:convert';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_call_notification.dart' show notificationBackgroundTapHandler;

/// 📍 家屬端「安心提醒」（長輩定位異常：晚歸／久未更新／離家太遠）的本機通知
///
/// 管線與 [ElderQuestionNotification]（長輩提問轉交）同一類：依專案硬規則 14，
/// 喚醒類 FCM 一律只送純 `data` payload、不帶 `notification` block，系統不會
/// 自動彈通知，必須由本檔當消費端；Socket 通路（`location-alert`）在家屬 App
/// 開著時走 `Signaling.onLocationAlert` → 本檔 [show]，因為這類提醒沒有收件匣
/// UI，通知欄就是唯一的呈現處。
///
/// ⚠️ **通知強度刻意是「一般」**（比照長輩提問、**不要**對齊 `CctvAlertNotification`）：
/// `Importance.defaultImportance`、不 `fullScreenIntent`、不繞過勿擾、不改音量、
/// 不 `AndroidIntent`／`bringToFront`——這是「安心」提醒而不是人身安全警報，
/// 用警報等級半夜吵醒子女只會讓他們把整個 App 的通知關掉（連真正的跌倒警報
/// 都一起收不到）。見 `CLAUDE.md` §3.1 第 13 條（強制開啟只准長輩端）。
///
/// 🔒 **角色守門（fail-closed）**：只有確定是家屬端才顯示，見 [isFamilyDevice]。
/// 後端本來就只會推給家屬，這裡是第二道防線——長輩機若因 prefs 殘留／token
/// 漂移而誤收到，絕不能彈出「某某長輩晚歸」這種含長輩行蹤的通知。
///
/// 👆 **點擊導航**：通知 payload 帶 `elderId`／`elderName`，點擊後由
/// `main.dart` 開啟 `ElderLocationMapScreen`。
/// - 暖啟動（App 活著）：走 [_onResponse] → [onTapOpenMap]。
/// - 冷啟動（App 被殺死）：走 [consumeLaunchTap]（讀 launch details），
///   由 `main.dart` 等 Splash 結束後再導航（護欄 G13）。
class LocationAlertNotification {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool _launchConsumed = false;

  static const String channelId = 'uban_location_alert';
  static const String channelName = '安心提醒';
  static const String channelDesc = '長輩晚歸、久未更新位置或離家太遠時的提醒';

  /// payload 的 `type` 值；用來和其他通知（來電備援等）的 payload 區分。
  static const String payloadType = 'location-alert';

  /// 使用者點了「安心提醒」通知時的導航回呼，由 `main.dart` 在啟動時指派。
  /// 參數為 (elderId, elderName)。
  static void Function(String elderId, String elderName)? onTapOpenMap;

  /// 🔒 是否確定為家屬端裝置。**fail-closed**：判斷不出來一律回傳 `false`。
  ///
  /// 背景 FCM isolate 沒有 `Signaling._role`，只能讀本機 prefs；而 prefs 的
  /// `user_role` 與 `saved_role` 由不同畫面寫入、有過漂移史（見
  /// `CLAUDE_call-monitor.md` 第十六輪），所以規則刻意從嚴：
  /// 1. 兩個鍵「有值的」必須**全部**是 `family`，且至少要有一個有值；
  ///    任一鍵為 `elder`（或其他值）＝角色矛盾 → 不顯示。
  /// 2. `saved_is_cctv == true`（本機是監控機）一定是長輩端 → 不顯示。
  /// 3. 讀 prefs 本身失敗 → 不顯示。
  /// 代價是「家屬機 prefs 異常時漏通知」，這比「長輩機收到家屬專屬的行蹤通知」
  /// 可接受得多（此類提醒另有 App 內定位畫面可補查）。
  static Future<bool> isFamilyDevice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      try {
        // 背景 isolate 的快取可能落後主 isolate 的寫入，讀前先刷新；失敗不致命。
        await prefs.reload();
      } catch (_) {}
      if (prefs.getBool('saved_is_cctv') == true) return false;
      final roles = <String>[
        (prefs.getString('user_role') ?? '').trim(),
        (prefs.getString('saved_role') ?? '').trim(),
      ].where((r) => r.isNotEmpty).toList();
      if (roles.isEmpty) return false;
      return roles.every((r) => r == 'family');
    } catch (e) {
      debugPrint('⚠️ [LocationAlertNotification] 角色判斷失敗，視為非家屬端: $e');
      return false;
    }
  }

  static Future<void> _ensureInit() async {
    // 點擊回呼每次都重新宣告（見 [_registerPlugin] 的說明）；channel 只建一次。
    await _registerPlugin();
    if (_initialized) return;
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

  /// `FlutterLocalNotificationsPlugin` 是全域單例，`initialize` 的
  /// `onDidReceiveNotificationResponse` 是「最後一次呼叫者獨佔」——
  /// `CctvAlertNotification`／`ElderQuestionNotification` 的 `initialize` 沒帶回呼，
  /// 會把前一位指派的回呼清成 null。因此點擊回呼不能只在 [_ensureInit] 設一次，
  /// 需要時可重新宣告（[ensureTapHandler]），且回呼必須把「不是本通知」的點擊
  /// 原樣交還給來電備援通知的既有 handler（與 `LocalCallNotification._onTap`
  /// 相同行為），不能吞掉。
  static Future<void> _registerPlugin() async {
    // ⚠️ 初始化設定必須與 `LocalCallNotification._ensureInit` 逐項一致
    //（同樣只有 Android、icon 同為 `@mipmap/ic_launcher`、沒有 Darwin 設定），
    // 不可降級它的設定。
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onResponse,
      // 🔴 來電備援通知的「拒接」action 在 App 被殺死時靠這個背景 handler 處理
      // （`LocalCallNotification` 也是同時傳這兩個回呼）。`initialize` 會整組覆寫
      // 回呼，若這裡漏帶，重新宣告後被殺死狀態下的拒接會失效。必須傳同一個
      // 頂層 `@pragma('vm:entry-point')` 函式。
      onDidReceiveBackgroundNotificationResponse:
          notificationBackgroundTapHandler,
    );
  }

  /// 重新宣告點擊回呼（冪等）。只在家屬端才會真的註冊，其他角色什麼都不做，
  /// 以免覆蓋長輩端排程提醒等通知的點擊回呼。
  static Future<void> ensureTapHandler() async {
    if (kIsWeb) return;
    try {
      if (!await isFamilyDevice()) return;
      await _registerPlugin();
    } catch (e) {
      debugPrint('⚠️ [LocationAlertNotification] 註冊點擊回呼失敗: $e');
    }
  }

  static void _onResponse(NotificationResponse response) {
    final tap = _parseTap(response.payload);
    if (tap == null) {
      // 不是安心提醒：交還來電備援通知的既有處理（非來電 payload 它會自行略過）。
      notificationBackgroundTapHandler(response);
      return;
    }
    final cb = onTapOpenMap;
    if (cb == null) {
      debugPrint('⚠️ [LocationAlertNotification] 點擊回呼尚未指派，略過導航');
      return;
    }
    cb(tap.$1, tap.$2);
  }

  /// 解析 payload；不是安心提醒或缺 `elderId` 一律回傳 null。
  static (String, String)? _parseTap(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;
      if (decoded['type']?.toString() != payloadType) return null;
      final elderId = (decoded['elderId'] ?? '').toString().trim();
      if (elderId.isEmpty) return null;
      final elderName = (decoded['elderName'] ?? '').toString().trim();
      return (elderId, elderName.isEmpty ? '長輩' : elderName);
    } catch (_) {
      return null;
    }
  }

  /// 冷啟動：APP 被殺死時點擊通知，payload 只會出現在 launch details。
  /// 回傳 (elderId, elderName)；不是本通知啟動、非家屬端、已消費過都回傳 null。
  /// 由 `main.dart` 在 Splash 結束後呼叫並導航。
  static Future<(String, String)?> consumeLaunchTap() async {
    if (kIsWeb || _launchConsumed) return null;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) return null;
      final tap = _parseTap(details.notificationResponse?.payload);
      if (tap == null) return null;
      _launchConsumed = true; // 同一次啟動只導航一次
      if (!await isFamilyDevice()) return null;
      return tap;
    } catch (e) {
      debugPrint('⚠️ [LocationAlertNotification] 讀取 launch details 失敗: $e');
      return null;
    }
  }

  /// 規則 → 通知內文的退路（後端 `body`／`message` 為空時才用）。
  static String _fallbackBody(String rule, String elderName) {
    switch (rule) {
      case 'late_return':
        return '$elderName 比平常晚回家了';
      case 'no_update':
        return '已經有一段時間沒有收到 $elderName 的位置更新';
      case 'far_from_home':
        return '$elderName 目前離家較遠';
      default:
        return '$elderName 的位置有異常，請點開確認';
    }
  }

  /// 顯示一則「安心提醒」通知。
  ///
  /// 欄位對應後端 FCM data（`elderId`/`elderName`/`rule`/`title`/`body`/`alertId`）；
  /// Socket `location-alert` 的 `elder_id`/`elder_name`/`message`/`alert_id`
  /// 由呼叫端先轉成同名參數再傳入。三條呼叫路徑（背景 FCM、前景 FCM、Socket 回呼）
  /// 共用本函式，角色守門因此只有這一處。
  static Future<void> show({
    required String elderId,
    required String elderName,
    required String rule,
    required String title,
    required String body,
    required String alertId,
  }) async {
    if (kIsWeb) return;
    try {
      // 背景 Isolate 需要自己註冊 plugin，否則 SharedPreferences／_plugin 會直接失敗。
      DartPluginRegistrant.ensureInitialized();

      // 🔒 角色守門必須在任何初始化／顯示之前，fail-closed。
      if (!await isFamilyDevice()) {
        debugPrint('🔒 [LocationAlertNotification] 本機非確定的家屬端，略過安心提醒');
        return;
      }
      await _ensureInit();

      final name = elderName.trim().isEmpty ? '長輩' : elderName.trim();
      final heading = title.trim().isEmpty ? channelName : title.trim();
      final text =
          body.trim().isEmpty ? _fallbackBody(rule, name) : body.trim();

      // 用 alertId 當通知 id（映射到專屬區段，避免撞到其他通知類型的 id），
      // 同一則提醒重送不會疊出多條。alertId 非數字時退回字串雜湊。
      final int base = int.tryParse(alertId) ?? alertId.hashCode;
      final int notificationId = 1200000000 + (base.abs() % 900000000);

      final androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDesc,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        styleInformation: BigTextStyleInformation(
          text,
          contentTitle: heading,
        ),
        category: AndroidNotificationCategory.status,
        // 🚫 不設 fullScreenIntent、不設 audioAttributesUsage alarm、
        //    不 bypassDnd——這不是緊急事件，理由見類別註解。
      );

      await _plugin.show(
        notificationId,
        heading,
        text,
        NotificationDetails(android: androidDetails),
        payload: jsonEncode(<String, String>{
          'type': payloadType,
          'elderId': elderId,
          'elderName': name,
        }),
      );
      debugPrint('📍 [LocationAlertNotification] 已顯示安心提醒 rule=$rule alertId=$alertId');
    } catch (e) {
      debugPrint('⚠️ [LocationAlertNotification] 顯示失敗: $e');
    }
  }
}
