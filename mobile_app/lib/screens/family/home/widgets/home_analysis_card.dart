import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../models/elder.dart';
import '../../../../models/memoir_story.dart';
import '../../../../services/api/location_api.dart';
import '../../../../services/api_service.dart';
import '../../../../services/memoir_service.dart';
import '../../../../widgets/ui/ui.dart';
import '../../emotion_timeline_screen.dart';
import '../../health_trends_screen.dart';
import '../../memoirs_gallery_screen.dart';
import '../../outing_trends_screen.dart';
import '../../widgets/fam_data_ui.dart';
import '../../widgets/fam_ui.dart';
import '../models/analysis_buckets.dart';

/// 首頁「近況分析」卡片：用一張卡、三段切換（健康／外出／情緒與故事）呈現最近 7 天的
/// 迷你長條圖與一兩句事實摘要，細節一律用「看詳細」連到既有的完整頁面。
///
/// - 各分頁**第一次被選到才載入**並快取；切換長輩、父層刷新訊號（[refreshToken]）變動時
///   清掉快取，只重載目前選中的那一段。
/// - 沒有資料的日子不畫長條，也不當成 0（步數 null ≠ 走 0 步）。
/// - 外出：長輩關閉位置分享、沒有定位資料、請求失敗各有不同文案（沿用外出趨勢頁）。
/// - 情緒：只有「偵測到的負面情緒」，沒有紀錄不代表心情平穩，卡片上誠實註明。
class HomeAnalysisCard extends StatefulWidget {
  final Elder? currentElder;
  final int? userId;

  /// 父層遞增即重讀（與 [HomeCheckinCard] 同一條刷新路徑）。
  final int refreshToken;

  // 以下為測試注入點；null 時走真實 API。
  final Future<Map<String, dynamic>> Function(String elderId, int? familyId)? stepsLoader;
  final Future<Map<String, dynamic>?> Function(String elderId, int userId)? outingLoader;
  final Future<Map<String, dynamic>> Function(String elderId, int? familyId)? emotionLoader;
  final Future<List<MemoirStory>> Function(String elderId)? memoirLoader;

  const HomeAnalysisCard({
    super.key,
    this.currentElder,
    this.userId,
    this.refreshToken = 0,
    this.stepsLoader,
    this.outingLoader,
    this.emotionLoader,
    this.memoirLoader,
  });

  @override
  State<HomeAnalysisCard> createState() => _HomeAnalysisCardState();
}

enum _Seg { health, outing, emotion }

enum _St { idle, loading, ready, empty, error, sharingOff }

class _HomeAnalysisCardState extends State<HomeAnalysisCard> {
  _Seg _seg = _Seg.health;

  final Map<_Seg, _St> _status = {for (final s in _Seg.values) s: _St.idle};
  final Map<_Seg, String> _error = {};
  final Map<_Seg, int> _seq = {for (final s in _Seg.values) s: 0};

  List<DayValue> _steps = const [];
  List<DayValue> _outing = const [];
  bool _hasHome = false;
  List<DayValue> _emotion = const [];
  List<MemoirStory> _stories = const [];

  /// 與資料庫 id 不同：這是長輩端的字串 id（GPS／回憶錄用），缺漏退回資料庫 id。
  String? get _elderKey => widget.currentElder?.elderId ?? widget.currentElder?.id.toString();

  @override
  void initState() {
    super.initState();
    MemoirService.instance.addListener(_onMemoirsChanged);
    _ensureLoaded();
  }

