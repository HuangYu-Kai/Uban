import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';

/// 😊 情緒關注事件（第四十九輪：拿掉假造的一整天情緒曲線，改真實資料）
///
/// 原本的 `_generateMockData()` 每次進畫面隨機生 12 個點，在
/// 開心/平靜/焦慮/悲傷 四類之間輪替，畫成一整天的平滑曲線與百分比分佈——
/// 這在資料上不可能成立：`routers/ai.py::run_emotion_analysis()` 只在偵測到
/// sad/angry 且信心度 ≥0.4 時才會把結果寫進 `activity_log`，開心／平靜／
/// 中性的時刻從未被持久化，重建不出一整天的情緒曲線，也算不出四類分佈。
///
/// 這裡改成誠實的呈現方式：近期「負面情緒關注事件」清單，每一筆都是真的
/// 從長輩發言分析出來的紀錄（見 `GET /api/family_insight/emotion_events`），
/// 而不是連續曲線。清單是空的，代表這段期間沒有偵測到明顯負面情緒——但也
/// 可能是長輩這段期間很少用語音對話，兩者在資料上無法區分，畫面上會誠實
/// 提示這一點，不假裝「一切都好」。
class EmotionTimelineScreen extends StatefulWidget {
  final String elderName;
  final int? elderId;
  // 保留參數相容既有呼叫端（目前沒有呼叫端會傳）；清單型畫面改用時間範圍
  // 篩選，不再依賴單一日期的前後翻頁。
  final DateTime? initialDate;

  const EmotionTimelineScreen({
    super.key,
    required this.elderName,
    this.elderId,
    this.initialDate,
  });

  @override
  State<EmotionTimelineScreen> createState() => _EmotionTimelineScreenState();
}

enum _EventsRange { week, month, halfYear }

enum _SectionStatus { loading, hasData, empty, error }

class _EmotionTimelineScreenState extends State<EmotionTimelineScreen> {
  _EventsRange _range = _EventsRange.month;
  _SectionStatus _status = _SectionStatus.loading;
  List<Map<String, dynamic>> _events = [];
  String _errorMsg = '';
  int? _familyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  int _daysFor(_EventsRange r) {
    switch (r) {
      case _EventsRange.week:
        return 7;
      case _EventsRange.month:
        return 30;
      case _EventsRange.halfYear:
        return 180;
    }
  }

  String _rangeLabel(_EventsRange r) {
    switch (r) {
      case _EventsRange.week:
        return '週';
      case _EventsRange.month:
        return '月';
      case _EventsRange.halfYear:
        return '半年';
    }
  }

  Future<void> _load() async {
    setState(() => _status = _SectionStatus.loading);

    if (widget.elderId == null) {
      setState(() {
        _status = _SectionStatus.error;
        _errorMsg = '尚未配對長輩';
      });
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      _familyId = prefs.getInt('caregiver_id');
    } catch (_) {
      _familyId = null;
    }

    final resp = await ApiService.getEmotionEvents(
      widget.elderId.toString(),
      familyId: _familyId,
      days: _daysFor(_range),
      limit: 100,
    );

    if (!mounted) return;

    if (resp['status'] != 'success') {
      setState(() {
        _status = _SectionStatus.error;
        _errorMsg = (resp['message'] ?? resp['error'] ?? '情緒事件載入失敗').toString();
      });
      return;
    }

    final data = resp['data'] as Map<String, dynamic>?;
    final events = ((data?['events'] as List?) ?? []).cast<Map<String, dynamic>>();
    setState(() {
      _events = events;
      _status = events.isEmpty ? _SectionStatus.empty : _SectionStatus.hasData;
    });
  }

  void _changeRange(_EventsRange r) {
    if (r == _range) return;
    setState(() => _range = r);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '情緒時間軸',
          style: GoogleFonts.notoSansTc(
            color: const Color(0xFF1E293B),
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildRangeSelector(),
              _buildExplainerBanner(),
              _buildContent(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRangeSelector() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: _EventsRange.values.map((r) {
          final selected = r == _range;
          return Expanded(
            child: GestureDetector(
              onTap: () => _changeRange(r),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFF3B82F6) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _rangeLabel(r),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : const Color(0xFF64748B),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildExplainerBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF3B82F6)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '這裡只列出系統從對話中偵測到的負面情緒（悲傷／生氣），不是完整的一整天情緒曲線；沒有紀錄不代表長輩心情一定平穩，也可能是這段期間互動較少。',
              style: GoogleFonts.notoSansTc(fontSize: 12, color: const Color(0xFF3B82F6), height: 1.5),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms, duration: 300.ms);
  }

  Widget _buildContent() {
    switch (_status) {
      case _SectionStatus.loading:
        return const Padding(
          padding: EdgeInsets.only(top: 60),
          child: Center(child: CircularProgressIndicator()),
        );
      case _SectionStatus.error:
        return Padding(
          padding: const EdgeInsets.only(top: 40),
          child: Center(
            child: Column(
              children: [
                const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 32),
                const SizedBox(height: 10),
                Text(
                  _errorMsg,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansTc(color: const Color(0xFFEF4444), fontSize: 14),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text('重試', style: GoogleFonts.notoSansTc(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        );
      case _SectionStatus.empty:
        return Padding(
          padding: const EdgeInsets.only(top: 40),
          child: Center(
            child: Column(
              children: [
                const Text('🙂', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 12),
                Text(
                  '這段期間沒有偵測到負面情緒事件',
                  style: GoogleFonts.notoSansTc(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
          ),
        ).animate().fadeIn(duration: 300.ms);
      case _SectionStatus.hasData:
        return _buildEventsList();
    }
  }

  Widget _buildEventsList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '近${_rangeLabel(_range)}內共 ${_events.length} 次負面情緒關注事件',
              style: GoogleFonts.notoSansTc(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF64748B)),
            ),
          ),
        ),
        ..._events.map(_buildEventCard),
      ],
    );
  }

  Widget _buildEventCard(Map<String, dynamic> event) {
    final emotion = event['emotion'] as String?;
    final isAngry = emotion == 'angry';
    final color = isAngry ? const Color(0xFFEF4444) : const Color(0xFF3B82F6);
    final emoji = isAngry ? '😠' : '😢';
    final label = isAngry ? '生氣' : '悲傷';

    final ts = DateTime.tryParse((event['timestamp'] ?? '').toString());
    final timeLabel = ts != null
        ? '${ts.year}/${ts.month}/${ts.day} ${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}'
        : '時間未知';

    final confidence = event['confidence'];
    final confidencePct = confidence is num ? (confidence * 100).round() : null;
    final rawText = (event['raw_text'] as String?)?.trim();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border(left: BorderSide(color: color, width: 4)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$label · $timeLabel',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansTc(fontSize: 14, fontWeight: FontWeight.w800, color: color),
                ),
              ),
              if (confidencePct != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '信心度 $confidencePct%',
                    style: GoogleFonts.notoSansTc(fontSize: 11, fontWeight: FontWeight.w700, color: color),
                  ),
                ),
            ],
          ),
          if (rawText != null && rawText.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '「$rawText」',
                style: GoogleFonts.notoSansTc(fontSize: 13, color: const Color(0xFF475569), height: 1.5),
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05, end: 0);
  }
}
