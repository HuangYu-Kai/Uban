import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'caregiver_pairing_screen.dart';

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

class _FamilyOnboardingScreenState extends State<FamilyOnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, String>> _onboardingData = [
    {
      'title': '溫馨陪伴，無遠弗屆',
      'description': '隨時透過即時視訊與 AI 生成的動態日誌，感受長輩的生活點滴，就像在身邊一樣。',
      'icon': '🏠',
      'color': '0xFFE0F2FE', // Light Blue
    },
    {
      'title': 'AI 智慧守護',
      'description': '我們的 AI 會協助分析長輩的情緒與活動，並在關鍵時刻提供溫馨提醒，讓您更懂他的心。',
      'icon': '🤖',
      'color': '0xFFF0FDF4', // Light Green
    },
    {
      'title': '一鍵配對，立即開始',
      'description': '準備好長輩端的手機或平板，掃描畫面上的 QR Code 或輸入配對碼，守護關係即刻建立。',
      'icon': '💙',
      'color': '0xFFFFF7ED', // Light Orange
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (value) => setState(() => _currentPage = value),
                itemCount: _onboardingData.length,
                itemBuilder: (context, index) => _buildPage(index),
              ),
            ),
            _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(int index) {
    final data = _onboardingData[index];
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              color: Color(int.parse(data['color']!)),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(data['icon']!, style: const TextStyle(fontSize: 80)),
            ),
          ),
          const SizedBox(height: 60),
          Text(
            data['title']!,
            style: GoogleFonts.notoSansTc(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF1E293B),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Text(
            data['description']!,
            style: GoogleFonts.notoSansTc(
              fontSize: 16,
              color: const Color(0xFF64748B),
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _onboardingData.length,
              (index) => _buildDot(index),
            ),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () {
                if (_currentPage == _onboardingData.length - 1) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CaregiverPairingScreen(
                        familyId: widget.userId,
                        familyName: widget.userName,
                      ),
                    ),
                  );
                } else {
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF59B294),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: Text(
                _currentPage == _onboardingData.length - 1 ? '開始配對' : '下一步',
                style: GoogleFonts.notoSansTc(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          if (_currentPage < _onboardingData.length - 1)
            TextButton(
              onPressed: () {
                _pageController.jumpToPage(_onboardingData.length - 1);
              },
              child: Text(
                '跳過',
                style: GoogleFonts.notoSansTc(
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    return Container(
      height: 8,
      width: _currentPage == index ? 24 : 8,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: _currentPage == index
            ? const Color(0xFF59B294)
            : const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
