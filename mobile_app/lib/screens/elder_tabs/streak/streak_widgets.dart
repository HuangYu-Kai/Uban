import 'package:flutter/material.dart';

import '../../../widgets/ui/ui.dart';
import 'streak_service.dart';

/// 連勝專用的固定色（設計稿 `.week i.on`、火焰漸層、慶祝畫面金色數字）。
///
/// 設計系統的 [UbanColors] 沒有對應的語意色（它們是慶祝用的「橘金」，不隨亮暗
/// 主題改變），所以集中放在這裡，避免散落在各個 widget 裡。
class StreakPalette {
  StreakPalette._();

  static const Color dayOn = Color(0xFFF59A3C);
  static const Color gold = Color(0xFFFFB547);
  static const Color flameBottom = Color(0xFFF26B3A);
  static const Color flameTop = Color(0xFFFFB547);
  static const Color flameCore = Color(0xFFFFE08A);
}

/// 設計稿 `#i-flame` 火焰（24×24 viewBox 的向量路徑，以 CustomPainter 重畫）。
class StreakFlame extends StatelessWidget {
  final double size;

  const StreakFlame({super.key, this.size = 36});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _FlamePainter()),
      ),
    );
  }
}

class _FlamePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);

    final outer = Path()
      ..moveTo(12, 22)
      ..cubicTo(7.6, 22, 4.5, 19, 4.5, 14.8)
      ..cubicTo(4.5, 11.4, 6.7, 9.1, 8.2, 7.5)
      ..cubicTo(8.6, 9.2, 9.5, 10.4, 10.6, 10.9)
      ..cubicTo(10.3, 7, 12, 4, 14.6, 2)
      ..cubicTo(14.5, 4.8, 15.9, 6.6, 17.4, 8.4)
      ..cubicTo(18.7, 9.9, 20, 11.7, 20, 14.6)
      ..cubicTo(20, 19, 16.6, 22, 12, 22)
      ..close();
    final outerPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [StreakPalette.flameBottom, StreakPalette.flameTop],
      ).createShader(const Rect.fromLTWH(0, 2, 24, 20));
    canvas.drawPath(outer, outerPaint);

    final inner = Path()
      ..moveTo(12, 22)
      ..cubicTo(9.8, 22, 8.3, 20.5, 8.3, 18.4)
      ..cubicTo(8.3, 16.5, 9.6, 15.2, 10.7, 14.0)
      ..cubicTo(10.9, 15, 11.5, 15.6, 12.2, 15.8)
      ..cubicTo(12.3, 13.9, 13.2, 12.4, 14.5, 11.5)
      ..cubicTo(14.5, 13.1, 15.1, 14.1, 15.8, 15.1)
      ..cubicTo(16.4, 16.0, 16.9, 16.9, 16.9, 18.2)
      ..cubicTo(16.9, 20.4, 14.8, 22, 12, 22)
      ..close();
    canvas.drawPath(inner, Paint()..color = StreakPalette.flameCore);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FlamePainter old) => false;
}

/// 設計稿 `.week`：一～日 7 欄，每欄上方星期、下方 34 圓點。
/// 完成＝橘底白勾；今天未完成＝橘色環；其餘＝灰底。[onDark] 用於慶祝畫面的深色底。
class StreakWeekRow extends StatelessWidget {
  final List<StreakWeekDay> week;
  final bool onDark;

  /// 今天那一格的縮放（慶祝時用來做「啵」一下的彈跳）。
  final double todayScale;

  const StreakWeekRow({
    super.key,
    required this.week,
    this.onDark = false,
    this.todayScale = 1,
  });

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final labelColor = onDark ? Colors.white.withValues(alpha: .7) : c.text2;
    final offColor = onDark ? Colors.white.withValues(alpha: .12) : c.surface2;
    final doneCount = week.where((d) => d.done).length;
    return Semantics(
      label: '本週完成 $doneCount 天',
      excludeSemantics: true,
      child: Row(
        children: [
          for (final d in week)
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(d.label,
                      maxLines: 1,
                      style: ubanText(18, FontWeight.w700, labelColor)),
                  const SizedBox(height: 4),
                  Transform.scale(
                    scale: d.isToday ? todayScale : 1,
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: d.done ? StreakPalette.dayOn : offColor,
                        border: (d.isToday && !d.done)
                            ? Border.all(color: StreakPalette.dayOn, width: 2.5)
                            : null,
                      ),
                      child: d.done
                          ? const Icon(Icons.check_rounded,
                              size: 22, color: Colors.white)
                          : null,
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

/// 設計稿 `.streakcard`：火焰＋「連續 N 天」＋本週 7 天圓點。
class StreakCard extends StatelessWidget {
  final StreakSnapshot snapshot;

  const StreakCard({super.key, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return UbanCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.warmContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const StreakFlame(size: 36),
              ),
              const SizedBox(width: 14),
              // 數字可能很大（三位數）＋大字級：數字列用 FittedBox 縮小，說明可換行。
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text.rich(
                        TextSpan(
                          text: '${snapshot.days}',
                          style: ubanBrandText(36, FontWeight.w600, c.text,
                              height: 1.2),
                          children: [
                            TextSpan(
                              text: ' 天',
                              style: ubanText(20, FontWeight.w700, c.text),
                            ),
                          ],
                        ),
                        maxLines: 1,
                      ),
                    ),
                    Text('連續把每天的事都做完',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: ubanText(18, FontWeight.w400, c.text2)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          StreakWeekRow(week: snapshot.week),
        ],
      ),
    );
  }
}
