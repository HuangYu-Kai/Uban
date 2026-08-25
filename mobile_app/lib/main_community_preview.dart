import 'package:flutter/material.dart';

import 'screens/elder_home_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const CommunityPreviewApp());
}

class CommunityPreviewApp extends StatelessWidget {
  const CommunityPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '暖心社群預覽',
      theme: buildAppTheme(context),
      home: const ElderHomeScreen(
        userId: 1,
        userName: '玉軒阿公',
        roomId: 'preview-room',
      ),
    );
  }
}
