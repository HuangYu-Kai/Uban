import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'screens/identification_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/family_main_screen.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // 強化初始化：同時載入 zh 與 zh_TW，並設定全域預設 Locale
    await Future.wait([
      initializeDateFormatting('zh_TW', null),
      initializeDateFormatting('zh', null),
    ]);
    Intl.defaultLocale = 'zh_TW';
  } catch (e) {
    debugPrint('Intl initialization failed: $e');
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
      home: const SplashScreen(),
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
    );
  }
}
