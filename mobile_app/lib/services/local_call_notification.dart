import 'dart:convert';
import 'dart:ui' show Color, DartPluginRegistrant;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

/// ★ 2026-07-22 第十一輪：原生高優先級通知備援。
///
/// 背景：`flutter_callkit_incoming` 在 MIUI 被殺死的背景 isolate 中，原生 CallKit
/// 通知會**靜默建立失敗**（`showCallkitIncoming` 射後不理，Dart 端無從得知），
/// 導致 FCM 已送達卻沒有任何來電畫面。這裡用標準 Android notification builder
/// （`flutter_local_notifications`，成熟穩定、不經 CallKit 的 RemoteViews 自訂通知）
/// 發一則 heads-up 高優先級來電通知作為備援。
///
/// ★ 2026-07-27 第十三輪：
///   1. CallKit 恢復為主要來電路徑，本備援**只在 CallKit 確實建立失敗時**才由
///      `main.dart::_showFullScreenCallkit` 補發（互斥，杜絕雙重推播）。
///   2. 樣式向 CallKit 來電 UI 靠攏：大頭像 + 「拒接 / 視訊」兩顆動作按鈕。
///      註：flutter_local_notifications 18.x 不支援 Android 原生 `Notification.CallStyle`，
///      無法做到與 CallKit 像素一致；這是純 Dart 能達到的最接近版本。
///   3. 新增 [consumeLaunchPayload]：APP 被殺死時點擊通知本體，plugin 走的是
///      launch-details 路徑而**不保證**觸發背景 tap handler，先前因此完全沒有
///      消費 payload → 冷啟動只進主畫面。現在由 `main()` 主動撈取。
///
/// 兩個 isolate（主 + 背景 FCM handler）都會用到，故做成頂層函式 + 惰性初始化。
class LocalCallNotification {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// 固定通知 ID：同一時間只會有一通來電，用固定 ID 便於 cancel。
  static const int callNotificationId = 8801;

  /// ★ 2026-08-12 第二十三輪（需求 2「來電音效是系統提醒音效，而非系統來電音效」）：
  ///
  /// 舊 channel `uban_incoming_call_backup` 建立時只給了 `playSound: true`、**沒給 `sound:`**，
  /// 所以 Android 用的是該 channel 的預設「通知音」（短促的一聲提示音），
  /// 而不是使用者預期的「來電鈴聲」。CallKit 那條路是對的
  /// （`AndroidParams.ringtonePath: 'system_ringtone_default'`），
  /// 只有 CallKit 建立失敗時才會落到這個備援，於是聽起來就變成引用錯音效。
  ///
  /// ⚠️ **Android 的 channel 一旦建立，音效／重要度就不可再更改**——對既有安裝
  /// 呼叫 `createNotificationChannel` 傳新的 `sound` 完全沒有效果。
  /// 因此必須**換一個新的 channel id**，並把舊的刪掉（否則設定頁會殘留一個沒用的項目）。
  /// 之後若還要再改鈴聲，一樣得再開新 id，不要試圖就地修改。
  static const String _legacyChannelId = 'uban_incoming_call_backup';
  static const String _channelId = 'uban_incoming_call_ringtone';
  static const String _channelName = '來電通知（備援）';
  static const String _channelDesc = 'App 被系統關閉時，確保仍能收到視訊來電通知';

  /// 系統預設來電鈴聲（`Settings.System.DEFAULT_RINGTONE_URI`）。
  /// 搭配 `AudioAttributesUsage.notificationRingtone`，音量才會走「鈴聲」音量軌
  /// 而不是「通知」音量軌——長輩常把通知音量調很小，走錯音軌等於沒響。
  static const AndroidNotificationSound _ringtoneSound =
      UriAndroidNotificationSound('content://settings/system/ringtone');

  /// `Notification.FLAG_INSISTENT`：讓鈴聲**持續重複**直到通知被取消，
  /// 而不是只響一聲。這是備援通知能像真正來電的關鍵。
  /// 對應的取消點：接聽／拒接（`cancelNotification: true`）、
  /// `cancel-call`、`endAllCalls` 之後的 [cancel]，以及下方的 `timeoutAfter`。
  static final Int32List _insistentFlag = Int32List.fromList(<int>[4]);

