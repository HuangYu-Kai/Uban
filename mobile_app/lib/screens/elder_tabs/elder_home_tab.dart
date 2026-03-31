import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lunar/lunar.dart';
import 'package:intl/intl.dart';
import '../elder_screen.dart';
import '../../services/api_service.dart';

class ElderHomeTab extends StatefulWidget {
  final int userId;
  final String userName;

  const ElderHomeTab({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<ElderHomeTab> createState() => _ElderHomeTabState();
}

class _ElderHomeTabState extends State<ElderHomeTab> {
  late String _lunarDate;
  late String _solarTerm;
  late String _dayName;
  late String _dateStr;
  late String _monthStr;
  late String _yearStr;

  List<dynamic> _familyList = [];
  bool _isLoadingFamily = true;

  @override
  void initState() {
    super.initState();
    _updateTime();
    _fetchFamily();
  }

  Future<void> _fetchFamily() async {
    try {
      final family = await ApiService.getPairedFamily(widget.userId);
      if (mounted) {
        setState(() {
          _familyList = family;
          _isLoadingFamily = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingFamily = false);
      }
    }
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
                      _buildCalendarCard(),
                      const SizedBox(height: 20),
                      _buildMainFeaturesRow(),
                      const SizedBox(height: 20),
                      // ✨ 新增小遊戲插件
                      _buildPetMiniGame(),
                      const SizedBox(height: 30),
                      _buildNewsSection(),
                      const SizedBox(height: 120), // 留白給浮動底部
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

  Widget _buildHeader() {
    return const SizedBox(height: 20);
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
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 5))],
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
        // 聯絡親友大按鈕
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: () => _showFriendsBottomSheet(context),
            child: Container(
              height: 220,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFCFEADF),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF59B294).withValues(alpha: 0.2),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.diversity_1_rounded,
                      size: 48,
                      color: Color(0xFF59B294),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '聯絡家人',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '點擊可通話',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF59B294),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPetMiniGame() {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      height: 180,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withValues(alpha: 0.1),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左半邊溫馨圖片
          Expanded(
            flex: 2,
            child: ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(28)),
              child: Image.asset('assets/images/pet_garden.png', fit: BoxFit.cover),
            ),
          ),
          // 右半邊遊戲進度
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAF7),
                borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.eco_rounded, size: 28, color: Color(0xFF388E3C)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '小花 正在等您...',
                          style: GoogleFonts.notoSansTc(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1B5E20),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: 0.7,
                      minHeight: 14,
                      backgroundColor: const Color(0xFFC8E6C9),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF43A047)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '再走 500 步就能升級囉！🌱',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 14,
                      color: const Color(0xFF2E7D32),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── ✨ 聯絡家人彈跳視窗與邏輯 ───────────────────────────────────
  void _showFriendsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _buildContactListSheet(ctx),
    );
  }

  Widget _buildContactListSheet(BuildContext popupContext) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '請問您想聯絡誰？',
            style: GoogleFonts.notoSansTc(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 24),
          if (_isLoadingFamily)
            const Center(child: CircularProgressIndicator())
          else if (_familyList.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                "目前尚未綁定任何家屬",
                style: GoogleFonts.notoSansTc(color: Colors.grey, fontSize: 18),
              ),
            )
          else
            ..._familyList.map((family) => Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: _buildContactListItem(
                      popupContext, family['user_name'] ?? '家人', '主要照護者'),
                )),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _buildContactListItem(BuildContext popupContext, String name, String relation) {
    return InkWell(
      onTap: () {
        Navigator.pop(popupContext); // Close first popup
        _showActionBottomSheet(context, name, relation); // Open second popup
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: const Color(0xFFCFEADF),
              child: const Icon(Icons.person, size: 35, color: Color(0xFF59B294)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  Text(
                    relation,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 16,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }

  void _showActionBottomSheet(BuildContext context, String name, String relation) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _buildActionSheet(ctx, name, relation),
    );
  }

  Widget _buildActionSheet(BuildContext popupContext, String name, String relation) {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: const Color(0xFFCFEADF),
            child: const Icon(Icons.person, size: 45, color: Color(0xFF59B294)),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            style: GoogleFonts.notoSansTc(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF1E293B),
            ),
          ),
          Text(
            relation,
            style: GoogleFonts.notoSansTc(
              fontSize: 18,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: _buildCallButton(
                  icon: Icons.call_rounded,
                  label: '語音通話',
                  color: const Color(0xFF3B82F6),
                  onTap: () {
                    Navigator.pop(popupContext);
                    _handleCall(name, isVideo: false);
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildCallButton(
                  icon: Icons.videocam_rounded,
                  label: '視訊通話',
                  color: const Color(0xFF10B981),
                  onTap: () {
                    Navigator.pop(popupContext);
                    _handleCall(name, isVideo: true);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildCallButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Icon(icon, size: 32, color: Colors.white),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: GoogleFonts.notoSansTc(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleCall(String friendName, {bool isVideo = true}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ElderScreen(
          roomId: widget.userId.toString(),
          deviceName: widget.userName,
          autoCall: true,
        ),
      ),
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
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1.4,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '繼續閱讀',
                    style: GoogleFonts.notoSansTc(
                      color: const Color(0xFF59B294),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_rounded, color: Color(0xFF59B294), size: 18),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
