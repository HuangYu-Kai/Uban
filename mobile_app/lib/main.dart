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
import 'network/http_overrides_stub.dart'
    if (dart.library.io) 'network/http_overrides_io.dart';

// Screens
import 'screens/video_call_screen.dart';
import 'screens/splash_screen.dart';

// Utils & Globals
import 'globals.dart';
import 'services/signaling.dart' as sig;

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
  // ⚠️ 移除重複的 CallKit 通知邏輯
  // Firebase 在背景時只用來觸發 Socket.IO 訊號，
  // 真正的來電通知由信令層 (signaling.dart) 統一發送，
  // 避免重複顯示兩個通知
  
  debugPrint("📩 Background message received: ${message.data}");
  
  // 該訊息將由信令層通過 Socket.IO 的 'call' event 處理
  // 詳見 lib/services/signaling.dart 的 'call' 事件監聽
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureHttpOverrides();

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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint("☀️ [Main] App Resumed. Triggering self-healing reconnection...");
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
      if (message.data['type'] == 'call-request') {
        final roomId = message.data['roomId'];
        final senderId = message.data['senderId'];
        final callId = message.data['callId'];
        
        debugPrint("🔔 [FCM-Backup] Call Request from $senderId in room $roomId (ID: $callId)");
        // 備援：如果 Socket 沒連接，或是剛好斷線，這裡同樣調用彈窗邏輯。
        // 但為了避免重複彈窗，我們由 _setupSignalingListener 內的 _showIncomingCallDialog 統一控管。
        _showIncomingCallDialog(roomId, senderId, callId: callId);
      }
    });
  }

  void _setupSignalingListener() {
    final s = sig.Signaling();
    
    // 響鈴彈窗
    s.onCallRequest = (roomId, senderId, callId) {
      _showIncomingCallDialog(roomId, senderId, callId: callId);
    };

    // 對方取消來電
    s.onCancelCall = (roomId, senderId, callId) {
      if (_activeCallDialogContext != null) {
        debugPrint("🔕 [Main] Remote canceled call. Dismissing global dialog...");
        if (Navigator.canPop(_activeCallDialogContext!)) {
          Navigator.pop(_activeCallDialogContext!);
        }
        _activeCallDialogContext = null;
      }
    };

    // WebRTC Offer 自動答應 (因為已經在 CallRequest 階段按過接聽了)
    s.onIncomingCall = (callerId, callType) async {
      debugPrint("📞 [Main] Global Incoming Offer from $callerId (Type: $callType). Auto-accepting...");
      return true; 
    };
  }

  void _showIncomingCallDialog(String roomId, String senderId, {String? callId}) {
    if (_activeCallDialogContext != null) {
      debugPrint("🚫 [Main] Dialog already showing, skipping...");
      return;
    }

    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint("⚠️ [Main] Cannot show dialog: navigatorKey.currentContext is NULL!");
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
        _sendDeclineEvent(roomId, senderId);
      }
    });
  }

  void _sendDeclineEvent(String roomId, String senderId) {
    debugPrint(
        "❌ Call Declined from CallKit, sending call-busy to $senderId...");
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
      socket.emit('join',
          {'room': roomId, 'role': 'family', 'deviceName': 'Decline_Handler'});
      socket.emit('call-busy', {'targetId': senderId});

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
