import 'package:flutter/material.dart';
import '../services/session_manager.dart';
import 'elder_pairing_display_screen.dart';
import 'login_screen.dart';
import 'monitor_pairing_screen.dart'; // ★ issue 7：監視器角色
import '../widgets/login_flow_parts.dart';
import '../widgets/ui/ui.dart';

class IdentificationScreen extends StatefulWidget {
  const IdentificationScreen({super.key});

  @override
  State<IdentificationScreen> createState() => _IdentificationScreenState();
}

class _IdentificationScreenState extends State<IdentificationScreen> {
  @override
  void initState() {
    super.initState();
    // ★ 2026-08-10 第二十輪（需求 1）：進到身分選擇頁就代表使用者尚未選擇身分，
    //   此時必須主動釋放上一個 session，否則會繼續收到上一個帳號的來電推播，
    //   而且下次冷啟動會直接跳回被綁死的帳號。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SessionManager.releaseIfBound();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const UbanLabel('UBAN'),
                  const SizedBox(height: 8),
                  Text('誰在使用這支手機？', style: ubanH1(context)),
                  const SizedBox(height: 22),
                  // 長者身分卡
                  _buildRoleCard(
                    context: context,
                    label: '我是長者',
                    subtitle: '看新聞、跟家人視訊、和小嘎聊天',
                    faceColor: c.warmContainer,
                    face: const _RoleFace(elder: true),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const ElderPairingDisplayScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 22),
                  // 家屬身分卡
                  _buildRoleCard(
                    context: context,
                    label: '我是家屬／照護者',
                    subtitle: '關心長輩近況、設定提醒',
                    faceColor: c.brandContainer,
                    face: const _RoleFace(elder: false),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const LoginScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 22),
                  // ★ issue 7：監視器設備入口（文字按鈕）
                  UbanButton(
                    label: '這台是監控設備',
                    variant: UbanButtonVariant.ghost,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const MonitorPairingScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 設計稿 `.role`：84 臉＋標題 24/900＋說明 16＋箭頭，整張可點、按壓縮放。
  Widget _buildRoleCard({
    required BuildContext context,
    required String label,
    required String subtitle,
    required Color faceColor,
    required Widget face,
    required VoidCallback onTap,
  }) {
    final c = UbanColors.of(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: UbanCard(
        onTap: onTap,
        radius: 28,
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: faceColor,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Center(child: face),
            ),
            const SizedBox(width: 16),
            // 標題與說明可收縮換行，大字級也不溢位。
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style:
                          ubanText(24, FontWeight.w900, c.text, height: 1.25)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: ubanText(16, FontWeight.w400, c.text2,
                          height: 1.4)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, size: 28, color: c.text3),
          ],
        ),
      ),
    );
  }
}

/// 身分卡上的人物插畫（設計稿 60×60 viewBox 的 SVG，插畫固定色不隨主題變動）。
class _RoleFace extends StatelessWidget {
  final bool elder;
  const _RoleFace({required this.elder});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 60,
        height: 60,
        child: CustomPaint(painter: _RoleFacePainter(elder: elder)),
      );
}

class _RoleFacePainter extends CustomPainter {
  final bool elder;
  _RoleFacePainter({required this.elder});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 60, size.height / 60);
    final skin = Paint()..color = const Color(0xFFF2C9A0);
    if (elder) {
      canvas.drawCircle(const Offset(30, 24), 12, skin);
      final hair = Path()
        ..moveTo(18, 22)
        ..relativeCubicTo(0, -9, 6, -13, 12, -13)
        ..relativeCubicTo(6, 0, 12, 4, 12, 13)
        ..relativeCubicTo(-3, -4, -7, -5, -12, -5)
        ..relativeCubicTo(-5, 0, -9, 1, -12, 5)
        ..close();
      canvas.drawPath(hair, Paint()..color = const Color(0xFFE8E4DE));
    } else {
      canvas.drawCircle(const Offset(30, 23), 11, skin);
      final hair = Path()
        ..moveTo(19, 21)
        ..relativeCubicTo(0, -7, 5, -11, 11, -11)
        ..relativeCubicTo(6, 0, 11, 4, 11, 11)
        ..relativeCubicTo(-2, -3, -6, -4, -11, -4)
        ..relativeCubicTo(-5, 0, -9, 1, -11, 4)
        ..close();
      canvas.drawPath(hair, Paint()..color = const Color(0xFF3B3330));
    }
    final body = Path()
      ..moveTo(12, 56)
      ..arcToPoint(const Offset(48, 56), radius: const Radius.circular(18))
      ..close();
    canvas.drawPath(
        body,
        Paint()
          ..color =
              elder ? const Color(0xFFC9782C) : const Color(0xFF3D9C7C));
  }

  @override
  bool shouldRepaint(covariant _RoleFacePainter old) => old.elder != elder;
}
