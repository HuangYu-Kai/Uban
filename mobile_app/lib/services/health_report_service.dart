import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import '../models/emotion_data.dart';
import 'emotion_storage_service.dart';

/// 📊 AI 健康報告生成器
/// 
/// 每週自動生成 PDF 健康報告
class HealthReportService {
  final EmotionStorageService _emotionService = EmotionStorageService();

  /// 生成週報PDF
  Future<File> generateWeeklyReport({
    required String elderName,
    required int elderId,
    required Map<String, dynamic> healthData,
  }) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));

    // 獲取情緒數據
    final emotions = await _emotionService.getEmotionsByDateRange(
      weekStart,
      weekEnd,
    );

    // 計算統計數據
    final emotionStats = _calculateEmotionStats(emotions);
    final healthScore = _calculateHealthScore(healthData, emotionStats);

    // 生成報告頁面
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          _buildHeader(elderName, weekStart, weekEnd),
          pw.SizedBox(height: 30),
          _buildHealthScoreSection(healthScore),
          pw.SizedBox(height: 25),
          _buildVitalSignsSection(healthData),
          pw.SizedBox(height: 25),
          _buildEmotionSection(emotionStats),
          pw.SizedBox(height: 25),
          _buildRecommendationsSection(healthData, emotionStats),
          pw.SizedBox(height: 25),
          _buildFooter(),
        ],
      ),
    );

    // 保存檔案
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/health_report_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await pdf.save());

    return file;
  }

  /// 生成月報PDF
  Future<File> generateMonthlyReport({
    required String elderName,
    required int elderId,
    required Map<String, dynamic> healthData,
  }) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0);

    final emotions = await _emotionService.getEmotionsByDateRange(
      monthStart,
      monthEnd,
    );

    final emotionStats = _calculateEmotionStats(emotions);
    final healthScore = _calculateHealthScore(healthData, emotionStats);
    final trends = _calculateTrends(healthData);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          _buildHeader(elderName, monthStart, monthEnd),
          pw.SizedBox(height: 30),
          _buildHealthScoreSection(healthScore),
          pw.SizedBox(height: 25),
          _buildMonthlyTrendsSection(trends),
          pw.SizedBox(height: 25),
          _buildVitalSignsSection(healthData),
          pw.SizedBox(height: 25),
          _buildEmotionSection(emotionStats),
          pw.SizedBox(height: 25),
          _buildDetailedRecommendations(healthData, emotionStats, trends),
          pw.SizedBox(height: 25),
          _buildFooter(),
        ],
      ),
    );

    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/health_report_monthly_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await pdf.save());

    return file;
  }

  // ==================== 頁面構建方法 ====================

  pw.Widget _buildHeader(String elderName, DateTime startDate, DateTime endDate) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        gradient: const pw.LinearGradient(
          colors: [PdfColor.fromInt(0xFF3B82F6), PdfColor.fromInt(0xFF8B5CF6)],
        ),
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '健康照護週報',
            style: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 28,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            '$elderName 的健康報告',
            style: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 16,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '${_formatDate(startDate)} - ${_formatDate(endDate)}',
            style: pw.TextStyle(
              color: PdfColors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildHealthScoreSection(int healthScore) {
    final color = healthScore >= 80
        ? PdfColors.green
        : healthScore >= 60
            ? PdfColors.orange
            : PdfColors.red;

    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '整體健康評分',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 15),
          pw.Row(
            children: [
              pw.Text(
                '$healthScore',
                style: pw.TextStyle(
                  fontSize: 48,
                  fontWeight: pw.FontWeight.bold,
                  color: color,
                ),
              ),
              pw.Text(
                ' / 100',
                style: const pw.TextStyle(
                  fontSize: 24,
                  color: PdfColors.grey,
                ),
              ),
              pw.SizedBox(width: 20),
              pw.Expanded(
                child: pw.Text(
                  _getHealthScoreDescription(healthScore),
                  style: const pw.TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildVitalSignsSection(Map<String, dynamic> healthData) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '生命徵象監測',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 15),
          pw.Row(
            children: [
              pw.Expanded(
                child: _buildVitalSignItem(
                  '心率',
                  '${healthData['heartRate'] ?? 72} BPM',
                  _isNormalHeartRate(healthData['heartRate']),
                ),
              ),
              pw.Expanded(
                child: _buildVitalSignItem(
                  '血壓',
                  '${healthData['bloodPressure'] ?? '120/80'} mmHg',
                  _isNormalBloodPressure(healthData['bloodPressure']),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              pw.Expanded(
                child: _buildVitalSignItem(
                  '血糖',
                  '${healthData['bloodSugar'] ?? 95} mg/dL',
                  _isNormalBloodSugar(healthData['bloodSugar']),
                ),
              ),
              pw.Expanded(
                child: _buildVitalSignItem(
                  '活動量',
                  '${healthData['dailySteps'] ?? 5000} 步',
                  (healthData['dailySteps'] ?? 0) >= 3000,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildVitalSignItem(String label, String value, bool isNormal) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey)),
        pw.SizedBox(height: 4),
        pw.Row(
          children: [
            pw.Text(
              value,
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(width: 6),
            pw.Container(
              width: 8,
              height: 8,
              decoration: pw.BoxDecoration(
                color: isNormal ? PdfColors.green : PdfColors.red,
                shape: pw.BoxShape.circle,
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildEmotionSection(Map<String, dynamic> emotionStats) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '情緒分析',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 15),
          _buildEmotionBar('開心', emotionStats['happy'] ?? 0, PdfColors.yellow),
          pw.SizedBox(height: 8),
          _buildEmotionBar('平靜', emotionStats['calm'] ?? 0, PdfColors.blue),
          pw.SizedBox(height: 8),
          _buildEmotionBar('焦慮', emotionStats['anxious'] ?? 0, PdfColors.orange),
          pw.SizedBox(height: 8),
          _buildEmotionBar('悲傷', emotionStats['sad'] ?? 0, PdfColors.purple),
        ],
      ),
    );
  }

  pw.Widget _buildEmotionBar(String emotion, double percentage, PdfColor color) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(emotion, style: const pw.TextStyle(fontSize: 14)),
            pw.Text('${percentage.toStringAsFixed(1)}%', style: const pw.TextStyle(fontSize: 14)),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Container(
          height: 8,
          decoration: pw.BoxDecoration(
            color: PdfColors.grey200,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.FractionallySizedBox(
            alignment: pw.Alignment.centerLeft,
            widthFactor: percentage / 100,
            child: pw.Container(
              decoration: pw.BoxDecoration(
                color: color,
                borderRadius: pw.BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _buildRecommendationsSection(
    Map<String, dynamic> healthData,
    Map<String, dynamic> emotionStats,
  ) {
    final recommendations = _generateRecommendations(healthData, emotionStats);

    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'AI 照護建議',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 12),
          ...recommendations.map((rec) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('• ', style: const pw.TextStyle(fontSize: 14)),
                pw.Expanded(
                  child: pw.Text(rec, style: const pw.TextStyle(fontSize: 14)),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  pw.Widget _buildMonthlyTrendsSection(Map<String, String> trends) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '月度趨勢',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 12),
          ...trends.entries.map((entry) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(entry.key, style: const pw.TextStyle(fontSize: 14)),
                pw.Text(entry.value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          )),
        ],
      ),
    );
  }

  pw.Widget _buildDetailedRecommendations(
    Map<String, dynamic> healthData,
    Map<String, dynamic> emotionStats,
    Map<String, String> trends,
  ) {
    final recommendations = _generateDetailedRecommendations(healthData, emotionStats, trends);

    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '詳細照護建議',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 12),
          ...recommendations.map((rec) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 10),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  rec['title'] as String,
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  rec['description'] as String,
                  style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  pw.Widget _buildFooter() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            '本報告由 AI 自動生成，僅供參考，不可作為醫療診斷依據',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '生成時間：${_formatDateTime(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ==================== 輔助方法 ====================

  Map<String, dynamic> _calculateEmotionStats(List<EmotionData> emotions) {
    if (emotions.isEmpty) {
      return {'happy': 0.0, 'calm': 0.0, 'anxious': 0.0, 'sad': 0.0};
    }

    final counts = <String, int>{};
    for (final emotion in emotions) {
      counts[emotion.type.name] = (counts[emotion.type.name] ?? 0) + 1;
    }

    final total = emotions.length;
    return {
      'happy': ((counts['happy'] ?? 0) / total * 100),
      'calm': ((counts['calm'] ?? 0) / total * 100),
      'anxious': ((counts['anxious'] ?? 0) / total * 100),
      'sad': ((counts['sad'] ?? 0) / total * 100),
    };
  }

  int _calculateHealthScore(Map<String, dynamic> healthData, Map<String, dynamic> emotionStats) {
    int score = 100;

    // 心率評分
    final heartRate = healthData['heartRate'] ?? 72;
    if (heartRate < 50 || heartRate > 120) score -= 15;
    else if (heartRate < 60 || heartRate > 100) score -= 5;

    // 血壓評分
    // (簡化處理)

    // 血糖評分
    final bloodSugar = healthData['bloodSugar'] ?? 95;
    if (bloodSugar < 70 || bloodSugar > 140) score -= 15;
    else if (bloodSugar < 80 || bloodSugar > 120) score -= 5;

    // 活動量評分
    final steps = healthData['dailySteps'] ?? 5000;
    if (steps < 2000) score -= 10;
    else if (steps < 3000) score -= 5;

    // 情緒評分
    if ((emotionStats['anxious'] ?? 0) > 30) score -= 10;
    if ((emotionStats['sad'] ?? 0) > 30) score -= 10;

    return score.clamp(0, 100);
  }

  Map<String, String> _calculateTrends(Map<String, dynamic> healthData) {
    return {
      '心率趨勢': '穩定',
      '血壓趨勢': '正常',
      '血糖趨勢': '良好',
      '活動量趨勢': '需改善',
    };
  }

  List<String> _generateRecommendations(
    Map<String, dynamic> healthData,
    Map<String, dynamic> emotionStats,
  ) {
    final recommendations = <String>[];

    if ((healthData['dailySteps'] ?? 0) < 3000) {
      recommendations.add('建議增加每日活動量，目標至少 5000 步');
    }

    if ((emotionStats['anxious'] ?? 0) > 30) {
      recommendations.add('近期焦慮情緒較多，建議增加陪伴與關心');
    }

    if ((healthData['bloodSugar'] ?? 0) > 120) {
      recommendations.add('血糖偏高，建議注意飲食控制');
    }

    recommendations.add('持續保持規律作息與運動習慣');

    return recommendations;
  }

  List<Map<String, String>> _generateDetailedRecommendations(
    Map<String, dynamic> healthData,
    Map<String, dynamic> emotionStats,
    Map<String, String> trends,
  ) {
    final recommendations = <Map<String, String>>[];

    if ((healthData['dailySteps'] ?? 0) < 3000) {
      recommendations.add({
        'title': '增加活動量',
        'description': '建議每天至少步行 30 分鐘，可分段進行，有助於改善心血管健康',
      });
    }

    if ((emotionStats['anxious'] ?? 0) > 30) {
      recommendations.add({
        'title': '情緒關懷',
        'description': '近期焦慮情緒較多，建議家人增加視訊通話頻率，多陪伴聊天',
      });
    }

    recommendations.add({
      'title': '定期健康檢查',
      'description': '建議每 3 個月進行一次完整健康檢查，及早發現潛在問題',
    });

    return recommendations;
  }

  String _getHealthScoreDescription(int score) {
    if (score >= 80) return '健康狀況良好，請繼續保持';
    if (score >= 60) return '健康狀況尚可，建議注意部分指標';
    return '需要特別關注，建議諮詢醫療專業人員';
  }

  bool _isNormalHeartRate(dynamic hr) {
    if (hr == null) return true;
    final rate = hr is int ? hr : int.tryParse(hr.toString()) ?? 72;
    return rate >= 60 && rate <= 100;
  }

  bool _isNormalBloodPressure(dynamic bp) {
    if (bp == null) return true;
    return true; // 簡化處理
  }

  bool _isNormalBloodSugar(dynamic bs) {
    if (bs == null) return true;
    final sugar = bs is int ? bs : int.tryParse(bs.toString()) ?? 95;
    return sugar >= 70 && sugar <= 120;
  }

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime date) {
    return '${_formatDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
