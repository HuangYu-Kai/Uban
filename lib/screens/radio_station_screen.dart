import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class RadioStationScreen extends StatelessWidget {
  const RadioStationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF0),
      appBar: AppBar(
        title: Text('老友廣播站', style: GoogleFonts.notoSansTc()),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const FaIcon(
              FontAwesomeIcons.radio,
              size: 80,
              color: Color(0xFFFFB673),
            ),
            const SizedBox(height: 20),
            Text(
              '老友廣播站功能開發中...',
              style: GoogleFonts.notoSansTc(fontSize: 20, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            Text(
              '敬請期待復古旋鈕介面',
              style: GoogleFonts.notoSansTc(
                fontSize: 16,
                color: Colors.grey[400],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
