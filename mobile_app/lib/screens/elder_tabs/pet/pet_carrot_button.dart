import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../widgets/ui/uban_text.dart';

/// 舞台右下角毛玻璃圓鈕：胡蘿蔔圖＋剩餘數量徽章。
///
/// 只負責外觀；點擊／拖曳由 [PetBuddyStage] 以 Listener 處理。
/// [count] 為 0 時整顆變灰（[empty] 為 true），徽章改灰色。
class PetCarrotButton extends StatelessWidget {
  static const double size = 68;

  final int count;

  const PetCarrotButton({super.key, required this.count});

  bool get empty => count <= 0;

  static const _gray = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    Widget icon = Transform.rotate(
      angle: -20 * 3.1415926535 / 180,
      child: Image.asset(
        'assets/images/pet_foods/carrot_cartoon.png',
        width: 46,
        height: 46,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
        errorBuilder: (_, __, ___) =>
            const Text('🥕', style: TextStyle(fontSize: 34)),
      ),
    );
    if (empty) {
      icon = Opacity(
        opacity: .5,
        child: ColorFiltered(colorFilter: _gray, child: icon),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipOval(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: empty ? .55 : .82),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: .9), width: 1),
                  ),
                  child: Center(child: icon),
                ),
              ),
            ),
          ),
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: const EdgeInsets.symmetric(horizontal: 7),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: empty ? const Color(0xFF8A9A93) : const Color(0xFFF28C28),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: ubanBrandText(15, FontWeight.w600, Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
