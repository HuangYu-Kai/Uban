import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 顯示 AI 語音陪伴對話紀錄彈窗
void showFullDialogueDialog(BuildContext context, String query, String ai, String timeStr) {
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;

  showDialog(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: cs.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          const Icon(Icons.auto_stories_rounded, color: Color(0xFFF59E0B)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '🗣️ AI 語音陪伴對話紀錄 ($timeStr)',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.notoSansTc(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('👴 長輩提問：', style: GoogleFonts.notoSansTc(color: cs.primary, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
            ),
            child: Text(query, style: GoogleFonts.notoSansTc(color: cs.onSurface, height: 1.4)),
          ),
          const SizedBox(height: 14),
          Text('🤖 AI 小嘎回報與陪伴：', style: GoogleFonts.notoSansTc(color: isDark ? const Color(0xFFFCD34D) : const Color(0xFFD97706), fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
            ),
            child: Text(ai, style: GoogleFonts.notoSansTc(color: cs.onSurface, height: 1.4)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: Text('關閉', style: GoogleFonts.notoSansTc(color: cs.primary, fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
}
