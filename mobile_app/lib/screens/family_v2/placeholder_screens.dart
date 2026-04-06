// lib/screens/family_v2/care_script_editor_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 主動關心劇本編輯器（佔位頁面）
/// 
/// 完整開發將在 Phase 2 進行
class CareScriptEditorScreen extends StatelessWidget {
  final int elderId;

  const CareScriptEditorScreen({super.key, required this.elderId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('主動關心劇本', style: GoogleFonts.notoSansTc()),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.schedule_send, size: 80, color: Colors.purple),
            SizedBox(height: 20),
            Text(
              '功能建置中',
              style: GoogleFonts.notoSansTc(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Phase 2 將開發完整功能',
              style: GoogleFonts.notoSansTc(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

// 其他佔位頁面
class LiveCompanionScreen extends StatelessWidget {
  final int elderId;
  const LiveCompanionScreen({super.key, required this.elderId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('即時陪伴窗口', style: GoogleFonts.notoSansTc())),
      body: Center(child: Text('Phase 2 將開發', style: GoogleFonts.notoSansTc())),
    );
  }
}

class AiPersonaEditorScreen extends StatelessWidget {
  final int elderId;
  const AiPersonaEditorScreen({super.key, required this.elderId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('AI 人格調教', style: GoogleFonts.notoSansTc())),
      body: Center(child: Text('Phase 2 將開發', style: GoogleFonts.notoSansTc())),
    );
  }
}

class DailyScheduleScreen extends StatelessWidget {
  final int elderId;
  const DailyScheduleScreen({super.key, required this.elderId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('每日時間表', style: GoogleFonts.notoSansTc())),
      body: Center(child: Text('Phase 3 將開發', style: GoogleFonts.notoSansTc())),
    );
  }
}

class HealthReminderScreen extends StatelessWidget {
  final int elderId;
  const HealthReminderScreen({super.key, required this.elderId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('健康提醒中心', style: GoogleFonts.notoSansTc())),
      body: Center(child: Text('Phase 3 將開發', style: GoogleFonts.notoSansTc())),
    );
  }
}

class ContentPushScreen extends StatelessWidget {
  final int elderId;
  const ContentPushScreen({super.key, required this.elderId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('內容推送', style: GoogleFonts.notoSansTc())),
      body: Center(child: Text('Phase 3 將開發', style: GoogleFonts.notoSansTc())),
    );
  }
}

class MoodDashboardScreen extends StatelessWidget {
  final int elderId;
  const MoodDashboardScreen({super.key, required this.elderId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('心情儀表板', style: GoogleFonts.notoSansTc())),
      body: Center(child: Text('Phase 4 將開發', style: GoogleFonts.notoSansTc())),
    );
  }
}

class MemoryBoxScreen extends StatelessWidget {
  final int elderId;
  const MemoryBoxScreen({super.key, required this.elderId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('家庭回憶寶盒', style: GoogleFonts.notoSansTc())),
      body: Center(child: Text('Phase 4 將開發', style: GoogleFonts.notoSansTc())),
    );
  }
}
