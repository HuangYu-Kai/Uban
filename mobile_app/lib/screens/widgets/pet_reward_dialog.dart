import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class PetRewardDialog extends StatefulWidget {
  final String title;
  final String message;
  final int intimacyExp;
  final int coins;
  final VoidCallback? onDismiss;

  const PetRewardDialog({
    super.key,
    this.title = '活力滿滿！',
    this.message = '小嘎收到你的溫馨分享囉～',
    this.intimacyExp = 10,
    this.coins = 2,
    this.onDismiss,
  });

  static Future<void> show(
    BuildContext context, {
    String title = '活力滿滿！',
    String message = '小嘎收到你的溫馨分享囉～',
    int intimacyExp = 10,
    int coins = 2,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => PetRewardDialog(
        title: title,
        message: message,
        intimacyExp: intimacyExp,
        coins: coins,
      ),
    );
  }

  @override
  State<PetRewardDialog> createState() => _PetRewardDialogState();
}

class _PetRewardDialogState extends State<PetRewardDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );

    _bounceAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
      ),
    );

    _controller.forward();

    // 2.5 秒後自動淡出關閉
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
        widget.onDismiss?.call();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF55B695).withValues(alpha: 0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
              border: Border.all(
                color: const Color(0xFF55B695).withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 寵物頭像與光芒
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDFFFF4),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF55B695).withValues(alpha: 0.3),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      '🐾',
                      style: TextStyle(fontSize: 48),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.title,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF1E3A34),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF4A5568),
                  ),
                ),
                const SizedBox(height: 20),
                // 獎勵勳章膠囊
                ScaleTransition(
                  scale: _bounceAnimation,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildRewardChip(
                        icon: '💖',
                        label: '親密度 +${widget.intimacyExp}',
                        color: const Color(0xFFFFF1F2),
                        textColor: const Color(0xFFE11D48),
                        borderColor: const Color(0xFFFDA4AF),
                      ),
                      const SizedBox(width: 12),
                      _buildRewardChip(
                        icon: '🪙',
                        label: '活力幣 +${widget.coins}',
                        color: const Color(0xFFFEF9C3),
                        textColor: const Color(0xFFB45309),
                        borderColor: const Color(0xFFFDE047),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '點擊任意處或稍候自動關閉',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRewardChip({
    required String icon,
    required String label,
    required Color color,
    required Color textColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.notoSansTc(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
