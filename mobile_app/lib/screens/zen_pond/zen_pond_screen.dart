import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import 'controllers/zen_pond_controller.dart';
import 'widgets/pond_background.dart';
import 'widgets/interactive_ripples.dart';
import 'widgets/pond_decorations.dart';
import 'widgets/koi_fish_notification.dart';
import 'widgets/lotus_leaf_card.dart';

class ZenPondScreen extends StatefulWidget {
  const ZenPondScreen({super.key});

  @override
  State<ZenPondScreen> createState() => ZenPondScreenState();
}

class ZenPondScreenState extends State<ZenPondScreen> {
  final ZenPondController _controller = ZenPondController();

  void addNotification(String message) {
    _controller.showNotification(message);
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: const _ZenPondContent(),
    );
  }
}

class _ZenPondContent extends StatelessWidget {
  const _ZenPondContent();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ZenPondController>();
    
    // 莫蘭迪淺藍綠底色，SOS 模式時轉紅
    final Color bgColor = controller.isSOSMode 
        ? const Color(0xFFFFEAEA) 
        : const Color(0xFFE6F5EC); 

    return Scaffold(
      backgroundColor: bgColor,
      body: InteractiveRipples(
        onTap: controller.handleTap,
        isSOSMode: controller.isSOSMode,
        child: Stack(
          children: [
            // 第一層：緩慢水波背景
            const PondBackground(),
            
            // 第二層：邊緣石頭裝飾
            const PondDecorations(),
            
            // 提示文字
            if (!controller.isSOSMode)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '點擊水面與我說話',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 24,
                        color: const Color(0xFF64748B).withOpacity(0.6),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '(連續點擊 5 次可觸發求救)',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 14,
                        color: const Color(0xFF94A3B8).withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              
              // SOS 警報提示
            if (controller.isSOSMode)
              Center(
                child: Text(
                  'SOS 求救已觸發！',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 32,
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

            // 第三層：錦鯉通知 (有通知時游入)
            if (controller.isKoiVisible)
              KoiFishNotification(
                onTap: controller.tapKoi,
              ),

            // 第四層：蓮葉文字卡片 (點擊錦鯉後浮現)
            if (controller.isLotusVisible && controller.currentNotification != null)
              LotusLeafCard(
                message: controller.currentNotification!,
                onDismiss: controller.dismissLotus,
              ),

            // ★ 測試用：模擬收到訊息的按鈕 (測試完可移除)
            Positioned(
              left: 20,
              top: 50,
              child: ElevatedButton.icon(
                onPressed: () {
                  controller.showNotification('爺爺！今天天氣很好，下午記得去公園散步走走喔！\n愛您的女兒 秀珠 ❤️');
                },
                icon: const Icon(Icons.notifications_active),
                label: const Text('模擬家人傳訊息'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.8),
                  foregroundColor: Colors.teal,
                  elevation: 4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
