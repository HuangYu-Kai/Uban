import 'dart:ui' show Color, DartPluginRegistrant;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ★ 2026-08-05 第十七輪：YOLO 跌倒警報的高優先級通知。
///
/// 結構完全比照 `local_call_notification.dart`（`_ensureInit()` + 高優先級 channel +
/// `show()` + `cancel()`），但用途不同：這裡沒有接聽/拒接動作，純粹是「強制點亮螢幕 +
/// 提醒家屬立即查看監視畫面」的一次性警報通知，因此**不加任何 action 按鈕**——
/// `local_call_notification.dart` 的動作按鈕曾因為跑在未初始化的裸 isolate 而整條
/// 失效（拒接鍵完全沒作用），修了一整輪才修好；這裡沒有按鈕邏輯要處理，不重蹈覆轍。
///
/// channel（`uban_cctv_alert_v3` / `uban_cctv_alert_v3_dnd`，動態依 DND 授權狀態
/// 二選一，見下方 [_notificationPolicyChannel] 的說明）與通知 id（`8811`）都與來電備援
/// （`uban_incoming_call_backup` / `8801`，見 `local_call_notification.dart`）分開，
/// 不可共用——來電備援 channel 是 CallKit 失敗時唯一的來電管道，共用會互相干擾。
class CctvAlertNotification {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// 固定通知 ID：同一時間只會有一則跌倒警報通知，用固定 ID 便於 cancel；
  /// 與來電備援的 8801 錯開，避免互相覆蓋。
  static const int alertNotificationId = 8811;

  /// ★ 2026-08-19：舊 channel 建立時只給了 `playSound: true`、**沒給 `sound:`**，
  /// Android 因此套用該 channel 的預設「通知音」（短促提示音，走 NOTIFICATION 音量軌），
  /// 會被勿擾模式靜音、通知音量也常被家屬調小——跌倒警報因此可能完全沒聲音。
  /// 改用救護車警報音（見下方 [_sirenSound]）＋ ALARM 音軌
  /// （`AudioAttributesUsage.alarm`，見 `_ensureInit()` / `show()`）。
  ///
  /// ★ 2026-08-20：channel 的建立／刪除改由原生負責，Dart 不再自己管理。
  ///
  /// ⚠️ **Android 的 channel 一旦建立，音效／音訊屬性／`bypassDnd` 就不可再更改**——
  /// 對既有安裝呼叫 `createNotificationChannel` 傳新設定完全沒有效果，OS 會直接
  /// 忽略；`setBypassDnd(true)`（讓警報繞過勿擾模式）更嚴格：只有 channel「建立
  /// 當下」APP 就已經持有「通知政策存取」權限才會生效，事後才授權也不會回溯生效。
  /// 這代表「先建立、之後再視授權狀態切換」這條路完全走不通，只能在每次啟動／回
  /// 前景時依「當下」的授權狀態決定要用哪一個 channel id、並把另一個變體刪掉——
  /// 而只有原生才能在 `onCreate` / `onResume` 精準攔到「使用者剛從系統設定頁授權
  /// 完返回」這個時機，因此整個 channel 生命週期（建立、刪除、依授權狀態切換、
  /// 清 v1/v2 legacy id）都交給原生的 `MainActivity.kt::ensureAlertChannel()`
  /// （完整原理見該函式註解）。Dart 這裡只透過 [_notificationPolicyChannel] 問一次
  /// 「現在該用哪個 channel id」，不再自己建立或刪除 channel。
  /// （與 2026-08-12 第二十三輪換鈴聲時踩到的「channel 不可變」是同一個坑，
  /// 這輪只是把管理權完整移交給原生。）
  static const MethodChannel _notificationPolicyChannel =
      MethodChannel('com.example.app/notification_policy');

  /// 原生 MethodChannel 呼叫失敗時的最終安全退回值：不需要 DND 權限的版本，
  /// 一定能用。例如 [show] 會直接從 FCM 背景 isolate 呼叫——該 isolate 用的是
  /// 另一個 headless FlutterEngine，沒有掛載 `MainActivity.configureFlutterEngine()`
  /// 註冊的自訂 MethodChannel，呼叫會丟 `MissingPluginException`。但在退到這個
  /// 值之前，[_ensureInit] 會先試著讀 [_activeChannelPrefsKey] 快取——完整的
  /// 三層解析順序與原因見 [_ensureInit] 內的說明。
  static const String _fallbackChannelId = 'uban_cctv_alert_v3';

