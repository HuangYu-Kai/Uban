import 'package:flutter/material.dart';
import '../widgets/login_flow_parts.dart';
import '../widgets/ui/ui.dart';
import 'caregiver_pairing_screen.dart';

/// 家屬註冊完成後的三頁說明：介紹 Uban、準備長輩手機、如何配對。
class FamilyOnboardingScreen extends StatefulWidget {
  final int userId;
  final String userName;

  const FamilyOnboardingScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<FamilyOnboardingScreen> createState() => _FamilyOnboardingScreenState();
}

class _OnboardingItem {
  final IconData icon;
  final String text;
  const _OnboardingItem(this.icon, this.text);
}

class _OnboardingPage {
  final String title;
  final String? body;
  final String image;
  final List<_OnboardingItem> items;
  final bool numbered;
  final String? footnote;
  const _OnboardingPage({
    required this.title,
    this.body,
    required this.image,
    required this.items,
    this.numbered = false,
    this.footnote,
  });
}

class _FamilyOnboardingScreenState extends State<FamilyOnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  List<_OnboardingPage> get _pages => [
        _OnboardingPage(
          title: widget.userName.trim().isEmpty
              ? '歡迎使用 Uban'
              : '歡迎，${widget.userName.trim()}',
          body: 'Uban 讓你不在長輩身邊，也能照顧他。',
          image: 'assets/images/family_illustration.png',
          items: const [
            _OnboardingItem(Icons.event_available_rounded, '看長輩今天的打卡與近況'),
            _OnboardingItem(Icons.videocam_rounded, '一鍵和長輩視訊'),
            _OnboardingItem(Icons.medication_rounded, '設定吃藥提醒'),
            _OnboardingItem(Icons.notifications_active_rounded, '長輩跌倒時立即通知你'),
          ],
        ),
        const _OnboardingPage(
          title: '先準備長輩的手機',
          image: 'assets/images/elder_illustration.png',
          numbered: true,
          items: [
            _OnboardingItem(Icons.download_rounded, '在長輩手機安裝 Uban'),
            _OnboardingItem(Icons.person_rounded, '打開後選「我是長者」'),
            _OnboardingItem(Icons.qr_code_2_rounded, '畫面會出現 4 位數配對碼和 QR Code'),
          ],
        ),
        const _OnboardingPage(
          title: '掃描或輸入配對碼',
          image: 'assets/images/family_call.png',
          numbered: true,
          items: [
            _OnboardingItem(
                Icons.qr_code_scanner_rounded, '下一頁按「掃描 QR Code」對準長輩手機'),
            _OnboardingItem(Icons.pin_rounded, '掃不到也可以手動輸入 4 位數'),
            _OnboardingItem(Icons.badge_rounded, '填上長輩的稱呼，就完成了'),
          ],
          footnote: '配對碼幾分鐘後會自動更新，請以長輩手機上最新的為準',
        ),
      ];

  bool get _isLast => _currentPage == _pages.length - 1;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goPairing() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => CaregiverPairingScreen(
          familyId: widget.userId,
          familyName: widget.userName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final pages = _pages;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (value) => setState(() => _currentPage = value),
                itemCount: pages.length,
                itemBuilder: (context, index) => _buildPage(pages[index]),
              ),
            ),
            _buildBottomControls(pages.length),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(_OnboardingPage page) {
    final c = UbanColors.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 小螢幕（高度不足）時插圖縮小，整頁仍可捲動，避免溢位。
        final imageHeight = (constraints.maxHeight * 0.28).clamp(96.0, 200.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: imageHeight,
                  child: Image.asset(
                    page.image,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Center(
                      child: Container(
                        width: imageHeight * 0.7,
                        height: imageHeight * 0.7,
                        decoration: BoxDecoration(
                          color: c.brandContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.favorite_rounded,
                            size: imageHeight * 0.3, color: c.brandStrong),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(page.title,
                    style: ubanH1(context, size: 28),
                    textAlign: TextAlign.center),
                if (page.body != null) ...[
                  const SizedBox(height: 10),
                  Text(page.body!,
                      style: ubanBody(context, size: 17),
                      textAlign: TextAlign.center),
                ],
                const SizedBox(height: 20),
                for (int i = 0; i < page.items.length; i++)
                  _buildItemRow(page, i),
                if (page.footnote != null) ...[
                  const SizedBox(height: 8),
                  Text(page.footnote!,
                      style: ubanText(14, FontWeight.w500, c.text3, height: 1.5),
                      textAlign: TextAlign.center),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildItemRow(_OnboardingPage page, int i) {
    final c = UbanColors.of(context);
    final item = page.items[i];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration:
                BoxDecoration(color: c.brandContainer, shape: BoxShape.circle),
            child: page.numbered
                ? Text('${i + 1}',
                    style: ubanText(18, FontWeight.w800, c.brandStrong))
                : Icon(item.icon, size: 22, color: c.brandStrong),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(item.text,
                style: ubanText(17, FontWeight.w600, c.text, height: 1.4)),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(count, _buildDot),
          ),
          const SizedBox(height: 16),
          UbanButton(
            label: _isLast ? '開始配對' : '下一步',
            onPressed: () {
              if (_isLast) {
                _goPairing();
              } else {
                _pageController.nextPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              }
            },
          ),
          // 最後一頁保留同高度空位，避免按鈕跳動。
          SizedBox(
            height: 48,
            child: _isLast
                ? null
                : UbanButton(
                    label: '跳過',
                    variant: UbanButtonVariant.ghost,
                    onPressed: () => _pageController.jumpToPage(count - 1),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    final c = UbanColors.of(context);
    final active = _currentPage == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 8,
      width: active ? 24 : 8,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: active ? c.brand : c.line,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
