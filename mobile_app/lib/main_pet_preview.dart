import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/pet_companion_studio/pet_studio_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitUp,
  ]);

  runApp(const PetPreviewApp());
}

class PetPreviewApp extends StatelessWidget {
  const PetPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Uban 守護伴侶互動工坊',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF59B294)),
      ),
      // ⚠️ 這是離線預覽用的獨立 main()，非 App 正式進入點：userId 固定填正式
      // 環境「宇璿」對應的真實 user_id（見 uban-api 測試資料），純供本機
      // 預覽時解析好友排行榜 elder_id 使用，與正式登入流程無關。
      home: const PetStudioScreen(
        initialSteps: 3500,
        userName: '宇璿',
        userId: 2,
      ),
    );
  }
}
