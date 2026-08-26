import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/almanac_data_helper.dart';

/// 長輩專用「每日農民曆與神明誕辰」大字版專頁
class FarmerAlmanacScreen extends StatefulWidget {
  final DateTime? initialDate;
  final String userName;

  const FarmerAlmanacScreen({
    super.key,
    this.initialDate,
    this.userName = '長輩',
  });

  @override
  State<FarmerAlmanacScreen> createState() => _FarmerAlmanacScreenState();
}

class _FarmerAlmanacScreenState extends State<FarmerAlmanacScreen> {
  late DateTime _currentDate;
  late DayAlmanacInfo _almanacInfo;
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    _currentDate = widget.initialDate ?? DateTime.now();
    _updateAlmanac();
    _initTts();
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('zh-TW');
      await _tts.setSpeechRate(0.46);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);

      _tts.setCompletionHandler(() {
        if (mounted) setState(() => _isSpeaking = false);
      });
      _tts.setCancelHandler(() {
        if (mounted) setState(() => _isSpeaking = false);
      });
      _tts.setErrorHandler((_) {
        if (mounted) setState(() => _isSpeaking = false);
      });
    } catch (e) {
      debugPrint('TTS Init error: $e');
    }
  }

  void _updateAlmanac() {
    setState(() {
      _almanacInfo = AlmanacDataHelper.calculateForDate(_currentDate);
    });
  }

  void _changeDate(int offsetDays) {
    HapticFeedback.selectionClick();
    _stopTts();
    setState(() {
      _currentDate = _currentDate.add(Duration(days: offsetDays));
      _updateAlmanac();
    });
  }

  void _resetToToday() {
    HapticFeedback.mediumImpact();
    _stopTts();
    setState(() {
      _currentDate = DateTime.now();
      _updateAlmanac();
    });
  }

  Future<void> _pickCustomDate() async {
    HapticFeedback.selectionClick();
    _stopTts();
    final picked = await showDatePicker(
      context: context,
      initialDate: _currentDate,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(2050, 12, 31),
      locale: const Locale('zh', 'TW'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFC2410C),
              onPrimary: Colors.white,
              onSurface: Color(0xFF1E293B),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _currentDate) {
      setState(() {
        _currentDate = picked;
        _updateAlmanac();
      });
    }
  }

  Future<void> _toggleTts() async {
    HapticFeedback.mediumImpact();
    if (_isSpeaking) {
      await _stopTts();
    } else {
      final speechText = _almanacInfo.toSpeechString();
      setState(() => _isSpeaking = true);
      await _tts.speak(speechText);
    }
  }

  Future<void> _stopTts() async {
    if (_isSpeaking) {
      await _tts.stop();
      if (mounted) setState(() => _isSpeaking = false);
    }
  }

  void _showMeaningDialog(String term) {
    HapticFeedback.lightImpact();
    final meaning = AlmanacDataHelper.getMeaning(term);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('📖', style: TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 10),
            Text(
              '「$term」是什麼意思？',
              style: GoogleFonts.notoSansTc(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B),
              ),
            ),
          ],
        ),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            meaning,
            style: GoogleFonts.notoSansTc(
              fontSize: 18,
              height: 1.5,
              color: const Color(0xFF334155),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFF55B695),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text(
              '知道了',
              style: GoogleFonts.notoSansTc(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isToday = _currentDate.year == DateTime.now().year &&
        _currentDate.month == DateTime.now().month &&
        _currentDate.day == DateTime.now().day;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildAppBar(isToday),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                children: [
                  // 1. 傳統吉祥大撕曆卡片
                  _buildTearCalendarCard(isToday),
                  const SizedBox(height: 16),

                  // 2. 🌟 神明聖誕金光特報卡（或下個神誕倒數）
                  _buildDeityCelebrationCard(),
                  const SizedBox(height: 16),

                  // 3. ⚖️ 每日宜忌吉凶對照面板
                  _buildYiJiPanel(),
                  const SizedBox(height: 16),

                  // 4. 🧭 吉神方位、沖煞生肖與百忌
                  _buildLuckyDirectionAndChongCard(),
                ],
              ),
            ),

            // 5. 底部快速翻日切換列
            _buildDateSwitcherBottomBar(isToday),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isToday) {
    return AppBar(
      backgroundColor: const Color(0xFFFFFFFF),
      elevation: 0,
      scrolledUnderElevation: 2,
      centerTitle: true,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF1E293B)),
        ),
        onPressed: () {
          HapticFeedback.lightImpact();
          _stopTts();
          Navigator.pop(context);
        },
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🏮', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 6),
          Text(
            '每日農民曆',
            style: GoogleFonts.notoSansTc(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 14),
          child: InkWell(
            onTap: _toggleTts,
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _isSpeaking ? const Color(0xFFEF4444) : const Color(0xFFE0F2FE),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isSpeaking ? const Color(0xFFDC2626) : const Color(0xFF0284C7),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isSpeaking ? Icons.stop_circle_rounded : Icons.volume_up_rounded,
                    color: _isSpeaking ? Colors.white : const Color(0xFF0369A1),
                    size: 20,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isSpeaking ? '停止' : '唸給我聽',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: _isSpeaking ? Colors.white : const Color(0xFF0369A1),
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

  Widget _buildTearCalendarCard(bool isToday) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFDC2626), Color(0xFFEA580C)],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Row(
              children: [
                const Icon(Icons.wb_sunny_rounded, color: Color(0xFFFEF08A), size: 20),
                const SizedBox(width: 6),
                Text(
                  '歲次 ${_almanacInfo.ganZhiYear}年（${_almanacInfo.shengXiao}）',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                if (isToday)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '今日吉日',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFFDC2626),
                      ),
                    ),
                  )
                else
                  Text(
                    '${_currentDate.year}年',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFFEF08A),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_currentDate.month}月',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      Text(
                        '${_currentDate.day}',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 66,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFFDC2626),
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _almanacInfo.solarWeekDay,
                          style: GoogleFonts.notoSansTc(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 110,
                  width: 1.5,
                  color: const Color(0xFFE2E8F0),
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                ),
                Expanded(
                  flex: 6,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '農曆',
                              style: GoogleFonts.notoSansTc(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF92400E),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _almanacInfo.ganZhiMonth,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 14,
                              color: const Color(0xFF64748B),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _almanacInfo.lunarShort,
                        style: GoogleFonts.notoSansTc(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (_almanacInfo.solarTerm.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDCFCE7),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF16A34A).withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('🍃', style: TextStyle(fontSize: 13)),
                                  const SizedBox(width: 4),
                                  Text(
                                    _almanacInfo.solarTerm,
                                    style: GoogleFonts.notoSansTc(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFF15803D),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(width: 8),
                          Text(
                            _almanacInfo.ganZhiDay,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeityCelebrationCard() {
    if (_almanacInfo.hasDeityBirthday) {
      final deity = _almanacInfo.deities.first;
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFF59E0B), width: 1.8),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(deity.iconEmoji, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFB45309),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '今日神明萬壽',
                              style: GoogleFonts.notoSansTc(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            deity.category,
                            style: GoogleFonts.notoSansTc(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFB45309),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        deity.name,
                        style: GoogleFonts.notoSansTc(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF78350F),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(color: Color(0xFFFDE68A), thickness: 1.5, height: 22),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('🙏 ', style: TextStyle(fontSize: 16)),
                Expanded(
                  child: Text(
                    deity.blessing,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF92400E),
                    ),
                  ),
                ),
              ],
            ),
            if (deity.customNote.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🏮 ', style: TextStyle(fontSize: 16)),
                  Expanded(
                    child: Text(
                      '傳統習俗：${deity.customNote}',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFB45309),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }

    final upcoming = _almanacInfo.upcomingDeity;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF86EFAC)),
      ),
      child: Row(
        children: [
          const Text('🍀', style: TextStyle(fontSize: 30)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '平安吉祥日',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF166534),
                  ),
                ),
                const SizedBox(height: 3),
                if (upcoming != null)
                  Text(
                    '🌟 距離【${upcoming.deity.title}】還有 ${upcoming.daysAway} 天',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF15803D),
                    ),
                  )
                else
                  Text(
                    '身心自在，心寬延壽，福澤綿長。',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF15803D),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYiJiPanel() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('⚖️', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Text(
                '今日宜忌指南',
                style: GoogleFonts.notoSansTc(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const Spacer(),
              Text(
                '（點擊查看白話解說）',
                style: GoogleFonts.notoSansTc(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '宜',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _almanacInfo.yiList.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '諸事皆宜',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF166534),
                        ),
                      ),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _almanacInfo.yiList.map((term) {
                        return InkWell(
                          onTap: () => _showMeaningDialog(term),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FDF4),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFBBF7D0)),
                            ),
                            child: Text(
                              term,
                              style: GoogleFonts.notoSansTc(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF166534),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
              ),
            ],
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(color: Color(0xFFF1F5F9), thickness: 1.5),
          ),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '忌',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _almanacInfo.jiList.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '無特定禁忌',
                        style: GoogleFonts.notoSansTc(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF475569),
                        ),
                      ),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _almanacInfo.jiList.map((term) {
                        return InkWell(
                          onTap: () => _showMeaningDialog(term),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFFECACA)),
                            ),
                            child: Text(
                              term,
                              style: GoogleFonts.notoSansTc(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF991B1B),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLuckyDirectionAndChongCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🧭', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Text(
                '吉神方位與沖煞提醒',
                style: GoogleFonts.notoSansTc(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: _buildDirectionPill('💰 財神', _almanacInfo.caiShen, const Color(0xFFFEF3C7), const Color(0xFF92400E)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDirectionPill('💖 喜神', _almanacInfo.xiShen, const Color(0xFFFCE7F3), const Color(0xFF9D174D)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDirectionPill('🍀 福神', _almanacInfo.fuShen, const Color(0xFFE0F2FE), const Color(0xFF075985)),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFFEDD5)),
            ),
            child: Row(
              children: [
                const Text('⚠️', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '今日沖煞：${_almanacInfo.chongDesc}',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFC2410C),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectionPill(String title, String direction, Color bg, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: GoogleFonts.notoSansTc(fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
          ),
          const SizedBox(height: 2),
          Text(
            direction.isEmpty ? '正北' : direction,
            style: GoogleFonts.notoSansTc(fontSize: 16, fontWeight: FontWeight.w900, color: textColor),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSwitcherBottomBar(bool isToday) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: () => _changeDate(-1),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: EdgeInsets.zero,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.chevron_left_rounded, size: 24, color: Color(0xFF334155)),
                    Text(
                      '前一日',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF334155),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: isToday ? null : _resetToToday,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE2E8F0),
                disabledForegroundColor: const Color(0xFF94A3B8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                elevation: isToday ? 0 : 2,
              ),
              child: Text(
                '回今天',
                style: GoogleFonts.notoSansTc(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          IconButton(
            onPressed: _pickCustomDate,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFF1F5F9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.all(12),
            ),
            icon: const Icon(Icons.calendar_month_rounded, color: Color(0xFF0F172A), size: 24),
            tooltip: '選擇日期',
          ),
          const SizedBox(width: 10),

          Expanded(
            child: SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: () => _changeDate(1),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: EdgeInsets.zero,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '後一日',
                      style: GoogleFonts.notoSansTc(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF334155),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, size: 24, color: Color(0xFF334155)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
