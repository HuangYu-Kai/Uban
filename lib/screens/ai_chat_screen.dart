import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AIChatScreen extends StatelessWidget {
  const AIChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF0),
      appBar: AppBar(
        title: Text('AI 貼心陪聊', style: GoogleFonts.notoSansTc()),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Text(
          'AI 陪聊功能開發中...',
          style: GoogleFonts.notoSansTc(fontSize: 20, color: Colors.grey),
        ),
      ),
    );
  }
}
