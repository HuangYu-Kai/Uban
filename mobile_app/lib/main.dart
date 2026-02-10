// 路徑: mobile_app/lib/main.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/identification_screen.dart'; 
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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF6B6B)),
        useMaterial3: true,
        textTheme: GoogleFonts.notoSansTcTextTheme(Theme.of(context).textTheme),
      ),
      // ★★★ 關鍵修改：設定首頁為識別頁 ★★★
      home: const IdentificationScreen(),
      //home: const RoleSelectionScreen(),
      // ★★★ 路由設定說明 ★★★
      // 舊的寫法 '/monitor': (context) => const CameraScreen() 會報錯，
      // 因為 CameraScreen 現在必須要有 roomId。
      routes: {
        // 如果之後有不需要傳參數的頁面，可以在這裡加
      },
    );
  }
}
