// 路徑: mobile_app/lib/main.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
//import 'screens/identification_screen.dart'; 
import 'screens/role_selection_screen.dart'; 

// ★★★ 1. 定義全域導航 Key ★★★
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Uban',
      navigatorKey: navigatorKey, // ★★★ 2. 綁定 Key ★★★
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