  /// [_notificationPolicyChannel] 問不到原生結果時（典型情況：背景 isolate）的
  /// 第二層退回來源——上一次「前景」成功問到原生結果時，[_ensureInit] 順手寫入
  /// 的快取值。用 `shared_preferences` 而不是讓原生直接寫 Android 原生
  /// SharedPreferences 檔案，是因為 `shared_preferences` 是正牌 pub.dev 外掛，
  /// 會透過 `GeneratedPluginRegistrant` 註冊到包含 headless 背景在內的「每一個」
  /// FlutterEngine，讀寫都在 Dart 這一側完成、不需要跨語言對齊儲存格式；完整
  /// 原理見 [_ensureInit] 的說明。
  static const String _activeChannelPrefsKey = 'uban_active_alert_channel_id';

  /// 目前實際要送去的 channel id，由 [_ensureInit] 問過原生（或退回快取／
  /// 硬編碼值）後更新；初始值等於 [_fallbackChannelId]，讓所有非同步流程
  /// 完成前就有安全預設。
  static String _channelId = _fallbackChannelId;

  static const String _channelName = '跌倒警報';
  static const String _channelDesc = 'YOLO 監視機偵測到疑似跌倒時的高優先級提醒';

  /// 跌倒警報音效：救護車雙音（來源檔 `assets/sounds/emergency_siren.wav`）。
  /// `flutter_local_notifications` 的 `RawResourceAndroidNotificationSound` 讀的是
  /// Android 原生 `res/raw/` 資源、**不是** Flutter assets（兩者是不同的檔案系統），
  /// 因此同一支音檔已另外複製一份到
  /// `android/app/src/main/res/raw/emergency_siren.wav`（資源名稱不含副檔名）。
  /// 搭配 `AudioAttributesUsage.alarm`，音量才會走「鬧鐘」音量軌——Android 預設的
  /// 勿擾模式對「鬧鐘」類別是放行的，NOTIFICATION 音軌則會被勿擾模式直接靜音。
  static const AndroidNotificationSound _sirenSound =
      RawResourceAndroidNotificationSound('emergency_siren');

