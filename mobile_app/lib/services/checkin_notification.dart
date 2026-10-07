import 'dart:convert';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart' show kIsWeb, ValueNotifier;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_call_notification.dart' show notificationBackgroundTapHandler;
import 'location_alert_notification.dart' show LocationAlertNotification;

/// 點擊「長輩打卡」通知後要做的事（由首頁打卡卡片消費）。
class CheckinTap {
  /// `elder-checkin`（完成）或 `elder-checkin-missed`（漏打卡）。
  final String type;
  final String elderId;
  final String elderName;
  final int? reminderId;
  final String title;
  final String localDate;
  const CheckinTap({
    required this.type,
    required this.elderId,
    required this.elderName,
    required this.reminderId,
    required this.title,
    required this.localDate,
  });

  bool get isMissed => type == CheckinNotification.typeMissed;
}

/// ★ 2026-10-07 每日一問：點擊「長輩回答了今天的小問題」通知後要做的事
/// （由家屬互動分頁的每日一問卡片消費，開啟 DailyQuestionScreen 並定位到該題）。
class DailyAnswerTap {
  final String elderId;
  final String elderName;
  final int? questionId;
  const DailyAnswerTap({
    required this.elderId,
    required this.elderName,
    required this.questionId,
  });
}

/// ★ 2026-10-07 打卡雙向互動：家屬端「長輩打卡／漏打卡」本機通知。
///
/// 管線比照 [LocationAlertNotification]（同一套硬規則 13／14）：
/// - FCM 為純 `data`、normal 優先級，系統不會自動彈通知，必須由本檔當消費端；
///   家屬 App 開著時走 Socket（`Signaling.onElderCheckin`／`onElderCheckinMissed`）
///   → 本檔 [show]。三條呼叫路徑（背景 FCM、前景 FCM、Socket）共用 [show]，
///   角色守門與開關檢查因此只有這一處。
/// - ⚠️ 強度刻意是「一般」：`Importance.defaultImportance`、不 `fullScreenIntent`、
///   不繞過勿擾、不改音量、不 bringToFront。不要順手對齊 `CctvAlertNotification`。
/// - 🔒 角色守門沿用 [LocationAlertNotification.isFamilyDevice]（fail-closed，
///   不另寫一份判斷以免兩邊漂移）。
/// - 🔔 `FlutterLocalNotificationsPlugin` 是全域單例：[_registerPlugin] 的初始化設定
///   與 `LocalCallNotification._ensureInit` 逐項一致，並帶
///   `notificationBackgroundTapHandler`，否則被殺死時備援來電的「拒接」會失效。
/// - 🔕 裝置偏好 `checkin_notify_enabled`（預設開）：不屬於 SessionManager 的
///   `_sessionKeys`（G58/G59：換帳號不該重置裝置偏好）。
class CheckinNotification {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool _launchConsumed = false;

  static const String channelId = 'elder_checkin';
  static const String channelName = '長輩打卡';
  static const String channelDesc = '長輩完成或漏掉打卡事項時的通知';

  static const String typeDone = 'elder-checkin';
  static const String typeMissed = 'elder-checkin-missed';

  /// 裝置偏好鍵：是否顯示長輩打卡通知（預設 true）。
  static const String prefKey = 'checkin_notify_enabled';

  /// 去重視窗：同一 (type, reminderId, localDate) 10 分鐘內只顯示一次。
  static const Duration dedupeWindow = Duration(minutes: 10);
  static final Map<String, DateTime> _recent = <String, DateTime>{};

  /// 暖啟動點擊／冷啟動消費後的待處理動作；`HomeCheckinCard` 監聽並消費（消費後設回 null）。
  static final ValueNotifier<CheckinTap?> pendingTap =
      ValueNotifier<CheckinTap?>(null);

  // ───────── ★ 2026-10-07 每日一問：長輩回答通知（沿用本類別的 plugin／守門／點擊轉交） ─────────

