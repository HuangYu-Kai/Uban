import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../../theme/family_theme.dart';
import '../../widgets/ui/ui.dart';
import 'widgets/fam_data_ui.dart';
import 'widgets/fam_interaction_ui.dart';
import 'widgets/fam_ui.dart';
import 'widgets/gps_ui.dart';

/// 📊 健康趨勢中心（第四十九輪：接上真實資料，拿掉 `_generateMockData()`）
///
/// 三類指標，處理方式不同：
/// - **步數**：真實資料（`elder_daily_step`），畫真正的趨勢圖。
/// - **體重／身高**：真實資料，但需要家屬手動輸入（全庫沒有量測管道）；
///   新表 `elder_body_metrics`，畫面上有「+ 新增紀錄」入口。
/// - **心率／血壓／血糖**：全庫沒有任何欄位、裝置整合或輸入管道，這輪
///   **刻意不假造**——固定顯示 `--` 並註明「需穿戴裝置，目前無法偵測」，
///   保留 UI 版位，之後真的接了裝置可以直接填進來，不用重做版面。
///
/// 載入中／有資料／沒有資料／請求失敗 四種狀態在畫面上必須長得不一樣，
/// 見 `_SectionStatus`。
///
/// 2026-10 起外觀改家屬新設計：`UbanSegmented` 切換步數／體重／身高、`FamFilterChip` 切換
/// 週／月／半年／年、`fl_chart` 配色走 [UbanColors]。資料與 API 呼叫與改版前完全相同。
class HealthTrendsScreen extends StatefulWidget {
  final String elderName;
  final int? elderId;

  /// ★ 2026-10-07 交接 B1／E：呼叫端已知的家屬 user id；`caregiver_id` 讀不到時的退路。
  final int? userId;

  const HealthTrendsScreen({
    super.key,
    required this.elderName,
    this.elderId,
    this.userId,
  });

  @override
  State<HealthTrendsScreen> createState() => _HealthTrendsScreenState();
}

enum TimeRange { week, month, halfYear, year }

enum _SectionStatus { loading, hasData, empty, error }

class _HealthTrendsScreenState extends State<HealthTrendsScreen> {
  TimeRange _selectedTimeRange = TimeRange.month;
  int? _familyId;

  // 0 步數／1 體重／2 身高（純畫面選取，不影響載入）。
  int _metric = 0;

  // 家屬主題之下的 context（State 自己的 context 在 FamilyThemeScope 之上）：
  // 開 sheet／日期選擇器／SnackBar 用它，才吃得到家屬色票；每次 build 更新。
  BuildContext? _themed;
  BuildContext get _themeCtx => _themed ?? context;
  UbanColors get _c => UbanColors.of(_themeCtx);

  _SectionStatus _stepsStatus = _SectionStatus.loading;
  List<Map<String, dynamic>> _stepsSeries = []; // [{date: DateTime, steps: int?}]
  String _stepsErrorMsg = '';

  _SectionStatus _bodyStatus = _SectionStatus.loading;
  List<Map<String, dynamic>> _bodySeries = []; // [{date: DateTime, weight_kg, height_cm}]
  String _bodyErrorMsg = '';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  int _daysForRange(TimeRange range) {
    switch (range) {
      case TimeRange.week:
        return 7;
      case TimeRange.month:
        return 30;
      case TimeRange.halfYear:
        return 180;
      case TimeRange.year:
        return 366;
    }
  }

  String _getTimeRangeLabel(TimeRange range) {
    switch (range) {
      case TimeRange.week:
        return '週';
      case TimeRange.month:
        return '月';
      case TimeRange.halfYear:
        return '半年';
      case TimeRange.year:
        return '年';
    }
  }

