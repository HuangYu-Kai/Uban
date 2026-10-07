import 'package:flutter/material.dart';
import '../services/session_manager.dart';
import 'elder_pairing_display_screen.dart';
import 'login_screen.dart';
import 'monitor_pairing_screen.dart'; // ★ issue 7：監視器角色
import '../widgets/login_flow_parts.dart';
import '../widgets/spotlight_tutorial.dart';
import '../widgets/ui/ui.dart';
import '../widgets/policy_detail_dialog.dart';
import '../data/privacy_policy_content.dart';

class IdentificationScreen extends StatefulWidget {
  const IdentificationScreen({super.key});

  @override
  State<IdentificationScreen> createState() => _IdentificationScreenState();
}

class _IdentificationScreenState extends State<IdentificationScreen> {
  // ★ 2026-10-07 身分選擇導覽：高光目標
  final GlobalKey _elderCardKey = GlobalKey();
  final GlobalKey _familyCardKey = GlobalKey();
  final GlobalKey _monitorKey = GlobalKey();

  static const String _tutorialId = 'identification_v1';

  List<TutorialStep> get _tutorialSteps => [
        const TutorialStep(
          title: '歡迎使用 Uban',
          body: 'Uban 是長輩和家人一起使用的 App。一個家庭通常會有好幾支手機：'
              '長輩的手機、家人的手機，也可以多一台當監控設備。'
              '請依「這支手機是誰在用」來選擇。',
        ),
        TutorialStep(
          targetKey: _elderCardKey,
          title: '我是長者',
          body: '給長輩使用的手機。可以跟小嘎聊天、聽新聞、和家人視訊，'
              '每天打卡、照顧小豬。第一次使用會顯示配對碼，請家人用手機掃描完成綁定。',
        ),
        TutorialStep(
          targetKey: _familyCardKey,
          title: '我是家屬／照護者',
          body: '給子女或照顧者使用。需要註冊登入，綁定長輩後可以查看長輩近況、'
              '設定吃藥提醒、視訊通話，並在長輩跌倒時收到通知。',
        ),
        TutorialStep(
          targetKey: _monitorKey,
          title: '這台是監控設備',
          body: '把家裡閒置的手機或平板放在客廳等地方，當作看護攝影機，'
              '偵測跌倒並通知家人。一般使用者不需要選這個。',
        ),
        const TutorialStep(
          title: '還是不確定嗎？',
          body: '長輩的手機請選「我是長者」，您自己的手機請選「我是家屬」。'
              '之後隨時可以按右上角的「怎麼選？」再看一次。',
        ),
      ];

  void _showTutorialIfNeeded() {
    SpotlightTutorial.showIfNeeded(
      context,
      tutorialId: _tutorialId,
      steps: _tutorialSteps,
      ignoreAllDismissed: true,
    );
  }

  void _showTutorialForce() {
    SpotlightTutorial.showForce(
      context,
      tutorialId: _tutorialId,
      steps: _tutorialSteps,
    );
  }

  @override
  void initState() {
    super.initState();
    // ★ 2026-08-10 第二十輪（需求 1）：進到身分選擇頁就代表使用者尚未選擇身分，
    //   此時必須主動釋放上一個 session，否則會繼續收到上一個帳號的來電推播，
    //   而且下次冷啟動會直接跳回被綁死的帳號。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SessionManager.releaseIfBound();
      // ★ 2026-10-07 身分選擇導覽：首次進入自動顯示（放在 releaseIfBound 之後）
      if (mounted) _showTutorialIfNeeded();
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
                  // ★ 2026-10-07 身分選擇導覽：右上角「怎麼選？」說明入口
                  Row(
                    children: [
                      // 左側吃掉剩餘寬度；右側按鈕維持原本寬度。之前兩邊都用
                      // Flexible 加 Spacer，三者平分一列，按鈕只分到三分之一寬，
                      // 「怎麼選？」被擠成兩行。
                      const Expanded(child: UbanLabel('UBAN')),
                      Semantics(
                        button: true,
                        label: '身分選擇說明',
                        excludeSemantics: true,
                        child: UbanButton(
                          label: '怎麼選？',
                          icon: Icons.help_outline_rounded,
                          variant: UbanButtonVariant.ghost,
                          expand: false,
                          onPressed: _showTutorialForce,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('誰在使用這支手機？', style: ubanH1(context)),
                  const SizedBox(height: 22),
                  // 長者身分卡
                  _buildRoleCard(
                    key: _elderCardKey,
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
                    key: _familyCardKey,
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
                  KeyedSubtree(
                    key: _monitorKey,
                    child: UbanButton(
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
                  ),
                  UbanButton(
                    label: '閱讀完整服務條款',
                    variant: UbanButtonVariant.ghost,
                    onPressed: () {
                      PolicyDetailDialog.show(
                        context,
                        title: PrivacyPolicyContent.title,
                        introText: PrivacyPolicyContent.introText,
                        headerIcon: Icons.privacy_tip_outlined,
                        primaryColor: UbanColors.of(context).brandStrong,
                        secondaryColor: UbanColors.of(context).brandFill,
                        sections: PrivacyPolicyContent.sections,
                        lastUpdated: '最後更新：${PrivacyPolicyContent.lastUpdated}',
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
    required GlobalKey key,
    required BuildContext context,
    required String label,
    required String subtitle,
    required Color faceColor,
    required Widget face,
    required VoidCallback onTap,
  }) {
    final c = UbanColors.of(context);
    return KeyedSubtree(
      key: key,
      child: Semantics(
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
                        style: ubanText(24, FontWeight.w900, c.text,
                            height: 1.25)),
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
          ..color = elder ? const Color(0xFFC9782C) : const Color(0xFF3D9C7C));
  }

  @override
  bool shouldRepaint(covariant _RoleFacePainter old) => old.elder != elder;
}
