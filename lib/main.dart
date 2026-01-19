import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/identification_screen.dart';

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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFFB673)),
        useMaterial3: true,
        // 設定預設字體
        textTheme: GoogleFonts.notoSansTcTextTheme(Theme.of(context).textTheme),
      ),
      home: const IdentificationScreen(), // 設定首頁為身分選擇畫面
    );
  }
}
