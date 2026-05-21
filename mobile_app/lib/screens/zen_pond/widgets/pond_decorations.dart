import 'package:flutter/material.dart';

class PondDecorations extends StatelessWidget {
  const PondDecorations({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 左上角的石頭群
        Positioned(
          top: -20,
          left: -10,
          child: _buildRock(width: 120, height: 80, color: const Color(0xFF94A3B8), angle: 0.2),
        ),
        Positioned(
          top: 40,
          left: -30,
          child: _buildRock(width: 90, height: 110, color: const Color(0xFF64748B), angle: -0.1),
        ),
        
        // 右下角的石頭
        Positioned(
          bottom: -20,
          right: -20,
          child: _buildRock(width: 150, height: 100, color: const Color(0xFF94A3B8), angle: -0.2),
        ),
        Positioned(
          bottom: 60,
          right: -10,
          child: _buildRock(width: 60, height: 70, color: const Color(0xFFCBD5E1), angle: 0.4),
        ),
        
        // 右上角的點綴石頭
        Positioned(
          top: 30,
          right: -10,
          child: _buildRock(width: 60, height: 40, color: const Color(0xFF94A3B8), angle: 0.1),
        ),
        
        // 左下角的點綴石頭
        Positioned(
          bottom: 120,
          left: -20,
          child: _buildRock(width: 50, height: 80, color: const Color(0xFFCBD5E1), angle: 0.3),
        ),
      ],
    );
  }

  Widget _buildRock({required double width, required double height, required Color color, required double angle}) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.all(Radius.elliptical(width, height * 0.8)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(4, 4),
            ),
          ],
        ),
      ),
    );
  }
}
