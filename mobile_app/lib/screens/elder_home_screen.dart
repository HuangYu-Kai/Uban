import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ElderHomeScreen extends StatelessWidget {
  const ElderHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF0),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.home_rounded, size: 100, color: Colors.orange),
            const SizedBox(height: 24),
            Text(
              '長輩首頁',
              style: GoogleFonts.notoSansTc(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Text('配對成功！您現在可以開始使用 UBan。'),
          ],
        ),
      ),
    );
  }
}
