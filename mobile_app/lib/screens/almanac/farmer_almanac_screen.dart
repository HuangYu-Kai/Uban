import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../models/almanac_data_helper.dart';
import '../../widgets/ui/ui.dart';

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
        final c = UbanColors.of(context);
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: c.brandFill,
                  onPrimary: c.onBrand,
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
    // 設計稿 `#dl-meaning`：詞彙大標＋白話解說＋「知道了」。
    showUbanDialog<void>(
      context,
      (ctx) {
        final c = UbanColors.of(ctx);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '「$term」是什麼意思？',
              style: ubanText(24, FontWeight.w900, c.text, height: 1.3),
            ),
            const SizedBox(height: 10),
            Text(
              meaning,
              style: ubanText(20, FontWeight.w500, c.text2, height: 1.6),
            ),
            const SizedBox(height: 18),
            UbanButton(label: '知道了', onPressed: () => Navigator.pop(ctx)),
          ],
        );
      },
    );
  }

  /// 農民曆頭部固定色（內容固定色，不隨亮暗模式）：設計稿 `.alm-head`。
  static const Color _almRed = Color(0xFFC8553D);
  static const Color _almRedDeep = Color(0xFFA63D2B);

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final now = DateTime.now();
    final isToday = _currentDate.year == now.year &&
        _currentDate.month == now.month &&
        _currentDate.day == now.day;
    // 字級放大到 1.15 以上時，「唸給我聽」換到標題下一列，避免標題被擠成省略號。
    final bigText = MediaQuery.textScalerOf(context).scale(10) > 11.5;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                children: [
                  _buildTopBar(c, bigText),
                  const SizedBox(height: 16),

                  // 1. 傳統吉祥大撕曆卡片
                  _buildTearCalendarCard(c, isToday),
                  const SizedBox(height: 14),

                  // 2. 神明聖誕特報卡（或下個神誕倒數）
                  _buildDeityCelebrationCard(c),
                  const SizedBox(height: 14),

                  // 3. 每日宜忌吉凶對照面板
                  _buildYiJiPanel(c),
                  const SizedBox(height: 14),

                  // 4. 吉神方位、沖煞生肖
                  _buildLuckyDirectionAndChongCard(c),
                ],
              ),
            ),

            // 5. 底部快速翻日切換列
            _buildDateSwitcherBottomBar(c, isToday),
          ],
        ),
      ),
    );
  }

  /// 頂列：返回＋標題＋「唸給我聽」切換（`_toggleTts` 原函式）。
  Widget _buildTopBar(UbanColors c, bool bigText) {
    final tts = _buildTtsButton(c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UbanTopBar(
          title: '農民曆',
          onBack: () {
            HapticFeedback.lightImpact();
            _stopTts();
            Navigator.pop(context);
          },
          trailing: bigText ? null : tts,
        ),
        if (bigText) ...[
          const SizedBox(height: 10),
          tts,
        ],
      ],
    );
  }

  Widget _buildTtsButton(UbanColors c) {
    return UbanButton(
      label: _isSpeaking ? '停止' : '唸給我聽',
      icon: _isSpeaking ? Icons.stop_circle_rounded : Icons.volume_up_rounded,
      variant:
          _isSpeaking ? UbanButtonVariant.danger : UbanButtonVariant.tonal,
      expand: false,
      onPressed: _toggleTts,
    );
  }

  /// 設計稿 `.tag`：膠囊標籤。
  Widget _tag(String text, Color bg, Color fg, {double size = 16}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: ubanText(size, FontWeight.w700, fg)),
    );
  }

  Widget _buildTearCalendarCard(UbanColors c, bool isToday) {
    return UbanCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          children: [
            // 紅色頭部：內容固定色（農民曆傳統紅），白字
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_almRed, _almRedDeep],
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '歲次 ${_almanacInfo.ganZhiYear}年（${_almanacInfo.shengXiao}）',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ubanText(18, FontWeight.w900, Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isToday)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('今天',
                          style: ubanText(16, FontWeight.w700, Colors.white)),
                    )
                  else
                    Text(
                      '${_currentDate.year}年',
                      style: ubanText(
                          18, FontWeight.w700, Colors.white.withValues(alpha: 0.92)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_currentDate.month}月',
                        style: ubanText(20, FontWeight.w700, c.text2),
                      ),
                      Text(
                        '${_currentDate.day}',
                        style: ubanBrandText(74, FontWeight.w600, _almRed,
                            height: 1),
                      ),
                      const SizedBox(height: 6),
                      _tag(_almanacInfo.solarWeekDay, c.surface2, c.text2),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _tag('農曆・${_almanacInfo.ganZhiMonth}', c.surface2,
                            c.text2),
                        const SizedBox(height: 8),
                        // 農曆日期可能較長，字級放大時縮小而不是溢位
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _almanacInfo.lunarShort,
                            maxLines: 1,
                            style: ubanText(28, FontWeight.w900, c.text),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_almanacInfo.solarTerm.isNotEmpty) ...[
                          _tag(_almanacInfo.solarTerm, c.brandContainer,
                              c.brandStrong),
                          const SizedBox(height: 8),
                        ],
                        Text(
                          _almanacInfo.ganZhiDay,
                          style: ubanText(18, FontWeight.w500, c.text2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeityCelebrationCard(UbanColors c) {
    if (_almanacInfo.hasDeityBirthday) {
      final deity = _almanacInfo.deities.first;
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: c.warmContainer,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(deity.iconEmoji, style: const TextStyle(fontSize: 32)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _tag('今日神明萬壽', c.warm, c.warmContainer, size: 15),
                          Text(deity.category,
                              style: ubanText(16, FontWeight.w700, c.warm)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        deity.name,
                        style: ubanText(24, FontWeight.w900, c.warm,
                            height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '🙏 ${deity.blessing}',
              style: ubanText(18, FontWeight.w700, c.text, height: 1.5),
            ),
            if (deity.customNote.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '🏮 傳統習俗：${deity.customNote}',
                style: ubanText(18, FontWeight.w500, c.text2, height: 1.5),
              ),
            ],
          ],
        ),
      );
    }

    final upcoming = _almanacInfo.upcomingDeity;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.brandSoft,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('平安吉祥日', style: ubanText(20, FontWeight.w900, c.text)),
          const SizedBox(height: 4),
          Text(
            upcoming != null
                ? '距離【${upcoming.deity.title}】還有 ${upcoming.daysAway} 天'
                : '身心自在，心寬延壽，福澤綿長。',
            style: ubanText(18, FontWeight.w500, c.text2, height: 1.5),
          ),
        ],
      ),
    );
  }

  /// 宜／忌詞彙膠囊（點擊 → 白話解說，原 `_showMeaningDialog`）。
  Widget _termChip(String term, Color bg, Color fg) {
    return PressableScale(
      onTap: () => _showMeaningDialog(term),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(term, style: ubanText(18, FontWeight.w700, fg)),
      ),
    );
  }

  Widget _yiJiRow({
    required String badge,
    required Color badgeBg,
    required Color badgeFg,
    required List<String> terms,
    required String emptyText,
    required Color emptyColor,
    required Color chipBg,
    required Color chipFg,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: badgeBg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(badge, style: ubanText(18, FontWeight.w900, badgeFg)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: terms.isEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(emptyText,
                      style: ubanText(18, FontWeight.w700, emptyColor)),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: terms
                      .map((term) => _termChip(term, chipBg, chipFg))
                      .toList(),
                ),
        ),
      ],
    );
  }

  Widget _buildYiJiPanel(UbanColors c) {
    return UbanCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text('今日宜忌',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ubanText(20, FontWeight.w900, c.text)),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '點一下看白話解說',
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  style: ubanText(15, FontWeight.w500, c.text3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _yiJiRow(
            badge: '宜',
            badgeBg: c.brandFill,
            badgeFg: c.onBrand,
            terms: _almanacInfo.yiList,
            emptyText: '諸事皆宜',
            emptyColor: c.brandStrong,
            chipBg: c.brandContainer,
            chipFg: c.brandStrong,
          ),
          const SizedBox(height: 14),
          _yiJiRow(
            badge: '忌',
            badgeBg: c.danger,
            badgeFg: Colors.white,
            terms: _almanacInfo.jiList,
            emptyText: '無特定禁忌',
            emptyColor: c.text2,
            chipBg: c.dangerContainer,
            chipFg: c.danger,
          ),
        ],
      ),
    );
  }

  Widget _buildLuckyDirectionAndChongCard(UbanColors c) {
    String dir(String d) => d.isEmpty ? '正北' : d;
    return UbanCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('吉神方位與沖煞提醒', style: ubanText(20, FontWeight.w900, c.text)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _tag('財神 ${dir(_almanacInfo.caiShen)}', c.surface2, c.text,
                  size: 18),
              _tag('喜神 ${dir(_almanacInfo.xiShen)}', c.surface2, c.text,
                  size: 18),
              _tag('福神 ${dir(_almanacInfo.fuShen)}', c.surface2, c.text,
                  size: 18),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: c.warmContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '今日沖煞：${_almanacInfo.chongDesc}',
              style: ubanText(18, FontWeight.w700, c.warm, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  /// 底部翻日列（設計稿 `.alm-bar`）：前一日／回今天／日曆／後一日，高 56。
  Widget _buildDateSwitcherBottomBar(UbanColors c, bool isToday) {
    Widget barButton({
      required VoidCallback? onTap,
      required Widget child,
      Color? bg,
    }) {
      return PressableScale(
        enabled: onTap != null,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: bg ?? Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: FittedBox(fit: BoxFit.scaleDown, child: child),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: c.glass,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.glassLine),
        boxShadow: c.shadows.card,
      ),
      child: Row(
        children: [
          Expanded(
            child: barButton(
              onTap: () => _changeDate(-1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chevron_left_rounded, size: 24, color: c.text),
                  Text('前一日', style: ubanText(17, FontWeight.w700, c.text)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: barButton(
              onTap: isToday ? null : _resetToToday,
              bg: isToday ? c.surface2 : c.brandFill,
              child: Text(
                '回今天',
                style: ubanText(17, FontWeight.w700,
                    isToday ? c.text3 : c.onBrand),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 56,
            child: Tooltip(
              message: '選擇日期',
              child: barButton(
                onTap: _pickCustomDate,
                child: Icon(Icons.calendar_month_rounded,
                    size: 26, color: c.text),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: barButton(
              onTap: () => _changeDate(1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('後一日', style: ubanText(17, FontWeight.w700, c.text)),
                  Icon(Icons.chevron_right_rounded, size: 24, color: c.text),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
