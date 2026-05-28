import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/services.dart';
import 'package:flutter_line_sdk/flutter_line_sdk.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:app_links/app_links.dart';
import 'network/http_overrides_stub.dart'
    if (dart.library.io) 'network/http_overrides_io.dart';

// Screens
import 'screens/video_call_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/elder_home_screen.dart';

// Utils & Globals
import 'globals.dart';
import 'services/signaling.dart' as sig;
import 'services/api_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final StreamController<String> callKitDeclineStream =
    StreamController<String>.broadcast();

bool _supportsCallKit() {
  return !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint("📩 Background message received: ${message.data}");

  // ★ 緊急通話喚醒：如果收到緊急通話，強制喚醒螢幕並啟動 APP
  if (message.data['type'] == 'emergency-call') {
    debugPrint("🚨 Emergency Call Received in Background. Waking up device...");
    try {
      final intent = const AndroidIntent(
        action: 'android.intent.action.MAIN',
        flags: [
          Flag.FLAG_ACTIVITY_NEW_TASK,
          Flag.FLAG_ACTIVITY_REORDER_TO_FRONT,
        ],
        package: 'com.example.flutter_application_1', // MainActivity package
        componentName: 'com.example.flutter_application_1.MainActivity',
      );
      await intent.launch();
    } catch (e) {
      debugPrint("❌ Failed to launch MainActivity from background: $e");
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureHttpOverrides();
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {}

  try {
    // Initialize date formatting
    await Future.wait([
      initializeDateFormatting('zh_TW', null),
      initializeDateFormatting('zh', null),
    ]);
    Intl.defaultLocale = 'zh_TW';
  } catch (e) {
    debugPrint('Intl initialization failed: $e');
  }

  try {
    // Bug 16: Ensure role is loaded at boot (Check both common keys)
    final prefs = await SharedPreferences.getInstance();
    appRole = prefs.getString('user_role') ?? prefs.getString('saved_role');
    debugPrint("🛠️ App Booting. Detected Role: $appRole");

    if (kIsWeb) {
      // On Web, skip initialization if FirebaseOptions is missing to prevent crash
      debugPrint("🌐 Web platform detected. Skipping Firebase if no options.");
    } else {
      await Firebase.initializeApp();
      // Initialize Firebase Analytics
      try {
        FirebaseAnalytics.instance.logAppOpen();
      } catch (e) {
        debugPrint("⚠️ Firebase Analytics initialization failed: $e");
      }

      // Initialize LINE SDK
      await LineSDK.instance.setup("2009500424").then((_) {
        debugPrint("🟢 LineSDK Initialized in main()");
      });
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);
      await FirebaseMessaging.instance.requestPermission();
    }
  } catch (e) {
    debugPrint("⚠️ Firebase initialization failed or missing: $e");
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  // ★ 問題4修復：FCM 消息去重，防止 Socket.IO + FCM 重複通知
  final Map<String, int> _fcmCallIdCache = {}; // 記錄已處理的 callId 和時間戳
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    isAppReady = true; // ★ 標記 APP 已就緒，允許導航
    if (!kIsWeb) {
      _setupForegroundMessaging(); // ★ 新增：背景推播之外，前景也要監聽
      if (_supportsCallKit()) {
        _setupCallKitListener();
        _checkInitialCall(); // ★ 冷啟動檢查：是否有正在進行的 CallKit
      }
    }
    _setupSignalingListener();
    
    // 延遲初始化 Deep Link，確保 Navigator 已就緒
    Future.delayed(const Duration(milliseconds: 1500), () {
      _initDeepLinks();
    });
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _initDeepLinks() async {
    // 檢查冷啟動傳入的連結
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }
    } catch (e) {
      debugPrint('Deep Link initialization failed: $e');
    }

    // 監聽熱啟動傳入的連結
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    }, onError: (err) {
      debugPrint('Deep Link Stream error: $err');
    });
  }

  void _handleDeepLink(Uri uri) {
    debugPrint('🔗 Caught Deep Link: $uri');
    // 支援 uban://recovery?code=xxx 或 HTTP(S) url
    if (uri.path == '/recovery' || uri.scheme == 'uban' && uri.host == 'recovery' || uri.path.contains('recovery')) {
      final code = uri.queryParameters['code'];
      if (code != null) {
        debugPrint('🔑 Extracted recovery code: $code');
        // 延遲 300ms 確保 App 已完全回到前景並穩定渲染，再彈出 Dialog
        Future.delayed(const Duration(milliseconds: 300), () {
          _showRecoveryConfirmationDialog(code);
        });
      }
    }
  }

  Widget _buildIllustration(String elderName, String familyName) {
    final elderInit = elderName.isNotEmpty ? elderName[0] : '長';
    final familyInit = familyName.isNotEmpty ? familyName[0] : '家';

    return Container(
      height: 120,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 裝飾性 bezier 連接點線
          Positioned.fill(
            child: CustomPaint(
              painter: ConnectionLinePainter(),
            ),
          ),
          
          // 裝飾用圓圈背景 (長輩側)
          Positioned(
            left: 50,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF59B294).withValues(alpha: 0.08),
              ),
            ),
          ),
          
          // 裝飾用圓圈背景 (家屬側)
          Positioned(
            right: 50,
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF7043).withValues(alpha: 0.08),
              ),
            ),
          ),
          
          // 長輩頭貼 (左)
          Positioned(
            left: 70,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF59B294), Color(0xFF2E7D78)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2E7D78).withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: Center(
                child: Text(
                  elderInit,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),

          // 子女頭貼 (右)
          Positioned(
            right: 70,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF8A65), Color(0xFFFF7043)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF7043).withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: Center(
                child: Text(
                  familyInit,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),

          // 自訂黃金鑰匙圖示 (中間偏上)
          Positioned(
            top: 20,
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CustomPaint(
                    painter: GoldenKeyPainter(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showRecoveryConfirmationDialog(String code) {
    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint('⚠️ Cannot show recovery dialog: navigatorKey.currentContext is null');
      return;
    }

    debugPrint('💬 Showing recovery dialog for code: $code');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        bool isLoading = true;
        bool isVerified = false;
        String? errorMsg;
        String elderName = '';
        String familyName = '';
        Map<String, dynamic>? verifiedData;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            void runVerification() async {
              try {
                final result = await ApiService.verifyRecoveryCode(code);
                if (!dialogContext.mounted) return;
                
                if (result['status'] == 'success' && result['data'] != null) {
                  setDialogState(() {
                    isLoading = false;
                    isVerified = true;
                    verifiedData = result['data'];
                    elderName = verifiedData!['elder_name'] ?? '長輩';
                    familyName = verifiedData!['family_name'] ?? '家人';
                  });
                } else {
                  setDialogState(() {
                    isLoading = false;
                    isVerified = false;
                    errorMsg = result['message'] ?? result['error'] ?? result['detail'] ?? '驗證失敗';
                  });
                }
              } catch (e) {
                if (!dialogContext.mounted) return;
                setDialogState(() {
                  isLoading = false;
                  isVerified = false;
                  errorMsg = '網路連線失敗: $e';
                });
              }
            }

            if (isLoading && errorMsg == null && !isVerified) {
              Future.microtask(() => runVerification());
            }

            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(32),
              ),
              elevation: 10,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: Container(
                  color: const Color(0xFFFFFDF9), // 溫馨象牙白
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isLoading) ...[
                        const SizedBox(height: 20),
                        const SizedBox(
                          width: 50,
                          height: 50,
                          child: CircularProgressIndicator(
                            color: Color(0xFFFF7043),
                            strokeWidth: 4,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          '正在安全地驗證登入金鑰...',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 16,
                            color: const Color(0xFF555555),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ] else if (errorMsg != null) ...[
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: SizedBox(
                              width: 32,
                              height: 32,
                              child: CustomPaint(
                                painter: CozyErrorPainter(),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '金鑰驗證失敗',
                          style: GoogleFonts.notoSansTc(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF991B1B),
                            fontSize: 22,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          errorMsg!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.notoSansTc(
                            fontSize: 15,
                            color: const Color(0xFF555555),
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF7043),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              '關閉',
                              style: GoogleFonts.notoSansTc(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ] else if (isVerified) ...[
                        _buildIllustration(elderName, familyName),
                        const SizedBox(height: 24),
                        Text(
                          '👵 「您好，請問是 $elderName 嗎？」',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.notoSansTc(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF2E7D78),
                            fontSize: 30,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '「家人 $familyName 正在幫您登入 Uban 系統。」',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.notoSansTc(
                            fontSize: 22,
                            color: const Color(0xFF4A4A4A),
                            height: 1.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              height: 64,
                              child: ElevatedButton(
                                onPressed: () async {
                                  setDialogState(() {
                                    isLoading = true;
                                  });
                                  
                                  try {
                                    final int elderUserId = verifiedData!['user_id'];
                                    final String name = verifiedData!['elder_name'] ?? '長輩';
                                    
                                    final prefs = await SharedPreferences.getInstance();
                                    await prefs.setInt('caregiver_id', elderUserId);
                                    await prefs.setString('caregiver_name', name);
                                    await prefs.setString('user_role', 'elder');
                                    appRole = 'elder';

                                    if (navigatorKey.currentState != null) {
                                      navigatorKey.currentState!.pop();
                                      navigatorKey.currentState!.pushAndRemoveUntil(
                                        MaterialPageRoute(
                                          builder: (_) => ElderHomeScreen(
                                            userId: elderUserId,
                                            userName: name,
                                          ),
                                        ),
                                        (route) => false,
                                      );
                                    }
                                  } catch (e) {
                                    setDialogState(() {
                                      isLoading = false;
                                      errorMsg = '寫入登入狀態失敗: $e';
                                    });
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF59B294),
                                  foregroundColor: Colors.white,
                                  shadowColor: const Color(0xFF59B294).withValues(alpha: 0.3),
                                  elevation: 4,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                                child: Text(
                                  '是的，這是我',
                                  style: GoogleFonts.notoSansTc(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 22,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: TextButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF888888),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: Text(
                                  '不是我',
                                  style: GoogleFonts.notoSansTc(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint(
          "☀️ [Main] App Resumed. Triggering self-healing reconnection...");
      sig.Signaling().reconnect();
    }
  }

  // ★ 冷啟動恢復：如果 App 因點擊接聽而啟動，這裡會抓到並導航
  Future<void> _checkInitialCall() async {
    final activeCalls = await FlutterCallkitIncoming.activeCalls();
    if (activeCalls is List && activeCalls.isNotEmpty) {
      final call = activeCalls.first;
      final extra = call['extra'];
      if (extra != null) {
        final roomId = extra['roomId'] as String?;
        final senderId = extra['senderId'] as String?;
        if (roomId != null && senderId != null) {
          debugPrint("🚀 [Main] Initial Active Call found! Auto-navigating...");
          _navigateToVideoCall(roomId, senderId, callId: extra['callId']);
        }
      }
    }
  }

  BuildContext? _activeCallDialogContext;

  void _setupForegroundMessaging() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint("📩 [Main] Foreground message received: ${message.data}");
      if (message.data['type'] == 'call-request' || message.data['type'] == 'emergency-call') {
        final roomId = message.data['roomId'];
        final senderId = message.data['senderId'];
        final callId = message.data['callId'];
        final senderRole = message.data['role'];
        final isEmergency = message.data['type'] == 'emergency-call';

        if (senderRole != null && appRole == senderRole) {
          debugPrint("📞 [FCM-Backup] Ignoring call-request: sender role ($senderRole) matches our appRole ($appRole)");
          return;
        }

        // ★ 問題4修復：檢查此 callId 是否最近已被處理（防止 Socket.IO + FCM 重複通知）
        final int currentTime = DateTime.now().millisecondsSinceEpoch;
        if (callId != null) {
          if (_fcmCallIdCache.containsKey(callId)) {
            final lastProcessedTime = _fcmCallIdCache[callId] ?? 0;
            if ((currentTime - lastProcessedTime) < 3000) { // 3秒去重窗口
              debugPrint("⚠️ [FCM-Backup] 忽略重複的 ${isEmergency ? '緊急' : ''}來電（CallId 已在 3 秒內處理: $callId）");
              return;
            }
          }
          // 更新緩存
          _fcmCallIdCache[callId] = currentTime;
          // ★ 清理舊的快取（超過5秒的記錄）
          _fcmCallIdCache.removeWhere((key, value) => (currentTime - value) > 5000);
        }

        debugPrint(
            "🔔 [FCM-Backup] ${isEmergency ? '緊急' : ''}Call Request from $senderId in room $roomId (ID: $callId)");
        // ★ 備援：FCM 用作備份，以防 Socket 連接不穩定時收不到來電
        // 由於 Socket 優先級更高，FCM 的去重機制確保不會重複彈窗
        _showIncomingCallDialog(roomId, senderId, callId: callId, isEmergency: isEmergency);
      }
    });
  }

  void _setupSignalingListener() {
    final s = sig.Signaling();

    // 響鈴彈窗
    s.onCallRequest = (roomId, senderId, callId) {
      _showIncomingCallDialog(roomId, senderId, callId: callId, isEmergency: false);
    };
    
    // ★ 緊急呼叫處理
    s.onEmergencyCall = (roomId, senderId, callId) {
      _showIncomingCallDialog(roomId, senderId, callId: callId, isEmergency: true);
    };

    // 對方取消來電
    s.onCancelCall = (roomId, senderId, callId) {
      if (_activeCallDialogContext != null) {
        debugPrint(
            "🔕 [Main] Remote canceled call. Dismissing global dialog...");
        if (Navigator.canPop(_activeCallDialogContext!)) {
          Navigator.pop(_activeCallDialogContext!);
        }
        _activeCallDialogContext = null;
      }
    };

    // WebRTC Offer 自動答應 (因為已經在 CallRequest 階段按過接聽了)
    s.onIncomingCall = (callerId, callType) async {
      debugPrint(
          "📞 [Main] Global Incoming Offer from $callerId (Type: $callType). Auto-accepting...");
      return true;
    };
  }

  void _showIncomingCallDialog(String roomId, String senderId,
      {String? callId, bool isEmergency = false}) {
    if (_activeCallDialogContext != null) {
      debugPrint("🚫 [Main] Dialog already showing, skipping...");
      return;
    }

    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint(
          "⚠️ [Main] Cannot show dialog: navigatorKey.currentContext is NULL!");
      return;
    }

    final String callerLabel = (appRole == 'elder') ? '您的家人' : '長輩';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) {
        _activeCallDialogContext = c;
        return AlertDialog(
          title: const Text('💡 視訊通話申請'),
          content: Text('$callerLabel 正在呼叫 (房間: $roomId)'),
          actions: [
            TextButton(
              onPressed: () {
                _activeCallDialogContext = null;
                Navigator.pop(c);
                sig.Signaling().sendCallBusy(senderId, callId: callId);
              },
              child: const Text('拒絕', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton(
              onPressed: () {
                _activeCallDialogContext = null;
                Navigator.pop(c);
                _navigateToVideoCall(roomId, senderId, callId: callId);
              },
              child: const Text('接聽'),
            ),
          ],
        );
      },
    );
  }

  void _setupCallKitListener() {
    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) {
      if (event == null) return;

      final extra = event.body['extra'];
      if (extra == null || extra is! Map) return;
      final roomId = extra['roomId'] as String?;
      final senderId = extra['senderId'] as String?;
      final callId = extra['callId'] as String?;

      if (roomId == null || senderId == null) return;

      if (event.event == Event.actionCallAccept) {
        _navigateToVideoCall(roomId, senderId, callId: callId);
      } else if (event.event == Event.actionCallDecline) {
        // Broadcast the decline event so that active dialogs in the app can close themselves
        callKitDeclineStream.add(roomId);

        // Remove any active incoming call dialog if the app is open
        if (navigatorKey.currentState != null) {
          navigatorKey.currentState?.popUntil((route) => route.isFirst);
        }
        _sendDeclineEvent(roomId, senderId, callId: callId);
      }
    });
  }

  void _sendDeclineEvent(String roomId, String senderId, {String? callId}) async {
    debugPrint(
        "❌ Call Declined from CallKit, sending call-busy to $senderId (callId: $callId)...");
    
    final prefs = await SharedPreferences.getInstance();
    final int? userId = prefs.getInt('caregiver_id');
    final String? role = prefs.getString('user_role') ?? 'family';
    
    final io.Socket socket = io.io(
        sig.Signaling.serverUrl,
        io.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .enableForceNew()
            .build());

    socket.connect();
    socket.onConnect((_) {
      debugPrint('✅ Socket 連線成功 (Main-Decline Handler)');
      socket.emit('join', {
        'room': roomId,
        'role': role,
        'deviceName': 'Decline_Handler',
        'userId': userId,
      });
      socket.emit('call-busy', {'targetId': senderId, 'callId': callId});

      // Delay to ensure the event is fired, then disconnect to clean up
      Future.delayed(const Duration(milliseconds: 500), () {
        socket.disconnect();
      });
    });
  }

  void _navigateToVideoCall(String roomId, String senderId, {String? callId}) {
    // ★ Bug 16 解決方案：如果身分是長輩，絕對不可啟動 VideoCallScreen (那是給家屬用的)。
    // 我們僅儲存 pendingAcceptedCall，讓長輩主畫面 (ElderScreen) 啟動後去接手。
    if (appRole == 'elder') {
      debugPrint(
          "📱 Elder role detected, skipping VideoCallScreen push and caching accepted call.");
      pendingAcceptedCall.value = <String, String?>{
        'roomId': roomId,
        'senderId': senderId,
        'callId': callId
      };

      // ★ 喚醒長輩 APP 並帶到最前台，這會觸發 ElderScreen 的 _checkPendingAcceptedCall
      try {
        final intent = const AndroidIntent(
          action: 'android.intent.action.MAIN',
          flags: [
            Flag.FLAG_ACTIVITY_NEW_TASK,
            Flag.FLAG_ACTIVITY_REORDER_TO_FRONT
          ],
          package: 'com.example.flutter_application_1',
          componentName: 'com.example.flutter_application_1.MainActivity',
        );
        intent.launch();

        const platform = MethodChannel('com.example.app/bring_to_front');
        platform.invokeMethod('bringToFront');
      } catch (e) {
        debugPrint("Failed to bring elder app to front: $e");
      }
      return;
    }

    if (navigatorKey.currentState != null && isAppReady) {
      // Pop any active dialogs (like the incoming call alert on the dashboard)
      // before bringing up the VideoCallScreen from CallKit.
      navigatorKey.currentState?.popUntil((route) => route.isFirst);

      Future.microtask(() {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (context) => VideoCallScreen(
              roomId: roomId,
              targetSocketId: senderId,
              isIncomingCall: true,
            ),
          ),
        );
      });
    } else {
      // App is cold booting or navigator not ready. Save it for Dashboard/Elder screen to pick up.
      pendingAcceptedCall.value = {'roomId': roomId, 'senderId': senderId};
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey, // ★ 關鍵：必須綁定 navigatorKey，否則無法顯示彈窗或導航
      title: 'UBan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF59B294)),
        useMaterial3: true,
        textTheme: GoogleFonts.notoSansTcTextTheme(Theme.of(context).textTheme),
      ),
      // ★★★ 還原為原始入口：SplashScreen ★★★
      home: const SplashScreen(),
      /*
      onGenerateRoute: (settings) {
        if (settings.name == '/family_home') {
          final args = settings.arguments as Map<String, dynamic>? ?? {};
          return MaterialPageRoute(
            builder: (context) => FamilyMainScreen(
              userId: args['user_id'] ?? 0,
              userName: args['user_name'] ?? '使用者',
            ),
          );
        }
        return null; // Let 'routes' handle it
      },
      routes: {
        '/login': (context) => const LoginScreen(),
        '/identification': (context) => const IdentificationScreen(),
      },
      */
    );
  }
}

class GoldenKeyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFF7043)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width * 0.5, size.height * 0.35);

    canvas.drawCircle(center, size.width * 0.22, paint);

    canvas.drawLine(
      center + Offset(0, size.width * 0.22),
      Offset(size.width * 0.5, size.height * 0.9),
      paint,
    );

    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.7),
      Offset(size.width * 0.75, size.height * 0.7),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.85),
      Offset(size.width * 0.7, size.height * 0.85),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ConnectionLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF59B294).withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final p0 = Offset(size.width * 0.32, size.height * 0.55);
    final p1 = Offset(size.width * 0.5, size.height * 0.15);
    final p2 = Offset(size.width * 0.68, size.height * 0.55);

    for (double t = 0; t <= 1.0; t += 0.05) {
      final x = (1 - t) * (1 - t) * p0.dx + 2 * (1 - t) * t * p1.dx + t * t * p2.dx;
      final y = (1 - t) * (1 - t) * p0.dy + 2 * (1 - t) * t * p1.dy + t * t * p2.dy;
      canvas.drawCircle(Offset(x, y), 2.5, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CozyErrorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(size.width * 0.3, size.height * 0.3),
      Offset(size.width * 0.7, size.height * 0.7),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.7, size.height * 0.3),
      Offset(size.width * 0.3, size.height * 0.7),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
