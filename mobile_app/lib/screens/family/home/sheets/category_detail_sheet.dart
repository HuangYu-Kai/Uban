import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/activity_log_entry.dart';
import '../dialogs/full_dialogue_dialog.dart';

/// 顯示單一主題分類詳細動態清單 BottomSheet
void showCategoryDetailModal(
  BuildContext context, {
  required String categoryTitle,
  required IconData categoryIcon,
  required Color categoryColor,
  required List<Map<String, dynamic>> items,
}) {
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;

  final cleanTitle = categoryTitle.replaceAll(RegExp(r'^[^\w\u4e00-\u9fa5]+'), '').trim();
  final displayTitle = cleanTitle.isNotEmpty ? cleanTitle : categoryTitle;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (c) {
      return Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black87 : cs.primary.withValues(alpha: 0.08),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          children: [
            const SizedBox(height: 14),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: categoryColor.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(categoryIcon, color: categoryColor, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayTitle,
                          style: GoogleFonts.notoSansTc(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          '共 ${items.length} 筆$displayTitle詳細紀錄',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 13.5,
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                    onPressed: () => Navigator.pop(c),
                  ),
                ],
              ),
            ),
            Divider(color: cs.outlineVariant.withValues(alpha: 0.3), height: 24),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        '尚無該主題分類的新紀錄',
                        style: GoogleFonts.notoSansTc(color: cs.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      itemCount: items.length,
                      itemBuilder: (context, idx) {
                        final item = items[idx];
                        final parsed = ActivityLogParser.parseActivityLogItem(item, cs);
                        final isChat = parsed.isChat || item['isChat'] == true;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: cs.outline.withValues(alpha: isDark ? 0.3 : 0.15),
                              width: 1.2,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                                    decoration: BoxDecoration(
                                      color: parsed.themeColor.withValues(alpha: isDark ? 0.25 : 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      parsed.categoryTag,
                                      style: GoogleFonts.notoSansTc(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: parsed.themeColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                    decoration: BoxDecoration(
                                      color: isDark ? cs.surfaceContainerHighest : cs.surfaceContainerHighest.withValues(alpha: 0.6),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      parsed.statusText,
                                      style: GoogleFonts.notoSansTc(
                                        fontSize: 12.0,
                                        fontWeight: FontWeight.w700,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  if (parsed.timeText.isNotEmpty)
                                    Text(
                                      parsed.timeText,
                                      style: GoogleFonts.inter(
                                        fontSize: 13.0,
                                        color: cs.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: parsed.themeColor.withValues(alpha: isDark ? 0.25 : 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(parsed.icon, size: 17, color: parsed.themeColor),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          parsed.title,
                                          style: GoogleFonts.notoSansTc(
                                            fontSize: 16.0,
                                            fontWeight: FontWeight.bold,
                                            color: cs.onSurface,
                                            height: 1.35,
                                          ),
                                        ),
                                        if (parsed.subtitle != null && parsed.subtitle!.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            parsed.subtitle!,
                                            style: GoogleFonts.notoSansTc(
                                              fontSize: 13.5,
                                              height: 1.4,
                                              color: cs.onSurfaceVariant,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (isChat && (parsed.fullQuery.isNotEmpty || item['fullQuery'] != null)) ...[
                                const SizedBox(height: 12),
                                InkWell(
                                  onTap: () {
                                    showFullDialogueDialog(
                                      context,
                                      parsed.fullQuery.isNotEmpty ? parsed.fullQuery : (item['fullQuery'] as String? ?? ''),
                                      parsed.fullAi.isNotEmpty ? parsed.fullAi : (item['fullAi'] as String? ?? ''),
                                      parsed.timeText.isNotEmpty ? parsed.timeText : (item['time'] as String? ?? ''),
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.2 : 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.auto_awesome_rounded, size: 15, color: Color(0xFFF59E0B)),
                                        const SizedBox(width: 6),
                                        Text(
                                          '📖 展開檢視長輩與 AI 完整對話逐字稿',
                                          style: GoogleFonts.notoSansTc(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? const Color(0xFFFCD34D) : const Color(0xFFB45309),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}
