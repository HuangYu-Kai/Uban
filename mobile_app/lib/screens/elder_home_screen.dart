import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'elder_tabs/elder_home_tab.dart';
import 'friends_screen.dart';
import 'elder_community_screen.dart';
import 'elder_chat_screen.dart';
import 'elder_tabs/elder_profile_tab.dart';
import '../globals.dart';
import 'elder_screen.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:convert';
import '../services/signaling.dart';
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import '../widgets/google_assistant_overlay.dart';

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
    // ★ 2026-08-10 第二十輪（需求 6）：語音喚醒總開關的即時生效。
    wakeWordEnabledNotifier.addListener(_onWakeWordEnabledChanged);
    // 檢查是否有在背景接聽的通話初始化前就傳入的待接聽電話
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _onPendingCallChanged();
    });

    // 監聽來自親人的呼叫與推播留言
    _restoreSignalingCallbacks();
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
      // ★ 2026-08-10 第二十輪（需求 6）：先讀總開關再決定要不要初始化語音喚醒。
      //   預設 false——這是使用者明確要求的行為（避免雜訊誤觸開麥克風／鏡頭）。
      wakeWordEnabledNotifier.value =
          prefs.getBool(kWakeWordEnabledKey) ?? false;
      _initWakeWordListener();
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
          final text = result.recognizedWords.toLowerCase();
          debugPrint('🎙️ [WakeWord Recognized] $text (Target AI: $_aiName)');

          if (_isDynamicWakeWordMatch(text, _aiName)) {
            debugPrint('🎯 [WakeWord Match Success!] 觸發 AI 助理彈窗 (識別內容: $text)');
            _wakeWordStt.stop();
            _wakeWordListening = false;
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

  /// 動態喚醒詞比對算法：100% 覆蓋所有中文 ASR 轉錄同音字、前綴與常見意圖問句
  bool _isDynamicWakeWordMatch(String text, String customAiName) {
    final lowerText = text.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final lowerAi = customAiName.toLowerCase().trim();
    if (lowerAi.isEmpty) return false;

    // 1. 完整包含自訂 AI 名稱
    if (lowerText.contains(lowerAi)) return true;

    // 2. 嘎蛙超廣角同音字與轉錄變體 (嘎蛙 / 嘎挖 / 嘎娃 / 嘎哇 / gawa / 黑嘎 / 嘿嘎 / 嗨嘎 / 嘎)
    final Set<String> targetVariants = {
      lowerAi,
      '嘎蛙', '嘎挖', '嘎娃', '嘎哇', '黑嘎', '嘿嘎', '嗨嘎', 'gawa', 'gawha', '小嘎', '嘎', '蛙'
    };

    for (final variant in targetVariants) {
      if (lowerText.contains(variant)) return true;
    }

    // 3. 常見喚醒前綴 (Hey / 黑 / 嘿 / 嗨 / Hi / 哈囉 / 呼叫 / 小 / 喂)
    final prefixes = ['hey', 'hi', 'hello', '黑', '嘿', '嗨', '哈囉', '呼叫', '小', '喂'];
    for (final prefix in prefixes) {
      if (lowerText.contains(prefix)) return true;
    }

    // 4. 常見意圖問句 (防止 ASR 裁切掉前導喚醒詞時漏接，如："可以幹嘛", "在嗎", "幫我", "幾點")
    final intentPhrases = ['可以幹嘛', '在嗎', '你好', '幫我', '幾點', '天氣', '請問', '做什麼', '幹嘛'];
    for (final intent in intentPhrases) {
      if (lowerText.contains(intent)) return true;
    }

    return false;
  }

  void _triggerGoogleAssistantOverlay([String? prompt]) async {
    if (_isAssistantShowing) return;
    _isAssistantShowing = true;
    _wakeWordStt.stop();
    _wakeWordListening = false;

    await GoogleAssistantOverlay.show(
      context,
      userName: _userName,
      aiName: _aiName,
      userId: widget.userId,
      initialPrompt: prompt,
    );

    if (mounted) {
      setState(() {
        _isAssistantShowing = false;
      });
      _safeRestartWakeWordListening('overlay_closed');
    }
  }

  void _restoreSignalingCallbacks() {
    debugPrint("🔄 [ElderHomeScreen] 重新綁定 Signaling Callbacks");
    // 監聽來自家屬的來電請求
    Signaling().onCallRequest = (roomId, senderId, callId, [senderName]) {
      if (!mounted) return;
      _showIncomingCallDialog(roomId, senderId, callId);
    };
    // ★ issue 4 fix: 監聽家屬取消來電，關閉彈窗
    Signaling().onCancelCall = (roomId, senderId, callId, [senderName]) {
      if (!mounted) return;
      debugPrint('🔕 [ElderHomeScreen] 家屬取消來電，關閉彈窗');
      if (_isIncomingCallDialogOpen && Navigator.canPop(context)) {
        Navigator.of(context).pop();
        _isIncomingCallDialogOpen = false;
      }
    };

    // 監聽家屬發送的主動關心留言 (Heartbeat)
    Signaling().onHeartbeatMessage = (message) {
      if (mounted) {
        _handleProactiveMessage(message);
      }
    };
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
        return AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.phone_in_talk,
                    color: Colors.green, size: 28),
              ),
              SizedBox(width: 12),
              Text('家屬來電'),
            ],
          ),
          content: const Text('您的家人正在呼叫您！', style: TextStyle(fontSize: 18)),
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
              icon: const Icon(Icons.call_end),
              label: const Text('拒接', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _isIncomingCallDialogOpen = false;

                // 接聽後跳轉到通話畫面
                Signaling().sendCallAccept(senderId, callId: callId);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ElderScreen(
                      roomId: widget.roomId ?? widget.userId.toString(),
                      deviceName: widget.userName,
                    ),
                  ),
                ).then((_) {
                  // ★ 從 ElderScreen 退出時重新綁定 callbacks
                  if (mounted) {
                    _restoreSignalingCallbacks();
                  }
                });
              },
              icon: const Icon(Icons.videocam),
              label: const Text('接聽', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        );
      },
    ).then((_) => _isIncomingCallDialogOpen = false);
  }

  final FlutterTts _flutterTts = FlutterTts();

  Future<void> _handleProactiveMessage(String message) async {
    String displayText = message;
    try {
      final data = jsonDecode(message);
      if (data is Map && data.containsKey('reply')) {
        displayText = data['reply'];
        // 檢查是否為禮物
        if (data['type'] == 'family_gift') {
          displayText = "嘎挖！大驚喜！🎁 子女給您送禮物來了：\n$displayText";
        }
      }
    } catch (e) {
      debugPrint("Home Heartbeat is plain text.");
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
    wakeWordEnabledNotifier.removeListener(_onWakeWordEnabledChanged);
    Signaling().onHeartbeatMessage = null;
    Signaling().onCallRequest = null;
    Signaling().onCancelCall = null;
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
              ),
              // 1 電話（好友列表）
              FriendsScreen(
                userId: widget.userId,
                userName: widget.userName,
                roomId: widget.roomId,
              ),
              // 2 社群（家人與熟人限定）
              ElderCommunityScreen(
                userId: widget.userId,
                userName: widget.userName,
              ),
              // 3 聊天（小雲 AI 聊天）
              ElderChatScreen(
                userId: widget.userId,
                userName: widget.userName,
              ),
              // 4 我的
              ElderProfileTab(
                userId: widget.userId,
                userName: widget.userName,
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
        ],
      ),
    );
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
        onTap: () => setState(() => _selectedIndex = index),
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
