import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../controllers/pet_controller.dart';

/// 寵物互動室畫面 (入口)
/// 使用 Provider 注入 PetController，並構建包含 3D 背景與玻璃擬態 UI 的介面
class PetInteractionScreen extends StatelessWidget {
  final int userId;
  final int steps;
  final int level;

  const PetInteractionScreen({
    super.key,
    required this.userId,
    required this.steps,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PetController(),
      child: const Scaffold(
        backgroundColor: Colors.black, // 背景設為黑色以突顯 3D 模型
        body: _PetRoomView(),
      ),
    );
  }
}

/// 寵物互動室視圖 (View)
/// 負責渲染 3D 模型層與上方的互動 UI 層
class _PetRoomView extends StatelessWidget {
  const _PetRoomView();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PetController>();

    return Stack(
      children: [
        // 1. 底層：3D 渲染區域 (model_viewer_plus)
        Positioned.fill(
          child: ModelViewer(
            src: 'assets/models/modern_apartment_interior.glb',
            alt: 'A premium 3D interior room',
            ar: true,
            autoRotate: false,
            cameraControls: true,
            cameraOrbit: '0deg 75deg 0.5m',
            cameraTarget: '0m 1.2m 0m',
            fieldOfView: '90deg',
            interpolationDecay: 200,
            animationName: controller.currentAnimation,
            javascriptChannels: {
              JavascriptChannel(
                'ModelClickChannel',
                onMessageReceived: (message) {
                  // 接收 JS 傳回的點擊物件名稱
                  controller.handleModelClick(message.message);
                },
              )
            },
            // 進階 JS：偵測點擊的節點名稱
            relatedJs: '''
              const modelViewer = document.querySelector('model-viewer');
              modelViewer.addEventListener('click', (event) => {
                const hit = modelViewer.sample(event.clientX, event.clientY);
                if (hit) {
                  // 如果點擊到物件，嘗試獲取該物件的名稱
                  ModelClickChannel.postMessage(hit.nodeName || 'object');
                } else {
                  ModelClickChannel.postMessage('floor');
                }
              });
            ''',
          ),
        ),

        // 2. 中層：2D 寵物角色疊加 (帶有動畫效果)
        Positioned(
          bottom: 180,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Image.asset(
                controller.petAssetPath,
                width: 280,
                height: 280,
              )
              .animate(target: controller.isAnimating ? 1 : 0)
              .shake(duration: 600.ms, hz: 4)
              .scale(begin: const Offset(1, 1), end: const Offset(1.1, 1.1)),
            ),
          ),
        ),

        // 3. 上層：Premium UI - 返回按鈕
        Positioned(
          top: 60,
          left: 20,
          child: _GlassContainer(
            padding: const EdgeInsets.all(8),
            borderRadius: BorderRadius.circular(50),
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ).animate().fadeIn(duration: 600.ms).slideX(begin: -0.2),
        ),

        // 4. 上層：Premium UI - 狀態控制面板 (右上角)
        Positioned(
          top: 60,
          right: 20,
          child: _GlassContainer(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildStatusRow('飽食', controller.status.hunger, Colors.orangeAccent),
                const SizedBox(height: 10),
                _buildStatusRow('活力', controller.status.energy, Colors.lightBlueAccent),
                const SizedBox(height: 10),
                _buildStatusRow('心情', controller.status.happiness, Colors.pinkAccent),
              ],
            ),
          ).animate().fadeIn(duration: 600.ms).slideX(begin: 0.2),
        ),

        // 5. 上層：Premium UI - 寵物對話框 (中間偏上)
        Positioned(
          top: 150,
          left: 30,
          right: 30,
          child: Center(
            child: _GlassContainer(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              borderRadius: BorderRadius.circular(30),
              child: Text(
                controller.currentDialog,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  fontSize: 17, 
                  fontWeight: FontWeight.w600, 
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ).animate(key: ValueKey(controller.currentDialog))
             .fadeIn(duration: 400.ms)
             .scale(duration: 400.ms, curve: Curves.backOut),
          ),
        ),

        // 6. 下層：Premium UI - 互動動作按鈕 (底部)
        Positioned(
          bottom: 50,
          left: 20,
          right: 20,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildInteractionBtn(
                icon: Icons.auto_awesome, 
                label: '玩耍', 
                color: Colors.purpleAccent,
                onPressed: () => controller.play(),
              ),
              _buildInteractionBtn(
                icon: Icons.fastfood_rounded, 
                label: '餵食', 
                color: Colors.orangeAccent,
                onPressed: () => controller.feed(),
              ),
              _buildInteractionBtn(
                icon: Icons.nightlight_round, 
                label: '休息', 
                color: Colors.indigoAccent,
                onPressed: () => controller.sleep(),
              ),
            ],
          ).animate().fadeIn(duration: 800.ms).slideY(begin: 0.2),
        ),
      ],
    );
  }

  /// 建立狀態列的輔助元件
  Widget _buildStatusRow(String label, int value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label, 
          style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)
        ),
        const SizedBox(width: 8),
        Container(
          width: 80,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value / 100,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [color.withOpacity(0.6), color]),
                borderRadius: BorderRadius.circular(4),
                boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 4)],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 建立互動按鈕的輔助元件
  Widget _buildInteractionBtn({
    required IconData icon, 
    required String label, 
    required Color color, 
    required VoidCallback onPressed
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onPressed,
          child: _GlassContainer(
            padding: const EdgeInsets.all(16),
            borderRadius: BorderRadius.circular(20),
            borderColor: color.withOpacity(0.5),
            child: Icon(icon, color: color, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label, 
          style: GoogleFonts.outfit(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)
        ),
      ],
    );
  }
}

/// 玻璃擬態容器組件 (Glassmorphism)
class _GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final Color? borderColor;

  const _GlassContainer({
    required this.child,
    this.padding = const EdgeInsets.all(0),
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: borderRadius,
            border: Border.all(
              color: borderColor ?? Colors.white.withOpacity(0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                spreadRadius: 2,
              )
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
