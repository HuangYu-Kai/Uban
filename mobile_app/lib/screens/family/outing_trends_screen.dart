import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/api/location_api.dart';
import 'elder_location_map_screen.dart';
import 'elder_places_screen.dart';

/// 📊 外出趨勢（移動軌跡延伸第三階段）
///
/// 家屬端：長輩最近 7／30 天的每日移動距離、外出次數、在外時間。
/// 資料來自 `LocationApi.getDaily`（`GET /location/daily/{elderId}`）；
/// 版面與 `health_trends_screen.dart` 同一套（白底卡片、`fl_chart`）。
///
/// 幾個要記得的規則：
/// - **今天是「統計中」**：回傳的最後一筆是今天（還沒過完），長條用較淡的顏色，
///   並在圖下方標註 `今天（統計中）`；平均值一律**排除今天**，否則一早打開
///   就會被當天還沒累積的資料拉低。
/// - **沒設定「家」就沒有外出次數／在外時間**（後端回 `null`），這兩張圖改顯示
///   引導卡，帶使用者去 `ElderPlacesScreen` 設定，回來後重新載入。
/// - 點某一天的長條 → 開 `ElderLocationMapScreen` 看那天的軌跡。
class OutingTrendsScreen extends StatefulWidget {
  final String elderId;
  final int userId;
  final String elderName;

  const OutingTrendsScreen({
    super.key,
    required this.elderId,
    required this.userId,
    this.elderName = '長輩',
  });

  @override
  State<OutingTrendsScreen> createState() => _OutingTrendsScreenState();
}

enum _LoadState { loading, ready, sharingDisabled, empty, error }

/// 一天的統計（`days` 陣列的一筆）。
class _DayStat {
  final DateTime date;
  final int distanceM;
  final int? outingCount;
  final int? outsideMinutes;
  final int pointCount;

  const _DayStat({
    required this.date,
    required this.distanceM,
    required this.outingCount,
    required this.outsideMinutes,
    required this.pointCount,
  });
}

class _OutingTrendsScreenState extends State<OutingTrendsScreen> {
  static const Color _distanceColor = Color(0xFF3B82F6);
  static const Color _countColor = Color(0xFF10B981);
  static const Color _timeColor = Color(0xFF8B5CF6);

  int _days = 7;
  _LoadState _state = _LoadState.loading;
  bool _hasHome = false;
  List<_DayStat> _series = const [];
  // 每次 _load 遞增；await 回來後若序號已被更新的載入取代就丟棄結果，
  // 避免快速切換 7／30 天時舊請求覆蓋新結果。
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    if (mounted && _state != _LoadState.loading) setState(() => _state = _LoadState.loading);

    final data = await LocationApi.getDaily(
      elderId: widget.elderId,
      userId: widget.userId,
      days: _days,
    );
    if (!mounted || seq != _loadSeq) return;

    if (data == null) {
      setState(() => _state = _LoadState.error);
      return;
    }
    if (data['sharing_enabled'] != true) {
      setState(() => _state = _LoadState.sharingDisabled);
      return;
    }

