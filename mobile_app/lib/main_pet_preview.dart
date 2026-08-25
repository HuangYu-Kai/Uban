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
      home: const PetStudioScreen(
        initialSteps: 3500,
        userName: '宇璿',
      ),
    );
  }
}