  @override
  void dispose() {
    MemoirService.instance.removeListener(_onMemoirsChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HomeAnalysisCard old) {
    super.didUpdateWidget(old);
    if (old.currentElder?.id != widget.currentElder?.id ||
        old.currentElder?.elderId != widget.currentElder?.elderId ||
        old.userId != widget.userId ||
        old.refreshToken != widget.refreshToken) {
      for (final s in _Seg.values) {
        _status[s] = _St.idle;
        _seq[s] = (_seq[s] ?? 0) + 1; // 丟棄還在路上的舊請求
      }
      _ensureLoaded();
    }
  }

  void _onMemoirsChanged() {
    if (mounted && _status[_Seg.emotion] == _St.ready) {
      _load(_Seg.emotion, silent: true);
    }
  }

  void _ensureLoaded() {
    if (_status[_seg] == _St.idle) _load(_seg);
  }

  Future<int?> _familyId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt('caregiver_id') ?? widget.userId;
    } catch (_) {
      return widget.userId;
    }
  }

  Future<void> _load(_Seg seg, {bool silent = false}) async {
    final elder = widget.currentElder;
    if (elder == null) {
      setState(() => _status[seg] = _St.error);
      _error[seg] = '尚未選擇長輩';
      return;
    }
    final seq = (_seq[seg] ?? 0) + 1;
    _seq[seg] = seq;
    if (!silent) setState(() => _status[seg] = _St.loading);
    final today = DateTime.now();

    try {
      switch (seg) {
        case _Seg.health:
          final fid = await _familyId();
          final resp = await (widget.stepsLoader ?? _defaultSteps)(elder.id.toString(), fid);
          if (!mounted || seq != _seq[seg]) return;
          if (resp['status'] != 'success') {
            return _fail(seg, (resp['detail'] ?? resp['message'] ?? resp['error'] ?? '步數資料載入失敗').toString());
          }
          final data = resp['data'];
          if (data is! Map || data['available'] == false) {
            return _fail(seg, '步數資料來源目前無法查詢，請稍後再試');
          }
          final days = AnalysisBuckets.bucketDaily((data['series'] as List?) ?? const [], 'steps', today);
          setState(() {
            _steps = days;
            _status[seg] = days.any((d) => d.value != null) ? _St.ready : _St.empty;
          });
        case _Seg.outing:
          final uid = widget.userId;
          final key = _elderKey;
          if (uid == null || key == null) return _fail(seg, '載入失敗，請稍後再試');
          final data = await (widget.outingLoader ?? _defaultOuting)(key, uid);
          if (!mounted || seq != _seq[seg]) return;
          if (data == null) return _fail(seg, '載入失敗，請稍後再試');
          if (data['sharing_enabled'] != true) {
            setState(() => _status[seg] = _St.sharingOff);
            return;
          }
          final raw = (data['days'] as List?) ?? const [];
          final days = AnalysisBuckets.bucketDaily(raw, 'outing_count', today);
          final hasAnyPoint = raw.any((e) =>
              e is Map && (((e['point_count'] as num?) ?? 0) > 0 || ((e['distance_m'] as num?) ?? 0) > 0));
          setState(() {
            _outing = days;
            _hasHome = data['has_home'] == true;
            _status[seg] = hasAnyPoint ? _St.ready : _St.empty;
          });
        case _Seg.emotion:
          final fid = await _familyId();
          final key = _elderKey;
          final results = await Future.wait([
            (widget.emotionLoader ?? _defaultEmotion)(elder.id.toString(), fid),
            (widget.memoirLoader ?? MemoirService.instance.getMemoirs)(key ?? 'default_elder')
                .catchError((_) => <MemoirStory>[]),
          ]);
          if (!mounted || seq != _seq[seg]) return;
          final resp = results[0] as Map<String, dynamic>;
          if (resp['status'] != 'success') {
            return _fail(seg, (resp['detail'] ?? resp['message'] ?? resp['error'] ?? '情緒事件載入失敗').toString());
          }
          final events = ((resp['data'] as Map?)?['events'] as List?) ?? const [];
          setState(() {
            _emotion = AnalysisBuckets.bucketEvents(events, today);
            _stories = results[1] as List<MemoirStory>;
            _status[seg] = _St.ready; // 即使 0 次情緒也要顯示圖與人生故事
          });
      }
    } catch (_) {
      if (mounted && seq == _seq[seg]) _fail(seg, '載入失敗，請稍後再試');
    }
  }

  void _fail(_Seg seg, String msg) {
    setState(() {
      _status[seg] = _St.error;
      _error[seg] = msg;
    });
  }

  static Future<Map<String, dynamic>> _defaultSteps(String id, int? fid) =>
      ApiService.getStepsTrend(id, familyId: fid, days: 7);
  static Future<Map<String, dynamic>?> _defaultOuting(String id, int uid) =>
      LocationApi.getDaily(elderId: id, userId: uid, days: 7);
  static Future<Map<String, dynamic>> _defaultEmotion(String id, int? fid) =>
      ApiService.getEmotionEvents(id, familyId: fid, days: 7, limit: 100);

  void _select(int i) {
    final seg = _Seg.values[i];
    if (seg == _seg) return;
    setState(() => _seg = seg);
    _ensureLoaded();
  }

  // ── 導覽 ──
  String get _name => widget.currentElder?.displayName ?? '長輩';

  void _push(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  void _openHealth() => _push(HealthTrendsScreen(elderName: _name, elderId: widget.currentElder?.id));

  void _openOuting() {
    final uid = widget.userId;
    final key = _elderKey;
    if (uid == null || key == null) return;
    _push(OutingTrendsScreen(elderId: key, userId: uid, elderName: _name));
  }

  void _openEmotion() => _push(EmotionTimelineScreen(elderName: _name, elderId: widget.currentElder?.id));

  Future<void> _openGallery() async {
    final key = _elderKey ?? 'default_elder';
    String familyName = '家人';
    try {
      final prefs = await SharedPreferences.getInstance();
      final n = prefs.getString('caregiver_name');
      if (n != null && n.isNotEmpty) familyName = n;
    } catch (_) {}
    if (!mounted) return;
    _push(MemoirsGalleryScreen(
      elderId: key,
      elderName: _name,
      familyUserName: familyName,
      familyId: widget.userId,
    ));
  }

  // ── 畫面 ──
  @override
  Widget build(BuildContext context) {
    return FamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FamSecHead(title: '近況分析'),
          const SizedBox(height: 10),
          UbanSegmented(
            small: true,
            labels: const ['健康', '外出', '情緒與故事'],
            index: _Seg.values.indexOf(_seg),
            onChanged: _select,
          ),
          const SizedBox(height: 12),
          _buildBody(context),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final c = UbanColors.of(context);
    final st = _status[_seg] ?? _St.idle;
    switch (st) {
      case _St.idle:
      case _St.loading:
        return const FamStateBlock(
          height: 120,
          child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
        );
      case _St.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_error[_seg] ?? '載入失敗，請稍後再試',
                style: famText(c.danger, 14, weight: FontWeight.w700, height: 1.5)),
            if (widget.currentElder != null) FamMore(label: '重試', onTap: () => _load(_seg)),
          ],
        );
      case _St.sharingOff:
        return _note(c, '長輩已關閉位置分享');
      case _St.empty:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _note(c, _seg == _Seg.health ? '這 7 天還沒有步數資料' : '這 7 天沒有定位資料'),
            _links([
              FamMore(label: '看詳細', onTap: _seg == _Seg.health ? _openHealth : _openOuting),
            ]),
          ],
        );
      case _St.ready:
        return switch (_seg) {
          _Seg.health => _healthBody(c),
          _Seg.outing => _outingBody(c),
          _Seg.emotion => _emotionBody(c),
        };
    }
  }

  Widget _note(UbanColors c, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(text, style: famText(c.text2, 14, height: 1.5)),
      );

  Widget _summary(UbanColors c, String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(text, style: famText(c.text, 14, weight: FontWeight.w700, height: 1.5)),
      );

  Widget _links(List<Widget> children) => Wrap(
        spacing: 8,
        runSpacing: 0,
        alignment: WrapAlignment.end,
        children: children,
      );

  Widget _healthBody(UbanColors c) {
    final s = AnalysisBuckets.stepsSummary(_steps);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MiniBars(days: _steps, color: c.brandFill),
        if (s != null) _summary(c, s),
        _links([FamMore(label: '看詳細', onTap: _openHealth)]),
      ],
    );
  }

  Widget _outingBody(UbanColors c) {
    final s = AnalysisBuckets.outingSummary(_outing, hasHome: _hasHome);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_hasHome) _MiniBars(days: _outing, color: c.info),
        if (s != null) _summary(c, s),
        _links([FamMore(label: '看詳細', onTap: _openOuting)]),
      ],
    );
  }

  Widget _emotionBody(UbanColors c) {
    final total = _emotion.fold<int>(0, (a, d) => a + (d.value ?? 0));
    String two(int n) => n.toString().padLeft(2, '0');
    final recent = _stories.take(2).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MiniBars(days: _emotion, color: c.warm),
        _summary(c, AnalysisBuckets.emotionSummary(_emotion, _stories.length)),
        if (total == 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '沒有紀錄不代表心情一定平穩，也可能是這段期間長輩比較少和小豬聊天。',
              style: famText(c.text2, 13, height: 1.5),
            ),
          ),
        const SizedBox(height: 10),
        Text('最近的人生故事', style: famText(c.text2, 13, weight: FontWeight.w700)),
        if (recent.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('長輩還沒有分享故事，可以「委託小豬提問」讓小豬主動發問。',
                style: famText(c.text2, 13, height: 1.5)),
          )
        else
          for (var i = 0; i < recent.length; i++)
            FamStoryRow(
              first: i == 0,
              title: recent[i].title,
              meta: '${two(recent[i].recordedDate.month)}/${two(recent[i].recordedDate.day)}・${recent[i].tag}',
              onTap: _openGallery,
            ),
        const SizedBox(height: 4),
        _links([
          FamMore(label: '看情緒紀錄', onTap: _openEmotion),
          FamMore(label: '翻閱人生故事', onTap: _openGallery),
        ]),
        FamButton(
          label: '委託小豬提問',
          kind: FamButtonKind.outline,
          height: 44,
          onPressed: _openGallery,
        ),
      ],
    );
  }
}

/// 7 天迷你長條圖：不畫座標軸數字，只標每天日期；今天（統計中）顏色較淡；
/// value 為 null（沒資料）不畫長條。
class _MiniBars extends StatelessWidget {
  final List<DayValue> days;
  final Color color;

  const _MiniBars({required this.days, required this.color});

  @override
  Widget build(BuildContext context) {
    final c = UbanColors.of(context);
    final maxV = days.fold<int>(0, (m, d) => (d.value ?? 0) > m ? d.value! : m);
    final maxY = (maxV < 3 ? 3 : maxV).toDouble();
    final groups = [
      for (var i = 0; i < days.length; i++)
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: (days[i].value ?? 0).toDouble(),
              width: 16,
              color: i == days.length - 1 ? color.withValues(alpha: 0.35) : color,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
              backDrawRodData: BackgroundBarChartRodData(show: true, toY: maxY, color: c.surface2),
            ),
          ],
        ),
    ];
    return SizedBox(
      height: 120,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          minY: 0,
          maxY: maxY,
          barGroups: groups,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(enabled: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= days.length) return const SizedBox();
                  final d = days[i].date;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('${d.month}/${d.day}', style: famText(c.text3, 10, tabular: true)),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
