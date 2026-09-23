import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'elder_tabs/elder_home_tab.dart';
import 'friends_screen.dart';
import 'elder_community_screen.dart';
import 'elder_chat_screen.dart';
import 'elder_tabs/elder_profile_tab.dart';
import '../globals.dart';
import '../theme/app_theme.dart'; // ElderScale：長輩端字級慣例（第五十輪來電通知放大用）
import 'elder_screen.dart';
import 'emergency_permission_guide_screen.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:convert';
import '../services/signaling.dart';
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import '../widgets/google_assistant_overlay.dart';
import '../widgets/global_assistant_button.dart';
// ★ 第四十輪（item 4）：onCancelCall 現在也要關備援本機通知，見下方說明。
import '../services/local_call_notification.dart';
// ★ 第四十一輪（item 2）：步驟式高光新手指引元件。
import '../widgets/spotlight_tutorial.dart';
// ⏰ 排程提醒管理器
import '../services/elder_reminder_manager.dart';
import '../services/local_reminder_notification.dart';
import '../widgets/heartbeat_overlay.dart';
import 'package:intl/intl.dart';
import '../services/care_message_store.dart';

/// ★ 第四十輪（item 4）：取消來電時清除待處理通話 prefs 的共用邏輯。
/// 與 `main.dart::_clearPendingCallPrefsOnCancel` 同一邏輯（該函式對本檔
/// library-private，無法跨檔重用，故在此複製一份，比照專案既有的「同一段
/// 三鍵清除邏輯在多處各自複製一份」慣例，見 `CLAUDE_call-monitor.md` §3.4）。
/// 不論 callId 是否吻合都無條件清除——裝置同一時間只會有一通待處理來電。
Future<void> _clearPendingCallPrefsOnCancel() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pendingAcceptedCall');
    await prefs.remove('pendingRingCallData');
    await prefs.remove('pendingRingCall');
  } catch (_) {}
}

class ElderHomeScreen extends StatefulWidget {
  final int userId;
  final String userName;
  final String? roomId;

  const ElderHomeScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.roomId,
  });

  @override
  State<ElderHomeScreen> createState() => _ElderHomeScreenState();
}

