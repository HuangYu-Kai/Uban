import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

// 使用真實圖片作為荷葉背景

class LotusLeafCard extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const LotusLeafCard({super.key, required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Dismissible(
        key: UniqueKey(),
        direction: DismissDirection.horizontal, // 左右滑動刪除
        onDismissed: (_) => onDismiss(),
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.85,
          height: MediaQuery.of(context).size.width * 0.85,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Image.asset(
                'assets/images/lotus_leaf.png',
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.contain,
              ),
              Padding(
                padding: const EdgeInsets.all(40.0),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 32,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      const Shadow(color: Colors.black38, blurRadius: 4, offset: Offset(2, 2)),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 40,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '👉 往左右滑動可刪除',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ).animate(onPlay: (c) => c.repeat(reverse: true)).fadeIn(duration: 1.seconds),
              ),
            ],
          ),
        ),
      ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
    );
  }
}