  /// 動作按鈕 ID（背景 tap handler 依此分辨接聽/拒接）
  static const String actionAcceptId = 'uban_call_accept';
  static const String actionDeclineId = 'uban_call_decline';

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
    // ★ 2026-08-12 第二十三輪：先刪掉沒有鈴聲的舊 channel，再建帶鈴聲的新 channel。
    //   刪除失敗（例如本來就不存在）不影響後續。
    try {
      await androidPlugin?.deleteNotificationChannel(_legacyChannelId);
    } catch (e) {
      debugPrint('⚠️ [LocalNotif] 刪除舊 channel 失敗（忽略）: $e');
    }
    await androidPlugin?.createNotificationChannel(
      AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.max,
        playSound: true,
        sound: _ringtoneSound,
        audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
        enableVibration: true,
      ),
    );
    _initialized = true;
  }

  /// 顯示來電備援通知。**僅在 CallKit 確認未建立時呼叫**（見 `_showFullScreenCallkit`）。
  static Future<void> show(Map<String, dynamic> data) async {
    if (kIsWeb) return;
    try {
      await _ensureInit();
      final callerName =
          (data['callerName'] ?? data['senderName'] ?? '有人來電').toString();
      final bool isEmergency = data['type'] == 'emergency-call';
      final payload = jsonEncode({
        'roomId': (data['roomId'] ?? '').toString(),
        'senderId': (data['senderId'] ?? '').toString(),
        'callId': (data['callId'] ?? '').toString(),
        'issuedAt': (data['issuedAt'] ?? '').toString(),
        'expiresAt': (data['expiresAt'] ?? '').toString(),
        'senderRole': (data['role'] ?? '').toString(),
        // ★ Fix E：透傳是否為視訊通話，false = 純語音（電話），預設 true。
        'isVideoCall': (data['isVideoCall'] ?? 'true').toString(),
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
        // ★ 2026-08-12 第二十三輪（需求 2）：channel 決定 Android 8+ 的音效，
        //   這裡的 sound / audioAttributesUsage 則負責 Android 7 及以下。兩邊都要給。
        playSound: true,
        sound: _ringtoneSound,
        audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
        additionalFlags: _insistentFlag, // FLAG_INSISTENT：鈴聲重複直到通知被取消
        // 安全網：萬一取消鏈路全斷（isolate 被殺、cancel-call 未達），
        // 也不能讓 FLAG_INSISTENT 的鈴聲無限響下去。與第二十二輪需求 10
        // 「來電最多等 1 分鐘」同一個預算。
        timeoutAfter: 60000,
        // ★ 2026-08-02 第十四輪：通知底色向 CallKit 來電 UI 靠攏
        color: const Color(0xFF1A472A),
        colorized: true,
        // ★ 第十三輪：向 CallKit 來電 UI 靠攏——大頭像 + 拒接/視訊 兩顆按鈕
        largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        actions: const <AndroidNotificationAction>[
          AndroidNotificationAction(
            actionDeclineId,
            '✕ 拒絕',
            titleColor: Color(0xFFD32F2F), // 紅，對齊 CallKit 來電 UI 的拒接鍵
            showsUserInterface: false,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            actionAcceptId,
            '✓ 接聽',
            titleColor: Color(0xFF2E7D32), // 綠，對齊 CallKit 來電 UI 的接聽鍵
            showsUserInterface: true,
            cancelNotification: true,
          ),
        ],
      );
      await _plugin.show(
        callNotificationId,
        callerName,
        isEmergency ? '🚨 緊急視訊通話' : '📞 視訊通話',
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

  /// ★ 2026-07-27 第十三輪：冷啟動消費「點擊備援通知而啟動 APP」的 payload。
  ///
  /// APP 被系統殺死時，使用者點擊通知本體會直接啟動 APP，此時
  /// `onDidReceiveBackgroundNotificationResponse` **不保證**被呼叫——payload 只會
  /// 出現在 `getNotificationAppLaunchDetails()` 裡。先前完全沒有讀取這裡，導致
  /// `pendingAcceptedCall` 從未被寫入，冷啟動兜底鏈全部落空（只進主畫面）。
  ///
  /// 必須在 `main()` 讀取 `pendingAcceptedCall` prefs **之前**呼叫。
  static Future<void> consumeLaunchPayload() async {
    if (kIsWeb) return;
    try {
      await _ensureInit();
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) return;
      final response = details.notificationResponse;
      if (response == null) return;
      if (response.actionId == actionDeclineId) {
        debugPrint('🔕 [LocalNotif] 冷啟動 launch details 為拒接，忽略');
        return;
      }
      debugPrint('✅ [LocalNotif] 冷啟動偵測到備援通知點擊，寫入 pendingAcceptedCall');
      await _persistTapAsAccepted(response.payload);
      await cancel();
    } catch (e) {
      debugPrint('⚠️ [LocalNotif] consumeLaunchPayload 失敗: $e');
    }
  }

  /// 前景點擊：把來電資料寫入 pendingAcceptedCall prefs，交由 main() / 頁面 listener 接手導航。
  static void _onTap(NotificationResponse response) {
    notificationBackgroundTapHandler(response);
  }
}

/// 背景 isolate 點擊 handler（必須是頂層 + vm:entry-point）。
@pragma('vm:entry-point')
Future<void> notificationBackgroundTapHandler(NotificationResponse response) async {
  // ★ 2026-08-02 第十四輪：背景 isolate 未初始化 binding/plugin registrant 時，
  //   SharedPreferences 與 HTTP 都會拋 MissingPluginException——這正是
  //   「備援通知只能接聽、無法拒絕」的根因（拒接整段被 catch 吞掉）。
  //   比照 main.dart 的 FCM 背景 handler 先做初始化。
  try {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
  } catch (e) {
    debugPrint('⚠️ [LocalNotif] 背景 isolate 初始化失敗: $e');
  }
  if (response.actionId == LocalCallNotification.actionDeclineId) {
    await _handleDecline(response.payload);
    return;
  }
  await _persistTapAsAccepted(response.payload);
}

/// 點擊備援通知 / 按「視訊」= 接聽：寫入 pendingAcceptedCall，
/// 冷啟動時 main() → Splash 兜底導向 ElderScreen / VideoCallScreen。
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
        // ★ Fix E：透傳是否為視訊通話，false = 純語音（電話），預設 true。
        'isVideoCall': (data['isVideoCall'] ?? 'true').toString(),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }),
    );
    debugPrint('✅ [LocalNotif] 點擊接聽 → 已寫入 pendingAcceptedCall (callId=${data['callId']})');
  } catch (e) {
    debugPrint('⚠️ [LocalNotif] 處理通知點擊失敗: $e');
  }
}

