import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';

class FamilyCareJournalView extends StatefulWidget {
  const FamilyCareJournalView({super.key});

  @override
  State<FamilyCareJournalView> createState() => _FamilyCareJournalViewState();
}

class _FamilyCareJournalViewState extends State<FamilyCareJournalView> {
  bool _isAnalyzing = false;

  void _runDeepAnalysis() async {
    setState(() => _isAnalyzing = true);
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    setState(() => _isAnalyzing = false);

    // Show a dialog with the result
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Colors.orange),
            const SizedBox(width: 8),
            Text(
              'AI 深度分析報告',
              style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          '根據過去 30 天的互動數據，長輩的情緒穩定度提升了 15%。\n\n建議：增加下午時段的音樂互動，長輩在聽老歌時的心率與互動意願數值最高。',
          style: GoogleFonts.notoSansTc(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '確定',
              style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF0),
      appBar: AppBar(
        title: Text(
          '照護日誌',
          style: GoogleFonts.notoSansTc(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFFFFFBF0),
        elevation: 0,
        foregroundColor: Colors.black87,
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.share_outlined)),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Weekly Mood Trend Header
            _buildSectionHeader('本週心情趨勢', Icons.trending_up),
            const SizedBox(height: 16),
            _buildMoodChart(),
            const SizedBox(height: 32),

            // 2. AI Sentiment Summary
            _buildSectionHeader('AI 情感摘要', Icons.auto_awesome),
            const SizedBox(height: 16),
            _buildAISummaryCard(),
            const SizedBox(height: 32),

            // 3. Activity History
            _buildSectionHeader('活動歷史紀錄', Icons.history),
            const SizedBox(height: 16),
            _buildActivityList(),
            const SizedBox(height: 32),

            // 4. Deep Analysis Button
            _buildDeepAnalysisButton(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFFF9800), size: 24),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.notoSansTc(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildMoodChart() {
    return Container(
      height: 220,
      padding: const EdgeInsets.fromLTRB(16, 32, 24, 16),
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
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  const days = ['一', '二', '三', '四', '五', '六', '日'];
                  if (value.toInt() < 0 || value.toInt() >= days.length) {
                    return const SizedBox();
                  }
                  return Text(
                    days[value.toInt()],
                    style: GoogleFonts.notoSansTc(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  );
                },
              ),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: [
                const FlSpot(0, 3),
                const FlSpot(1, 4),
                const FlSpot(2, 3.5),
                const FlSpot(3, 5),
                const FlSpot(4, 4.5),
                const FlSpot(5, 5),
                const FlSpot(6, 4.8),
              ],
              isCurved: true,
              color: const Color(0xFFFF9800),
              barWidth: 4,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                color: const Color(0xFFFF9800).withValues(alpha: 0.1),
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 800.ms).slideY(begin: 0.1);
  }

  Widget _buildAISummaryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade50, Colors.orange.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '最近三天的關鍵洞察：',
            style: GoogleFonts.notoSansTc(
              fontWeight: FontWeight.bold,
              color: Colors.orange.shade900,
            ),
          ),
          const SizedBox(height: 12),
          _buildInsightItem('情緒趨於穩定，早晨的互動最為積極。'),
          _buildInsightItem('對於故鄉話題展現極高熱忱。'),
          _buildInsightItem('午休時間延後，可能影響其夜間睡眠。'),
        ],
      ),
    );
  }

  Widget _buildInsightItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: Color(0xFFFF9800), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.notoSansTc(
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityList() {
    return Column(
      children: [
        _buildActivityItem(
          '昨天 18:30',
          '完成長輩端對話：藥後叮嚀',
          Icons.chat_bubble_outline,
          Colors.blue,
        ),
        _buildActivityItem(
          '昨天 15:00',
          '情緒標註：非常開心',
          Icons.sentiment_very_satisfied,
          Colors.green,
        ),
        _buildActivityItem(
          '昨天 10:20',
          '回憶錄製：老家門前的大樹',
          Icons.mic,
          Colors.purple,
        ),
      ],
    );
  }

  Widget _buildActivityItem(
    String time,
    String title,
    IconData icon,
    Color color,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.notoSansTc(fontWeight: FontWeight.w600),
                ),
                Text(
                  time,
                  style: GoogleFonts.notoSansTc(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.grey, size: 16),
        ],
      ),
    );
  }

  Widget _buildDeepAnalysisButton() {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: _isAnalyzing ? null : _runDeepAnalysis,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF212121),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
        ),
        child: _isAnalyzing
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.auto_awesome),
                  const SizedBox(width: 12),
                  Text(
                    '啟動 AI 深度數據分析',
                    style: GoogleFonts.notoSansTc(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