    try {
      final raw = (data['days'] as List?) ?? const [];
      final series = <_DayStat>[];
      for (final e in raw) {
        final m = Map<String, dynamic>.from(e as Map);
        final date = DateTime.tryParse(m['date'] as String? ?? '');
        if (date == null) continue;
        series.add(_DayStat(
          date: DateTime(date.year, date.month, date.day),
          distanceM: (m['distance_m'] as num?)?.toInt() ?? 0,
          outingCount: (m['outing_count'] as num?)?.toInt(),
          outsideMinutes: (m['outside_minutes'] as num?)?.toInt(),
          pointCount: (m['point_count'] as num?)?.toInt() ?? 0,
        ));
      }
      final hasAnyPoint = series.any((d) => d.pointCount > 0 || d.distanceM > 0);
      setState(() {
        _hasHome = data['has_home'] == true;
        _series = series;
        _state = hasAnyPoint ? _LoadState.ready : _LoadState.empty;
      });
    } catch (_) {
      // 後端格式不如預期時當成載入失敗，不要讓畫面炸掉。
      setState(() => _state = _LoadState.error);
    }
  }

  void _changeDays(int days) {
    if (days == _days) return;
    HapticFeedback.lightImpact();
    setState(() => _days = days);
    _load();
  }

  Future<void> _openPlaces() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ElderPlacesScreen(
          elderId: widget.elderId,
          userId: widget.userId,
          elderName: widget.elderName,
        ),
      ),
    );
    // 不管有沒有回傳「有變更」都重新載入——設定「家」是這個畫面的主要用途，
    // 多打一次 API 的成本遠低於漏掉更新。
    if (mounted) await _load();
  }

  void _openDayMap(DateTime date) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ElderLocationMapScreen(
          elderId: widget.elderId,
          userId: widget.userId,
          elderName: widget.elderName,
          initialDate: date,
        ),
      ),
    );
  }

  bool _isLast(int index) => index == _series.length - 1;

  // ── build ─────────────────────────────────────────────────────────────
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
          '外出趨勢',
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
              ..._buildBody(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return [_messageCard(child: _loadingBox())];
      case _LoadState.sharingDisabled:
        return [
          _messageCard(
            child: _infoBox(
              icon: Icons.location_off_rounded,
              color: const Color(0xFF64748B),
              message: '長輩已關閉位置分享',
            ),
          ),
        ];
      case _LoadState.error:
        return [_messageCard(child: _errorBox('載入失敗，請稍後再試'))];
      case _LoadState.empty:
        return [
          _messageCard(
            child: _infoBox(
              icon: Icons.route_rounded,
              color: const Color(0xFF64748B),
              message: '這段期間沒有定位資料',
            ),
          ),
        ];
      case _LoadState.ready:
        return [
          _buildSummary(),
          _buildDistanceSection(),
          _buildCountSection(),
          _buildTimeSection(),
        ];
    }
  }

  // ── 7／30 天切換（與 health_trends 的時間範圍選擇同一風格） ──────────────
  Widget _buildRangeSelector() {
    Widget item(int days, String label) {
      final isSelected = _days == days;
      return Expanded(
        child: GestureDetector(
          onTap: () => _changeDays(days),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF3B82F6) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
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
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(children: [item(7, '7 天'), item(30, '30 天')]),
    ).animate().fadeIn(duration: 300.ms);
  }

  // ── 摘要列：平均值（排除今天，今天還沒過完） ─────────────────────────────
  Widget _buildSummary() {
    final done = _series.length > 1 ? _series.sublist(0, _series.length - 1) : const <_DayStat>[];
    final prefix = _days == 7 ? '本週' : '近 30 天';

    String text;
    if (done.isEmpty) {
      text = '$prefix還沒有完整的一天可以統計';
    } else {
      final avgKm = done.fold<int>(0, (a, d) => a + d.distanceM) / done.length / 1000.0;
      if (_hasHome) {
        final avgCount = done.fold<int>(0, (a, d) => a + (d.outingCount ?? 0)) / done.length;
        text = '$prefix平均每天外出 ${avgCount.toStringAsFixed(1)} 次・移動 ${avgKm.toStringAsFixed(1)} 公里';
      } else {
        // 沒有「家」算不出外出次數，只講距離，不要編造 0 次。
        text = '$prefix平均每天移動 ${avgKm.toStringAsFixed(1)} 公里';
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      // 摘要文字長度會隨數字變動，包 Expanded 讓它在窄螢幕換行而不是溢位（鐵律 #14）。
      child: Row(
        children: [
          const Icon(Icons.directions_walk_rounded, color: Color(0xFF3B82F6), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.notoSansTc(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1E3A8A),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 50.ms, duration: 400.ms);
  }

  // ── 三個區塊 ───────────────────────────────────────────────────────────
  Widget _buildDistanceSection() {
    final values = _series.map((d) => d.distanceM / 1000.0).toList();
    return _cardShell(
      title: '每日移動距離',
      unit: '公里',
      child: _buildBarChart(
        values: values,
        color: _distanceColor,
        emptyMax: 1,
        integerOnly: false,
        format: (v) => '${v.toStringAsFixed(1)} 公里',
      ),
      legendColor: _distanceColor,
    ).animate().fadeIn(delay: 100.ms, duration: 400.ms);
  }

  Widget _buildCountSection() {
    if (!_hasHome) {
      return _cardShell(
        title: '每日外出次數',
        child: _homeHint(),
      ).animate().fadeIn(delay: 150.ms, duration: 400.ms);
    }
    final values = _series.map((d) => (d.outingCount ?? 0).toDouble()).toList();
    return _cardShell(
      title: '每日外出次數',
      unit: '次',
      child: _buildBarChart(
        values: values,
        color: _countColor,
        emptyMax: 3,
        integerOnly: true,
        format: (v) => '${v.toInt()} 次',
      ),
      legendColor: _countColor,
    ).animate().fadeIn(delay: 150.ms, duration: 400.ms);
  }

  Widget _buildTimeSection() {
    if (!_hasHome) {
      return _cardShell(
        title: '每日在外時間',
        child: _infoBox(
          icon: Icons.home_outlined,
          color: const Color(0xFF64748B),
          message: '同樣要先設定「家」，才算得出在外時間',
          height: 100,
        ),
      ).animate().fadeIn(delay: 200.ms, duration: 400.ms);
    }
    // 圖用「小時」畫（軸上的數字比分鐘好讀），提示文字用 `1.5 小時`。
    final values = _series.map((d) => (d.outsideMinutes ?? 0) / 60.0).toList();
    return _cardShell(
      title: '每日在外時間',
      unit: '小時',
      child: _buildBarChart(
        values: values,
        color: _timeColor,
        emptyMax: 2,
        integerOnly: false,
        format: _formatHours,
      ),
      legendColor: _timeColor,
    ).animate().fadeIn(delay: 200.ms, duration: 400.ms);
  }

  /// 小時數文字：`1.5 小時`；不到 1 分鐘顯示 `0 小時`。
  static String _formatHours(double hours) {
    final rounded = (hours * 10).round() / 10.0;
    final s = rounded == rounded.roundToDouble() ? rounded.toInt().toString() : rounded.toStringAsFixed(1);
    return '$s 小時';
  }

  /// 沒設定「家」的引導卡：說明原因並帶使用者去設定。
  Widget _homeHint() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '設定「家」之後就能看到外出次數與在外時間',
            style: GoogleFonts.notoSansTc(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF475569),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          // 用 Wrap 讓按鈕在極窄螢幕也能換行，不會溢位。
          Wrap(
            children: [
              FilledButton.icon(
                onPressed: _openPlaces,
                icon: const Icon(Icons.home_rounded, size: 18),
                label: Text('設定常去地點', style: GoogleFonts.notoSansTc(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 長條圖 ─────────────────────────────────────────────────────────────
  /// [values] 與 `_series` 一一對應（最後一筆是今天）。
  Widget _buildBarChart({
    required List<double> values,
    required Color color,
    required double emptyMax,
    required bool integerOnly,
    required String Function(double) format,
  }) {
    final n = values.length;
    final axis = _niceAxis(values.fold<double>(0, math.max), emptyMax: emptyMax, integerOnly: integerOnly);
    // 30 天時不能每根都標日期；以「今天」為基準每 5 天標一次，今天一定有標。
    final labelStep = n > 10 ? 5 : 1;
    final barWidth = n > 10 ? 6.0 : 18.0;

    final groups = List.generate(n, (i) {
      final isToday = _isLast(i);
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: values[i],
            width: barWidth,
            color: isToday ? color.withValues(alpha: 0.35) : color,
            borderRadius: BorderRadius.vertical(top: Radius.circular(barWidth > 10 ? 6 : 3)),
            // 底色長條：讓 0 的日子也有可點的區域（allowTouchBarBackDraw）。
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: axis.maxY,
              color: const Color(0xFFF1F5F9),
            ),
          ),
        ],
      );
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              minY: 0,
              maxY: axis.maxY,
              barGroups: groups,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: axis.interval,
                getDrawingHorizontalLine: (v) => const FlLine(color: Color(0xFFE2E8F0), strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    interval: axis.interval,
                    getTitlesWidget: (value, meta) => Text(
                      _axisLabel(value),
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
                      if (idx < 0 || idx >= _series.length) return const SizedBox();
                      if ((n - 1 - idx) % labelStep != 0) return const SizedBox();
                      final d = _series[idx].date;
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
              barTouchData: BarTouchData(
                allowTouchBarBackDraw: true,
                touchCallback: (event, response) {
                  // 點一下（手指抬起）才開地圖；按下去只顯示提示泡泡。
                  if (event is! FlTapUpEvent) return;
                  final idx = response?.spot?.touchedBarGroupIndex;
                  if (idx == null || idx < 0 || idx >= _series.length) return;
                  _openDayMap(_series[idx].date);
                },
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (group) => Colors.white,
                  fitInsideHorizontally: true,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final d = _series[groupIndex].date;
                    final suffix = _isLast(groupIndex) ? '（今天，統計中）' : '';
                    return BarTooltipItem(
                      '${d.month}/${d.day}$suffix\n${format(values[groupIndex])}',
                      GoogleFonts.notoSansTc(color: color, fontWeight: FontWeight.w700, fontSize: 12),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _axisLabel(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  /// 算出好讀的 Y 軸上限與刻度間隔（約 4 格；1／2／5 × 10^k）。
  /// [emptyMax]：資料全是 0（或很小）時的最小上限，避免軸只有 0 一個刻度。
  /// [integerOnly]：次數這類整數單位，間隔至少 1。
  static ({double maxY, double interval}) _niceAxis(
    double maxValue, {
    required double emptyMax,
    required bool integerOnly,
  }) {
    final top = math.max(maxValue, emptyMax);
    final raw = top / 4;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final norm = raw / mag;
    var step = (norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 5 ? 5 : 10) * mag;
    if (integerOnly) step = math.max(1.0, step.ceilToDouble());
    var maxY = step * (top / step).ceil();
    // 最高的長條不要頂到圖的邊緣。
    if (maxY < top * 1.05) maxY += step;
    return (maxY: maxY, interval: step);
  }

  // ── 卡片外殼與狀態元件（沿用 health_trends 的樣式） ─────────────────────
  Widget _cardShell({
    required String title,
    String? unit,
    required Widget child,
    Color? legendColor,
  }) {
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
            children: [
              // 標題與單位同列，標題可收縮（鐵律 #14）。
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1E293B),
                  ),
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 8),
                Text(
                  '（$unit）',
                  style: GoogleFonts.notoSansTc(fontSize: 12, color: const Color(0xFF64748B)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          child,
          if (legendColor != null) ...[
            const SizedBox(height: 10),
            _legend(legendColor),
          ],
        ],
      ),
    );
  }

  /// 圖例：標明淡色長條是「今天（統計中）」，另提示點長條可看當天軌跡。
  Widget _legend(Color color) {
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '今天（統計中）',
              style: GoogleFonts.notoSansTc(fontSize: 12, color: const Color(0xFF64748B)),
            ),
          ],
        ),
        Text(
          '點長條看當天軌跡',
          style: GoogleFonts.notoSansTc(fontSize: 12, color: const Color(0xFF94A3B8)),
        ),
      ],
    );
  }

  /// 載入中／錯誤／空狀態共用的整頁外殼（沒有標題）。
  Widget _messageCard({required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: child,
    );
  }

  Widget _loadingBox() => const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator()),
      );

  Widget _infoBox({
    required IconData icon,
    required Color color,
    required String message,
    double height = 160,
  }) =>
      SizedBox(
        height: height,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansTc(color: color, fontSize: 14),
              ),
            ],
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
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text('重試', style: GoogleFonts.notoSansTc(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );
}
