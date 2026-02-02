import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/identification_screen.dart'; // 假設您有這個檔案
import 'screens/camera_screen.dart'; 

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CompanionFlow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF6B6B)),
        useMaterial3: true,
        textTheme: GoogleFonts.notoSansTcTextTheme(Theme.of(context).textTheme),
      ),
      //home: const IdentificationScreen(),
      home: const CameraScreen(), 
      routes: {
        '/monitor': (context) => const CameraScreen(),
      },
    );
  }
}