  static Future<void> _ensureInit() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);

    // ★ 2026-08-20：channel 的建立／刪除（含 v1/v2 legacy id 的清理）已全部改由
    //   原生 `MainActivity.kt::ensureAlertChannel()` 負責，這裡只問一次「目前
    //   實際存在、該送去哪個 channel id」，不再自己呼叫
    //   createNotificationChannel／deleteNotificationChannel（原因見上方
    //   [_notificationPolicyChannel] 註解：bypassDnd 只在 channel 建立當下持有
    //   權限才生效、且 channel 建立後不可變，只有原生能精準抓到授權狀態變化的
    //   時機）。
    //
    // ★ 2026-08-20（追加修正）：純背景冷啟動讀不到 MethodChannel 的致命缺口。
    //   問題鏈：FCM 把整個被殺掉的 APP 進程叫醒時，用的是 Firebase 另外建立的
    //   headless FlutterEngine，這個 engine **不會**跑過
    //   `MainActivity.configureFlutterEngine()`（那只在有畫面的 Activity 附掛
    //   engine 時才執行），所以手動註冊的 [_notificationPolicyChannel] 在這個
    //   engine 上根本不存在，invokeMethod 必定丟 MissingPluginException。
    //   若這時只回退硬編碼的 [_fallbackChannelId]（無 bypass 版本），後果不是
    //   「單純沒有 bypass」：`ensureAlertChannel()` 在已取得 DND 權限時，會把
    //   [_fallbackChannelId] 那個 channel **明確刪掉**，所以背景這裡會讓
    //   `flutter_local_notifications` 找不到該 channel、依
    //   [AndroidNotificationDetails] 的欄位**重新生出一個沒有 bypassDnd 的
    //   同名 channel**——等於在「手機收在口袋、螢幕關閉、APP 被殺、長輩跌倒」
    //   這個本功能存在的核心情境下，親手把原生剛刪掉的非繞過版 channel 復活，
    //   警報改送到那個新生 channel，完全繞不過勿擾模式。
    //
    //   修法：不試圖讓原生直接寫 Android 原生 SharedPreferences 檔案給 Dart
    //   讀（`shared_preferences` 外掛在 Android 端的實際儲存檔名／key 前綴等
    //   編碼細節會隨外掛版本演進，原生手動對齊容易悄悄壞掉、且這個環境難以
    //   實機驗證），改成「Dart 自己寫、Dart 自己讀」：每次在前景成功問到原生
    //   結果，就順手把結果寫進 [_activeChannelPrefsKey]。這條路徑的可靠性
    //   已經在 `local_call_notification.dart`（`_persistTapAsAccepted` /
    //   `_handleDecline`）驗證過——`shared_preferences` 是正牌 pub.dev 外掛，
    //   會透過 `GeneratedPluginRegistrant` 註冊到「每一個」FlutterEngine
    //   （含 headless 背景那個），只要背景 isolate 先跑過
    //   `WidgetsFlutterBinding.ensureInitialized()` +
    //   `DartPluginRegistrant.ensureInitialized()`（[show] 已經在呼叫
    //   `_ensureInit()` 之前做了），`SharedPreferences.getInstance()` 就讀寫
    //   得到，不像 [_notificationPolicyChannel] 那樣只活在前景 engine。
    //   channel id 解析順序因此變成三層：
    //     (1) MethodChannel 問得到 → 用最新結果，並寫回 [_activeChannelPrefsKey]
    //         供之後的背景冷啟動使用；
    //     (2) MethodChannel 問不到（典型情況：背景冷啟動）→ 讀
    //         [_activeChannelPrefsKey] 裡「上一次前景執行留下的紀錄」——channel
    //         本身在系統裡是持久的，一旦原生建立過就會一直存在，因此只要
    //         「讀到 id」就等於「那個 channel 還在」，不需要重新建立；
    //     (3) 連快取都沒有（例如剛授權完 DND 就立刻被殺、從未真正前景執行過
    //         一次 ensureAlertChannel）→ 才退回硬編碼的 [_fallbackChannelId]。
    //
    //   誠實的殘留限制：如果使用者「從未」在授予 DND 權限後開過一次 APP，
    //   系統裡就真的還沒有任何 DND 版本的 channel 存在，這種情況下背景警報
    //   本來就不可能繞過勿擾模式——這是 Android「channel 建立當下才判定
    //   bypassDnd」與「channel 不可變」兩條規則疊加的先天限制，不是程式碼能
    //   繞過的問題。家屬設定頁引導使用者去開權限的那個當下，會觸發一次
    //   onResume → ensureAlertChannel，正常使用流程下不會踩到這個缺口。
    try {
      final result = await _notificationPolicyChannel.invokeMethod<String>(
        'ensureAlertChannel',
      );
      if (result != null && result.isNotEmpty) {
        _channelId = result;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_activeChannelPrefsKey, result);
        } catch (e) {
          debugPrint('⚠️ [CctvAlertNotif] 寫入 channel id 快取失敗（忽略）: $e');
        }
      }
    } catch (e) {
      debugPrint('⚠️ [CctvAlertNotif] 取得原生 channel id 失敗（可能是背景 isolate），改讀取上次前景留下的快取: $e');
      try {
        final prefs = await SharedPreferences.getInstance();
        final cached = prefs.getString(_activeChannelPrefsKey);
        _channelId = (cached != null && cached.isNotEmpty)
            ? cached
            : _fallbackChannelId;
      } catch (e2) {
        debugPrint('⚠️ [CctvAlertNotif] 讀取 channel id 快取也失敗，退回無 DND 版本: $e2');
        _channelId = _fallbackChannelId;
      }
    }

    _initialized = true;
  }

  /// 顯示跌倒警報通知。**會直接從 FCM 背景 isolate 呼叫**（見 C-6：
  /// `CctvAlertNotification.show(message.data)`），故比照
  /// `local_call_notification.dart::notificationBackgroundTapHandler` 的做法，
  /// 呼叫外部套件前先確保 binding 初始化，避免 MissingPluginException。
  ///
  /// [data] 直接吃 FCM 的 `message.data`（`Map<String, dynamic>`）。後端
  /// （`yolo_alert_dispatcher.py`）自 2026-08-20 起會送 `elderName`
  /// （查 `elder_profile.elder_name`，查無或例外時後端已自行退回 `elderId` 字串，
  /// 故正常情況下這個鍵一定存在、不會是空字串）。這裡仍保留
  /// `elderName → elderId → 「長輩」` 三層退回鏈，是為了相容尚未帶
  /// `elderName` 欄位的舊版後端／舊快取訊息，不是死碼。
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
        sound: _sirenSound,
        audioAttributesUsage: AudioAttributesUsage.alarm,
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
