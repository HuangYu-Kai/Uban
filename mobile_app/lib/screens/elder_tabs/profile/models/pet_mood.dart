import 'package:flutter/material.dart';

/// 🐾 零負擔守護小寵物的心情列舉
enum PetMood {
  superHappy, // 活力滿滿 / 達標 / 任務100% / 摸摸
  walking,    // 散步走動中
  content,    // 悠哉陪伴中
  reminding,  // 子女排程待辦提醒
  sleeping,   // 休息睡眠中
}

/// 寵物摸摸愛心粒子模型
class PetHeartParticle {
  Offset position;
  Offset velocity;
  double scale;
  double opacity;
  Color color;

  PetHeartParticle({
    required this.position,
    required this.velocity,
    required this.scale,
    required this.opacity,
    required this.color,
  });
}
