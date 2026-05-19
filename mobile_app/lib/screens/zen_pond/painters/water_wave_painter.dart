import 'package:flutter/material.dart';
import 'dart:math' as math;

class WaterWavePainter extends CustomPainter {
  final double animationValue;
  final bool isSOSMode;

  WaterWavePainter({required this.animationValue, this.isSOSMode = false});

  @override
  void paint(Canvas canvas, Size size) {
    // 使用原本的青石綠與水藍綠作為波浪顏色，確保在淺底色上可見
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0 // 加粗波紋讓它更顯眼
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0); // 加上柔和模糊，模擬水面質感

    // 在水面上繪製多個不同位置、不同時間差的「擴散漣漪」
    
    // 漣漪 1 (左上)
    _drawExpandingRipple(canvas, size, paint, 
        center: Offset(size.width * 0.3, size.height * 0.2), 
        progress: animationValue, 
        color: const Color(0xFFBCE0D1));
        
    // 漣漪 2 (右下)
    _drawExpandingRipple(canvas, size, paint, 
        center: Offset(size.width * 0.75, size.height * 0.65), 
        progress: (animationValue + 0.33) % 1.0, // 錯開動畫時間
        color: const Color(0xFFD4E9DF));
        
    // 漣漪 3 (中下)
    _drawExpandingRipple(canvas, size, paint, 
        center: Offset(size.width * 0.4, size.height * 0.85), 
        progress: (animationValue + 0.66) % 1.0, 
        color: const Color(0xFFBCE0D1));
        
    // 漣漪 4 (右上，較大)
    _drawExpandingRipple(canvas, size, paint, 
        center: Offset(size.width * 0.8, size.height * 0.1), 
        progress: (animationValue + 0.5) % 1.0, 
        color: const Color(0xFFD4E9DF),
        scale: 1.5);
  }

  // 繪製單個緩慢擴散並漸隱的漣漪
  void _drawExpandingRipple(Canvas canvas, Size size, Paint paint, 
      {required Offset center, required double progress, required Color color, double scale = 1.0}) {
    
    // 漣漪半徑隨進度擴大 (最大半徑)
    double maxRadius = size.width * 0.6 * scale;
    double radius = progress * maxRadius;
    
    // 漣漪的不透明度 (開始時淡，中間最清楚，擴散到最大時消失)
    double opacity = math.sin(progress * math.pi) * 0.7; // 最高 70% 不透明度
    
    paint.color = color.withOpacity(opacity);
    canvas.drawCircle(center, radius, paint);
    
    // 畫第二圈內圈漣漪 (增添層次感)
    if (radius > 40) {
      paint.color = color.withOpacity(opacity * 0.4); // 內圈更淡
      canvas.drawCircle(center, radius - 30, paint);
    }
  }

  @override
  bool shouldRepaint(covariant WaterWavePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue || oldDelegate.isSOSMode != isSOSMode;
  }
}