class _ElderHomeScreenState extends State<ElderHomeScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0; // 0:首頁 1:電話 2:社群 3:聊天 4:我的

  bool _isNavigatingToCall = false;

  // Google / Uban 助理與全域語音喚醒設定
  String _aiName = '嘎蛙';
  String _userName = '宇璿';
  final SpeechToText _wakeWordStt = SpeechToText();
  bool _wakeWordListening = false;
  bool _isAssistantShowing = false;

  // ★ 第四十一輪（item 2）：新手指引用的高光目標 GlobalKey。
  //   全部由本畫面（IndexedStack 的父層）持有並往下傳給各分頁——
  //   IndexedStack 會讓五個分頁的 initState 在本畫面第一次建構時就全部跑過
  //   一次（保活），無法用各分頁自己的 initState 偵測「使用者第一次切過
  //   來」，因此「第一次切到哪個分頁」的判斷邏輯與對應的 key 都集中在這裡，
  //   詳見 _onNavTap / _maybeShowTabTutorial。
  final List<GlobalKey> _navItemKeys = List.generate(5, (_) => GlobalKey());
  // 首頁分頁
  final GlobalKey _homeDateCardKey = GlobalKey();
  final GlobalKey _homeNewsCardKey = GlobalKey();
  final GlobalKey _homeMoreNewsKey = GlobalKey();
  // 電話分頁
  final GlobalKey _phoneTabBarKey = GlobalKey();
  final GlobalKey _phoneCallKey = GlobalKey();
  final GlobalKey _phoneVideoKey = GlobalKey();
  // 社群分頁
  final GlobalKey _communityPrivacyKey = GlobalKey();
  final GlobalKey _communityCreatePostKey = GlobalKey();
  final GlobalKey _communityLikeKey = GlobalKey();
  final GlobalKey _communityCommentKey = GlobalKey();
  // 聊天分頁
  final GlobalKey _chatVoiceToggleKey = GlobalKey();
  final GlobalKey _chatInputAreaKey = GlobalKey();
  final GlobalKey _chatLanguageToggleKey = GlobalKey();
  // 我的分頁
  final GlobalKey _profilePetKey = GlobalKey();
  final GlobalKey _profileTasksKey = GlobalKey();
  final GlobalKey _profileFamilyPairingKey = GlobalKey();
  final GlobalKey _profileAiAssistantKey = GlobalKey();

  /// 本次畫面存活期間，已經嘗試顯示過教學的分頁 index。
  /// 只避免同一個 session 內因快速連續切換而重複呼叫；「使用者是否真的看過
  /// 教學」這個跨 session 的持久判斷，交給 SpotlightTutorial 內部的
  /// SharedPreferences 完成旗標。
  final Set<int> _tabTutorialAttempted = {};


  Future<void> _requestPermissions() async {
    try {
      await [
        Permission.systemAlertWindow,
        Permission.notification,
      ].request();
    } catch (_) {}
    // ★ 2026-07-22 第十一輪 Fix 2：Android 14+ 全螢幕來電需特殊權限
    //   USE_FULL_SCREEN_INTENT，MIUI 常預設關閉 → CallKit / 備援通知的全螢幕來電
    //   無法彈出。用套件 API 檢查+引導（原生層自帶版本判斷，Android 13- 恆 true、
    //   requestFullIntentPermission 安全略過，故跨版本通用）。
    try {
      final canUse = await FlutterCallkitIncoming.canUseFullScreenIntent();
      if (canUse == false && mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Row(children: [
              Icon(Icons.phone_in_talk, color: Colors.green),
              SizedBox(width: 10),
              Text('開啟來電顯示'),
            ]),
            content: const Text(
              '為確保手機休眠或 App 關閉時仍能收到家人的視訊來電，\n'
              '請在接下來的設定頁面開啟「全螢幕通知」權限。',
              style: TextStyle(fontSize: 16),
            ),
            actions: [
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  try {
                    await FlutterCallkitIncoming.requestFullIntentPermission();
                  } catch (_) {}
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text('前往設定'),
              ),
            ],
          ),
        );
      }
    } catch (_) {}
  }

  /// ★ 2026-08-20 新增：長輩端首次進入首頁時，若偵測到是 MIUI 家族裝置，自動
  /// 導向「鎖屏與背景權限設定」引導頁（`EmergencyPermissionGuideScreen`）一次。
  ///
  /// 為什麼放在這裡（而不是 splash_screen.dart 或 main.dart）：本專案有多輪
  /// 因為在冷啟動路徑加東西而導致白屏／無法撥打的故障史（見
  /// CLAUDE_call-monitor.md §8 第二十一輪），因此刻意放在「已經到達穩定首頁」
  /// 之後才觸發，且用 addPostFrameCallback 確保第一影格已經畫出、Navigator
  /// 已經就緒，不影響任何既有的通話／來電／冷啟動判斷邏輯——呼叫本身也完全
  /// 不 await，不會拖慢 initState 或擋住其他初始化流程。
  ///
  /// 家屬端有對稱的觸發點：`family_main_screen.dart::_maybeShowMiuiPermissionGuide`
  /// （2026-08-20 補上，見該檔說明），兩邊共用同一個 `prefsSeenKey`，任一端顯示
  /// 過一次後另一端就不會再自動彈。家屬端另外還能從「設定 → 緊急通知權限」
  /// 手動再次開啟同一個畫面（見 `family_settings_view.dart`）。
  ///
  /// 任何一步失敗（SharedPreferences 不可用、MethodChannel 未實作／拋例外）都
  /// 直接 return，不顯示引導頁——APP 其餘行為與目前版本完全相同，不會因為這個
  /// 新功能而多出任何啟動風險。
  Future<void> _maybeShowMiuiPermissionGuide() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alreadySeen =
          prefs.getBool(EmergencyPermissionGuideScreen.prefsSeenKey) ?? false;
      if (alreadySeen) return;

      final isMiui = await const MethodChannel(
        'com.example.app/notification_policy',
      ).invokeMethod<bool>('isMiuiFamily');
      if (isMiui != true) return;

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const EmergencyPermissionGuideScreen(),
        ),
      );
    } catch (_) {
      // 靜默失敗：不顯示引導頁，APP 其餘行為不受影響。
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    isAppReady = true;
    _requestPermissions();
    _loadAssistantSettings();

    // ★ 核心修復：強制使用長輩的專屬配對房間號 (elder_id)，且帶有 comm_elder_ 字首，確保與後端格式及權限匹配
    final String rawRoomId = widget.roomId ?? widget.userId.toString();
    final String roomToJoin = rawRoomId.startsWith('comm_elder_') ||
            rawRoomId.startsWith('monitor_elder_')
        ? rawRoomId
        : 'comm_elder_$rawRoomId';
    _connectSocket(roomToJoin);

    pendingAcceptedCall.addListener(_onPendingCallChanged);
    isMediaPlayingNotifier.addListener(_onMediaPlayingChanged);
    // ★ 2026-09-22 第五十一輪（長5）：把本畫面的助理啟動流程登記為全域啟動器，
    //   讓掛在 MaterialApp.builder 的浮動麥克風鈕在**任何**畫面上都能叫出小嘎。
    //   刻意共用同一個方法而不是複製一份——喚醒詞暫停、畫面情境注入、
    //   autoCall 撥號接手都只有這一份實作。本畫面在推出去的路由底下仍然
    //   mounted，`context` 也仍然有效，彈出的 bottom sheet 走的是同一個
    //   root Navigator，所以會蓋在當前畫面之上。
    elderAssistantLauncherNotifier.value = _triggerGoogleAssistantOverlay;
    // ★ 2026-08-10 第二十輪（需求 6）：語音喚醒總開關的即時生效。
    wakeWordEnabledNotifier.addListener(_onWakeWordEnabledChanged);
    // 檢查是否有在背景接聽的通話初始化前就傳入的待接聽電話
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _onPendingCallChanged();
    });

    // 監聽來自親人的呼叫與推播留言
    _restoreSignalingCallbacks();

    // ★ ⏰ 註冊前景 context 取得器並啟動長輩端排程提醒守護（在線彈窗＋離線定時看門狗）
    ElderReminderManager.instance.setContextGetter(() => mounted ? context : null);
    ElderReminderManager.instance.start(
      userId: widget.userId,
      userName: widget.userName,
    );

    // ★ 2026-08-20 新增：MIUI 家族裝置的「鎖定螢幕顯示／後台彈出介面」權限
    //   引導。等第一影格畫出後才檢查與導航（此時 Navigator 已就緒），且完全
    //   不 await、不擋任何既有的啟動流程；詳見 _maybeShowMiuiPermissionGuide。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _maybeShowMiuiPermissionGuide();
      // ★ ⏰ 檢查是否由點擊排程提醒通知啟動
      final launchReminder = await LocalReminderNotification.consumeLaunchPayload();
      if (launchReminder != null && mounted) {
        ElderReminderManager.instance.handleIncomingReminder(launchReminder, force: true);
      }
    });

    // ★ 第四十一輪（item 2）：主介面（五個底部標籤）的新手指引，長輩第一次
    //   進入首頁就會看到。獨立一個 addPostFrameCallback（不與上面的 MIUI
    //   引導共用），且內部一律先確認沒有來電才會顯示——見
    //   _maybeShowMainTutorial 的說明。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowMainTutorial();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint('📱 [WakeWord Emergency Protection] 系統狀態改變: $state - 保持全時背景與休眠緊急喚醒監聽');
    // ★ 2026-08-10 第二十輪（需求 6）：關閉語音喚醒時，生命週期變化不再重啟麥克風。
    if (!wakeWordEnabledNotifier.value) return;
    if (mounted && !_isAssistantShowing && !_wakeWordListening) {
      _safeRestartWakeWordListening('lifecycle');
    }
  }

  Future<void> _loadAssistantSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          final savedUserName = prefs.getString('caregiver_name') ??
              prefs.getString('user_name') ??
              prefs.getString('elder_name');
          if (savedUserName != null && savedUserName.isNotEmpty) {
            _userName = savedUserName;
          } else if (widget.userName.isNotEmpty) {
            _userName = widget.userName;
          } else {
            _userName = '宇璿';
          }

          _aiName = prefs.getString('ai_assistant_name') ??
              prefs.getString('ai_name') ??
              '嘎蛙';
        });
      }
      // 🚨 2026-09-23 第五十二輪：喚醒詞遷移補在冷啟動路徑（與
      //   ai_assistant_settings_dialog.dart 共用同一把版本化旗標鍵
      //   wake_word_pref_reset_v52）。第五十一輪之前的版本會在「每次載入
      //   首頁」時把 kWakeWordEnabledKey 強制寫成 true（不是使用者的選
      //   擇），而使用者的裝置多半從未打開過 AI 語音助理設定頁，只在那邊
      //   遷移救不到這些裝置——必須在下面讀取 kWakeWordEnabledKey **之
      //   前**先跑同一套遷移，否則這次啟動仍會讀到舊值。旗標不存在 →
      //   這是第一次套用本次遷移，把鍵強制拉回 false 並寫入旗標；旗標
      //   一旦存在，代表使用者之後自己的開關選擇（不論開或關）都不會
      //   再被本遷移覆蓋。
      const wakeWordMigrationFlagKey = 'wake_word_pref_reset_v52';
      if (!(prefs.getBool(wakeWordMigrationFlagKey) ?? false)) {
        await prefs.setBool(kWakeWordEnabledKey, false);
        await prefs.setBool(wakeWordMigrationFlagKey, true);
      }
      // ★ 護欄 G59：語音喚醒預設「關閉」，且只讀不寫。
      //   這裡以前會在讀到 false 時強制寫回 true，等於長輩在個人資料頁關掉麥克風，
      //   下次進首頁又被打開（麥克風無限開開關關）。開關唯一的寫入點是
      //   `elder_tabs/elder_profile_tab.dart`。
      final bool wakeWordEnabled = prefs.getBool(kWakeWordEnabledKey) ?? false;
      wakeWordEnabledNotifier.value = wakeWordEnabled;
      _initWakeWordListener();

      // ★ 載入這位長輩既有的主動關懷訊息，讓「小嘎說過的話」在重開 App
      //   之後仍查得到。
      await CareMessageStore.instance.load(widget.userId);
    } catch (e) {
      debugPrint('🤖 [_loadAssistantSettings Error] $e');
    }
  }

  /// ★ 2026-08-10 第二十輪（需求 6）：設定頁切換總開關時即時生效，不必重開 App。
  void _onWakeWordEnabledChanged() {
    if (!mounted) return;
    if (wakeWordEnabledNotifier.value) {
      debugPrint('🎙️ [WakeWord] 使用者啟用語音喚醒，開始初始化');
      _initWakeWordListener();
    } else {
      debugPrint('🔇 [WakeWord] 使用者關閉語音喚醒，停止監聽並取消看門狗');
      _wakeWordWatchdogTimer?.cancel();
      _wakeWordWatchdogTimer = null;
      _wakeWordListening = false;
      try {
        _wakeWordStt.cancel();
      } catch (e) {
        debugPrint('⚠️ [WakeWord] 停止監聽失敗（忽略）: $e');
      }
    }
  }

  String? _preferredLocaleId;
  Timer? _wakeWordWatchdogTimer;
  bool _isStartingListen = false;

  Future<void> _initWakeWordListener() async {
    // ★ 2026-08-10 第二十輪（需求 6）：總開關關閉時完全不啟動語音喚醒。
    //   注意這裡連 `Permission.microphone.request()` 都不呼叫——那個請求本身
    //   就會讓系統把麥克風標記為使用中，是「打開 App 就一直開關麥克風」
    //   使用者觀感的一部分。
    if (!wakeWordEnabledNotifier.value) {
      debugPrint('🔇 [WakeWord] 語音喚醒已關閉（wake_word_enabled=false），不初始化監聽');
      return;
    }
    try {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        debugPrint('🎙️ [WakeWord] 麥克風權限未授予');
        return;
      }

      bool available = await _wakeWordStt.initialize(
        onError: (val) {
          debugPrint('🤖 [WakeWord Error] $val');
          if (mounted && !_isAssistantShowing && !_isStartingListen) {
            _wakeWordListening = false;
            Future.delayed(const Duration(milliseconds: 600), () {
              if (mounted) _safeRestartWakeWordListening('onError');
            });
          }
        },
        onStatus: (status) {
          debugPrint('🤖 [WakeWord Status] $status');
          if ((status == 'done' || status == 'notListening') && mounted) {
            _wakeWordListening = false;
            if (!_isAssistantShowing && !_isStartingListen) {
              Future.delayed(const Duration(milliseconds: 400), () {
                if (mounted) _safeRestartWakeWordListening('onStatus');
              });
            }
          }
        },
      );

      if (available) {
        final systemLoc = await _wakeWordStt.systemLocale();
        _preferredLocaleId = systemLoc?.localeId ?? 'zh_TW';
        debugPrint('🎙️ [WakeWord Locale] 使用系統適配語系: $_preferredLocaleId');

        if (mounted) {
          _safeRestartWakeWordListening('init');
          _startWakeWordWatchdog();
        }
      }
    } catch (e) {
      debugPrint('🤖 [WakeWord Init Failed] $e');
      _wakeWordListening = false;
    }
  }

  void _onMediaPlayingChanged() {
    if (!mounted) return;
    if (isMediaPlayingNotifier.value) {
      debugPrint('🛑 [WakeWord Listener] 全域媒體播放中 → 暫停背景喚醒');
      _wakeWordStt.stop();
      _wakeWordListening = false;
    } else {
      debugPrint('▶️ [WakeWord Listener] 全域媒體播放結束 → 恢復背景喚醒');
      _safeRestartWakeWordListening('media_stopped');
    }
  }

  /// 🐕 看門狗定時器：每 5 秒安全協調檢查，防止併發競態死鎖
  void _startWakeWordWatchdog() {
    _wakeWordWatchdogTimer?.cancel();
    // ★ 2026-08-10 第二十輪（需求 6）：關閉時不啟動看門狗（第二道閘門）。
    if (!wakeWordEnabledNotifier.value) return;
    _wakeWordWatchdogTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted && !isMediaPlayingNotifier.value && !_isAssistantShowing && !_isStartingListen && !_wakeWordStt.isListening) {
        debugPrint('🐕 [WakeWord Watchdog] 檢測到語音監聽完全停止，觸發安全重啟...');
        _safeRestartWakeWordListening('Watchdog');
      }
    });
  }

  /// 🛡️ 安全重啟協調器：帶有 Re-entrancy 互斥鎖與 Android cancel() 防併發死鎖
  Future<void> _safeRestartWakeWordListening([String reason = '']) async {
    // ★ 2026-08-10 第二十輪（需求 6）：總開關是所有重啟路徑的共同閘門。
    //   這個函式有五個呼叫端（init / onError / onStatus / 看門狗 / lifecycle /
    //   媒體播放結束），漏掉任何一個都會讓麥克風又自己開起來，
    //   所以閘門放在這裡而不是放在各呼叫端。
    if (!wakeWordEnabledNotifier.value) return;
    if (isMediaPlayingNotifier.value || _isAssistantShowing || _isStartingListen || !mounted) {
      if (isMediaPlayingNotifier.value) {
        debugPrint('🛑 [WakeWord] 檢測到媒體正在播放中，暫停背景語音喚醒監聽 (觸發源: $reason)');
        if (_wakeWordStt.isListening) {
          _wakeWordStt.stop();
          _wakeWordListening = false;
        }
      }
      return;
    }
    _isStartingListen = true;

    try {
      debugPrint('🎙️ [WakeWord SafeRestart] 正在重啟監聽 (觸發源: $reason)...');

      if (_wakeWordStt.isListening) {
        await _wakeWordStt.cancel();
        await Future.delayed(const Duration(milliseconds: 300));
      }

      if (_isAssistantShowing || !mounted) {
        _isStartingListen = false;
        return;
      }

      _wakeWordListening = true;
      await _wakeWordStt.listen(
        localeId: _preferredLocaleId ?? 'zh_TW',
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
        ),
        listenFor: const Duration(hours: 1),
        pauseFor: const Duration(seconds: 60),
        onResult: (result) {
          final text = result.recognizedWords;
          debugPrint('🎙️ [WakeWord Recognized] "$text" (Target AI: $_aiName)');

          if (_isDynamicWakeWordMatch(text, _aiName)) {
            debugPrint('🎯 [WakeWord Match Success!] 觸發 AI 助理 (識別內容: "$text")');
            _triggerGoogleAssistantOverlay(text);
          }
        },
      );
    } catch (e) {
      debugPrint('🎙️ [WakeWord Listen Exception] $e');
      _wakeWordListening = false;
    } finally {
      _isStartingListen = false;
    }
  }

  /// 動態喚醒詞比對算法：準確覆蓋所有中文 ASR 轉錄同音字與「Hey 嘎蛙/嘎挖」喚醒詞
  bool _isDynamicWakeWordMatch(String text, String customAiName) {
    final lowerText = text
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[，,。！!？?\.]'), '');
    final lowerAi = customAiName.toLowerCase().trim();

    // 1. 完整包含自訂 AI 名稱（長度 >= 2）
    if (lowerAi.length >= 2 && lowerText.contains(lowerAi)) return true;

    // 2. 嘎蛙/嘎挖 精準同音字與常見 ASR 變體
    const targetVariants = [
      '嘎蛙', '嘎挖', '嘎娃', '嘎哇', '嘎話', '嘎花',
      'gawa', 'gawha',
      '小嘎', '小蛙', '小嘎蛙',
      'hey嘎', '嘿嘎', '嗨嘎', '黑嘎', 'hi嘎', '哈囉嘎', '呼叫嘎'
    ];

    for (final variant in targetVariants) {
      if (lowerText.contains(variant)) return true;
    }

    return false;
  }

  /// 從喚醒詞語句中提取出使用者的實際問題（若只叫喚醒詞則返回 null）
  String? _extractUserQuery(String? rawText, String customAiName) {
    if (rawText == null || rawText.trim().isEmpty) return null;
    String text = rawText.trim();

    // 移除常見前綴詞 (hey, 嘿, 嗨, hi, hello, 哈囉, 呼叫, 喂, 黑)
    final prefixes = ['hey', 'hi', 'hello', '哈囉', '呼叫', '嘿', '嗨', '黑', '喂'];
    for (final p in prefixes) {
      if (text.toLowerCase().startsWith(p)) {
        text = text.substring(p.length).trim();
      }
    }

    // 移除 AI 助理名稱與變體 (嘎蛙, 嘎挖, 嘎娃, 嘎哇, gawa, customAiName 等)
    final aiVariants = [
      customAiName.toLowerCase(),
      '嘎蛙', '嘎挖', '嘎娃', '嘎哇', '嘎話', '嘎花', 'gawa', 'gawha', '小嘎', '小蛙', '小嘎蛙', '嘎'
    ];
    for (final v in aiVariants) {
      if (v.isNotEmpty && text.toLowerCase().startsWith(v)) {
        text = text.substring(v.length).trim();
      }
    }

    // 移除開頭標點符號與空白
    text = text.replaceAll(RegExp(r'^[，,。！!？?\s]+'), '').trim();

    // 若剩餘字串過短或為空，表示長輩只是呼叫喚醒詞，並未包含問題
    if (text.length <= 1) {
      return null;
    }
    return text;
  }

  /// 視覺情境感知：獲取長輩當前所在分頁的詳細脈絡，傳給小嘎助理
  String _getCurrentTabContext() {
    switch (_selectedIndex) {
      case 0:
        return '【首頁】。頁面上包含：「今日天氣（氣溫與降雨機率）與農民曆卡片」、「今日吃藥打卡按鈕（大字綠色打卡）」、以及「今日精選頭條新聞與語音播放」';
      case 1:
        return '【電話】分頁。頁面上列出長輩的家人與親友聯絡人卡片，點擊可直接撥打視訊或電話給老伴或子女';
      case 2:
        return '【社群】分頁。頁面上顯示親朋好友最近發布的生活動態照片與生活打卡，長輩可以瀏覽並點愛心打招呼';
      case 3:
        return '【聊天】分頁。這裡是長輩與您（AI 伴侶小嘎）一對一的語音文字聊天室，長輩可以向您傾訴心情、回憶過去或詢問生活';
      case 4:
        return '【我的／小豬之家】分頁。頁面上是一隻可愛粉紅的元氣小豬夥伴，中間有金黃色「餵小豬」大按鈕，並顯示成長階段與活力，下方有今日生活排程與用藥進度';
      default:
        return '【主功能頁面】';
    }
  }

  void _triggerGoogleAssistantOverlay([String? prompt]) async {
    if (_isAssistantShowing) return;
    _isAssistantShowing = true;
    try {
      await _wakeWordStt.cancel();
    } catch (_) {
      try {
        _wakeWordStt.stop();
      } catch (_) {}
    }
    _wakeWordListening = false;
    await Future.delayed(const Duration(milliseconds: 200));

    String? cleanedPrompt = _extractUserQuery(prompt, _aiName);

    // ★ 核心升級：若提問涉及「畫面/怎麼用/這是哪裡」，主動注入當前可見的 UI Context，讓小嘎睜開眼睛！
    final tabCtx = _getCurrentTabContext();
    if (cleanedPrompt != null && cleanedPrompt.isNotEmpty) {
      if (cleanedPrompt.contains('怎麼用') ||
          cleanedPrompt.contains('這是') ||
          cleanedPrompt.contains('操作') ||
          cleanedPrompt.contains('功能') ||
          cleanedPrompt.contains('做什麼')) {
        cleanedPrompt = '長輩目前正在 $tabCtx。長輩提問：$cleanedPrompt。請用親切溫暖的台語或國語，具體介紹這個畫面的主要功能，並指引長輩下一步可以點擊哪裡。';
      }
    }

    debugPrint('🎯 [Assistant Launch] rawPrompt="$prompt", enrichedPrompt="$cleanedPrompt"');

    if (!mounted) return;

    final assistantResult = await GoogleAssistantOverlay.show(
      context,
      userName: _userName,
      aiName: _aiName,
      userId: widget.userId,
      initialPrompt: cleanedPrompt,
    );

    if (mounted) {
      setState(() {
        _isAssistantShowing = false;
      });
      // 延遲重啟語音喚醒，防止搶奪音訊
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) _safeRestartWakeWordListening('overlay_closed');
      });
    }

    // ★ 第四十九輪 item 8：長輩說「幫我打電話／視訊給家人／好友」時，
    //   GoogleAssistantOverlay 已經念完確認語並帶出撥號請求，這裡接手實際
    //   撥出——完全比照 friends_screen.dart::_startCall() /
    //   _startFriendCall() 的既有配方，透過建構 ElderScreen(autoCall:true,
    //   ...) 完成，不呼叫 Signaling() 任何方法。`friendElderId` 有值時
    //   （後端 tools_service.py::initiate_video_call 已在真實好友清單裡唯一
    //   定位到對象）走好友通話（進對方房間、指定對象）；為 null 時走家人
    //   通話（整戶已綁定家屬的手機一起響，不支援指定某一位）——兩者都是
    //   ElderScreen 既有支援的公開建構參數，本檔沒有新增或修改該檔任何邏輯。
    if (mounted && assistantResult != null && assistantResult['autoCall'] == true) {
      String? roomId;
      try {
        final prefs = await SharedPreferences.getInstance();
        roomId = prefs.getString('elder_room_id')?.trim();
      } catch (e) {
        debugPrint('⚠️ [ElderHomeScreen] 讀取 elder_room_id 失敗: $e');
      }
      if (!mounted) return;
      if (roomId == null || roomId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('找不到您的通話帳號資料，請重新登入後再試')),
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ElderScreen(
              roomId: roomId!,
              friendCallTargetElderId: assistantResult['friendElderId'] as String?,
              deviceName: _userName,
              autoCall: true,
              isVideoCall: assistantResult['isVideo'] == true,
            ),
          ),
        );
      }
    }
  }

  // ★ G102（CLAUDE_call-monitor-guardrails.md）：`Signaling` 單例的回呼欄位只
  // 有一份，最後賦值者獨佔。本方法會被呼叫**多次**（initState、以及從
  // ElderScreen 返回的兩處 `.then()`），每次都要更新這些欄位，讓它們永遠
  // 代表「我最後一次指派的那一份」——`dispose()` 才能用 `identical()` 比對
  // 出單例上掛的是不是還是本畫面的閉包，而不是本畫面更早一次指派、後來又
  // 被自己蓋掉的舊閉包。
  CallRequestCallback? _ownCallRequest;
  CallRequestCallback? _ownCancelCall;
  Function(String message)? _ownHeartbeatMessage;
  Function(dynamic data)? _ownElderQuestionAnswered;
  void Function(Map<String, dynamic>)? _ownRemoteReminder;
  void Function(Map<String, dynamic>)? _ownReminderSync;

  void _restoreSignalingCallbacks() {
    debugPrint("🔄 [ElderHomeScreen] 重新綁定 Signaling Callbacks");
    // 監聽來自家屬的來電請求
    _ownCallRequest = (roomId, senderId, callId, [senderName]) {
      if (!mounted) return;
      _showIncomingCallDialog(roomId, senderId, callId);
    };
    Signaling().onCallRequest = _ownCallRequest;
    // ★ issue 4 fix: 監聽家屬取消來電，關閉彈窗
    // ★ 第四十輪（item 4）：`Signaling` 的回呼欄位只有一份，長輩停在本畫面時
    //   本檔這份會覆蓋 main.dart 的全域版本（見 CLAUDE_call-monitor.md §2.3），
    //   所以這裡也要補上同一份缺口——舊版只關 App 內彈窗，沒關 CallKit 來電
    //   畫面／備援本機通知，家屬撥打逾時取消後，長輩端可能還留著響鈴中的
    //   CallKit／備援通知。endAllCalls() 沿用 main.dart 既有 try/catch 慣例
    //   （MIUI 會拋 content-is-null）。
    _ownCancelCall = (roomId, senderId, callId, [senderName]) {
      if (!mounted) return;
      debugPrint('🔕 [ElderHomeScreen] 家屬取消來電，關閉彈窗');
      if (_isIncomingCallDialogOpen && Navigator.canPop(context)) {
        Navigator.of(context).pop();
        _isIncomingCallDialogOpen = false;
      }
      try {
        FlutterCallkitIncoming.endAllCalls();
      } catch (e) {
        debugPrint('⚠️ [ElderHomeScreen] endAllCalls 失敗（不影響）: $e');
      }
      unawaited(LocalCallNotification.cancel());
      unawaited(_clearPendingCallPrefsOnCancel());
    };
    Signaling().onCancelCall = _ownCancelCall;

    // 監聽家屬發送的主動關心留言 (Heartbeat)
    _ownHeartbeatMessage = (message) {
      if (mounted) {
        _handleProactiveMessage(message);
      }
    };
    Signaling().onHeartbeatMessage = _ownHeartbeatMessage;

    // 💬 子女回覆了長輩先前問小嘎、小嘎轉交出去的問題。
    //    做成一則關懷訊息：CareMessageStore 已經負責留存、首頁顯示對話框、
    //    聊天分頁接成小嘎的訊息，三個落點一次到位，不必另做一套。
    _ownElderQuestionAnswered = (data) {
      if (!mounted || data is! Map) return;
      final answer = (data['answer'] ?? '').toString().trim();
      if (answer.isEmpty) return;
      final question = (data['question'] ?? '').toString().trim();
      final text = question.isEmpty
          ? '家人回覆您了：$answer'
          : '您之前問的「$question」，家人回覆了：$answer';
      _handleProactiveMessage(jsonEncode({'reply': text, 'type': 'family'}));
    };
    Signaling().onElderQuestionAnswered = _ownElderQuestionAnswered;

    // ★ ⏰ 監聽排程提醒與同步信令
    _ownRemoteReminder = (data) {
      if (mounted) {
        debugPrint('⏰ [ElderHomeScreen] 收到 onRemoteReminder 信令: $data');
        ElderReminderManager.instance.handleIncomingReminder(data);
      }
    };
    Signaling().onRemoteReminder = _ownRemoteReminder;
    _ownReminderSync = (data) {
      if (mounted) {
        debugPrint('🔄 [ElderHomeScreen] 收到 onReminderSync 信令: $data');
        // ★ 2026-09-15：action='complete' 時把該筆寫進本機當日完成清單。
        //   「我的」分頁與首頁「下一包藥」讀的都是本機 completed_tasks_<date>，
        //   後端只寫 activity_log、UI 從來不讀。少了這段，透過提醒 API 或
        //   語音（「我吃過藥了」）完成的打卡，長輩畫面上永遠不會變。
        _applyRemoteReminderCompletion(data);
        ElderReminderManager.instance.syncReminders();
      }
    };
    Signaling().onReminderSync = _ownReminderSync;
  }

  /// 把遠端回報的「提醒已完成」寫入本機當日清單，與「我的」分頁的
  /// `_toggleTaskCompletion`、提醒彈窗使用同一個鍵，確保三條打卡路徑
  /// （清單點擊／提醒彈窗／對小嘎說「我吃過藥了」）看到同一個狀態。
  Future<void> _applyRemoteReminderCompletion(dynamic data) async {
    try {
      if (data is! Map) return;
      if ((data['action'] ?? '').toString() != 'complete') return;
      final rid = data['reminderId'];
      if (rid == null) return;

      final prefs = await SharedPreferences.getInstance();
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final key = 'completed_tasks_$today';
      final done = prefs.getStringList(key) ?? <String>[];
      final id = rid.toString();
      if (!done.contains(id)) {
        done.add(id);
        await prefs.setStringList(key, done);
        debugPrint('✅ [ElderHomeScreen] 遠端打卡已同步至本機清單: $id');
      }
    } catch (e) {
      debugPrint('⚠️ [ElderHomeScreen] 同步遠端打卡失敗: $e');
    }
  }

  bool _isIncomingCallDialogOpen = false;

  Future<void> _connectSocket(String roomToJoin) async {
    String? fcmToken;
    try {
      fcmToken = await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint("Error getting FCM token: $e");
    }

    Signaling().connect(
      roomToJoin,
      'elder',
      userId: widget.userId,
      deviceName: widget.userName,
      fcmToken: fcmToken,
    );
  }

  void _showIncomingCallDialog(String roomId, String senderId, String? callId) {
    if (_isIncomingCallDialogOpen) return;
    _isIncomingCallDialogOpen = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        // ★ 第五十一輪（長5）：來電響鈴畫面上，全域語音助理浮動鈕必須讓位，
        //   不可以擋到接聽／拒接鍵。
        return AssistantHiddenZone(
          child: AlertDialog(
          // ★ 第五十輪：長輩端「app 內來電通知」按鈕與文字放大 100%（需求 B）。
          //   只改字級／尺寸／間距等純視覺屬性，未動任何接聽/拒接邏輯或導航方式。
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16), // 8→16，跟著圖示等比放大
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.phone_in_talk,
                    color: Colors.green, size: 56), // 28→56（100%）
              ),
              const SizedBox(width: 24), // 12→24
              // 標題原本沒有 style（吃 AlertDialog 預設，約 22sp），這裡明確給一個
              // 放大後的樣式；沿用專案既有的 ElderScale.displayTitle（40sp）。
              // 包 Flexible + ellipsis：硬規則 14——同列還有圖示，長輩若把系統字級
              // 調更大，標題必須可收縮，否則會撐出 RenderFlex 溢位。
              Flexible(
                child: Text(
                  '家屬來電',
                  style: ElderScale.displayTitle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          // 內容文字 18→36（100%），沿用 ElderScale.body 當基底再覆寫字級；
          // 外面包 SingleChildScrollView：字放大後窄螢幕/小螢幕高度可能不夠，
          // 讓內容可捲動，避免溢位（硬規則 14）。
          content: SingleChildScrollView(
            child: Text(
              '您的家人正在呼叫您！',
              style: ElderScale.body.copyWith(fontSize: 36),
            ),
          ),
          backgroundColor: Colors.green.shade50,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          actions: [
            ElevatedButton.icon(
              onPressed: () {
                Signaling()
                    .sendCallBusy(senderId, callId: callId, room: roomId);
                Navigator.of(dialogContext).pop();
                _isIncomingCallDialogOpen = false;
              },
              icon: const Icon(Icons.call_end, size: ElderScale.buttonIcon), // 圖示跟著放大
              // 按鈕文字 16→32（100%），沿用 ElderScale.button 當基底再覆寫字級；
              // 包 Flexible + ellipsis：兩顆按鈕同列，字放大後必須可收縮，
              // 否則窄螢幕（如 320dp）會把 Row 撐爆、出現黃黑溢位條（硬規則 14）。
              label: Flexible(
                child: Text(
                  '拒接',
                  style: ElderScale.button.copyWith(fontSize: 32, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                // 20/12→40/24（100%），並保證最小點擊高度跟著放大，避免文字撐爆按鈕。
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                minimumSize: const Size(64, ElderScale.buttonHeight),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _isIncomingCallDialogOpen = false;

                // ★ 2026-08-17 第二十五輪（需求 1）：接聽用的房間號必須來自「這通來電
                //   實際送達的房間」，也就是本函式的 roomId 參數，而不是
                //   widget.roomId ?? widget.userId（widget.userId 是「使用者」ID，
                //   不是「長輩」ID，兩者常不同）。initState（見上方 :106-111）已對
                //   widget.roomId 做過同一套冪等正規化（補 comm_elder_ 前綴、不重複補），
                //   這裡必須套用相同正規化，否則 ElderScreen 會 join 到跟來電發起端
                //   對不上的房間——彈窗雖然接聽了，WebRTC 卻永遠連不上。
                //   只有 roomId 參數為空字串時才退回舊的 widget 表達式。
                final String rawAcceptRoomId = roomId.isNotEmpty
                    ? roomId
                    : (widget.roomId ?? widget.userId.toString());
                final String acceptRoomId = rawAcceptRoomId.startsWith('comm_elder_') ||
                        rawAcceptRoomId.startsWith('monitor_elder_')
                    ? rawAcceptRoomId
                    : 'comm_elder_$rawAcceptRoomId';

                // 接聽後跳轉到通話畫面
                Signaling().sendCallAccept(senderId, callId: callId);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ElderScreen(
                      roomId: acceptRoomId,
                      deviceName: widget.userName,
                      initialCallData: {
                        'roomId': acceptRoomId,
                        'senderId': senderId,
                        'callId': callId,
                        // ★ 2026-08-17 第二十五輪（需求 1）：isVideoCallRaw 在本檔從未定義
                        //   （flutter analyze 判為 compile error：Undefined name
                        //   'isVideoCallRaw'）——它只存在於 main.dart 的具名參數。正確作法
                        //   是向 Signaling 查詢這通來電當初登記的視訊旗標（callId 不吻合
                        //   或查無紀錄時安全預設為 true，見 signaling.dart:162）。
                        'isVideoCall': Signaling().isVideoCallFor(callId).toString(),
                      },
                    ),
                  ),
                ).then((_) {
                  // ★ 從 ElderScreen 退出時重新綁定 callbacks
                  if (mounted) {
                    _restoreSignalingCallbacks();
                  }
                });
              },
              icon: const Icon(Icons.videocam, size: ElderScale.buttonIcon), // 圖示跟著放大
              // 同上「拒接」按鈕的放大＋可收縮處理。
              label: Flexible(
                child: Text(
                  '接聽',
                  style: ElderScale.button.copyWith(fontSize: 32, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                minimumSize: const Size(64, ElderScale.buttonHeight),
              ),
            ),
          ],
          ),
        );
      },
    ).then((_) => _isIncomingCallDialogOpen = false);
  }

  final FlutterTts _flutterTts = FlutterTts();

  Future<void> _handleProactiveMessage(String message) async {
    String displayText = message;
    // ★ 2026-09-15：type 與 emotion 原本在首頁被整個丟掉（只有通話畫面會用），
    //   同一則關懷訊息在兩個畫面的呈現因此天差地遠。這裡一併解析出來。
    String type = 'chat';
    String emotion = 'caring';
    try {
      final data = jsonDecode(message);
      if (data is Map && data.containsKey('reply')) {
        displayText = data['reply'];
        type = (data['type'] ?? 'chat').toString();
        emotion = (data['emotion'] ?? 'caring').toString();
        // 檢查是否為禮物
        if (data['type'] == 'family_gift') {
          displayText = "嘎挖！大驚喜！🎁 子女給您送禮物來了：\n$displayText";
        }
      }
    } catch (e) {
      debugPrint("Home Heartbeat is plain text.");
    }

    // ★ 留存：先前首頁只朗讀、畫面什麼都不留。重聽長輩、手機靜音、或人不在
    //   旁邊時，關懷訊息完全遺失且無法回溯——沒有任何地方查得到「今天小嘎
    //   跟我說過什麼」。
    await CareMessageStore.instance
        .add(text: displayText, type: type, emotion: emotion);

    // ★ 視覺呈現：沿用通話畫面既有的 HeartbeatOverlay，不另做一套樣式。
    //   那個精美的毛玻璃對話框原本只掛在 elder_screen（長輩最少待的畫面）。
    if (mounted) {
      showDialog(
        context: context,
        barrierColor: Colors.black54,
        builder: (dialogCtx) => HeartbeatOverlay(
          message: displayText,
          type: type,
          emotion: emotion,
          onDismiss: () => Navigator.of(dialogCtx).pop(),
        ),
      );
    }

    // 1. 發出「豬叫」音效 (oink!) - 暫時用 TTS 模擬高頻短促音
    await _flutterTts.setLanguage("zh-TW");
    await _flutterTts.setPitch(2.0); // 極高音
    await _flutterTts.setSpeechRate(0.8);
    await _flutterTts.speak("喔！");

    // 5. 正式的語音朗讀
    await _flutterTts.setPitch(1.0); // 恢復正常音調
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.speak(displayText);
  }

  @override
  void dispose() {
    _wakeWordWatchdogTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _wakeWordStt.stop();
    isAppReady = false;
    pendingAcceptedCall.removeListener(_onPendingCallChanged);
    isMediaPlayingNotifier.removeListener(_onMediaPlayingChanged);
    // 與 G102 同樣的道理：只有自己仍是登記者時才清掉，避免把「接手畫面」
    //   剛登記好的啟動器誤清成 null（長輩端首頁重建時會前後重疊一瞬間）。
    // （用 `==` 不用 `identical`：Dart 只保證同一物件同一方法的 tear-off 相等，
    //   不保證是同一個實例。）
    if (elderAssistantLauncherNotifier.value ==
        _triggerGoogleAssistantOverlay) {
      elderAssistantLauncherNotifier.value = null;
    }
    wakeWordEnabledNotifier.removeListener(_onWakeWordEnabledChanged);
    // ★ G102（CLAUDE_call-monitor-guardrails.md）：無條件 = null 會誤清「接手
    //   畫面」剛註冊好的閉包——本畫面與 ElderScreen 互相導來導去時，兩邊都會
    //   指派同一批欄位，只有 identical() 判斷自己仍是持有者才可以清除。
    if (identical(Signaling().onHeartbeatMessage, _ownHeartbeatMessage)) {
      Signaling().onHeartbeatMessage = null;
    }
    if (identical(Signaling().onCallRequest, _ownCallRequest)) {
      Signaling().onCallRequest = null;
    }
    if (identical(Signaling().onCancelCall, _ownCancelCall)) {
      Signaling().onCancelCall = null;
    }
    if (identical(Signaling().onRemoteReminder, _ownRemoteReminder)) {
      Signaling().onRemoteReminder = null;
    }
    if (identical(Signaling().onElderQuestionAnswered, _ownElderQuestionAnswered)) {
      Signaling().onElderQuestionAnswered = null;
    }
    if (identical(Signaling().onReminderSync, _ownReminderSync)) {
      Signaling().onReminderSync = null;
    }
    ElderReminderManager.instance.setContextGetter(null);
    ElderReminderManager.instance.stop();
    super.dispose();
  }

  void _onPendingCallChanged() {
    final call = pendingAcceptedCall.value;
    if (call != null && !_isNavigatingToCall) {
      // ★ 2026-07-22 第八輪 Fix 3：防角色反轉。長輩端只應接聽「家屬」發起的來電。
      //   若 senderRole == 'elder'（自身角色），代表是自己這方發出、經 stale state
      //   回流的假來電 → 拒絕並清除，避免誤發接聽讓對端反被叫。
      final String? senderRole = call['senderRole'];
      if (senderRole != null &&
          senderRole.isNotEmpty &&
          senderRole == appRole) {
        debugPrint(
            "🚫 [ElderHomeScreen] 忽略角色反轉來電 (senderRole=$senderRole == appRole=$appRole, callId=${call['callId']})");
        pendingAcceptedCall.value = null;
        return;
      }
      final int now = DateTime.now().millisecondsSinceEpoch;
      final int? expiresAt = int.tryParse(call['expiresAt']?.toString() ?? '');
      final int? issuedAt = int.tryParse(call['issuedAt']?.toString() ?? '');
      // ★ 2026-07-20：有效期改用 kCallValidityMs（第二十二輪起為 60s），與後端一致。
      final bool isExpired = (expiresAt != null && now > expiresAt) || (issuedAt != null && (now - issuedAt) > kCallValidityMs);
      if (isExpired) {
        debugPrint("⏰ [ElderHomeScreen] 忽略過期待接聽來電 (callId=${call['callId']})");
        pendingAcceptedCall.value = null;
        return;
      }
      _isNavigatingToCall = true; // ★ Issue 3：防止重複導航
      debugPrint(
          "📱 ElderHomeScreen: Incoming call detected! Navigating to ElderScreen...");
      // 一定要清空，否則之後返回主頁會再次觸發
      pendingAcceptedCall.value = null;

      if (!mounted) {
        _isNavigatingToCall = false;
        return;
      }

      // ★ 2026-08-25（第三十三輪）：main.dart::_autoAcceptEmergencyCall 只會
      //   關閉它自己追蹤的 _activeCallDialogContext，並不知道本頁是否正巧
      //   開著自己的一般來電對話框（_showIncomingCallDialog／
      //   _isIncomingCallDialogOpen，本頁的來電對話框走的是自己的 context，
      //   main.dart 管不到）。緊急通話「長輩端永遠不得出現接聽／拒絕 UI」
      //   （G81），這裡順手把它清乾淨——不清的話畫面上雖然會被新 push 的
      //   ElderScreen 蓋住看不出異狀，但殘留的對話框路由仍卡在導航堆疊裡，
      //   通話結束返回本頁時會意外重新浮現，對著一通早已結束的舊來電要求
      //   使用者做選擇。這裡的判斷對一般來電（CallKit／備援通知接聽）也一體
      //   適用，並非只服務緊急通話。
      if (_isIncomingCallDialogOpen && Navigator.canPop(context)) {
        Navigator.of(context).pop();
        _isIncomingCallDialogOpen = false;
      }

      final currentContext = context;
      Navigator.push(
        currentContext,
        MaterialPageRoute(
          builder: (context) => ElderScreen(
            roomId: call['roomId']!,
            deviceName: widget.userName,
            initialCallData: call, // ★ 傳遞通話資料
          ),
        ),
      ).then((_) {
        _isNavigatingToCall = false; // ★ 導航結束，允許下次
        // ★ 當從 ElderScreen 退出時，重新綁定首頁的 callbacks
        if (mounted) {
          _restoreSignalingCallbacks();
        }
      });
    }
  }

  // ════════════════════════════════════════════════════════════════
  // ★ 第四十一輪（item 2）：新手指引（步驟式高光）
  // ════════════════════════════════════════════════════════════════

  /// 五個底部標籤的分頁切換入口。除了切換 `_selectedIndex`，還負責偵測
  /// 「使用者第一次切到某個分頁」並排程該分頁的教學。
  ///
  /// IndexedStack 會在本畫面第一次建構時就把五個分頁全部建出來並保活，
  /// 各分頁自己的 initState 因此只會在那一刻跑一次（等於五個分頁的
  /// initState 幾乎同時觸發），無法拿來偵測「使用者何時真的切過去看了那一
  /// 頁」——這正是為什麼判斷邏輯放在這裡（nav 的 onTap），而不是放進各分頁
  /// 自己的檔案。
  void _onNavTap(int index) {
    setState(() => _selectedIndex = index);
    if (_tabTutorialAttempted.add(index)) {
      // 等下一影格畫出（IndexedStack 切換後的新 index 已經 paint）再嘗試，
      // 確保 SpotlightTutorial 量測目標位置時拿到的是最新版面。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeShowTabTutorial(index);
      });
    }
  }

  /// 主介面教學：介紹最下面五個標籤分別是什麼。
  ///
  /// 🚨 硬性要求（來自任務指示，務必保留，不可移除）：教學遮罩絕對不能蓋住
  /// 來電對話框、也不能阻止接聽——長輩錯過一通電話遠比錯過教學嚴重。因此
  /// 顯示前一律先確認「目前沒有待接聽來電」也「沒有正在顯示的來電對話
  /// 框」，任一條件不成立就直接放棄本次顯示。SharedPreferences 的完成旗標
  /// 只在 `SpotlightTutorial.showIfNeeded` 真正跑完（走到 showGeneralDialog
  /// 那一步）後才會寫入，所以這裡提早 return 並不會讓教學被誤標記成
  /// 「已經看過」——下次進首頁、屆時沒有來電了，仍會再嘗試顯示一次。
  Future<void> _maybeShowMainTutorial() async {
    if (!mounted) return;
    if (pendingAcceptedCall.value != null) return;
    if (_isIncomingCallDialogOpen) return;
    await SpotlightTutorial.showIfNeeded(
      context,
      tutorialId: 'elder_main_v1',
      steps: [
        const TutorialStep(
          title: '歡迎使用',
          body: '接下來帶您看一下最下面的五個按鈕，跟著「下一步」看下去就可以了。',
        ),
        TutorialStep(
          targetKey: _navItemKeys[0],
          title: '首頁',
          body: '打開 App 就會先看到這裡，可以看到今天的日期，還有每天更新的新聞。',
        ),
        TutorialStep(
          targetKey: _navItemKeys[1],
          title: '電話',
          body: '想打電話給家人的時候，按這裡就對了。',
        ),
        TutorialStep(
          targetKey: _navItemKeys[2],
          title: '社群',
          body: '這裡可以看家人分享的近況，您也可以分享自己的照片和心情。',
        ),
        TutorialStep(
          targetKey: _navItemKeys[3],
          title: '聊天',
          body: '有什麼想問的、想聊的，都可以按這裡跟 AI 好朋友小嘎說話。',
        ),
        TutorialStep(
          targetKey: _navItemKeys[4],
          title: '我的',
          body: '這裡有您的小豬夥伴、每天的小任務，還有跟家人配對、設定的地方。',
        ),
      ],
    );

    // ★ 優化：主介面教學播完或跳過後，不再無縫硬塞首頁教學，讓長輩能自由探索畫面，徹底消除連續彈窗轟炸。
    //   若長輩日後需要說明，可隨時點擊右下角常駐的「❓ 怎麼用」救生圈或至「我的」重新開啟導覽。
  }

  /// 分頁教學的分派：只在 `_onNavTap` 判定「第一次切到這個分頁」時呼叫一次。
  void _maybeShowTabTutorial(int index) {
    if (!mounted) return;
    switch (index) {
      case 0:
        _showHomeTutorial();
        break;
      case 1:
        _showPhoneTutorial();
        break;
      case 2:
        _showCommunityTutorial();
        break;
      case 3:
        _showChatTutorial();
        break;
      case 4:
        _showProfileTutorial();
        break;
    }
  }

  void _showHomeTutorial() {
    SpotlightTutorial.showIfNeeded(
      context,
      tutorialId: 'elder_home_v1',
      steps: [
        TutorialStep(
          targetKey: _homeDateCardKey,
          title: '今日日期',
          body: '這裡會顯示今天的日期、農民曆和節氣，按下去還能看更多內容。',
        ),
        TutorialStep(
          targetKey: _homeNewsCardKey,
          title: '今日頭條',
          body: '每天都會更新新聞，按下去可以用聽的，不用自己看小字。',
        ),
        TutorialStep(
          targetKey: _homeMoreNewsKey,
          title: '看更多新聞',
          body: '想看其他新聞的話，按這裡就可以看到更多則。',
        ),
      ],
    );
  }

  void _showPhoneTutorial() {
    SpotlightTutorial.showIfNeeded(
      context,
      tutorialId: 'elder_phone_v1',
      steps: [
        const TutorialStep(
          title: '打電話給家人',
          body: '這裡列出您的家人，想聯絡的時候可以打電話，也可以用視訊看到對方。',
        ),
        TutorialStep(
          targetKey: _phoneTabBarKey,
          title: '家人／朋友',
          body: '上面可以切換看「家人」或「朋友」名單。',
        ),
        TutorialStep(
          targetKey: _phoneCallKey,
          title: '電話鍵',
          body: '按這裡是打一般電話，只有聲音、沒有畫面。',
        ),
        TutorialStep(
          targetKey: _phoneVideoKey,
          title: '視訊鍵',
          body: '按這裡是打視訊電話，可以看到對方的畫面。',
        ),
      ],
    );
  }

  void _showCommunityTutorial() {
    SpotlightTutorial.showIfNeeded(
      context,
      tutorialId: 'elder_community_v1',
      steps: [
        TutorialStep(
          targetKey: _communityPrivacyKey,
          title: '放心分享',
          body: '這裡只有家人和認識的朋友看得到，請放心分享您的近況。',
        ),
        TutorialStep(
          targetKey: _communityCreatePostKey,
          title: '分享近況',
          body: '按這裡可以拍照、寫幾句話，跟家人分享您現在在做什麼。',
        ),
        TutorialStep(
          targetKey: _communityLikeKey,
          title: '送爪印',
          body: '看到家人的分享，按這裡送一個愛心，讓他們知道您有看到、很關心。',
        ),
        TutorialStep(
          targetKey: _communityCommentKey,
          title: '留言',
          body: '想跟家人說說話，也可以按這裡留言。',
        ),
      ],
    );
  }

  void _showChatTutorial() {
    SpotlightTutorial.showIfNeeded(
      context,
      tutorialId: 'elder_chat_v1',
      steps: [
        TutorialStep(
          targetKey: _chatVoiceToggleKey,
          title: '說話或打字',
          body: '按這裡可以切換成用「說」的，或是用打字的，跟小嘎聊天。',
        ),
        TutorialStep(
          targetKey: _chatInputAreaKey,
          title: '開始聊天',
          body: '按住這裡說話，或是打字，小嘎都會回應您。',
        ),
        TutorialStep(
          targetKey: _chatLanguageToggleKey,
          title: '國語／台語',
          body: '這裡可以切換小嘎用國語還是台語跟您說話。',
        ),
      ],
    );
  }

  void _showProfileTutorial() {
    SpotlightTutorial.showIfNeeded(
      context,
      tutorialId: 'elder_profile_v1',
      steps: [
        TutorialStep(
          targetKey: _profilePetKey,
          title: '您的小豬夥伴',
          body: '這是陪伴您的小豬，按一下摸摸牠，牠會陪您一起變健康。',
        ),
        TutorialStep(
          targetKey: _profileTasksKey,
          title: '今日任務',
          body: '這裡看家人幫您安排的小任務，完成了記得來打勾。',
        ),
        TutorialStep(
          targetKey: _profileFamilyPairingKey,
          title: '家人綁定',
          body: '要讓新的家人跟您配對時，按這裡出示配對碼。',
        ),
        TutorialStep(
          targetKey: _profileAiAssistantKey,
          title: '語音助理設定',
          body: '這裡可以設定「Hey 嘎蛙」語音喚醒的相關功能。',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Stack(
        children: [
          // 頁面內容切換
          IndexedStack(
            index: _selectedIndex,
            children: [
              // 0 首頁
              ElderHomeTab(
                userId: widget.userId,
                userName: widget.userName,
                roomId: widget.roomId,
                dateCardKey: _homeDateCardKey,
                newsCardKey: _homeNewsCardKey,
                moreNewsKey: _homeMoreNewsKey,
              ),
              // 1 電話（好友列表）
              FriendsScreen(
                userId: widget.userId,
                userName: widget.userName,
                roomId: widget.roomId,
                tabBarKey: _phoneTabBarKey,
                firstCallKey: _phoneCallKey,
                firstVideoKey: _phoneVideoKey,
              ),
              // 2 社群（家人與熟人限定；第四十二輪加「家人／朋友」頂部標籤）
              ElderCommunityScreen(
                userId: widget.userId,
                userName: widget.userName,
                showFriendTab: true,
                privacyCardKey: _communityPrivacyKey,
                createPostButtonKey: _communityCreatePostKey,
                firstPostLikeKey: _communityLikeKey,
                firstPostCommentKey: _communityCommentKey,
              ),
              // 3 聊天（小雲 AI 聊天）
              ElderChatScreen(
                userId: widget.userId,
                userName: widget.userName,
                voiceToggleKey: _chatVoiceToggleKey,
                inputAreaKey: _chatInputAreaKey,
                languageToggleKey: _chatLanguageToggleKey,
              ),
              // 4 我的
              ElderProfileTab(
                userId: widget.userId,
                userName: widget.userName,
                petKey: _profilePetKey,
                tasksKey: _profileTasksKey,
                familyPairingKey: _profileFamilyPairingKey,
                aiAssistantKey: _profileAiAssistantKey,
              ),
            ],
          ),
          // 浮動導覽列（永遠顯示）
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildFloatingNavBar(),
          ),
          // 🛟 長輩隨身救生圈：「❓ 怎麼用」隨叫隨到求助按鈕
          Positioned(
            right: 16,
            bottom: 116,
            child: _buildHelpButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _showHelpSheet,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF2E7D78),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.help_outline_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 6),
              Text(
                '怎麼用？',
                style: GoogleFonts.notoSansTc(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showHelpSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '👵 阿公阿嬤安心救生圈',
                style: GoogleFonts.notoSansTc(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1E293B),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '遇到看不懂或按不出來？點選下方隨時幫您：',
                style: GoogleFonts.notoSansTc(fontSize: 16, color: const Color(0xFF64748B)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _triggerGoogleAssistantOverlay('請告訴我這個畫面怎麼用');
                },
                icon: const Icon(Icons.mic_rounded, size: 26),
                label: Text(
                  '🎙️ 聽小嘎說話（語音幫忙）',
                  style: GoogleFonts.notoSansTc(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D78),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _replayCurrentTabTutorial();
                },
                icon: const Icon(Icons.menu_book_rounded, size: 24),
                label: Text(
                  '📖 觀看本頁功能導覽',
                  style: GoogleFonts.notoSansTc(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2E7D78),
                  side: const BorderSide(color: Color(0xFF2E7D78), width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _onNavTap(1);
                },
                icon: const Icon(Icons.phone_rounded, color: Color(0xFF0284C7), size: 24),
                label: Text(
                  '📞 撥打電話給家人',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 16,
                    color: const Color(0xFF0284C7),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _replayCurrentTabTutorial() {
    switch (_selectedIndex) {
      case 0:
        SpotlightTutorial.showForce(
          context,
          tutorialId: 'elder_home_v1',
          steps: [
            TutorialStep(
              targetKey: _homeDateCardKey,
              title: '今日日期',
              body: '這裡會顯示今天的日期、農民曆和節氣，按下去還能看更多內容。',
            ),
            TutorialStep(
              targetKey: _homeNewsCardKey,
              title: '今日頭條',
              body: '每天都會更新新聞，按下去可以用聽的，不用自己看小字。',
            ),
            TutorialStep(
              targetKey: _homeMoreNewsKey,
              title: '更多新聞',
              body: '想看更多各類新聞，按這裡就可以挑選有興趣的主題。',
            ),
          ],
        );
        break;
      case 1:
        SpotlightTutorial.showForce(
          context,
          tutorialId: 'elder_phone_v1',
          steps: [
            TutorialStep(
              targetKey: _phoneTabBarKey,
              title: '聯絡人類別',
              body: '可以在這裡切換家人或朋友的電話名冊。',
            ),
            TutorialStep(
              targetKey: _phoneCallKey,
              title: '撥打電話',
              body: '按綠色按鈕可以直接撥語音電話給家人。',
            ),
            TutorialStep(
              targetKey: _phoneVideoKey,
              title: '視訊通話',
              body: '按藍色按鈕可以看著家人的臉聊天喔！',
            ),
          ],
        );
        break;
      default:
        SpotlightTutorial.showForce(
          context,
          tutorialId: 'elder_main_v1',
          steps: [
            const TutorialStep(
              title: '歡迎使用 UBan',
              body: '最下面的五個按鈕是主要功能，點擊任一個都可以切換喔！',
            ),
          ],
        );
        break;
    }
  }

  Widget _buildFloatingNavBar() {
    return Container(
      height: 104,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(0, Icons.home_rounded, '首頁'),
          _buildNavItem(1, Icons.phone_rounded, '電話'),
          _buildNavItem(2, Icons.groups_rounded, '社群'),
          _buildNavItem(3, Icons.chat_bubble_rounded, '聊天'),
          _buildNavItem(4, Icons.person_rounded, '我的'),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    final Color activeColor = const Color(0xFF59B294);
    final Color inactiveColor = const Color(0xFF94A3B8);
    return Expanded(
      child: GestureDetector(
        key: _navItemKeys[index],
        onTap: () => _onNavTap(index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 32,
                color: isSelected ? activeColor : inactiveColor,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.notoSansTc(
                  fontSize: 17,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                  color: isSelected ? activeColor : inactiveColor,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
