import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/pet_growth_state.dart';

class PetEvolutionDialog extends StatelessWidget {
  final PetGrowthStage newStage;
  final String userName;

  const PetEvolutionDialog({
    super.key,
    required this.newStage,
    this.userName = '宇璿',
  });

  static Future<void> show(BuildContext context, PetGrowthStage newStage, {String userName = '宇璿'}) {
    HapticFeedback.heavyImpact();
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PetEvolutionDialog(newStage: newStage, userName: userName),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: const Color(0xFFFBBF24), width: 3),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 慶祝彩帶 Icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
                ),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFF59E0B), width: 2),
              ),
              child: Center(
                child: Text(
                  newStage.icon,
                  style: const TextStyle(fontSize: 44),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 標題
            Text(
              '🎉 叮咚！小豬長大升級囉！',
              style: GoogleFonts.notoSansTc(
                fontSize: 23,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF78350F),
              ),
            ),
            const SizedBox(height: 10),

            // 稱號
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFCD34D), width: 1.5),
              ),
              child: Text(
                '升級為【Lv.${newStage.level} ${newStage.title}】',
                style: GoogleFonts.notoSansTc(
                  fontSize: 18.5,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF92400E),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 描述
            Text(
              '在 $userName 的悉心散步與營養餵養下，小豬吃得白白胖胖、健康有福相！',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansTc(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF475569),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),

            // 解鎖新飾品
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFBBF7D0), width: 1.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🎁', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '解鎖外觀：${newStage.accessory}',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF166534),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // 確認按鈕
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.white,
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: Text(
                  '開開心心收下 ✨',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