  Future<void> _loadAll() async {
    setState(() {
      _stepsStatus = _SectionStatus.loading;
      _bodyStatus = _SectionStatus.loading;
    });

    if (widget.elderId == null) {
      setState(() {
        _stepsStatus = _SectionStatus.error;
        _stepsErrorMsg = '尚未配對長輩';
        _bodyStatus = _SectionStatus.error;
        _bodyErrorMsg = '尚未配對長輩';
      });
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      // ★ 2026-10-07 交接 B1／E：caregiver_id 優先，讀不到就退回呼叫端傳入的 userId
      //   （其他家屬畫面的做法一致），避免 familyId 為 null 時整頁拿不到資料。
      _familyId = prefs.getInt('caregiver_id');
    } catch (_) {
      _familyId = null;
    }
    if (_familyId == null || _familyId! <= 0) {
      final fallback = widget.userId;
      _familyId = (fallback != null && fallback > 0) ? fallback : null;
    }

    final elderIdStr = widget.elderId.toString();
    final days = _daysForRange(_selectedTimeRange);
    final bodyDays = days < 30 ? 30 : days;

    final results = await Future.wait([
      ApiService.getStepsTrend(elderIdStr, familyId: _familyId, days: days),
      ApiService.getBodyMetricsTrend(elderIdStr, familyId: _familyId, days: bodyDays),
    ]);

    if (!mounted) return;
    _applyStepsResponse(results[0]);
    _applyBodyResponse(results[1]);
  }

  void _applyStepsResponse(Map<String, dynamic> resp) {
    if (resp['status'] != 'success') {
      setState(() {
        _stepsStatus = _SectionStatus.error;
        _stepsErrorMsg = ApiService.failureMessageOf(resp, fallback: '步數資料載入失敗');
      });
      return;
    }

    final data = resp['data'] as Map<String, dynamic>?;
    if (data == null || data['available'] == false) {
      setState(() {
        _stepsStatus = _SectionStatus.error;
        _stepsErrorMsg = '步數資料來源目前無法查詢，請稍後再試';
      });
      return;
    }

    final rawSeries = (data['series'] as List?) ?? [];
    final series = rawSeries.map<Map<String, dynamic>>((e) {
      final m = e as Map<String, dynamic>;
      return {
        'date': DateTime.tryParse(m['date'] as String? ?? '') ?? DateTime.now(),
        'steps': m['steps'] == null ? null : (m['steps'] as num).toInt(),
      };
    }).toList();

    final hasAnyData = series.any((e) => e['steps'] != null);
    setState(() {
      _stepsSeries = series;
      _stepsStatus = hasAnyData ? _SectionStatus.hasData : _SectionStatus.empty;
    });
  }

  void _applyBodyResponse(Map<String, dynamic> resp) {
    if (resp['status'] != 'success') {
      setState(() {
        _bodyStatus = _SectionStatus.error;
        _bodyErrorMsg = ApiService.failureMessageOf(resp, fallback: '體重／身高資料載入失敗');
      });
      return;
    }

    final data = resp['data'] as Map<String, dynamic>?;
    if (data == null || data['available'] == false) {
      setState(() {
        _bodyStatus = _SectionStatus.error;
        _bodyErrorMsg = '體重／身高資料來源目前無法查詢，請稍後再試';
      });
      return;
    }

    final rawSeries = (data['series'] as List?) ?? [];
    final series = rawSeries.map<Map<String, dynamic>>((e) {
      final m = e as Map<String, dynamic>;
      return {
        'date': DateTime.tryParse(m['date'] as String? ?? '') ?? DateTime.now(),
        'weight_kg': (m['weight_kg'] as num?)?.toDouble(),
        'height_cm': (m['height_cm'] as num?)?.toDouble(),
      };
    }).toList();

    setState(() {
      _bodySeries = series;
      _bodyStatus = series.isEmpty ? _SectionStatus.empty : _SectionStatus.hasData;
    });
  }

  void _changeTimeRange(TimeRange range) {
    HapticFeedback.lightImpact();
    setState(() => _selectedTimeRange = range);
    _loadAll();
  }

