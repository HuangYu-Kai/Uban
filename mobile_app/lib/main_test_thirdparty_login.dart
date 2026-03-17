import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/thirdparty_login_test_screen.dart';
import 'services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 LINE SDK (替換為真實的 Channel ID)
  await AuthService.initLineSdk('2009500424');

  runApp(const MyTestApp());
}

class MyTestApp extends StatelessWidget {
  const MyTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Thirdparty Login Test',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF59B294)),
        useMaterial3: true,
        textTheme: GoogleFonts.notoSansTcTextTheme(Theme.of(context).textTheme),
      ),
      home: const ThirdpartyLoginTestScreen(),
    );
  }
}
