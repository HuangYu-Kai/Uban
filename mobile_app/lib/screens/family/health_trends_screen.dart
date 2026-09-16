import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';

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
class HealthTrendsScreen extends StatefulWidget {
  final String elderName;
  final int? elderId;

  const HealthTrendsScreen({
    super.key,
    required this.elderName,
    this.elderId,
  });

  @override
  State<HealthTrendsScreen> createState() => _HealthTrendsScreenState();
}

enum TimeRange { week, month, halfYear, year }

enum _SectionStatus { loading, hasData, empty, error }

class _HealthTrendsScreenState extends State<HealthTrendsScreen> {
  TimeRange _selectedTimeRange = TimeRange.month;
  int? _familyId;

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
      _familyId = prefs.getInt('caregiver_id');
    } catch (_) {
      _familyId = null;
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
        _stepsErrorMsg = (resp['message'] ?? resp['error'] ?? '步數資料載入失敗').toString();
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
        _bodyErrorMsg = (resp['message'] ?? resp['error'] ?? '體重／身高資料載入失敗').toString();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          '健康趨勢',
          style: GoogleFonts.notoSansTc(
            color: const Color(0xFF1E293B),
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _buildTimeRangeSelector(),
              _buildStepsSection(),
              _buildBodyMetricsSection(),
              _buildUnavailableVitalsSection(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeRangeSelector() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: TimeRange.values.map((range) {
          final isSelected = range == _selectedTimeRange;
          return Expanded(
            child: GestureDetector(
              onTap: () => _changeTimeRange(range),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF3B82F6) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _getTimeRangeLabel(range),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : const Color(0xFF64748B),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  // ── 卡片外殼（載入中／錯誤／空狀態共用） ──────────────────────────────
  Widget _cardShell({required String title, Widget? trailing, required Widget child}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
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
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1E293B),
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _loadingBox() => const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator()),
      );

  Widget _emptyBox(String message) => SizedBox(
        height: 160,
        child: Center(
          child: Text(
            message,
            style: GoogleFonts.notoSansTc(color: const Color(0xFF64748B), fontSize: 14),
          ),
        ),
      );

  /// 請求失敗的狀態必須長得跟「沒有資料」不一樣——紅色系＋可重試按鈕。
  Widget _errorBox(String message) => SizedBox(
        height: 160,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 28),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansTc(color: const Color(0xFFEF4444), fontSize: 13),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _loadAll,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text('重試', style: GoogleFonts.notoSansTc(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );

  // ── 步數 ────────────────────────────────────────────────────────────
  Widget _buildStepsSection() {
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
    return _cardShell(title: '步數趨勢', child: content)
        .animate()
        .fadeIn(delay: 100.ms, duration: 400.ms);
  }

  Widget _buildStepsChart() {
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
          segments.add(_stepsLineData(current));
          current = [];
        }
      } else {
        current.add(FlSpot(i.toDouble(), steps.toDouble()));
      }
    }
    if (current.isNotEmpty) segments.add(_stepsLineData(current));

    final labelEvery = (n / 6).ceil().clamp(1, n == 0 ? 1 : n);

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (v) => const FlLine(color: Color(0xFFE2E8F0), strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (value, meta) => Text(
                  value.toInt().toString(),
                  style: GoogleFonts.notoSansTc(fontSize: 10, color: const Color(0xFF64748B)),
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
                  final d = _stepsSeries[idx]['date'] as DateTime;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${d.month}/${d.day}',
                      style: GoogleFonts.notoSansTc(fontSize: 10, color: const Color(0xFF64748B)),
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
          minY: 0,
          maxY: maxY,
          lineBarsData: segments,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (spot) => Colors.white,
              getTooltipItems: (spots) => spots.map((s) {
                final idx = s.x.toInt();
                final d = idx >= 0 && idx < n ? _stepsSeries[idx]['date'] as DateTime : null;
                return LineTooltipItem(
                  '${s.y.toInt()} 步${d != null ? '\n${d.month}/${d.day}' : ''}',
                  GoogleFonts.notoSansTc(color: const Color(0xFF10B981), fontWeight: FontWeight.w700, fontSize: 12),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  LineChartBarData _stepsLineData(List<FlSpot> spots) {
    return LineChartBarData(
      spots: spots,
      isCurved: false,
      color: const Color(0xFF10B981),
      barWidth: 3,
      dotData: FlDotData(show: spots.length <= 60),
      belowBarData: BarAreaData(show: true, color: const Color(0xFF10B981).withValues(alpha: 0.1)),
    );
  }

  // ── 體重／身高 ──────────────────────────────────────────────────────
  Widget _buildBodyMetricsSection() {
    Widget content;
    switch (_bodyStatus) {
      case _SectionStatus.loading:
        content = _loadingBox();
        break;
      case _SectionStatus.error:
        content = _errorBox(_bodyErrorMsg);
        break;
      case _SectionStatus.empty:
        content = _emptyBox('還沒有體重／身高紀錄，點右上角新增一筆');
        break;
      case _SectionStatus.hasData:
        content = _buildBodyMetricsContent();
        break;
    }
    return _cardShell(
      title: '體重／身高（家屬手動紀錄）',
      trailing: TextButton.icon(
        onPressed: _openAddBodyMetricsSheet,
        icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
        label: Text('新增紀錄', style: GoogleFonts.notoSansTc(fontWeight: FontWeight.w700, fontSize: 13)),
      ),
      child: content,
    ).animate().fadeIn(delay: 200.ms, duration: 400.ms);
  }

  Widget _buildBodyMetricsContent() {
    final weightPoints = _bodySeries.where((e) => e['weight_kg'] != null).toList();
    final latestHeight = _bodySeries.lastWhere(
      (e) => e['height_cm'] != null,
      orElse: () => const {},
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (weightPoints.length >= 2)
          SizedBox(height: 180, child: _buildWeightChart(weightPoints))
        else if (weightPoints.length == 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '最新體重：${weightPoints.first['weight_kg']} kg（${_fmtDate(weightPoints.first['date'])}）\n再多記錄一筆才畫得出趨勢',
              style: GoogleFonts.notoSansTc(fontSize: 13, color: const Color(0xFF475569), height: 1.6),
            ),
          )
        else
          Text(
            '目前沒有體重紀錄',
            style: GoogleFonts.notoSansTc(fontSize: 13, color: const Color(0xFF64748B)),
          ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.height_rounded, size: 18, color: Color(0xFF8B5CF6)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  latestHeight.isEmpty
                      ? '身高：尚無紀錄'
                      : '身高：${latestHeight['height_cm']} cm（${_fmtDate(latestHeight['date'])} 記錄）',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansTc(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF475569)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _fmtDate(DateTime? d) => d == null ? '' : '${d.year}/${d.month}/${d.day}';

  Widget _buildWeightChart(List<Map<String, dynamic>> points) {
    final values = points.map((e) => e['weight_kg'] as double).toList();
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final pad = ((maxV - minV) * 0.2).clamp(1.0, 10.0);

    final spots = List.generate(
      points.length,
      (i) => FlSpot(i.toDouble(), points[i]['weight_kg'] as double),
    );

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => const FlLine(color: Color(0xFFE2E8F0), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(0),
                style: GoogleFonts.notoSansTc(fontSize: 10, color: const Color(0xFF64748B)),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= points.length) return const SizedBox();
                final d = points[idx]['date'] as DateTime;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${d.month}/${d.day}',
                    style: GoogleFonts.notoSansTc(fontSize: 10, color: const Color(0xFF64748B)),
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
        maxX: points.length <= 1 ? 1 : (points.length - 1).toDouble(),
        minY: (minV - pad).clamp(0, double.infinity),
        maxY: maxV + pad,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: const Color(0xFF8B5CF6),
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(show: true, color: const Color(0xFF8B5CF6).withValues(alpha: 0.1)),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (spot) => Colors.white,
            getTooltipItems: (spots) => spots.map((s) {
              final idx = s.x.toInt();
              final d = idx >= 0 && idx < points.length ? points[idx]['date'] as DateTime : null;
              return LineTooltipItem(
                '${s.y.toStringAsFixed(1)} kg${d != null ? '\n${d.month}/${d.day}' : ''}',
                GoogleFonts.notoSansTc(color: const Color(0xFF8B5CF6), fontWeight: FontWeight.w700, fontSize: 12),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _openAddBodyMetricsSheet() async {
    if (widget.elderId == null) return;
    final familyId = _familyId;
    if (familyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('找不到您的家屬帳號，請重新登入後再試', style: GoogleFonts.notoSansTc())),
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

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) {
        return StatefulBuilder(builder: (sheetContext, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('新增體重／身高紀錄',
                    style: GoogleFonts.notoSansTc(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B))),
                const SizedBox(height: 4),
                Text('至少填寫一項，家屬手動記錄的數值',
                    style: GoogleFonts.notoSansTc(fontSize: 12, color: const Color(0xFF64748B))),
                const SizedBox(height: 16),
                TextField(
                  controller: weightCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: '體重 (kg)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: heightCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: '身高 (cm)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
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
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: '量測日期',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(_fmtDate(selectedDate)),
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 10),
                  Text(errorText!, style: GoogleFonts.notoSansTc(color: const Color(0xFFEF4444), fontSize: 13)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
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
                            final measuredAt =
                                '${selectedDate.year.toString().padLeft(4, '0')}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
                            final resp = await ApiService.submitBodyMetrics(
                              elderId: widget.elderId.toString(),
                              familyId: familyId,
                              measuredAt: measuredAt,
                              weightKg: w,
                              heightCm: h,
                            );
                            if (resp['status'] == 'success') {
                              if (sheetContext.mounted) Navigator.pop(sheetContext);
                              await _loadAll();
                            } else {
                              setSheetState(() {
                                submitting = false;
                                errorText = (resp['message'] ?? resp['error'] ?? '儲存失敗，請重試').toString();
                              });
                            }
                          },
                    child: submitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text('儲存', style: GoogleFonts.notoSansTc(fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  // ── 需要穿戴裝置才能偵測的指標：保留版位，固定顯示 -- ─────────────────
  Widget _buildUnavailableVitalsSection() {
    final metrics = [
      {'icon': Icons.favorite, 'label': '心率', 'unit': 'bpm', 'color': const Color(0xFFEF4444)},
      {'icon': Icons.bloodtype, 'label': '血壓', 'unit': 'mmHg', 'color': const Color(0xFF3B82F6)},
      {'icon': Icons.opacity, 'label': '血糖', 'unit': 'mg/dL', 'color': const Color(0xFFF59E0B)},
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '需穿戴裝置偵測的指標',
            style: GoogleFonts.notoSansTc(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF1E293B)),
          ),
          const SizedBox(height: 4),
          Text(
            '目前系統沒有連接任何穿戴裝置，以下數值暫時無法偵測，日後接上裝置就會自動顯示',
            style: GoogleFonts.notoSansTc(fontSize: 12, color: const Color(0xFF64748B), height: 1.5),
          ),
          const SizedBox(height: 16),
          Row(
            children: metrics.map((m) {
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Icon(m['icon'] as IconData, size: 20, color: (m['color'] as Color).withValues(alpha: 0.5)),
                      const SizedBox(height: 8),
                      Text(
                        '--',
                        style: GoogleFonts.notoSansTc(fontSize: 22, fontWeight: FontWeight.w900, color: const Color(0xFF94A3B8)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${m['label']} (${m['unit']})',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSansTc(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 300.ms, duration: 400.ms);
  }
}
