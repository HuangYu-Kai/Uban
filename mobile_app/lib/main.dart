// 路徑: mobile_app/lib/main.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
// 如果之後要接回原本的主流程，保留此 import，目前先用不到可以註解或留著
import 'screens/identification_screen.dart'; 
// 引入刚刚建立的角色選擇頁面，這是新的入口
import 'screens/role_selection_screen.dart'; 

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Uban',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // 保留您原本的暖色系設計風格 (紅色/珊瑚色)
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF6B6B)),
        useMaterial3: true,
        // 設定字體
        textTheme: GoogleFonts.notoSansTcTextTheme(Theme.of(context).textTheme),
      ),
      
      // ★★★ 關鍵修改：設定首頁為角色選擇頁 ★★★
      // 因為現在 CameraScreen(roomId: ...) 需要參數，不能直接在這裡呼叫無參數的版本
      // 所以必須從 RoleSelectionScreen 進入，讓使用者輸入房號
      home: const IdentificationScreen(),
      //home: const RoleSelectionScreen(), 
      
      // ★★★ 路由設定說明 ★★★
      // 舊的寫法 '/monitor': (context) => const CameraScreen() 會報錯，
      // 因為 CameraScreen 現在必須要有 roomId。
      // 既然 RoleSelectionScreen 已經用 Navigator.push 直接跳轉，這裡可以先清空或留白。
      routes: {
        // 如果之後有不需要傳參數的頁面，可以在這裡加
        // '/home': (context) => const IdentificationScreen(),
      },
    );
  }
}