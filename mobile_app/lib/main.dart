import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:uuid/uuid.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

import 'screens/role_selection_screen.dart';
import 'screens/video_call_screen.dart'; // Add this import

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If you're going to use other Firebase services in the background, such as Firestore,
  // make sure you call `initializeApp` before using other Firebase services
  await Firebase.initializeApp();
  print("Handling a background message: \${message.messageId}");

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
      extra: <String, dynamic>{'senderId': senderId, 'roomId': roomId},
      headers: <String, dynamic>{'apiKey': 'v1.0', 'platform': 'flutter'},
      android: const AndroidParams(
        isCustomNotification: false,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0955fa',
        backgroundUrl: 'assets/test.png',
        actionColor: '#4CAF50',
        incomingCallNotificationChannelName: 'Incoming Call',
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
    final senderId = message.data['senderId'] ?? 'Unknown';
    final roomId = message.data['roomId'] ?? 'Unknown';

    final params = CallKitParams(
      id: const Uuid().v4(),
      nameCaller: "🚨 家屬緊急呼叫",
      appName: 'Uban',
      avatar: 'https://i.pravatar.cc/100',
      handle: '緊急呼叫',
      type: 0,
      duration: 30000,
      textAccept: '接聽',
      textDecline: '拒絕',
      extra: <String, dynamic>{'senderId': senderId, 'roomId': roomId, 'isEmergency': true},
      headers: <String, dynamic>{'apiKey': 'v1.0', 'platform': 'flutter'},
      android: const AndroidParams(
        isCustomNotification: false,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#FF0000',
        backgroundUrl: 'assets/test.png',
        actionColor: '#4CAF50',
        incomingCallNotificationChannelName: 'Incoming Call',
        isShowFullLockedScreen: true,
      ),
      ios: const IOSParams(iconName: 'CallKitLogo', handleType: 'generic', supportsVideo: true, maximumCallGroups: 2, maximumCallsPerCallGroup: 1, audioSessionMode: 'default', audioSessionActive: true, audioSessionPreferredSampleRate: 44100.0, audioSessionPreferredIOBufferDuration: 0.005, supportsDTMF: true, supportsHolding: true, supportsGrouping: false, supportsUngrouping: false, ringtonePath: 'system_ringtone_default'),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  } else if (message.data['type'] == 'cancel-call') {
    print("🔕 Background message: cancel-call received. Canceling CallKit.");
    await FlutterCallkitIncoming.endAllCalls();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  
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

      if (roomId == null || senderId == null) return;

      if (event.event == Event.actionCallAccept) {
        _navigateToVideoCall(roomId, senderId);
      } else if (event.event == Event.actionCallDecline) {
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
    final IO.Socket socket = IO.io('https://50ef-61-65-116-7.ngrok-free.app', 
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

  void _navigateToVideoCall(String roomId, String senderId) {
    if (navigatorKey.currentState != null) {
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Uban',
      navigatorKey: navigatorKey, 
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF59B294)),
        useMaterial3: true,
        textTheme: GoogleFonts.notoSansTcTextTheme(Theme.of(context).textTheme),
      ),
      // ★★★ 關鍵修改：設定首頁為啟動頁 ★★★
      home: const RoleSelectionScreen(),
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
