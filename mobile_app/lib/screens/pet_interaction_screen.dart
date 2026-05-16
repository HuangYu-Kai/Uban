import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/pet_controller.dart';
import 'pet_room_view.dart';

/// 寵物互動室畫面 (入口)
class PetInteractionScreen extends StatelessWidget {
  final int userId;
  final int steps;
  final int level;
  final Object? mood;
  final String? assetPath;

  const PetInteractionScreen({
    super.key,
    required this.userId,
    required this.steps,
    required this.level,
    this.mood,
    this.assetPath,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PetController(),
      child: const Scaffold(
        backgroundColor: Colors.blue,
        body: PetRoomView(),
      ),
    );
  }
}
