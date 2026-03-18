import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'screens/test_home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Future.wait([
      initializeDateFormatting('zh_TW', null),
      initializeDateFormatting('zh', null),
    ]);
    Intl.defaultLocale = 'zh_TW';
  } catch (e) {
    debugPrint('Intl initialization failed: $e');
  }
  
  runApp(const TestApp());
}

class TestApp extends StatelessWidget {
  const TestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '遊戲功能測試',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF59B294)),
        useMaterial3: true,
        textTheme: GoogleFonts.notoSansTcTextTheme(Theme.of(context).textTheme),
      ),
      home: const TestHomePage(),
    );
  }
}

/*
import 'screens/identification_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/family_main_screen.dart';
import 'screens/login_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:uuid/uuid.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

import 'dart:async';
import 'globals.dart';
import 'services/signaling.dart'; // import to access socketUrl
import 'screens/role_selection_screen.dart';
import 'screens/video_call_screen.dart'; // Add this import
import 'package:flutter/services.dart';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:shared_preferences/shared_preferences.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final StreamController<String> callKitDeclineStream = StreamController<String>.broadcast();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If you're going to use other Firebase services in the background, such as Firestore,
  // make sure you call `initializeApp` before using other Firebase services
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");

  // Only trigger CallKit if it's a call-request
  if (message.data['type'] == 'call-request') {
    final senderId = message.data['senderId'] ?? 'Unknown';
    final roomId = message.data['roomId'] ?? 'Unknown';

    final params = CallKitParams(
      id: const Uuid().v4(),
      nameCaller: "長輩來電 (FCM喚醒)",
      appName: 'Uban',
      avatar: 'https://i.pravatar.cc/100',
      handle: '緊急呼叫',
      type: 0,
      duration: 30000,
      textAccept: '接聽',
      textDecline: '拒絕',
      extra: <String, dynamic>{'senderId': senderId, 'roomId': roomId, 'callId': message.data['callId']},
      headers: <String, dynamic>{'apiKey': 'v1.0', 'platform': 'flutter'},
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0955fa',
        backgroundUrl: 'assets/test.png',
        actionColor: '#4CAF50',
        textColor: '#ffffff',
        incomingCallNotificationChannelName: 'Call_Ring_Channel',
        isShowFullLockedScreen: true,
      ),
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 2,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: true,
        supportsHolding: true,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  } else if (message.data['type'] == 'emergency-call') {
    print("🚨 Emergency Background trigger. Trying to wake app natively.");
    
    // Fallback: Store the emergency payload in SharedPreferences to pick it up when the App boots
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_emergency_room', message.data['roomId'] ?? '');
    await prefs.setString('pending_emergency_sender', message.data['senderId'] ?? '');

    // Attempt to bring the app to the foreground if it is in the background.
    try {
      final intent = const AndroidIntent(
        action: 'android.intent.action.MAIN',
        flags: [Flag.FLAG_ACTIVITY_NEW_TASK, Flag.FLAG_ACTIVITY_REORDER_TO_FRONT],
        package: 'com.example.flutter_application_1', 
        componentName: 'com.example.flutter_application_1.MainActivity',
      );
      await intent.launch();

      const platform = MethodChannel('com.example.app/bring_to_front');
      await platform.invokeMethod('bringToFront');
      
      // Auto-accept the call in CallKit so it drops the UI and just goes into the app
      // Note: 'params' is not defined in this scope for 'emergency-call'.
      // If CallKit is intended to be used here, 'params' needs to be constructed
      // similarly to the 'call-request' block, using data from 'message'.
      // For now, assuming 'params' is a placeholder or will be defined elsewhere.
      // If the intent is to just bring the app to front and handle the emergency
      // within the app, then `startCall` might not be necessary or might need
      // a different approach.
      // For the purpose of this edit, I'm adding the line as requested,
      // but flagging the potential missing 'params' definition.
      // If the user meant to use CallKit for emergency calls, 'params' would need to be built.
      // As the original code didn't use CallKit for emergency, this line might be problematic.
      // I will comment it out to avoid a compilation error, assuming the primary goal
      // is to bring the app to front. If CallKit integration is desired,
      // the user needs to define `params` for emergency calls.
      // await FlutterCallkitIncoming.startCall(params); 
    } catch (e) {
      print("Failed to bring app to front: $e");
    }
  } else if (message.data['type'] == 'cancel-call') {
    print("🔕 Background message: cancel-call received. Canceling CallKit.");
    await FlutterCallkitIncoming.endAllCalls();
  }
}

void originalMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  
  // ★ Bug 16 解決方案：在 APP 啟動最源頭就載入身份，確保冷啟動時的通話路由正確
  final prefs = await SharedPreferences.getInstance();
  appRole = prefs.getString('saved_role');
  print("🛠️ App Booting. Detected Role: $appRole");

  // Request permissions for high priority notifications on Android 13+ and iOS
  await FirebaseMessaging.instance.requestPermission();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {

  @override
  void initState() {
    super.initState();
    _setupCallKitListener();
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
    print("❌ Call Declined from CallKit, sending call-busy to $senderId...");
    final IO.Socket socket = IO.io(Signaling.socketUrl, 
      IO.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .enableForceNew()
        .build()
    );
    
    socket.connect();
    socket.onConnect((_) {
      print('✅ Socket 連線成功 (Main-Decline Handler)');
      socket.emit('join', {'room': roomId, 'role': 'family', 'deviceName': 'Decline_Handler'});
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
      print("📱 Elder role detected, skipping VideoCallScreen push and caching accepted call.");
      pendingAcceptedCall.value = <String, String?>{'roomId': roomId, 'senderId': senderId, 'callId': callId};
      
      // ★ 喚醒長輩 APP 並帶到最前台，這會觸發 ElderScreen 的 _checkPendingAcceptedCall
      try {
        final intent = const AndroidIntent(
          action: 'android.intent.action.MAIN',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK, Flag.FLAG_ACTIVITY_REORDER_TO_FRONT],
          package: 'com.example.flutter_application_1',
          componentName: 'com.example.flutter_application_1.MainActivity',
        );
        intent.launch();

        const platform = MethodChannel('com.example.app/bring_to_front');
        platform.invokeMethod('bringToFront');
      } catch (e) {
        print("Failed to bring elder app to front: $e");
      }
      return;
    }

    if (navigatorKey.currentState != null && isAppReady) {
      // Pop any active dialogs (like the incoming call alert on the dashboard) 
      // before bringing up the VideoCallScreen from CallKit.
      navigatorKey.currentState?.popUntil((route) => route.isFirst);
      
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => VideoCallScreen(
            roomId: roomId,
            targetSocketId: senderId,
            isIncomingCall: true,
          ),
        ),
      );
    } else {
      // App is cold booting or navigator not ready. Save it for Dashboard/Elder screen to pick up.
      pendingAcceptedCall.value = {'roomId': roomId, 'senderId': senderId};
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UBan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF59B294)),
        useMaterial3: true,
        textTheme: GoogleFonts.notoSansTcTextTheme(Theme.of(context).textTheme),
      ),
      // ★★★ 關鍵修改：設定首頁為啟動頁 ★★★
      home: const RoleSelectionScreen(),
    );
  }
}
*/
