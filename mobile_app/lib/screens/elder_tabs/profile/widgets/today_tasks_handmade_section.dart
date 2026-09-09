import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 📋 今日生活排程與用藥打卡手帳（直接呈現在卡片上，支援大字體打卡）
class TodayTasksHandmadeSection extends StatelessWidget {
  final List<Map<String, dynamic>> reminders;
  final Set<int> completedReminderIds;
  final bool isLoadingReminders;
  final ValueChanged<int> onToggleTask;
  final bool isLandscape;

  const TodayTasksHandmadeSection({
    super.key,
    required this.reminders,
    required this.completedReminderIds,
    required this.isLoadingReminders,
    required this.onToggleTask,
    this.isLandscape = false,
  });

  @override
  Widget build(BuildContext context) {
    final activeReminders =
        reminders.where((r) => r['is_active'] != false).toList();
    final totalTasks = activeReminders.length;
    final completedTasks = activeReminders
        .where((r) => completedReminderIds.contains(r['id']))
        .length;
    final bool isAllCompleted = totalTasks > 0 && completedTasks >= totalTasks;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isLandscape ? 14 : 20,
        vertical: isLandscape ? 10 : 20,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF9),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFEADBCE), width: 1.8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF78350F).withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 標頭
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(isLandscape ? 5 : 7),
                decoration: const BoxDecoration(
                  color: Color(0xFFFEF3C7),
                  shape: BoxShape.circle,
                ),
                child: Text('📋', style: TextStyle(fontSize: isLandscape ? 15 : 18)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '今日生活排程與用藥',
                      style: GoogleFonts.notoSansTc(
                        fontSize: isLandscape ? 16.5 : 18,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF451A03),
                      ),
                    ),
                    Text(
                      '點擊打卡即可完成，小豬陪您規律生活',
                      style: GoogleFonts.notoSansTc(
                        fontSize: isLandscape ? 11.5 : 12.5,
                        color: const Color(0xFF8C6D58),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // 完成進度標籤
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isLandscape ? 8 : 10,
                  vertical: isLandscape ? 3 : 5,
                ),
                decoration: BoxDecoration(
                  color: isAllCompleted
                      ? const Color(0xFFECFDF5)
                      : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isAllCompleted
                        ? const Color(0xFFA7F3D0)
                        : const Color(0xFFFDE68A),
                  ),
                ),
                child: Text(
                  isAllCompleted ? '全數達標 🌟' : '已完成 $completedTasks/$totalTasks',
                  style: GoogleFonts.notoSansTc(
                    fontSize: isLandscape ? 12 : 13,
                    fontWeight: FontWeight.w900,
                    color: isAllCompleted
                        ? const Color(0xFF047857)
                        : const Color(0xFF92400E),
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: isLandscape ? 8 : 14),

          if (isLoadingReminders)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF59B294)),
              ),
            )
          else if (activeReminders.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              alignment: Alignment.center,
              child: Text(
                '今天尚無待辦事項，悠閒放鬆一下吧！🌸',
                style: GoogleFonts.notoSansTc(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF8C6D58),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: activeReminders.length,
              separatorBuilder: (_, __) => SizedBox(height: isLandscape ? 4 : 10),
              itemBuilder: (context, index) {
                final r = activeReminders[index];
                final int rId = r['id'] as int;
                final bool isDone = completedReminderIds.contains(rId);
                final String cat = (r['category'] ?? '').toString();

                String catEmoji = '⏰';
                Color catBg = const Color(0xFFF1F5F9);
                if (cat == 'medication') {
                  catEmoji = '💊';
                  catBg = const Color(0xFFFFE4E6);
                } else if (cat == 'water') {
                  catEmoji = '💧';
                  catBg = const Color(0xFFE0F2FE);
                } else if (cat == 'exercise') {
                  catEmoji = '👟';
                  catBg = const Color(0xFFFEF3C7);
                }

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => onToggleTask(rId),
                    borderRadius: BorderRadius.circular(isLandscape ? 16 : 20),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: isLandscape ? 3.5 : 12,
                      ),
                      decoration: BoxDecoration(
                        color: isDone
                            ? const Color(0xFFF0FDF4)
                            : const Color(0xFFFAF7F2),
                        borderRadius: BorderRadius.circular(isLandscape ? 16 : 20),
                        border: Border.all(
                          color: isDone
                              ? const Color(0xFF86EFAC)
                              : const Color(0xFFEADBCE),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          // 類別 Emoji 圖標
                          Container(
                            width: isLandscape ? 30 : 44,
                            height: isLandscape ? 30 : 44,
                            decoration: BoxDecoration(
                              color: catBg,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                catEmoji,
                                style: TextStyle(fontSize: isLandscape ? 15 : 22),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // 內容文字
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: isDone
                                            ? const Color(0xFFDCFCE7)
                                            : const Color(0xFFF5EBE1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        r['time_str'] ?? '',
                                        style: GoogleFonts.inter(
                                          fontSize: isLandscape ? 10.5 : 12.5,
                                          fontWeight: FontWeight.w800,
                                          color: isDone
                                              ? const Color(0xFF15803D)
                                              : const Color(0xFF78350F),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        r['title'] ?? '',
                                        style: GoogleFonts.notoSansTc(
                                          fontSize: isLandscape ? 13.5 : 16.5,
                                          fontWeight: FontWeight.w900,
                                          color: isDone
                                              ? const Color(0xFF166534)
                                              : const Color(0xFF451A03),
                                          decoration: isDone
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                if ((r['note'] ?? '').toString().isNotEmpty) ...[
                                  const SizedBox(height: 1),
                                  Text(
                                    r['note'],
                                    style: GoogleFonts.notoSansTc(
                                      fontSize: isLandscape ? 10.5 : 13,
                                      color: isDone
                                          ? const Color(0xFF15803D)
                                          : const Color(0xFF78350F),
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          // ── 大字體觸控打卡核選扭 ──
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isLandscape ? 8 : 12,
                              vertical: isLandscape ? 3.5 : 7,
                            ),
                            decoration: BoxDecoration(
                              color: isDone
                                  ? const Color(0xFF10B981)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDone
                                    ? const Color(0xFF059669)
                                    : const Color(0xFFF59E0B),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (isDone
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFFF59E0B))
                                      .withValues(alpha: 0.18),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isDone
                                      ? Icons.check_circle_rounded
                                      : Icons.touch_app_rounded,
                                  size: isLandscape ? 13 : 16,
                                  color: isDone
                                      ? Colors.white
                                      : const Color(0xFF92400E),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  isDone ? '已打卡' : '打卡',
                                  style: GoogleFonts.notoSansTc(
                                    fontSize: isLandscape ? 11 : 13,
                                    fontWeight: FontWeight.w900,
                                    color: isDone
                                        ? Colors.white
                                        : const Color(0xFF92400E),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

          SizedBox(height: isLandscape ? 6 : 14),

          // 溫馨提示字卡
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isLandscape ? 12 : 14,
              vertical: isLandscape ? 5 : 9,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              children: [
                Text('💡', style: TextStyle(fontSize: isLandscape ? 13 : 15)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '定時服藥與多喝溫水，小豬會長得圓滾有元氣喔！',
                    style: GoogleFonts.notoSansTc(
                      fontSize: isLandscape ? 11.5 : 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF92400E),
                    ),
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
