import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lunar/lunar.dart';
import 'package:intl/intl.dart';

class ElderHomeScreen extends StatefulWidget {
  final int userId;
  final String userName;

  const ElderHomeScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<ElderHomeScreen> createState() => _ElderHomeScreenState();
}

class _ElderHomeScreenState extends State<ElderHomeScreen> {
  int _selectedIndex = 0; // 0: Home/Calendar, 1: Chat, 2: Profile/Settings
  late String _lunarDate;
  late String _solarTerm;
  late String _dayName;
  late String _dateStr;
  late String _monthStr;
  late String _yearStr;

  @override
  void initState() {
    super.initState();
    _updateTime();
  }

  void _updateTime() {
    final now = DateTime.now();
    final lunar = Lunar.fromDate(now);

    setState(() {
      _lunarDate = "${lunar.getMonthInChinese()}月${lunar.getDayInChinese()}";
      _solarTerm = lunar.getJieQi();
      if (_solarTerm.isEmpty) {
        _solarTerm = "立春";
      }

      try {
        _dayName = DateFormat('EEEE', 'zh_TW').format(now);
        _dateStr = DateFormat('dd').format(now);
        _monthStr = DateFormat('MM月', 'zh_TW').format(now);
        _yearStr = DateFormat('yyyy').format(now);
      } catch (e) {
        debugPrint('DateFormat error: $e');
        _dayName = "星期${['一', '二', '三', '四', '五', '六', '日'][now.weekday - 1]}";
        _dateStr = now.day.toString().padLeft(2, '0');
        _monthStr = "${now.month}月";
        _yearStr = now.year.toString();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Stack(
        children: [
          // 頁面內容切換
          IndexedStack(
            index: _selectedIndex,
            children: [
              _buildHomeView(),
              _buildEmptyView('聊天區域'),
              _buildEmptyView('個人頁面'),
            ],
          ),
          // 自定義浮動導覽列
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildFloatingNavBar(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView(String title) {
    return Center(
      child: Text(
        title,
        style: GoogleFonts.notoSansTc(fontSize: 24, color: Colors.grey),
      ),
    );
  }

  Widget _buildHomeView() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF59B294), Color(0xFFF1F5F9)],
          stops: [0.0, 0.3],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(32),
                    topRight: Radius.circular(32),
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _buildGreetingRow(),
                      const SizedBox(height: 20),
                      _buildCalendarCard(),
                      const SizedBox(height: 20),
                      _buildMainFeaturesRow(),
                      const SizedBox(height: 20),
                      _buildNewsSection(),
                      const SizedBox(height: 100), // 留白給浮動底部
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingNavBar() {
    return Container(
      height: 90,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(0, Icons.home_rounded),
          _buildNavItem(1, Icons.chat_bubble_rounded),
          _buildNavItem(2, Icons.person_rounded),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon) {
    final isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, isSelected ? -15 : 0, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF59B294) : Colors.transparent,
          shape: BoxShape.circle,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF59B294).withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ]
              : [],
        ),
        child: Icon(
          icon,
          size: 32,
          color: isSelected ? Colors.white : Colors.grey[400],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return const SizedBox(height: 20);
  }

  Widget _buildGreetingRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '早安！',
              style: GoogleFonts.notoSansTc(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.wb_sunny_rounded,
                    color: Colors.orange,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '超級會員',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 14,
                      color: Colors.orange[800],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        CircleAvatar(
          radius: 35,
          backgroundImage: const NetworkImage(
            'https://i.pravatar.cc/150?u=elder',
          ), // Mock
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCalendarCard() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Row(
        children: [
          // 左側西曆方塊
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: const Color(0xFF59B294).withValues(alpha: 0.3),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(
                      _monthStr,
                      style: GoogleFonts.notoSansTc(
                        color: const Color(0xFF59B294),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _yearStr,
                      style: GoogleFonts.inter(
                        color: const Color(0xFF59B294),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Text(
                  _dateStr,
                  style: GoogleFonts.inter(
                    fontSize: 64,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF59B294),
                  ),
                ),
                Text(
                  _dayName,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14,
                    color: const Color(0xFF59B294),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          // 右側農曆標註
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _lunarDate,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF59B294),
                  ),
                ),
                Text(
                  _solarTerm,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF59B294),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainFeaturesRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 代誌報給你知
        Expanded(
          flex: 3,
          child: Container(
            height: 220,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              image: const DecorationImage(
                image: AssetImage('assets/images/newspaper.png'),
                fit: BoxFit.cover,
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: 20,
                  left: 20,
                  right: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '代誌',
                        style: TextStyle(
                          fontFamily: 'StarPanda',
                          fontSize: 32,
                          color: const Color(0xFF334155),
                        ),
                      ),
                      Text(
                        '報給你知',
                        style: TextStyle(
                          fontFamily: 'StarPanda',
                          fontSize: 32,
                          color: const Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        // 朋友
        Expanded(
          flex: 2,
          child: Column(
            children: [
              Container(
                height: 220,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFCFEADF),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '朋友',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                        const Icon(
                          Icons.arrow_circle_right,
                          color: Color(0xFF59B294),
                          size: 28,
                        ),
                      ],
                    ),
                    const Expanded(child: SizedBox()),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildFriendAvatar('GAWA'),
                          _buildFriendAvatar('倪阿恭'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFriendAvatar(String name) {
    return Column(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: Colors.grey[200],
          child: const Icon(Icons.person, size: 20),
        ),
        const SizedBox(height: 4),
        Text(
          name,
          style: GoogleFonts.notoSansTc(
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildNewsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Text(
                  '最新',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                Container(
                  margin: const EdgeInsets.only(left: 4),
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 20),
                Text(
                  '賽金豬',
                  style: GoogleFonts.notoSansTc(
                    color: Colors.grey,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '頭條早知道',
          style: TextStyle(
            fontFamily: 'StarPanda',
            fontSize: 40,
            color: const Color(0xFF59B294),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.newspaper,
                        color: Colors.orange,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '聯合新聞網',
                        style: GoogleFonts.notoSansTc(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                  Text('02-05', style: GoogleFonts.inter(color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '過半台灣人想「微退休」！滙豐揭關鍵門檻：先存到 730 萬元',
                style: GoogleFonts.notoSansTc(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
