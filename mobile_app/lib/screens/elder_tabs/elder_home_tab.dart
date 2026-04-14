import 'dart:async';
import 'dart:math';

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
  final PageController _stageController = PageController();
  List<Map<String, dynamic>> _newsItems = [];
  bool _isLoadingNews = true;
  String? _newsError;
  final Random _random = Random();
  int _topNewsIndex = 0;
  Timer? _topNewsRotateTimer;
  bool _isStageSwitching = false;

  @override
  void initState() {
    super.initState();
    _updateTime();
    _fetchFamily();
    _fetchNews();
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

  Future<void> _fetchNews() async {
    try {
      final response = await ApiService.getNews(category: 'politics', limit: 8);
      final isSuccess = response['status'] == 'success';
      if (!isSuccess) {
        throw Exception(response['message'] ?? '新聞讀取失敗');
      }

      final data = response['data'];
      final items = (data is Map ? data['items'] : null);
      final parsed = <Map<String, dynamic>>[];
      if (items is List) {
        for (final item in items) {
          if (item is Map<String, dynamic>) {
            parsed.add(item);
          } else if (item is Map) {
            parsed
                .add(item.map((key, value) => MapEntry(key.toString(), value)));
          }
        }
      }

      if (mounted) {
        setState(() {
          _newsItems = parsed;
          _isLoadingNews = false;
          _newsError = null;
          if (_newsItems.isNotEmpty) {
            _topNewsIndex = _random.nextInt(_newsItems.length);
          } else {
            _topNewsIndex = 0;
          }
        });
        _startTopNewsRotation();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingNews = false;
          _newsError = '新聞暫時讀取失敗，稍後再試。';
        });
      }
      _topNewsRotateTimer?.cancel();
    }
  }

  void _startTopNewsRotation() {
    _topNewsRotateTimer?.cancel();
    if (_newsItems.length <= 1) {
      return;
    }
    _topNewsRotateTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted || _newsItems.length <= 1) return;
      setState(() {
        var next = _random.nextInt(_newsItems.length);
        if (next == _topNewsIndex) {
          next = (next + 1) % _newsItems.length;
        }
        _topNewsIndex = next;
      });
    });
  }

  Future<void> _goToTopStage() async {
    if (_isStageSwitching || !_stageController.hasClients) return;
    final current =
        _stageController.page ?? _stageController.initialPage.toDouble();
    if (current < 0.5) return;
    _isStageSwitching = true;
    try {
      await _stageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _isStageSwitching = false;
    }
  }

  bool _handleNewsStageScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;

    final isPullDownAtTop = notification.metrics.pixels <= 0 &&
        ((notification is OverscrollNotification &&
                notification.overscroll < -6) ||
            (notification is ScrollUpdateNotification &&
                (notification.scrollDelta ?? 0) < -10));

    if (isPullDownAtTop) {
      _goToTopStage();
      return true;
    }
    return false;
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
  void dispose() {
    _topNewsRotateTimer?.cancel();
    _stageController.dispose();
    super.dispose();
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
                child: PageView(
                  controller: _stageController,
                  scrollDirection: Axis.vertical,
                  physics:
                      const PageScrollPhysics(parent: ClampingScrollPhysics()),
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                                minHeight: constraints.maxHeight),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildCalendarCard(),
                                const SizedBox(height: 20),
                                _buildMainFeaturesRow(),
                                const SizedBox(height: 16),
                                _buildTopRotatingNewsCard(),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return NotificationListener<ScrollNotification>(
                          onNotification: _handleNewsStageScroll,
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics(),
                            ),
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight),
                              child: _buildNewsSection(),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
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
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 5))
              ],
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
        // 好友捷徑區
        Expanded(
          flex: 2,
          child: _buildFriendsQuickPanel(),
        ),
      ],
    );
  }

  Widget _buildFriendsQuickPanel() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrowPanel = constraints.maxWidth < 130;
        final topFamilies = _familyList.take(narrowPanel ? 1 : 2).toList();
        return Container(
          height: 220,
          padding: EdgeInsets.all(narrowPanel ? 10 : 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '朋友',
                    style: GoogleFonts.notoSansTc(
                      fontSize: narrowPanel ? 22 : 28,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () => _showFriendsBottomSheet(context),
                    borderRadius: BorderRadius.circular(999),
                    child: CircleAvatar(
                      radius: narrowPanel ? 14 : 16,
                      backgroundColor: const Color(0xFF59B294),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: narrowPanel ? 16 : 18,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '已配對子女',
                style: GoogleFonts.notoSansTc(
                  fontSize: narrowPanel ? 12 : 13,
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              if (_isLoadingFamily)
                const Expanded(
                  child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2.5)),
                )
              else if (topFamilies.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      '尚無已配對子女',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.notoSansTc(
                        fontSize: narrowPanel ? 12 : 13,
                        color: const Color(0xFF94A3B8),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      for (final family in topFamilies) ...[
                        _buildPairedFamilyRow(family),
                        const SizedBox(height: 8),
                      ],
                      _buildSocialPlaceholder(compact: narrowPanel),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPairedFamilyRow(dynamic family) {
    final map = family is Map ? family : <String, dynamic>{};
    final name = (map['user_name'] ?? '家人').toString();
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 130;
        final ultraCompact = constraints.maxWidth < 105;
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: ultraCompact ? 6 : (compact ? 8 : 10),
            vertical: ultraCompact ? 5 : (compact ? 6 : 8),
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: ultraCompact ? 11 : (compact ? 13 : 16),
                backgroundColor: const Color(0xFFCFEADF),
                child: Text(
                  name.isNotEmpty ? name.substring(0, 1) : '家',
                  style: GoogleFonts.notoSansTc(
                    fontSize: ultraCompact ? 10 : (compact ? 11 : 13),
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0F766E),
                  ),
                ),
              ),
              SizedBox(width: ultraCompact ? 4 : (compact ? 5 : 8)),
              if (!ultraCompact)
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.notoSansTc(
                      fontSize: compact ? 12 : 14,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                )
              else
                const Spacer(),
              SizedBox(width: ultraCompact ? 2 : 4),
              InkWell(
                onTap: () => _handleCall(name, isVideo: true),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  width: ultraCompact ? 22 : (compact ? 24 : 28),
                  height: ultraCompact ? 22 : (compact ? 24 : 28),
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.videocam_rounded,
                    color: Colors.white,
                    size: ultraCompact ? 12 : 14,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSocialPlaceholder({bool compact = false}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10, vertical: compact ? 6 : 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          CircleAvatar(
              radius: compact ? 9 : 11,
              backgroundColor: const Color(0xFFD1D5DB)),
          SizedBox(width: compact ? 4 : 6),
          CircleAvatar(
              radius: compact ? 9 : 11,
              backgroundColor: const Color(0xFFD1D5DB)),
          SizedBox(width: compact ? 6 : 8),
          Expanded(
            child: Text(
              compact ? '推薦好友' : '推薦好友（即將推出）',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.notoSansTc(
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF64748B),
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

  Widget _buildContactListItem(
      BuildContext popupContext, String name, String relation) {
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
              child:
                  const Icon(Icons.person, size: 35, color: Color(0xFF59B294)),
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
            const Icon(Icons.arrow_forward_ios_rounded,
                color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }

  void _showActionBottomSheet(
      BuildContext context, String name, String relation) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _buildActionSheet(ctx, name, relation),
    );
  }

  Widget _buildActionSheet(
      BuildContext popupContext, String name, String relation) {
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
                  BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4)),
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
          isVideoCall: isVideo, // ★ 傳遞語音/視訊模式
        ),
      ),
    );
  }

  Widget _buildNewsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isLoadingNews)
          Container(
            height: 220,
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(24)),
            child: const Center(child: CircularProgressIndicator()),
          )
        else if (_newsError != null)
          Container(
            height: 220,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(24)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _newsError!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansTc(
                    color: const Color(0xFF64748B),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _isLoadingNews = true;
                      _newsError = null;
                    });
                    _fetchNews();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重新整理'),
                ),
              ],
            ),
          )
        else if (_newsItems.isEmpty)
          Container(
            height: 220,
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(24)),
            child: Center(
              child: Text(
                '目前沒有新聞資料',
                style: GoogleFonts.notoSansTc(
                  color: const Color(0xFF64748B),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          )
        else
          Column(
            children: [
              for (final item in _orderedNewsItemsWithTopFirst().take(3)) ...[
                _buildNewsListCard(item),
                const SizedBox(height: 14),
              ],
            ],
          ),
      ],
    );
  }

  Widget _buildTopRotatingNewsCard() {
    if (_isLoadingNews) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildNewsHeader(),
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }

    if (_newsItems.isEmpty || _newsError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildNewsHeader(),
          Container(
            height: 220,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _newsError ?? '暫無新聞資料',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 15,
                    color: const Color(0xFF64748B),
                    height: 1.45,
                  ),
                ),
                const Spacer(),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _isLoadingNews = true;
                        _newsError = null;
                      });
                      _fetchNews();
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('重試'),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final item = _newsItems[_topNewsIndex % _newsItems.length];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildNewsHeader(),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: Container(
            key: ValueKey<String>(
                'top-news-${item['source_url'] ?? _topNewsIndex}'),
            child: _buildNewsListCard(item),
          ),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _orderedNewsItemsWithTopFirst() {
    if (_newsItems.isEmpty) return const [];
    final topIndex = _topNewsIndex % _newsItems.length;
    final topItem = _newsItems[topIndex];
    final others = <Map<String, dynamic>>[];
    for (var i = 0; i < _newsItems.length; i++) {
      if (i == topIndex) continue;
      others.add(_newsItems[i]);
    }
    return [topItem, ...others];
  }

  Widget _buildNewsHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '最新',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
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
              '新聞',
              style: GoogleFonts.notoSansTc(
                color: Colors.grey,
                fontSize: 17,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          '頭條早知道',
          style: TextStyle(
            fontFamily: 'StarPanda',
            fontSize: 40,
            color: Color(0xFF59B294),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildNewsListCard(Map<String, dynamic> item) {
    final imageUrl = (item['image_url'] ?? '').toString().trim();
    final hasImage =
        imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
    if (hasImage) {
      return _buildNewsImageCard(item, imageUrl);
    }
    return _buildNewsTextCard(item);
  }

  Widget _buildNewsTextCard(Map<String, dynamic> item) {
    final source = (item['category'] ?? '中央社').toString();
    final title = (item['title'] ?? '無標題').toString();
    final publishedAtRaw = (item['published_at_raw'] ?? '').toString();
    final publishedAt = (item['published_at'] ?? '').toString();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.newspaper_rounded,
                      color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    source,
                    style: GoogleFonts.notoSansTc(
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
              Text(
                _formatNewsDate(publishedAtRaw, publishedAt),
                style: GoogleFonts.inter(color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.notoSansTc(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              height: 1.3,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => _showNewsDetail(item),
            borderRadius: BorderRadius.circular(999),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '繼續閱讀',
                  style: GoogleFonts.notoSansTc(
                    color: const Color(0xFF59B294),
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_rounded,
                    color: Color(0xFF59B294), size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewsImageCard(Map<String, dynamic> item, String imageUrl) {
    final source = (item['category'] ?? '中央社').toString();
    final title = (item['title'] ?? '無標題').toString();
    final publishedAtRaw = (item['published_at_raw'] ?? '').toString();
    final publishedAt = (item['published_at'] ?? '').toString();

    return Container(
      height: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: () => _showNewsDetail(item),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.white,
                  alignment: Alignment.center,
                  child: const Icon(Icons.image_not_supported_rounded,
                      color: Color(0xFF94A3B8), size: 32),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.15),
                      Colors.black.withValues(alpha: 0.62),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.newspaper_rounded,
                            color: Colors.white, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            source,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.notoSansTc(
                              color: Colors.white.withValues(alpha: 0.95),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          _formatNewsDate(publishedAtRaw, publishedAt),
                          style: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.notoSansTc(
                        fontSize: 29,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '繼續閱讀',
                          style: GoogleFonts.notoSansTc(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_forward_rounded,
                            color: Colors.white, size: 18),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatNewsDate(String raw, String parsed) {
    if (raw.isNotEmpty) {
      if (raw.length >= 10) return raw.substring(0, 10);
      return raw;
    }
    if (parsed.isNotEmpty) {
      if (parsed.length >= 10) return parsed.substring(0, 10);
      return parsed;
    }
    return '--';
  }

  void _showNewsDetail(Map<String, dynamic> item) {
    final title = (item['title'] ?? '').toString();
    final content = (item['content'] ?? '').toString();
    final sourceUrl = (item['source_url'] ?? '').toString();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  content,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 16,
                    height: 1.55,
                    color: const Color(0xFF334155),
                  ),
                ),
                if (sourceUrl.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    '來源：$sourceUrl',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 13,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
