// 路徑: mobile_app/lib/main.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/identification_screen.dart';
import 'screens/camera_screen.dart'; // 引入新畫面

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // 應用程式的根組件
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CompanionFlow',
      debugShowCheckedModeBanner: false, // 隱藏 debug 標籤
      theme: ThemeData(
        // 設定種子顏色
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF6B6B)),
        useMaterial3: true,
        // 設定預設字體
        textTheme: GoogleFonts.notoSansTcTextTheme(Theme.of(context).textTheme),
      ),
      // 設定首頁為身分選擇畫面 (保持不變)
      home: const IdentificationScreen(),
      //home: const CameraScreen(),
      // 定義路由表，方便從任何地方跳轉到監控畫面
      routes: {
        '/monitor': (context) => const CameraScreen(),
      },
    );
  }
}