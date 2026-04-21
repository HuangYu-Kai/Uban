import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

class HeartbeatOverlay extends StatelessWidget {
  final String message;
  final String type; // greeting, medication, family, weather, chat
  final String emotion; // happy, caring, neutral
  final VoidCallback onDismiss;

  const HeartbeatOverlay({
    super.key,
    required this.message,
    required this.type,
    required this.emotion,
    required this.onDismiss,
  });

  Color _getThemeColor() {
    switch (type) {
      case 'medication':
        return Colors.redAccent;
      case 'family':
        return Colors.blueAccent;
      case 'weather':
        return Colors.orangeAccent;
      case 'greeting':
        return Colors.greenAccent;
      default:
        return Colors.amberAccent;
    }
  }

  IconData _getIcon() {
    switch (type) {
      case 'medication':
        return Icons.medication;
      case 'family':
        return Icons.family_restroom;
      case 'weather':
        return Icons.wb_sunny;
      case 'greeting':
        return Icons.wb_twilight;
      default:
        return Icons.favorite;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = _getThemeColor();
    
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 30),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: themeColor.withValues(alpha: 0.5),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: themeColor.withValues(alpha: 0.2),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icon & Type Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_getIcon(), color: themeColor, size: 32),
                        const SizedBox(width: 12),
                        Text(
                          _getTypeLabel(),
                          style: GoogleFonts.notoSansTc(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: themeColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    
                    // The Message
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.notoSansTc(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 30),
                    
                    // Interaction Button
                    GestureDetector(
                      onTap: onDismiss,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [themeColor, themeColor.withValues(alpha: 0.7)],
                          ),
                          borderRadius: BorderRadius.circular(40),
                          boxShadow: [
                            BoxShadow(
                              color: themeColor.withValues(alpha: 0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          "好喔，我知道了",
                          style: GoogleFonts.notoSansTc(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ).animate().scale(
        duration: 400.ms,
        curve: Curves.easeOutBack,
      ).fadeIn(),
    );
  }

  String _getTypeLabel() {
    switch (type) {
      case 'medication':
        return '用藥提醒';
      case 'family':
        return '家人留言';
      case 'weather':
        return '天氣注意';
      case 'greeting':
        return '溫馨問候';
      default:
        return 'AI 關懷';
    }
  }
}
