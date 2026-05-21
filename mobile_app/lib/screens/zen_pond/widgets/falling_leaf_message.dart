import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../controllers/zen_pond_controller.dart';

// 【落葉元件】手繪寫實葉片 CustomPainter 與複合物理飄落/浮動動畫

class FallingLeafMessage extends StatefulWidget {
  final LeafMessageItem item;
  final VoidCallback onTap;

  const FallingLeafMessage({
    super.key,
    required this.item,
    required this.onTap,
  });

  @override
  State<FallingLeafMessage> createState() => _FallingLeafMessageState();
}

class _FallingLeafMessageState extends State<FallingLeafMessage>
    with TickerProviderStateMixin {
  late AnimationController _idleController;
  AnimationController? _entranceController;

  late double _screenHeight;
  late double _screenWidth;
  bool _isEntranceComplete = false;

  @override
  void initState() {
    super.initState();

    // 1. 常態水面浮動動畫 (Idle Bobbing) - 永無止境的緩慢正弦律動
    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    )..repeat();

    // 2. 判斷是否為剛建立的新落葉 (3秒內建立的視為新落葉)
    final ageMs = DateTime.now().millisecondsSinceEpoch - widget.item.createdAt;
    if (ageMs < 3000) {
      _entranceController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2500),
      );

      _entranceController!.forward().then((_) {
        if (mounted) {
          setState(() {
            _isEntranceComplete = true;
          });
        }
      });
    } else {
      _isEntranceComplete = true;
    }
  }

  @override
  void dispose() {
    _idleController.dispose();
    _entranceController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 獲取螢幕尺寸以計算百分比定位
    final size = MediaQuery.of(context).size;
    _screenWidth = size.width;
    _screenHeight = size.height;

    // 計算目標靜止位置
    final targetX = widget.item.restingX * _screenWidth;
    final targetY = widget.item.restingY * _screenHeight;

    if (!_isEntranceComplete && _entranceController != null) {
      // 飄落登場動畫進行中
      return AnimatedBuilder(
        animation: _entranceController!,
        builder: (context, child) {
          final t = _entranceController!.value; // 0.0 -> 1.0

          // Y 座標：從螢幕上方 -100 降到靜止目標 Y
          final currentY = -100 + (targetY + 100) * t;

          // X 座標：在落水過程中做 sine 左右搖擺，並隨時間漸漸趨近 targetX
          final xSwing = math.sin(t * 3 * math.pi) * 35 * (1 - t);
          final currentX = targetX + xSwing;

          // 旋轉：螺旋打轉 3 圈
          final currentRotation = (1 - t) * 3 * 2 * math.pi + (widget.item.restingX * 2 * math.pi);

          // 縮放：從微小 0.2 展開到 1.0
          final currentScale = 0.2 + 0.8 * t;

          // 飄落透明度
          final currentOpacity = math.min(1.0, t * 1.5);

          return Positioned(
            left: currentX - 25,
            top: currentY - 25,
            child: Opacity(
              opacity: currentOpacity,
              child: Transform.scale(
                scale: currentScale,
                child: Transform.rotate(
                  angle: currentRotation,
                  child: _buildLeafBody(),
                ),
              ),
            ),
          );
        },
      );
    } else {
      // 登場完成，進入常態水面浮動 (Idle Bobbing)
      return AnimatedBuilder(
        animation: _idleController,
        builder: (context, child) {
          final t = _idleController.value * 2 * math.pi;

          // 微幅 Y 浮動 (上下 4.0 像素)
          final bobbingY = math.sin(t) * 4.0;
          // 微幅 X 划移 (左右 2.0 像素)
          final bobbingX = math.cos(t) * 2.0;
          // 微幅角度晃動 (約 -3度 到 +3度)
          final bobbingRotation = math.sin(t) * 0.05 + (widget.item.restingX * 2 * math.pi);

          return Positioned(
            left: targetX + bobbingX - 25,
            top: targetY + bobbingY - 25,
            child: Transform.rotate(
              angle: bobbingRotation,
              child: _buildLeafBody(),
            ),
          );
        },
      );
    }
  }

  Widget _buildLeafBody() {
    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SizedBox(
          width: 50,
          height: 60,
          child: CustomPaint(
            painter: LeafPainter(colorType: widget.item.colorType),
          ),
        ),
      ),
    );
  }
}

// 🎨 手繪高精細落葉 Painters
class LeafPainter extends CustomPainter {
  final LeafColorType colorType;

  LeafPainter({required this.colorType});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    Color leafColor;
    Color veinColor;

    // 莫蘭迪高質感禪意色系
    switch (colorType) {
      case LeafColorType.yellow:
        leafColor = const Color(0xFFE5C158); // 莫蘭迪金黃
        veinColor = const Color(0xFFC49F30); // 稍深黃褐色葉脈
        break;
      case LeafColorType.red:
        leafColor = const Color(0xFFC08A8A); // 莫蘭迪楓紅
        veinColor = const Color(0xFF9E6565); // 深紅褐葉脈
        break;
      case LeafColorType.green:
        leafColor = const Color(0xFF8CAF9F); // 莫蘭迪碧綠
        veinColor = const Color(0xFF6B8D7C); // 深綠灰葉脈
        break;
    }

    final w = size.width;
    final h = size.height;

    // 1. 繪製葉柄 (Petiole) - 稍微探出葉底
    final stemPaint = Paint()
      ..color = veinColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawLine(Offset(w * 0.1, h * 0.95), Offset(w * 0.25, h * 0.8), stemPaint);

    // 2. 繪製精緻的不對稱葉身形狀 (Path)
    paint.color = leafColor;
    final path = Path();

    // 起點是葉柄根部
    path.moveTo(w * 0.25, h * 0.8);
    // 左半緣弧 (優雅外擴再收縮至葉尖)
    path.quadraticBezierTo(w * -0.15, h * 0.35, w * 0.75, h * 0.05);
    // 右半緣弧 (不對稱微調，營造自然寫實感)
    path.quadraticBezierTo(w * 1.05, h * 0.55, w * 0.25, h * 0.8);
    path.close();

    // 繪製陰影 (為落葉營造浮在水面上的立體感)
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withOpacity(0.12)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
    );

    // 繪製葉身
    canvas.drawPath(path, paint);

    // 3. 繪製主葉脈 (Main stem) - 葉基至葉尖
    final mainVeinPaint = Paint()
      ..color = veinColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawLine(Offset(w * 0.25, h * 0.8), Offset(w * 0.75, h * 0.05), mainVeinPaint);

    // 4. 繪製左右細緻副葉脈 (Lateral veins)
    final sideVeinPaint = Paint()
      ..color = veinColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    // 左側副葉脈 (從主脈不同比例分佈)
    canvas.drawLine(Offset(w * 0.38, h * 0.61), Offset(w * 0.16, h * 0.52), sideVeinPaint);
    canvas.drawLine(Offset(w * 0.50, h * 0.43), Offset(w * 0.28, h * 0.31), sideVeinPaint);
    canvas.drawLine(Offset(w * 0.63, h * 0.24), Offset(w * 0.46, h * 0.15), sideVeinPaint);

    // 右側副葉脈
    canvas.drawLine(Offset(w * 0.33, h * 0.69), Offset(w * 0.58, h * 0.68), sideVeinPaint);
    canvas.drawLine(Offset(w * 0.45, h * 0.51), Offset(w * 0.72, h * 0.47), sideVeinPaint);
    canvas.drawLine(Offset(w * 0.58, h * 0.32), Offset(w * 0.80, h * 0.26), sideVeinPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
