import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../theme/uban_motion.dart';
import '../../../widgets/ui/pressable_scale.dart';
import '../../../widgets/ui/uban_button.dart';
import '../../../widgets/ui/uban_text.dart';
import 'streak_service.dart';
import 'streak_widgets.dart';

/// 顯示連勝慶祝覆蓋層（設計稿 `#streakfx`）。
///
/// 用根導覽的透明 dialog 路由顯示，這樣返回鍵可以關閉它，而且稍後才彈出的來電
/// 對話框（同樣是 route）一定在它上面，不會被擋住。「去餵小豬」會先關掉本層，再
/// 呼叫 [onFeedPig]（由 `ElderHomeScreen` 傳入、轉成既有的 `_onNavTap(2)`）。
Future<void> showStreakCelebration(
  BuildContext context,
  StreakCelebration data, {
  VoidCallback? onFeedPig,
}) {
  return showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    barrierLabel: '連續完成慶祝',
    barrierColor: Colors.transparent,
    transitionDuration: reduceMotion(context)
        ? Duration.zero
        : const Duration(milliseconds: 300),
    transitionBuilder: (ctx, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
    pageBuilder: (ctx, _, __) => StreakCelebrationOverlay(
      data: data,
      onClose: () {
        final nav = Navigator.of(ctx);
        if (nav.canPop()) nav.pop();
      },
      onFeedPig: onFeedPig == null
          ? null
          : () {
              final nav = Navigator.of(ctx);
              if (nav.canPop()) nav.pop();
              onFeedPig();
            },
    ),
  );
}

/// 慶祝畫面本體（獨立 widget 以便測試；背景固定深色，不隨亮暗主題）。
class StreakCelebrationOverlay extends StatefulWidget {
  final StreakCelebration data;
  final VoidCallback onClose;
  final VoidCallback? onFeedPig;

  const StreakCelebrationOverlay({
    super.key,
    required this.data,
    required this.onClose,
    this.onFeedPig,
  });

  @override
  State<StreakCelebrationOverlay> createState() =>
      _StreakCelebrationOverlayState();
}

