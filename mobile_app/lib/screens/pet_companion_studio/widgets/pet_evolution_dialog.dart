import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/uban_motion.dart';
import '../../../widgets/ui/uban_text.dart';
import '../models/pet_growth_state.dart';

/// 進化畫面（設計稿 `#evo`）：深色幕＋旋轉光芒，舊階段小豬亮到發白、淡出，
/// 新階段小豬縮放彈出，再依序浮出「長大到第 N 階了！」「福氣小豬變得更有精神了」
/// 與「太棒了」按鈕。**只顯示、不寫入任何資料。**
///
/// 傳 [oldStage] 與 [breedId] 時用 `assets/images/pet_breeds/` 的正面圖做
/// 新舊對照；沒傳（例如 `PetStudioScreen` 的預覽）則退回舊的階段油畫圖。
/// 減少動態時直接顯示最終畫面、光芒不旋轉。
class PetEvolutionDialog extends StatefulWidget {
  final PetGrowthStage newStage;
  final PetGrowthStage? oldStage;

  /// `pink`／`black`；null 表示使用舊的 `pet_stages` 圖。
  final String? breedId;
  final String userName;

  const PetEvolutionDialog({
    super.key,
    required this.newStage,
    this.oldStage,
    this.breedId,
    this.userName = '宇璿',
  });

  static Future<void> show(
    BuildContext context,
    PetGrowthStage newStage, {
    String userName = '宇璿',
    PetGrowthStage? oldStage,
    String? breedId,
  }) {
    HapticFeedback.heavyImpact();
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '小豬長大了',
      barrierColor: const Color.fromRGBO(10, 20, 16, .82),
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: (context, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
      pageBuilder: (context, _, __) => PetEvolutionDialog(
        newStage: newStage,
        oldStage: oldStage,
        breedId: breedId,
        userName: userName,
      ),
    );
  }

  @override
  State<PetEvolutionDialog> createState() => _PetEvolutionDialogState();
}

class _PetEvolutionDialogState extends State<PetEvolutionDialog>
    with TickerProviderStateMixin {
  late final AnimationController _rays;
  late final AnimationController _seq;
  bool _inited = false;

  @override
  void initState() {
    super.initState();
    _rays = AnimationController(vsync: this, duration: const Duration(seconds: 12));
    _seq = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;
    if (reduceMotion(context)) {
      _seq.value = 1;
    } else {
      _rays.repeat();
      _seq.forward();
    }
  }

  @override
  void dispose() {
    _rays.dispose();
    _seq.dispose();
    super.dispose();
  }

  int get _newNo => widget.newStage.index + 1;
  int get _oldNo => (widget.oldStage?.index ?? math.max(0, widget.newStage.index - 1)) + 1;

  String _path(PetGrowthStage st, int no) => widget.breedId == null
      ? st.imageAssetPath
      : 'assets/images/pet_breeds/${widget.breedId}_front_$no.png';

  /// 時間窗 [from]~[to]（毫秒）換成 0~1。
  double _win(double ms, double from, double to) =>
      ((ms - from) / (to - from)).clamp(0.0, 1.0);

  static ColorFilter _bright(double b) => ColorFilter.matrix(<double>[
        b, 0, 0, 0, 0, //
        0, b, 0, 0, 0,
        0, 0, b, 0, 0,
        0, 0, 0, 1, 0,
      ]);

  @override
  Widget build(BuildContext context) {
    final oldStage = widget.oldStage ??
        PetGrowthStage.values[math.max(0, widget.newStage.index - 1)];
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 旋轉光芒
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: const Alignment(0, -.16),
                child: AnimatedBuilder(
                  animation: _rays,
                  builder: (context, _) => Transform.rotate(
                    angle: _rays.value * 2 * math.pi,
                    child: const SizedBox(
                      width: 560,
                      height: 560,
                      child: CustomPaint(painter: _RaysPainter()),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: AnimatedBuilder(
                  animation: _seq,
                  builder: (context, _) => _content(oldStage),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(PetGrowthStage oldStage) {
    final ms = _seq.value * 2500;
    // 舊小豬 0~1600ms：亮度 1→4(50%)→6(70%)，縮放 1.05(50%)→.6，70% 起淡出
    final oldT = _win(ms, 0, 1600);
    final oldBright = oldT < .5
        ? 1 + 3 * (oldT / .5)
        : oldT < .7
            ? 4 + 2 * ((oldT - .5) / .2)
            : 6.0;
    final oldScale = oldT < .5 ? 1 + .05 * (oldT / .5) : 1.05 - .45 * ((oldT - .5) / .5);
    final oldOpacity = oldT < .7 ? 1.0 : 1 - (oldT - .7) / .3;
    // 新小豬 900~1900ms：縮放 .5→1（彈性）、亮度 5→1、透明度 0→1
    final newT = _win(ms, 900, 1900);
    final newK = UbanMotion.springBack.transform(newT);
    final newScale = .5 + .5 * newK;
    final newBright = 5 - 4 * newT;
    final newOpacity = newT;

    double enter(double from) => Curves.easeOut.transform(_win(ms, from, from + 500));
    Widget rise(double from, Widget child) {
      final k = enter(from);
      return Opacity(
        opacity: k,
        child: Transform.translate(offset: Offset(0, 14 * (1 - k)), child: child),
      );
    }

    final imgBox = SizedBox(
      width: 200,
      height: 240,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (oldOpacity > 0)
            Opacity(
              opacity: oldOpacity,
              child: Transform.scale(
                scale: oldScale,
                child: ColorFiltered(
                  colorFilter: _bright(oldBright),
                  child: Image.asset(_path(oldStage, _oldNo), fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                ),
              ),
            ),
          if (newOpacity > 0)
            Opacity(
              opacity: newOpacity,
              child: Transform.scale(
                scale: newScale,
                child: ColorFiltered(
                  colorFilter: _bright(newBright),
                  child: Semantics(
                    label: '第 $_newNo 階小豬',
                    child: Image.asset(_path(widget.newStage, _newNo),
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          imgBox,
          const SizedBox(height: 14),
          rise(
            1600,
            Text(
              '長大到第 $_newNo 階了！',
              textAlign: TextAlign.center,
              style: ubanText(34, FontWeight.w900, Colors.white),
            ),
          ),
          const SizedBox(height: 14),
          rise(
            1800,
            Text(
              '福氣小豬變得更有精神了',
              textAlign: TextAlign.center,
              style: ubanText(18, FontWeight.w500, Colors.white),
            ),
          ),
          const SizedBox(height: 14),
          rise(
            2000,
            SizedBox(
              width: 260,
              height: 64,
              child: FilledButton(
                key: const ValueKey('pet-evo-close'),
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  Navigator.of(context).pop();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF3D9C7C),
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                ),
                child: Text('太棒了', style: ubanText(22, FontWeight.w900, Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `repeating-conic-gradient(rgba(255,240,190,.22) 0 10deg, transparent 10deg 20deg)`
/// 外罩 `radial-gradient(circle, #000 20%, transparent 68%)` 遮罩。
class _RaysPainter extends CustomPainter {
  const _RaysPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.saveLayer(Offset.zero & size, Paint());
    final p = Paint()..color = const Color.fromRGBO(255, 240, 190, .22);
    for (var i = 0; i < 18; i++) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), i * math.pi / 9,
          math.pi / 18, true, p);
    }
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const RadialGradient(
          colors: [Colors.black, Colors.black, Colors.transparent],
          stops: [0, .283, .962],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RaysPainter old) => false;
}
