import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../../theme/family_theme.dart';
import '../../widgets/ui/ui.dart';
import 'widgets/fam_data_ui.dart';
import 'widgets/fam_ui.dart';

/// 情緒關注事件（第四十九輪：拿掉假造的一整天情緒曲線，改真實資料）
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
///
/// 2026-10 起外觀改家屬新設計（`UbanSegmented`、`FamCard`、色點取代 emoji）；資料與 API 不變。
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

  // 家屬主題之下的 context（State 自己的 context 在 FamilyThemeScope 之上）；每次 build 更新。
  BuildContext? _themed;
  BuildContext get _themeCtx => _themed ?? context;
  UbanColors get _c => UbanColors.of(_themeCtx);

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
        // ★ 第五十一輪：FastAPI 錯誤回應只有 `detail`（沒有 `message`／
        // `error`），原本的 fallback 鏈永遠找不到值、必然落到最後那句寫死的
        // 訊息，等於把「查無此長輩」「未與該長輩綁定，無權限查看」等實際
        // 原因都吃掉了——優先顯示 `detail`。
        _errorMsg = (resp['detail'] ?? resp['message'] ?? resp['error'] ?? '情緒事件載入失敗').toString();
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
    // 2026-10：push 出來的家屬頁要自己掛家屬主題；Builder 讓下方 context 位於主題之內。
    return FamilyThemeScope(
      child: Builder(builder: _buildScreen),
    );
  }

  Widget _buildScreen(BuildContext context) {
    _themed = context;
    final c = _c;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: famSubBar(context, title: '情緒時間軸'),
      body: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildRangeSelector(),
              const SizedBox(height: 12),
              _buildExplainerBanner(),
              const SizedBox(height: 12),
              _buildContent(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRangeSelector() {
    return UbanSegmented(
      small: true,
      labels: [for (final r in _EventsRange.values) _rangeLabel(r)],
      index: _EventsRange.values.indexOf(_range),
      onChanged: (i) => _changeRange(_EventsRange.values[i]),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildExplainerBanner() {
    return const FamNote(
      text: '這裡只列出系統從對話中偵測到的負面情緒（悲傷／生氣），不是完整的一整天情緒曲線；沒有紀錄不代表長輩心情一定平穩，也可能是這段期間互動較少。',
    ).animate().fadeIn(delay: 100.ms, duration: 300.ms);
  }

  Widget _buildContent() {
    final c = _c;
    switch (_status) {
      case _SectionStatus.loading:
        return const FamCard(
          child: FamStateBlock(
            height: 160,
            child: CircularProgressIndicator(),
          ),
        );
      case _SectionStatus.error:
        return FamCard(
          child: FamStateBlock(
            height: 160,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _errorMsg,
                  textAlign: TextAlign.center,
                  style: famText(c.danger, 14, weight: FontWeight.w700, height: 1.5),
                ),
                const SizedBox(height: 10),
                FamButton(
                  label: '重試',
                  kind: FamButtonKind.tonal,
                  expand: false,
                  height: 44,
                  onPressed: _load,
                ),
              ],
            ),
          ),
        );
      case _SectionStatus.empty:
        return FamCard(
          child: FamStateBlock(
            height: 160,
            child: Text(
              '這段期間沒有偵測到負面情緒事件',
              textAlign: TextAlign.center,
              style: famText(c.text, 15, weight: FontWeight.w700, height: 1.5),
            ),
          ),
        ).animate().fadeIn(duration: 300.ms);
      case _SectionStatus.hasData:
        return _buildEventsList();
    }
  }

  Widget _buildEventsList() {
    final c = _c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            '近${_rangeLabel(_range)}內共 ${_events.length} 次負面情緒關注事件',
            style: famText(c.text2, 13, weight: FontWeight.w700, height: 1.4),
          ),
        ),
        for (var i = 0; i < _events.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _buildEventCard(_events[i]),
        ],
      ],
    );
  }

  Widget _buildEventCard(Map<String, dynamic> event) {
    final c = _c;
    final emotion = event['emotion'] as String?;
    final isAngry = emotion == 'angry';
    // 嚴重度用色點表示（不用 emoji）：生氣＝danger、悲傷＝info。
    final dotColor = isAngry ? c.danger : c.info;
    final label = isAngry ? '生氣' : '悲傷';

    final ts = DateTime.tryParse((event['timestamp'] ?? '').toString());
    final timeLabel = ts != null
        ? '${ts.year}/${ts.month}/${ts.day} ${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}'
        : '時間未知';

    final confidence = event['confidence'];
    final confidencePct = confidence is num ? (confidence * 100).round() : null;
    final rawText = (event['raw_text'] as String?)?.trim();

    return FamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              FamDot(color: dotColor),
              const SizedBox(width: 10),
              // 時間字串與同列的信心度徽章：標題可收縮（鐵律 #14）。
              Expanded(
                child: Text(
                  '$label・$timeLabel',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: famText(c.text, 14.5, weight: FontWeight.w700, height: 1.35),
                ),
              ),
              if (confidencePct != null) ...[
                const SizedBox(width: 8),
                FamChip(label: '信心度 $confidencePct%'),
              ],
            ],
          ),
          if (rawText != null && rawText.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '「$rawText」',
                style: famText(c.text2, 13.5, height: 1.5),
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05, end: 0);
  }
}
