import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:uuid/uuid.dart';

import 'screens/role_selection_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If you're going to use other Firebase services in the background, such as Firestore,
  // make sure you call `initializeApp` before using other Firebase services.
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
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0955fa',
        backgroundUrl: 'assets/test.png',
        actionColor: '#4CAF50',
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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Uban',
      navigatorKey: navigatorKey, 
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF6B6B)),
        useMaterial3: true,
        textTheme: GoogleFonts.notoSansTcTextTheme(Theme.of(context).textTheme),
      ),
      //home: const IdentificationScreen(),
      home: const RoleSelectionScreen(),
      
    );
  }
}
