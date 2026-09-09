import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 🎙️ AI 人生故事膠囊提問引導橫幅（獨立卡片，點擊直接口述分享）
class ElderStoryPromptBanner extends StatelessWidget {
  final bool isLandscape;
  final String prompt;
  final bool isFromChild;
  final VoidCallback onTap;

  const ElderStoryPromptBanner({
    super.key,
    this.isLandscape = false,
    required this.prompt,
    required this.isFromChild,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (isFromChild
                    ? const Color(0xFFF97316)
                    : const Color(0xFF10B981))
                .withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isLandscape ? 14 : 18,
              vertical: isLandscape ? 11 : 14,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isFromChild
                    ? [const Color(0xFFFFF7ED), const Color(0xFFFFEDD5)]
                    : [const Color(0xFFF0FDF4), const Color(0xFFDCFCE7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isFromChild
                    ? const Color(0xFFF97316).withValues(alpha: 0.7)
                    : const Color(0xFF10B981).withValues(alpha: 0.7),
                width: 1.6,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: isFromChild
                            ? const Color(0xFFEA580C)
                            : const Color(0xFF059669),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isFromChild ? '💌 兒女悄悄話提問' : '🎙️ 小豬想聽你說',
                            style: GoogleFonts.notoSansTc(
                              fontSize: isLandscape ? 11 : 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '跟小豬說故事 🎙️',
                          style: GoogleFonts.notoSansTc(
                            fontSize: isLandscape ? 11.5 : 12.5,
                            fontWeight: FontWeight.w900,
                            color: isFromChild
                                ? const Color(0xFFC2410C)
                                : const Color(0xFF047857),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 11,
                          color: isFromChild
                              ? const Color(0xFFC2410C)
                              : const Color(0xFF047857),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '「$prompt」',
                  style: GoogleFonts.notoSansTc(
                    fontSize: isLandscape ? 14 : 15.5,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF451A03),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