/// 按「拒接」：走無狀態 HTTP 通知發起方停止等待，並清除三個陳舊狀態 key
/// （與 `main.dart::_sendDeclineEvent` 及 BG isolate CallKit listener 一致，護欄 #15）。
Future<void> _handleDecline(String? payload) async {
  if (payload == null || payload.isEmpty) return;
  String roomId = '';
  String senderId = '';
  String callId = '';
  try {
    final Map<String, dynamic> data = jsonDecode(payload);
    roomId = (data['roomId'] ?? '').toString();
    senderId = (data['senderId'] ?? '').toString();
    callId = (data['callId'] ?? '').toString();
  } catch (e) {
    debugPrint('⚠️ [LocalNotif] 拒接 payload 解析失敗: $e');
    return;
  }

  // ★ 2026-08-02 第十四輪：三段各自獨立 try/catch，任一段失敗都不得阻斷其餘兩段。
  //   先發 declineCall（最重要、只依賴 HTTP），再清 prefs，最後關通知。
  try {
    if (roomId.isNotEmpty && senderId.isNotEmpty) {
      debugPrint('🔕 [LocalNotif] 拒接 → HTTP declineCall (callId=$callId)');
      await ApiService.declineCall(
        roomId: roomId,
        senderId: senderId,
        callId: callId.isEmpty ? null : callId,
      );
    } else {
      debugPrint('⚠️ [LocalNotif] 拒接缺 roomId/senderId，略過 declineCall');
    }
  } catch (e) {
    debugPrint('⚠️ [LocalNotif] declineCall 失敗: $e');
  }

  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pendingAcceptedCall');
    await prefs.remove('pendingRingCallData');
    await prefs.remove('pendingRingCall');
  } catch (e) {
    debugPrint('⚠️ [LocalNotif] 拒接清除 prefs 失敗: $e');
  }

  try {
    await LocalCallNotification.cancel();
  } catch (e) {
    debugPrint('⚠️ [LocalNotif] 拒接關閉通知失敗: $e');
  }
}