class _StreakCelebrationOverlayState extends State<StreakCelebrationOverlay>
    with SingleTickerProviderStateMixin {
  // 全部時間點（毫秒）對應設計稿 ui.js／ui.css：450ms 後數字翻滾＋週條補今天＋彩紙，
  // 翻滾延遲 .5s／.7s，獎勵卡延遲 1.3s／.5s，胡蘿蔔 1.6s 起搖兩次。
  static const int _totalMs = 4200;
  static const int _rollStartMs = 450 + 500;
  static const int _rewardStartMs = 450 + 1300;
  static const int _popStartMs = 450;

  late final AnimationController _ctrl;
  bool _reduce = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _totalMs),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _reduce = reduceMotion(context);
    if (_reduce) {
      _ctrl.value = 1; // 不放翻滾、彈跳，直接顯示最終畫面
    } else {
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 把 [startMs, startMs+durMs] 區間映射成 0..1（套用 [curve]）。
  double _seg(double t, int startMs, int durMs, [Curve curve = Curves.linear]) {
    final ms = t * _totalMs;
    final v = ((ms - startMs) / durMs).clamp(0.0, 1.0);
    return curve.transform(v);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      label: '連續完成慶祝',
      child: Material(
        color: const Color.fromRGBO(17, 25, 22, .88),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!_reduce) const Positioned.fill(child: _Confetti()),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: box.maxHeight),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 16),
                        child: AnimatedBuilder(
                          animation: _ctrl,
                          builder: (context, _) => _content(d),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(StreakCelebration d) {
    final t = _ctrl.value;
    final flameIn = _reduce ? 1.0 : _seg(t, 0, 700, UbanMotion.springBack);
    final roll = _reduce
        ? 1.0
        : _seg(t, _rollStartMs, 700, const Cubic(.34, 1.4, .64, 1));
    final reward = _reduce
        ? 1.0
        : _seg(t, _rewardStartMs, 500, const Cubic(.34, 1.3, .64, 1));
    final todayDone = _reduce || t * _totalMs >= _popStartMs;
    // 今天那格：補上後彈一下（1 → 1.35 → 1，600ms）。
    final pop = _reduce ? 0.0 : _seg(t, _popStartMs, 600);
    final todayScale = 1 + 0.35 * math.sin(pop * math.pi);
    final carrotMs = t * _totalMs - 2050;
    // 胡蘿蔔搖兩次（每次 1s）。
    final wiggle = (_reduce || carrotMs < 0 || carrotMs > 2000)
        ? 0.0
        : math.sin((carrotMs % 1000) / 1000 * math.pi * 2);

    final week = todayDone ? d.weekAfter : d.weekBefore;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Transform.scale(
          scale: 0.3 + 0.7 * flameIn,
          child: Transform.rotate(
            angle: -0.21 * (1 - flameIn),
            child: Opacity(
              opacity: flameIn.clamp(0.0, 1.0),
              child: Container(
                width: 110,
                height: 110,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(255, 181, 71, .16),
                  borderRadius: BorderRadius.circular(36),
                ),
                child: const StreakFlame(size: 76),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _RollNumber(from: d.fromDays, to: d.toDays, progress: roll),
        const SizedBox(height: 12),
        Text(
          '連續 ${d.toDays} 天全部完成！',
          textAlign: TextAlign.center,
          style: ubanText(28, FontWeight.w900, Colors.white),
        ),
        const SizedBox(height: 12),
        StreakWeekRow(week: week, onDark: true, todayScale: todayScale),
        const SizedBox(height: 18),
        Opacity(
          opacity: reward.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - reward)),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(255, 255, 255, .1),
                border: Border.all(
                    color: const Color.fromRGBO(255, 255, 255, .14)),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Transform.rotate(
                    angle: wiggle * 0.2,
                    child: Transform.translate(
                      offset: Offset(0, -10 * wiggle.abs()),
                      child: ExcludeSemantics(
                        child: Image.asset(
                          'assets/images/pet_foods/food_carrot.png',
                          width: 58,
                          height: 58,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const SizedBox(
                            width: 58,
                            height: 58,
                            child: Center(
                              child: Text('🥕', style: TextStyle(fontSize: 36)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('今天打卡賺到 ${d.earnedCarrots} 根胡蘿蔔',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: ubanText(20, FontWeight.w900, Colors.white)),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('拿去餵小豬吧',
                              style: ubanText(18, FontWeight.w400,
                                  Colors.white.withValues(alpha: .75))),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (widget.onFeedPig != null)
          UbanButton(
            label: '去餵小豬',
            size: UbanButtonSize.xl,
            onPressed: widget.onFeedPig,
          ),
        const SizedBox(height: 8),
        _GhostCloseButton(label: '好', onTap: widget.onClose),
      ],
    );
  }
}

/// 白字、透明底的「好」：設計稿 `.btn.ghost` 套白字，但按鈕高度維持長輩端 ≥60。
class _GhostCloseButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _GhostCloseButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: PressableScale(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60, minWidth: 120),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(label, style: ubanText(20, FontWeight.w700, Colors.white)),
        ),
      ),
    );
  }
}

/// 設計稿 `.roll`：兩個數字上下疊，翻滾時從 [from] 滑到 [to]。
/// 外框尺寸固定（不隨系統字級放大），數字過寬時用 FittedBox 縮小。
class _RollNumber extends StatelessWidget {
  final int from;
  final int to;
  final double progress;

  const _RollNumber(
      {required this.from, required this.to, required this.progress});

  @override
  Widget build(BuildContext context) {
    const h = 84.0;
    final style = ubanBrandText(76, FontWeight.w600, StreakPalette.gold,
        height: h / 76);
    Widget cell(int n) => SizedBox(
          width: 140,
          height: h,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('$n',
                maxLines: 1, style: style, textScaler: TextScaler.noScaling),
          ),
        );
    return Semantics(
      label: '$to',
      excludeSemantics: true,
      child: SizedBox(
        width: 140,
        height: h,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: 0,
            maxHeight: h * 2,
            child: Transform.translate(
              offset: Offset(0, -h * progress),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [cell(from), cell(to)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 彩紙：120 片，物理常數取自 ui.js `confetti()`（每幀 vy += .32、vx *= .99，
/// 以 60fps 為單位換算成時間步），450ms 後從畫面上方 32% 處噴出，3.2 秒後停止。
class _Confetti extends StatefulWidget {
  const _Confetti();

  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _Particle {
  double x, y, vx, vy, r, a, va;
  final Color color;
  _Particle(
      this.x, this.y, this.vx, this.vy, this.r, this.a, this.va, this.color);
}

class _ConfettiState extends State<_Confetti>
    with SingleTickerProviderStateMixin {
  static const _colors = [
    Color(0xFF59B294),
    Color(0xFFFFB547),
    Color(0xFFF26B3A),
    Color(0xFFF09AA6),
    Color(0xFF8DBBEA),
    Color(0xFFFFE08A),
  ];
  static const int _delayMs = 450;
  static const int _runMs = 3200;

  late final Ticker _ticker;
  final _repaint = ValueNotifier<int>(0);
  final List<_Particle> _ps = [];
  Size _size = Size.zero;
  Duration _last = Duration.zero;
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  void _seed() {
    final rnd = math.Random();
    for (var i = 0; i < 120; i++) {
      _ps.add(_Particle(
        _size.width / 2 + (rnd.nextDouble() - .5) * 60,
        _size.height * .32,
        (rnd.nextDouble() - .5) * 11,
        -rnd.nextDouble() * 12 - 4,
        rnd.nextDouble() * 6 + 4,
        rnd.nextDouble() * 6,
        (rnd.nextDouble() - .5) * .3,
        _colors[i % _colors.length],
      ));
    }
  }

  void _tick(Duration elapsed) {
    final ms = elapsed.inMilliseconds;
    if (ms < _delayMs || _size.isEmpty) return;
    if (!_seeded) {
      _seeded = true;
      _seed();
      _last = elapsed;
    }
    if (ms - _delayMs > _runMs) {
      _ps.clear();
      _repaint.value++;
      _ticker.stop();
      return;
    }
    final f = ((elapsed - _last).inMicroseconds / 16667).clamp(0.0, 4.0);
    _last = elapsed;
    final drag = math.pow(.99, f).toDouble();
    for (final p in _ps) {
      p.vy += .32 * f;
      p.vx *= drag;
      p.x += p.vx * f;
      p.y += p.vy * f;
      p.a += p.va * f;
    }
    _repaint.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: LayoutBuilder(builder: (context, box) {
          _size = Size(box.maxWidth, box.maxHeight);
          return CustomPaint(
            size: _size,
            painter: _ConfettiPainter(_ps, _repaint),
          );
        }),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> ps;

  _ConfettiPainter(this.ps, Listenable repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in ps) {
      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.a);
      paint.color = p.color;
      canvas.drawRect(Rect.fromLTWH(-p.r / 2, -p.r / 4, p.r, p.r / 2), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => true;
}
