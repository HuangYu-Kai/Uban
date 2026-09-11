import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 溫馨早午晚標頭 (手繪厚塗繪本風格)
class StorybookHeaderCard extends StatelessWidget {
  final String greetingTitle;
  final String userName;
  final bool isLandscape;

  const StorybookHeaderCard({
    super.key,
    required this.greetingTitle,
    required this.userName,
    this.isLandscape = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isLandscape ? 16 : 20,
        vertical: isLandscape ? 7 : 14,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF9),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFEADBCE), width: 1.8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF78350F).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: isLandscape ? 38 : 58,
            height: isLandscape ? 38 : 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF59B294).withValues(alpha: 0.15),
              border: Border.all(color: const Color(0xFF59B294), width: 2.2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF59B294).withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text('👴', style: TextStyle(fontSize: isLandscape ? 22 : 32)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    // ★ 第四十五輪（例行溢位檢查）：userName 是長輩自訂顯示名稱，
                    // 長度不可控，同列還有固定寬度的「守護中」徽章；25pt／18.5pt
                    // 大字級加上長名字很容易把徽章擠出可視範圍，包 Flexible 並加
                    // ellipsis 可收縮，避免 RenderFlex 溢位。
                    Flexible(
                      child: Text(
                        '$greetingTitle，$userName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSansTc(
                          fontSize: isLandscape ? 18.5 : 25,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF451A03),
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isLandscape ? 8 : 10,
                        vertical: isLandscape ? 2 : 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('🌿', style: TextStyle(fontSize: 11)),
                          const SizedBox(width: 4),
                          Text(
                            '守護中',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF047857),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isLandscape ? 1 : 3),
                Text(
                  '${DateTime.now().month}月${DateTime.now().day}日 · 今天也要開開心心地活動身體喔！✨',
                  style: GoogleFonts.notoSansTc(
                    fontSize: isLandscape ? 13 : 14.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF8C6D58),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