  static const String typeDailyAnswer = 'daily-answer';
  static const String dailyChannelId = 'daily_answer';
  static const String dailyChannelName = '每日一問';
  static const String dailyChannelDesc = '長輩回答了每日一問時的通知';

  /// 裝置偏好鍵：是否顯示每日一問回答通知（預設 true；非 SessionManager session key，G58/G59）。
  static const String dailyPrefKey = 'daily_answer_notify_enabled';

  static bool _dailyChannelCreated = false;
  static bool _dailyLaunchConsumed = false;

  /// 暖啟動點擊／冷啟動消費後的待處理動作；每日一問卡片監聽並消費（消費後設回 null）。
  static final ValueNotifier<DailyAnswerTap?> pendingDailyTap =
      ValueNotifier<DailyAnswerTap?>(null);

  static Future<bool> isDailyEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      try {
        await prefs.reload();
      } catch (_) {}
      return prefs.getBool(dailyPrefKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setDailyEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(dailyPrefKey, value);
  }

  @visibleForTesting
  static DailyAnswerTap? parseDailyTap(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final d = jsonDecode(payload);
      if (d is! Map) return null;
      if (d['type']?.toString() != typeDailyAnswer) return null;
      final elderId = (d['elderId'] ?? '').toString().trim();
      if (elderId.isEmpty) return null;
      final name = (d['elderName'] ?? '').toString().trim();
      return DailyAnswerTap(
        elderId: elderId,
        elderName: name.isEmpty ? '長輩' : name,
        questionId: int.tryParse((d['questionId'] ?? '').toString()),
      );
    } catch (_) {
      return null;
    }
  }

  /// 冷啟動：App 被殺死時點擊每日一問通知。與 [consumeLaunchTap] 各自獨立的「只消費一次」旗標。
  static Future<void> consumeDailyLaunchTap() async {
    if (kIsWeb || _dailyLaunchConsumed) return;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) return;
      final tap = parseDailyTap(details.notificationResponse?.payload);
      if (tap == null) return;
      _dailyLaunchConsumed = true;
      if (!await LocationAlertNotification.isFamilyDevice()) return;
      pendingDailyTap.value = tap;
    } catch (e) {
      debugPrint('⚠️ [CheckinNotification] 讀取每日一問 launch details 失敗: $e');
    }
  }

  /// 顯示「長輩回答了今天的小問題」。欄位對應後端 data：
  /// elderId/elderName/questionId/question/answerText/hasAudio/answeredAt。
  /// 角色守門（fail-closed）、開關、10 分鐘去重與打卡通知同一套；強度一般
  /// （defaultImportance、不蓋屏、不繞勿擾、不改音量，硬規則 13）。
  static Future<void> showDailyAnswer({
    required String elderId,
    required String elderName,
    required String questionId,
    required String question,
    required String answerText,
  }) async {
    if (kIsWeb) return;
    try {
      DartPluginRegistrant.ensureInitialized();

      // 🔒 角色守門必須在任何初始化／顯示之前，fail-closed。
      if (!await LocationAlertNotification.isFamilyDevice()) {
        debugPrint('🔒 [CheckinNotification] 本機非確定的家屬端，略過每日一問通知');
        return;
      }
      if (!await isDailyEnabled()) {
        debugPrint('🔕 [CheckinNotification] 使用者已關閉每日一問通知');
        return;
      }

      final dedupeKey = '$typeDailyAnswer|$elderId|$questionId';
      if (seenRecently(dedupeKey)) {
        debugPrint('♻️ [CheckinNotification] 重複事件略過: $dedupeKey');
        return;
      }

      await _ensureInit();
      await _ensureDailyChannel();

      final name = elderName.trim().isEmpty ? '長輩' : elderName.trim();
      final answer = answerText.trim();
      final body = answer.isEmpty
          ? '（語音回答）'
          : (answer.length > 60 ? '${answer.substring(0, 60)}…' : answer);
      final heading = '$name回答了今天的小問題';

      // 專屬 id 區段（1.195e9～1.199e9：不與打卡 1.1e9～1.19e9、安心提醒 1.2e9～ 重疊）。
      final int notificationId =
          1195000000 + (_stableHash(dedupeKey) % 4000000);

      final androidDetails = AndroidNotificationDetails(
        dailyChannelId,
        dailyChannelName,
        channelDescription: dailyChannelDesc,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        styleInformation: BigTextStyleInformation(body, contentTitle: heading),
        category: AndroidNotificationCategory.status,
        // 🚫 不設 fullScreenIntent、不繞勿擾、不設鬧鐘音量。
      );

      await _plugin.show(
        notificationId,
        heading,
        body,
        NotificationDetails(android: androidDetails),
        payload: jsonEncode(<String, String>{
          'type': typeDailyAnswer,
          'elderId': elderId,
          'elderName': name,
          'questionId': questionId,
          'question': question,
        }),
      );
      debugPrint('✅ [CheckinNotification] 已顯示 daily-answer questionId=$questionId');
    } catch (e) {
      debugPrint('⚠️ [CheckinNotification] 每日一問通知顯示失敗: $e');
    }
  }

  static Future<void> _ensureDailyChannel() async {
    if (_dailyChannelCreated) return;
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
        dailyChannelId,
        dailyChannelName,
        description: dailyChannelDesc,
        importance: Importance.defaultImportance,
        playSound: true,
        enableVibration: true,
      ));
    }
    _dailyChannelCreated = true;
  }

  /// 從 Socket／FCM 的 data map 顯示每日一問回答通知（camelCase 欄位兩邊相同）。
  static Future<void> showDailyAnswerFromData(Map data) {
    String s(String k) => (data[k] ?? '').toString();
    return showDailyAnswer(
      elderId: s('elderId'),
      elderName: s('elderName'),
      questionId: s('questionId'),
      question: s('question'),
      answerText: s('answerText'),
    );
  }

  // ───────── ★ 2026-10-07 小豬共養：長輩用家屬送的點心餵了小豬（沿用本類別的 plugin／守門） ─────────
  // 只通知「送點心的那位家屬」（後端只推給 giver）。點擊通知只是打開 App（不另設 pendingTap）。

  static const String typePetGiftFed = 'pet-gift-fed';
  static const String petGiftChannelId = 'pet_gift';
  static const String petGiftChannelName = '小豬共養';
  static const String petGiftChannelDesc = '長輩用您送的點心餵了小豬時的通知';

  /// 裝置偏好鍵：是否顯示小豬共養通知（預設 true；非 SessionManager session key，G58/G59）。
  static const String petGiftPrefKey = 'pet_gift_notify_enabled';

  static bool _petGiftChannelCreated = false;

  static Future<bool> isPetGiftEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      try {
        await prefs.reload();
      } catch (_) {}
      return prefs.getBool(petGiftPrefKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setPetGiftEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(petGiftPrefKey, value);
  }

  /// 顯示「長輩用你送的點心餵了小豬」。欄位對應後端 data：
  /// elderId/elderName/giftId/foodId/foodName/fedAt。角色守門（fail-closed）、開關、
  /// 依 giftId 去重（三條呼叫路徑共用）；強度一般，不蓋屏、不繞勿擾、不改音量（硬規則 13）。
  static Future<void> showPetGiftFed({
    required String elderId,
    required String elderName,
    required String giftId,
    required String foodName,
  }) async {
    if (kIsWeb) return;
    try {
      DartPluginRegistrant.ensureInitialized();

      // 🔒 角色守門必須在任何初始化／顯示之前，fail-closed。
      if (!await LocationAlertNotification.isFamilyDevice()) {
        debugPrint('🔒 [CheckinNotification] 本機非確定的家屬端，略過小豬共養通知');
        return;
      }
      if (!await isPetGiftEnabled()) {
        debugPrint('🔕 [CheckinNotification] 使用者已關閉小豬共養通知');
        return;
      }

      final dedupeKey = '$typePetGiftFed|$giftId';
      if (seenRecently(dedupeKey)) {
        debugPrint('♻️ [CheckinNotification] 重複事件略過: $dedupeKey');
        return;
      }

      await _ensureInit();
      await _ensurePetGiftChannel();

      final name = elderName.trim().isEmpty ? '長輩' : elderName.trim();
      final food = foodName.trim().isEmpty ? '點心' : foodName.trim();
      final heading = '$name用你送的$food餵了小豬 🐷';
      const body = '小豬吃得好開心！';

      // 專屬 id 區段（1.1995e9～1.1999e9：不與每日一問 1.195e9～1.199e9、安心提醒 1.2e9～ 重疊）。
      final int notificationId =
          1199500000 + (_stableHash(dedupeKey) % 400000);

      final androidDetails = AndroidNotificationDetails(
        petGiftChannelId,
        petGiftChannelName,
        channelDescription: petGiftChannelDesc,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        category: AndroidNotificationCategory.status,
        // 🚫 不設 fullScreenIntent、不繞勿擾、不設鬧鐘音量。
      );

      await _plugin.show(
        notificationId,
        heading,
        body,
        NotificationDetails(android: androidDetails),
        payload: jsonEncode(<String, String>{
          'type': typePetGiftFed,
          'elderId': elderId,
          'elderName': name,
          'giftId': giftId,
        }),
      );
      debugPrint('✅ [CheckinNotification] 已顯示 pet-gift-fed giftId=$giftId');
    } catch (e) {
      debugPrint('⚠️ [CheckinNotification] 小豬共養通知顯示失敗: $e');
    }
  }

  static Future<void> _ensurePetGiftChannel() async {
    if (_petGiftChannelCreated) return;
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
        petGiftChannelId,
        petGiftChannelName,
        description: petGiftChannelDesc,
        importance: Importance.defaultImportance,
        playSound: true,
        enableVibration: true,
      ));
    }
    _petGiftChannelCreated = true;
  }

  /// 從 Socket／FCM 的 data map 顯示小豬共養通知（camelCase 欄位兩邊相同）。
  static Future<void> showPetGiftFedFromData(Map data) {
    String s(String k) => (data[k] ?? '').toString();
    return showPetGiftFed(
      elderId: s('elderId'),
      elderName: s('elderName'),
      giftId: s('giftId'),
      foodName: s('foodName'),
    );
  }

  // ───────── ★ 2026-10-07 家庭步數挑戰：本週過半／達標（沿用本類別的 plugin／守門） ─────────
  // 一般優先級、僅限家屬端；點擊只打開 App。

  static const String typeStepChallenge = 'step-challenge';
  static const String stepChallengeChannelId = 'step_challenge';
  static const String stepChallengeChannelName = '全家一起走';
  static const String stepChallengeChannelDesc = '全家本週步數挑戰過半或達標時的通知';

  /// 裝置偏好鍵：是否顯示全家一起走通知（預設 true；非 session key，G58/G59）。
  static const String stepChallengePrefKey = 'step_challenge_notify_enabled';

  static bool _stepChallengeChannelCreated = false;

  static Future<bool> isStepChallengeEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      try {
        await prefs.reload();
      } catch (_) {}
      return prefs.getBool(stepChallengePrefKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setStepChallengeEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(stepChallengePrefKey, value);
  }

  /// 台灣週（週一起算）的週一日期字串，供去重用（payload 沒帶週別，以收到當下的台灣日期推算）。
  @visibleForTesting
  static String twWeekKey([DateTime? now]) {
    final tw = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 8));
    final monday = DateTime.utc(tw.year, tw.month, tw.day)
        .subtract(Duration(days: tw.weekday - 1));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${monday.year}-${two(monday.month)}-${two(monday.day)}';
  }

  /// 純函式：組出通知標題／內文；kind 不是 half／achieved 回傳 null。
  @visibleForTesting
  static ({String title, String body})? stepChallengeText({
    required String kind,
    required String elderName,
    required String totalSteps,
    required String goalSteps,
    String rewardFoodName = '',
  }) {
    final name = elderName.trim().isEmpty ? '長輩' : elderName.trim();
    if (kind == 'half') {
      return (
        title: '全家這週已經走了一半囉！',
        body: '$totalSteps/$goalSteps 步，繼續加油',
      );
    }
    if (kind == 'achieved') {
      final food = rewardFoodName.trim();
      final reward = food.isEmpty ? '獎勵' : '一份$food';
      return (
        title: '全家達標了！🎉',
        body: '這週一起走了 $goalSteps 步，$name的小豬得到$reward',
      );
    }
    return null;
  }

  /// 顯示家庭步數挑戰通知。角色守門（fail-closed）、開關、依 elderId+kind+週別去重。
  static Future<void> showStepChallenge({
    required String elderId,
    required String elderName,
    required String kind,
    required String totalSteps,
    required String goalSteps,
    String rewardFoodName = '',
  }) async {
    if (kIsWeb) return;
    try {
      DartPluginRegistrant.ensureInitialized();

      final text = stepChallengeText(
        kind: kind,
        elderName: elderName,
        totalSteps: totalSteps,
        goalSteps: goalSteps,
        rewardFoodName: rewardFoodName,
      );
      if (text == null) return;

      // 🔒 角色守門必須在任何初始化／顯示之前，fail-closed。
      if (!await LocationAlertNotification.isFamilyDevice()) {
        debugPrint('🔒 [CheckinNotification] 本機非確定的家屬端，略過全家一起走通知');
        return;
      }
      if (!await isStepChallengeEnabled()) {
        debugPrint('🔕 [CheckinNotification] 使用者已關閉全家一起走通知');
        return;
      }

      final dedupeKey = '$typeStepChallenge|$elderId|$kind|${twWeekKey()}';
      if (seenRecently(dedupeKey)) {
        debugPrint('♻️ [CheckinNotification] 重複事件略過: $dedupeKey');
        return;
      }

      await _ensureInit();
      await _ensureStepChallengeChannel();

      // 專屬 id 區段（1.1990e9 起 0.4e6 內，避開小豬共養 1.1995e9～1.1999e9）。
      final int notificationId =
          1199000000 + (_stableHash(dedupeKey) % 400000);

      final androidDetails = AndroidNotificationDetails(
        stepChallengeChannelId,
        stepChallengeChannelName,
        channelDescription: stepChallengeChannelDesc,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        category: AndroidNotificationCategory.status,
        // 🚫 不設 fullScreenIntent、不繞勿擾、不設鬧鐘音量（硬規則 13）。
      );

      await _plugin.show(
        notificationId,
        text.title,
        text.body,
        NotificationDetails(android: androidDetails),
        payload: jsonEncode(<String, String>{
          'type': typeStepChallenge,
          'elderId': elderId,
          'kind': kind,
        }),
      );
      debugPrint('✅ [CheckinNotification] 已顯示 step-challenge kind=$kind');
    } catch (e) {
      debugPrint('⚠️ [CheckinNotification] 全家一起走通知顯示失敗: $e');
    }
  }

  static Future<void> _ensureStepChallengeChannel() async {
    if (_stepChallengeChannelCreated) return;
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
        stepChallengeChannelId,
        stepChallengeChannelName,
        description: stepChallengeChannelDesc,
        importance: Importance.defaultImportance,
        playSound: true,
        enableVibration: true,
      ));
    }
    _stepChallengeChannelCreated = true;
  }

  /// 從 Socket／FCM 的 data map 顯示全家一起走通知（camelCase 欄位兩邊相同）。
  static Future<void> showStepChallengeFromData(Map data) {
    String s(String k) => (data[k] ?? '').toString();
    return showStepChallenge(
      elderId: s('elderId'),
      elderName: s('elderName'),
      kind: s('kind'),
      totalSteps: s('totalSteps'),
      goalSteps: s('goalSteps'),
      rewardFoodName: s('rewardFoodName'),
    );
  }

  static Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      try {
        await prefs.reload();
      } catch (_) {}
      return prefs.getBool(prefKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefKey, value);
  }

  /// 去重：回傳 true 表示「近期已顯示過，應略過」；否則記錄並回傳 false。
  @visibleForTesting
  static bool seenRecently(String key, {DateTime? now}) {
    final t = now ?? DateTime.now();
    _recent.removeWhere((_, v) => t.difference(v) > dedupeWindow);
    if (_recent.containsKey(key)) return true;
    _recent[key] = t;
    return false;
  }

  @visibleForTesting
  static void resetDedupe() => _recent.clear();

  /// 穩定雜湊（FNV-1a 31 bit）：不依賴 `String.hashCode`，跨 isolate／跨次啟動都一致，
  /// 讓同一則打卡事件永遠對到同一個通知 id（重送只會覆蓋，不會疊出兩條）。
  static int _stableHash(String s) {
    var h = 0x811C9DC5;
    for (final u in s.codeUnits) {
      h ^= u;
      h = (h * 0x01000193) & 0x7FFFFFFF;
    }
    return h;
  }

  static Future<void> _ensureInit() async {
    await _registerPlugin();
    if (_initialized) return;
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      const channel = AndroidNotificationChannel(
        channelId,
        channelName,
        description: channelDesc,
        importance: Importance.defaultImportance,
        playSound: true,
        enableVibration: true,
      );
      await androidPlugin.createNotificationChannel(channel);
    }
    _initialized = true;
  }

  static Future<void> _registerPlugin() async {
    // ⚠️ 初始化設定必須與 `LocalCallNotification._ensureInit` 逐項一致（只有 Android、
    // icon 同為 `@mipmap/ic_launcher`、無 Darwin 設定），不可降級它的設定。
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onResponse,
      // 🔴 來電備援「拒接」在 App 被殺死時靠這個背景 handler；initialize 會整組覆寫
      // 回呼，漏帶會讓被殺死狀態下的拒接失效。
      onDidReceiveBackgroundNotificationResponse:
          notificationBackgroundTapHandler,
    );
  }

  /// 重新宣告點擊回呼（冪等）。只在家屬端才真的註冊，其他角色什麼都不做。
  static Future<void> ensureTapHandler() async {
    if (kIsWeb) return;
    try {
      if (!await LocationAlertNotification.isFamilyDevice()) return;
      await _registerPlugin();
    } catch (e) {
      debugPrint('⚠️ [CheckinNotification] 註冊點擊回呼失敗: $e');
    }
  }

  static void _onResponse(NotificationResponse response) {
    if (handleResponse(response)) return;
    // 不是打卡通知：轉交安心提醒通知的處理（它會再把非自己的點擊交還來電備援通知）。
    LocationAlertNotification.handleResponse(response);
  }

  /// 若是打卡通知的點擊就認領（放進 [pendingTap]）並回傳 true；否則回傳 false。
  /// 供 `LocationAlertNotification._onResponse` 轉交——兩個類別共用全域 plugin 的單一
  /// 點擊回呼，最後 `initialize` 者獨佔，所以必須互相轉交，否則後註冊者會吞掉對方的點擊。
  static bool handleResponse(NotificationResponse response) {
    // ★ 2026-10-07 每日一問：先認領每日一問通知（payload type=daily-answer）。
    final dailyTap = parseDailyTap(response.payload);
    if (dailyTap != null) {
      pendingDailyTap.value = dailyTap;
      return true;
    }
    final tap = parseTap(response.payload);
    if (tap == null) return false;
    pendingTap.value = tap;
    return true;
  }

  @visibleForTesting
  static CheckinTap? parseTap(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final d = jsonDecode(payload);
      if (d is! Map) return null;
      final type = d['type']?.toString();
      if (type != typeDone && type != typeMissed) return null;
      final elderId = (d['elderId'] ?? '').toString().trim();
      if (elderId.isEmpty) return null;
      final name = (d['elderName'] ?? '').toString().trim();
      return CheckinTap(
        type: type!,
        elderId: elderId,
        elderName: name.isEmpty ? '長輩' : name,
        reminderId: int.tryParse((d['reminderId'] ?? '').toString()),
        title: (d['title'] ?? '').toString(),
        localDate: (d['localDate'] ?? '').toString(),
      );
    } catch (_) {
      return null;
    }
  }

  /// 冷啟動：App 被殺死時點擊通知，payload 只在 launch details。消費後放進 [pendingTap]
  /// （一次啟動只消費一次、含家屬端守門）。由首頁打卡卡片掛載時呼叫。
  static Future<void> consumeLaunchTap() async {
    if (kIsWeb || _launchConsumed) return;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) return;
      final tap = parseTap(details.notificationResponse?.payload);
      if (tap == null) return;
      _launchConsumed = true;
      if (!await LocationAlertNotification.isFamilyDevice()) return;
      pendingTap.value = tap;
    } catch (e) {
      debugPrint('⚠️ [CheckinNotification] 讀取 launch details 失敗: $e');
    }
  }

  /// 顯示一則打卡通知。[done]＝true 為完成、false 為漏打卡。
  /// 欄位對應後端 data：elderId/elderName/reminderId/title/localDate，
  /// 漏打卡另帶 timeStr。
  static Future<void> show({
    required bool done,
    required String elderId,
    required String elderName,
    required String reminderId,
    required String title,
    required String localDate,
    String timeStr = '',
  }) async {
    if (kIsWeb) return;
    try {
      DartPluginRegistrant.ensureInitialized();

      // 🔒 角色守門必須在任何初始化／顯示之前，fail-closed。
      if (!await LocationAlertNotification.isFamilyDevice()) {
        debugPrint('🔒 [CheckinNotification] 本機非確定的家屬端，略過打卡通知');
        return;
      }
      // 🔕 使用者在設定關閉了「長輩打卡通知」。
      if (!await isEnabled()) {
        debugPrint('🔕 [CheckinNotification] 使用者已關閉打卡通知');
        return;
      }

      final type = done ? typeDone : typeMissed;
      final dedupeKey = '$type|$reminderId|$localDate';
      if (seenRecently(dedupeKey)) {
        debugPrint('♻️ [CheckinNotification] 重複事件略過: $dedupeKey');
        return;
      }

      await _ensureInit();

      final name = elderName.trim().isEmpty ? '長輩' : elderName.trim();
      final item = title.trim();
      final heading = done ? '$name完成了「$item」✓' : '$name還沒完成「$item」';
      final at = timeStr.trim().isEmpty ? '時間' : timeStr.trim();
      final text = done ? '點一下送個鼓勵給$name吧' : '原定 $at，要不要打個電話提醒一下？';

      // 專屬 id 區段（不與安心提醒 1.2e9～ 區段重疊）。
      final int notificationId =
          1100000000 + (_stableHash(dedupeKey) % 90000000);

      final androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDesc,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        styleInformation: BigTextStyleInformation(text, contentTitle: heading),
        category: AndroidNotificationCategory.status,
        // 🚫 不設 fullScreenIntent、不繞勿擾、不設鬧鐘音量——見類別註解。
      );

      await _plugin.show(
        notificationId,
        heading,
        text,
        NotificationDetails(android: androidDetails),
        payload: jsonEncode(<String, String>{
          'type': type,
          'elderId': elderId,
          'elderName': name,
          'reminderId': reminderId,
          'title': item,
          'localDate': localDate,
        }),
      );
      debugPrint('✅ [CheckinNotification] 已顯示 $type reminderId=$reminderId');
    } catch (e) {
      debugPrint('⚠️ [CheckinNotification] 顯示失敗: $e');
    }
  }

  /// 從 Socket／FCM 的 data map 顯示（欄位名兩邊相同，camelCase）。
  static Future<void> showFromData(bool done, Map data) {
    String s(String k) => (data[k] ?? '').toString();
    return show(
      done: done,
      elderId: s('elderId'),
      elderName: s('elderName'),
      reminderId: s('reminderId'),
      title: s('title'),
      localDate: s('localDate'),
      timeStr: s('timeStr'),
    );
  }
}
