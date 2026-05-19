import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/zen_pond_controller.dart';

class PondBackground extends StatefulWidget {
  const PondBackground({super.key});

  @override
  State<PondBackground> createState() => _PondBackgroundState();
}

class _PondBackgroundState extends State<PondBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // 20 秒一個週期的緩慢呼吸流動
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat(reverse: true); 
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 根據真實時間回傳不同的漸層顏色 (全面使用極淡的莫蘭迪粉彩色系)
  List<Color> _getGradientColorsForTime(DateTime time, {int? mockHour}) {
    int hour = mockHour ?? time.hour;
    if (hour >= 5 && hour < 9) {
      // 黎明晨光 (極淡的晨曦微黃與原始淺綠)
      return [const Color(0xFFFFF3E0), const Color(0xFFE6F5EC)];
    } else if (hour >= 9 && hour < 16) {
      // 白天明亮 (極淡的青石綠與極淡的水藍)
      return [const Color(0xFFE8F5E9), const Color(0xFFE0F2F1)];
    } else if (hour >= 16 && hour < 19) {
      // 黃昏夕陽 (極淡的暖霞粉與極淡的紫羅蘭)
      return [const Color(0xFFFBE9E7), const Color(0xFFF3E5F5)];
    } else {
      // 夜晚深邃 (稍微加深一點點的幽靜藍灰與青綠)
      return [const Color(0xFFCFD8DC), const Color(0xFFD4E9DF)];
    }
  }

  @override
  Widget build(BuildContext context) {
    // 監聽 Controller，用以處理 SOS 紅光遮罩
    final controller = context.watch<ZenPondController>();
    // 取得當前手機真實時間的對應環境色 (或測試覆寫時間)
    final colors = _getGradientColorsForTime(DateTime.now(), mockHour: controller.mockHour);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // 利用動畫數值微微移動漸層的中心，產生水色緩緩流動的生動感
        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(
                0.0 + _controller.value * 0.15, // 緩慢平移
                0.0 - _controller.value * 0.15,
              ),
              radius: 1.5,
              colors: colors,
            ),
          ),
          // 若為 SOS 模式，疊加紅色半透明遮罩
          child: controller.isSOSMode 
              ? Container(color: Colors.red.withOpacity(0.3)) 
              : null,
        );
      },
    );
  }
}
