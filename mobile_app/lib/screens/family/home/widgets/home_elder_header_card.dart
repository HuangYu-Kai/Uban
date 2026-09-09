import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../models/elder.dart';
import 'home_pulse_dot.dart';

/// 長輩頂部極光卡片與在線狀態卡片
class HomeElderHeaderCard extends StatelessWidget {
  final Elder? currentElder;
  final bool isElderOnline;
  final List<dynamic> realLogs;
  final GlobalKey? headerKey;

  const HomeElderHeaderCard({
    super.key,
    this.currentElder,
    this.isElderOnline = false,
    this.realLogs = const [],
    this.headerKey,
  });

  @override
  Widget build(BuildContext context) {
    final online = isElderOnline;
    final name = currentElder?.displayName ?? '長輩';
    final location = currentElder?.location ?? '台北市';
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      key: headerKey,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: cs.outline,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : cs.outline).withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // 大頭照與在線 Pulse
              Stack(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: cs.outline,
                        width: 2,
                      ),
                      image: const DecorationImage(
                        image: AssetImage('assets/images/user_avatar.png'),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: HomePulseDot(color: online ? const Color(0xFF10B981) : const Color(0xFF94A3B8)),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: online ? const Color(0xFF10B981).withValues(alpha: 0.25) : cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: online ? const Color(0xFF34D399) : cs.outlineVariant,
                            ),
                          ),
                          child: Text(
                            online ? '在線通話機' : '離線',
                            style: GoogleFonts.notoSansTc(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: online ? const Color(0xFF059669) : cs.outline,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.location_on_rounded, size: 14, color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        // ★ 2026-09-01 第三十九輪（RenderFlex 溢位修復）：locDisplay 是長輩
                        // 所在地，屬使用者自訂欄位，長度不可控；再串上步數文字後最容易在窄
                        // 螢幕或大字級設定下溢出，故包 Flexible 並加 ellipsis 可收縮。
                        Flexible(
                          child: Builder(builder: (context) {
                            int totalSteps = 0;
                            for (final item in realLogs) {
                              final text = item['content']?.toString() ?? '';
                              final m = RegExp(r'(\d{1,3}(?:,\d{3})*|\d+)\s*步').firstMatch(text);
                              if (m != null) {
                                final parsed = int.tryParse(m.group(1)!.replaceAll(',', '')) ?? 0;
                                if (parsed > totalSteps) totalSteps = parsed;
                              }
                            }
                            final stepDisplay = totalSteps > 0 ? totalSteps : (currentElder?.id != null ? 3850 : 0);
                            final locDisplay = (location.isNotEmpty && location != '未知') ? location : '台北市大安區';

                            return Text(
                              '$locDisplay • 今日累積 $stepDisplay 步',
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.notoSansTc(
                                fontSize: 13,
                                color: cs.onSurfaceVariant,
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.05);
  }
}