  // ── build ─────────────────────────────────────────────────────────────
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
    // ★ 第五十輪：本畫面原本沒有返回鍵，一旦用 Navigator.push 導覽進來就是死路；
    // famSubBar 內建返回鈕（預設 maybePop）。
    return Scaffold(
      backgroundColor: c.bg,
      appBar: famSubBar(context, title: '健康趨勢'),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UbanSegmented(
                small: true,
                labels: const ['步數', '體重', '身高'],
                index: _metric,
                onChanged: (i) {
                  HapticFeedback.lightImpact();
                  setState(() => _metric = i);
                },
              ),
              const SizedBox(height: 12),
              _buildTimeRangeSelector(),
              const SizedBox(height: 12),
              if (_metric == 0) ..._buildStepsSection() else ..._buildBodySection(),
              const SizedBox(height: 12),
              _buildUnavailableVitalsSection(),
            ],
          ),
        ),
      ),
    );
  }

  /// 週／月／半年／年（`.fchip`）。
  Widget _buildTimeRangeSelector() {
    return FamFilterRow(
      children: [
        for (final range in TimeRange.values)
          FamFilterChip(
            label: _getTimeRangeLabel(range),
            selected: range == _selectedTimeRange,
            onTap: () => _changeTimeRange(range),
          ),
      ],
    );
  }

  // ── 卡片外殼與狀態元件 ────────────────────────────────────────────────
  Widget _cardShell({
    required String title,
    required Color swatch,
    String? unit,
    required Widget child,
  }) {
    return FamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 標題與單位同列，標題可收縮（第 14 條）。
          GpsChartHead(title: title, unit: unit, swatch: swatch),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _loadingBox() => const FamStateBlock(
        height: 160,
        child: CircularProgressIndicator(),
      );

  Widget _emptyBox(String message) => FamStateBlock(
        height: 160,
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: famText(_c.text2, 14, height: 1.5),
        ),
      );

  /// 請求失敗的狀態必須長得跟「沒有資料」不一樣——danger 色文字＋可重試按鈕。
  Widget _errorBox(String message) => FamStateBlock(
        height: 160,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: famText(_c.danger, 14, weight: FontWeight.w700, height: 1.5),
            ),
            const SizedBox(height: 10),
            FamButton(
              label: '重試',
              kind: FamButtonKind.tonal,
              expand: false,
              height: 44,
              onPressed: _loadAll,
            ),
          ],
        ),
      );

  Widget _sumRow(List<Widget> cells) {
    // 格子用 Expanded 平分；IntrinsicHeight 讓三格等高（標籤可能一行或兩行）。
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: i < cells.length ? cells[i] : const SizedBox.shrink()),
          ],
        ],
      ),
    );
  }

  // ── 圖表共用 ────────────────────────────────────────────────────────
  static String _axisLabel(double v) {
    if (v.abs() >= 10000) return '${(v / 1000).toStringAsFixed(0)}k';
    if (v.abs() >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
  }

  static String _thousands(num v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  LineChartBarData _lineBar(List<FlSpot> spots, Color color) {
    final c = _c;
    return LineChartBarData(
      spots: spots,
      isCurved: false,
      color: color,
      barWidth: 3,
      dotData: FlDotData(
        show: spots.length <= 60,
        getDotPainter: (s, p, b, i) => FlDotCirclePainter(
          radius: 3,
          color: color,
          strokeWidth: 2,
          strokeColor: c.surface,
        ),
      ),
      belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.10)),
    );
  }

  /// 折線圖外框：[dates] 與資料點的 x（索引）一一對應；[refY] 有值時畫 warm 虛線。
  Widget _lineChart({
    required List<LineChartBarData> bars,
    required List<DateTime> dates,
    required double minY,
    required double maxY,
    required String Function(double) tipText,
    required double leftReserved,
    double? refY,
  }) {
    final c = _c;
    final n = dates.length;
    final labelEvery = (n / 5).ceil().clamp(1, n == 0 ? 1 : n);
    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (v) => FlLine(color: c.line, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: leftReserved,
                getTitlesWidget: (value, meta) => Text(
                  _axisLabel(value),
                  style: famText(c.text3, 11, tabular: true),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: labelEvery.toDouble(),
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= n) return const SizedBox();
                  final d = dates[idx];
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${d.month}/${d.day}',
                      style: famText(c.text3, 11, tabular: true),
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: n <= 1 ? 1 : (n - 1).toDouble(),
          minY: minY,
          maxY: maxY,
          lineBarsData: bars,
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              if (refY != null)
                HorizontalLine(
                  y: refY,
                  color: c.text3,
                  strokeWidth: 1.5,
                  dashArray: const [6, 4],
                ),
            ],
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              // 提示泡泡：text 底＋surface 字，淺深色都有足夠對比。
              getTooltipColor: (spot) => c.text,
              fitInsideHorizontally: true,
              getTooltipItems: (spots) => spots.map((s) {
                final idx = s.x.toInt();
                final d = idx >= 0 && idx < n ? dates[idx] : null;
                return LineTooltipItem(
                  '${tipText(s.y)}${d != null ? '\n${d.month}/${d.day}' : ''}',
                  famText(c.surface, 12, weight: FontWeight.w700),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  // ── 步數 ────────────────────────────────────────────────────────────
  List<Widget> _buildStepsSection() {
    final c = _c;
    Widget content;
    switch (_stepsStatus) {
      case _SectionStatus.loading:
        content = _loadingBox();
        break;
      case _SectionStatus.error:
        content = _errorBox(_stepsErrorMsg);
        break;
      case _SectionStatus.empty:
        content = _emptyBox('這段期間還沒有步數紀錄');
        break;
      case _SectionStatus.hasData:
        content = _buildStepsChart();
        break;
    }
    final values = _stepsSeries
        .map((e) => e['steps'] as int?)
        .whereType<int>()
        .toList();
    return [
      _cardShell(title: '步數趨勢', swatch: c.info, unit: '步', child: content),
      if (_stepsStatus == _SectionStatus.hasData && values.isNotEmpty) ...[
        const SizedBox(height: 12),
        _sumRow([
          GpsSumCell(
              label: '${_getTimeRangeLabel(_selectedTimeRange)}平均',
              value: _thousands(values.fold<int>(0, (a, b) => a + b) / values.length),
              unit: '步'),
          GpsSumCell(label: '最多一天', value: _thousands(values.reduce(math.max)), unit: '步'),
          GpsSumCell(label: '有紀錄', value: '${values.length}', unit: '天'),
        ]),
      ],
    ];
  }

  Widget _buildStepsChart() {
    final c = _c;
    final n = _stepsSeries.length;
    final maxSteps = _stepsSeries
        .map((e) => (e['steps'] as int?) ?? 0)
        .fold<int>(0, (a, b) => a > b ? a : b);
    final maxY = maxSteps <= 0 ? 100.0 : (maxSteps * 1.2);

    // 只在「連續有紀錄的日子」之間畫線，缺資料的日子不連線——避免看起來
    // 像是系統幫忙補了一條平滑趨勢線。
    final segments = <LineChartBarData>[];
    List<FlSpot> current = [];
    for (int i = 0; i < n; i++) {
      final steps = _stepsSeries[i]['steps'] as int?;
      if (steps == null) {
        if (current.isNotEmpty) {
          segments.add(_lineBar(current, c.info));
          current = [];
        }
      } else {
        current.add(FlSpot(i.toDouble(), steps.toDouble()));
      }
    }
    if (current.isNotEmpty) segments.add(_lineBar(current, c.info));

    // 虛線＝這段期間（有紀錄的日子）的平均步數；系統沒有「步數目標」資料，不假造目標值。
    final recorded = _stepsSeries.map((e) => e['steps'] as int?).whereType<int>().toList();
    final avg = recorded.isEmpty ? null : recorded.fold<int>(0, (a, b) => a + b) / recorded.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _lineChart(
          bars: segments,
          dates: [for (final e in _stepsSeries) e['date'] as DateTime],
          minY: 0,
          maxY: maxY,
          tipText: (y) => '${y.toInt()} 步',
          leftReserved: 40,
          refY: avg,
        ),
        if (avg != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Container(width: 5, height: 2, color: c.text3),
              ],
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '虛線：這段期間平均 ${_thousands(avg)} 步',
                  style: famText(c.text2, 12.5),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ── 體重／身高 ──────────────────────────────────────────────────────
  List<Widget> _buildBodySection() {
    final c = _c;
    final isWeight = _metric == 1;
    final key = isWeight ? 'weight_kg' : 'height_cm';
    final title = isWeight ? '體重趨勢' : '身高紀錄';
    final unit = isWeight ? 'kg' : 'cm';
    final color = isWeight ? c.brandFill : c.info;

    Widget content;
    switch (_bodyStatus) {
      case _SectionStatus.loading:
        content = _loadingBox();
        break;
      case _SectionStatus.error:
        content = _errorBox(_bodyErrorMsg);
        break;
      case _SectionStatus.empty:
        content = _emptyBox('還沒有體重／身高紀錄，點下方「新增紀錄」記一筆');
        break;
      case _SectionStatus.hasData:
        content = _buildBodyMetricsContent(key, unit, color);
        break;
    }

    final points = _bodySeries.where((e) => e[key] != null).toList();
    final values = points.map((e) => e[key] as double).toList();
    String fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

    return [
      _cardShell(
        title: '$title（家屬手動紀錄）',
        swatch: color,
        unit: unit,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            content,
            const SizedBox(height: 14),
            FamButton(
              label: '新增紀錄',
              kind: FamButtonKind.tonal,
              height: 46,
              onPressed: _openAddBodyMetricsSheet,
            ),
          ],
        ),
      ),
      if (_bodyStatus == _SectionStatus.hasData && values.isNotEmpty) ...[
        const SizedBox(height: 12),
        _sumRow([
          GpsSumCell(label: '最新', value: fmt(values.last), unit: unit),
          GpsSumCell(label: '最高', value: fmt(values.reduce(math.max)), unit: unit),
          GpsSumCell(label: '最低', value: fmt(values.reduce(math.min)), unit: unit),
        ]),
      ],
    ];
  }

  Widget _buildBodyMetricsContent(String key, String unit, Color color) {
    final c = _c;
    final points = _bodySeries.where((e) => e[key] != null).toList();
    final label = key == 'weight_kg' ? '體重' : '身高';

    if (points.length >= 2) {
      final values = points.map((e) => e[key] as double).toList();
      final minV = values.reduce(math.min);
      final maxV = values.reduce(math.max);
      final pad = ((maxV - minV) * 0.2).clamp(1.0, 10.0);
      final spots = List.generate(points.length, (i) => FlSpot(i.toDouble(), values[i]));
      return _lineChart(
        bars: [_lineBar(spots, color)],
        dates: [for (final e in points) e['date'] as DateTime],
        minY: (minV - pad).clamp(0, double.infinity),
        maxY: maxV + pad,
        tipText: (y) => '${y.toStringAsFixed(1)} $unit',
        leftReserved: 36,
      );
    }
    if (points.length == 1) {
      return FamStateBlock(
        height: 120,
        child: Text(
          '最新$label：${points.first[key]} $unit（${_fmtDate(points.first['date'])}）\n再多記錄一筆才畫得出趨勢',
          textAlign: TextAlign.center,
          style: famText(c.text2, 14, height: 1.6),
        ),
      );
    }
    return FamStateBlock(
      height: 120,
      child: Text(
        '目前沒有$label紀錄',
        textAlign: TextAlign.center,
        style: famText(c.text2, 14, height: 1.5),
      ),
    );
  }

  String _fmtDate(DateTime? d) => d == null ? '' : '${d.year}/${d.month}/${d.day}';

  Future<void> _openAddBodyMetricsSheet() async {
    if (widget.elderId == null) return;
    final familyId = _familyId;
    if (familyId == null) {
      ScaffoldMessenger.of(_themeCtx).showSnackBar(
        famSnackBar(_themeCtx, '找不到您的家屬帳號，請重新登入後再試', error: true),
      );
      return;
    }

    final weightCtrl = TextEditingController();
    final heightCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();
    bool submitting = false;
    String? errorText;

    try {
      await _showBodyMetricsSheet(
        weightCtrl: weightCtrl,
        heightCtrl: heightCtrl,
        initialDate: selectedDate,
        familyId: familyId,
        submittingInit: submitting,
        errorInit: errorText,
      );
    } finally {
      weightCtrl.dispose();
      heightCtrl.dispose();
    }
  }

  Future<void> _showBodyMetricsSheet({
    required TextEditingController weightCtrl,
    required TextEditingController heightCtrl,
    required DateTime initialDate,
    required int familyId,
    required bool submittingInit,
    required String? errorInit,
  }) async {
    DateTime selectedDate = initialDate;
    bool submitting = submittingInit;
    String? errorText = errorInit;

    // showUbanSheet 走 showModalBottomSheet，會沿用傳入 context 的 Theme（家屬主題）。
    await showUbanSheet<void>(_themeCtx, (sheetContext) {
      return StatefulBuilder(builder: (sheetContext, setSheetState) {
        final c = UbanColors.of(sheetContext);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            famDialogTitle(c, '新增體重／身高紀錄'),
            const SizedBox(height: 4),
            Text('至少填寫一項，家屬手動記錄的數值',
                style: famText(c.text2, 13, height: 1.5)),
            const SizedBox(height: 16),
            UbanTextField(
              label: '體重 (kg)',
              controller: weightCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            UbanTextField(
              label: '身高 (cm)',
              controller: heightCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            Text('量測日期',
                style: famText(c.text2, 15, weight: FontWeight.w700)),
            const SizedBox(height: 6),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                final picked = await showDatePicker(
                  context: sheetContext,
                  initialDate: selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  setSheetState(() => selectedDate = picked);
                }
              },
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: c.line, width: 1.5),
                ),
                child: Text(_fmtDate(selectedDate),
                    style: famText(c.text, 16, weight: FontWeight.w600, tabular: true)),
              ),
            ),
            if (errorText != null) ...[
              const SizedBox(height: 10),
              FamNote(text: errorText!, tone: FamTone.danger),
            ],
            const SizedBox(height: 20),
            FamButton(
              label: '儲存',
              loading: submitting,
              onPressed: submitting
                  ? null
                  : () async {
                      final w = double.tryParse(weightCtrl.text.trim());
                      final h = double.tryParse(heightCtrl.text.trim());
                      if (w == null && h == null) {
                        setSheetState(() => errorText = '請至少填寫體重或身高其中一項');
                        return;
                      }
                      setSheetState(() {
                        submitting = true;
                        errorText = null;
                      });
                      // 裝置本地日期字串，不能用伺服器時間——後端刻意要求
                      // 呼叫端自己算好這個值，理由見 family_insight_api.dart。
                      final metricDate =
                          '${selectedDate.year.toString().padLeft(4, '0')}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
                      final resp = await ApiService.submitBodyMetrics(
                        elderId: widget.elderId.toString(),
                        familyId: familyId,
                        metricDate: metricDate,
                        weightKg: w,
                        heightCm: h,
                      );
                      if (resp['status'] == 'success') {
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                        await _loadAll();
                      } else {
                        setSheetState(() {
                          submitting = false;
                          errorText = ApiService.failureMessageOf(resp, fallback: '儲存失敗，請重試');
                        });
                      }
                    },
            ),
          ],
        );
      });
    });
  }

  // ── 需要穿戴裝置才能偵測的指標：保留版位，固定顯示 -- ─────────────────
  Widget _buildUnavailableVitalsSection() {
    final c = _c;
    const metrics = [
      ('心率', 'bpm'),
      ('血壓', 'mmHg'),
      ('血糖', 'mg/dL'),
    ];

    return FamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FamSecHead(title: '需穿戴裝置偵測的指標'),
          const SizedBox(height: 6),
          Text(
            '目前系統沒有連接任何穿戴裝置，以下數值暫時無法偵測，日後接上裝置就會自動顯示',
            style: famText(c.text2, 13, height: 1.5),
          ),
          const SizedBox(height: 14),
          _sumRow([
            for (final m in metrics)
              GpsSumCell(label: '${m.$1} (${m.$2})', value: '--'),
          ]),
        ],
      ),
    );
  }
}
