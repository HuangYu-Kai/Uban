/// 智慧健康異常檢測引擎
/// 使用統計分析檢測異常數據並提供風險評估
class HealthAnomalyDetector {
  /// 健康指標的正常範圍
  static const Map<String, Map<String, double>> normalRanges = {
    'heart_rate': {'min': 60, 'max': 100, 'resting_max': 80},
    'steps': {'min': 1000, 'max': 15000, 'daily_target': 8000},
    'calories': {'min': 1200, 'max': 3000, 'daily_target': 2000},
    'sleep_quality': {'min': 60, 'max': 100, 'good_threshold': 70},
  };

  /// 異常檢測結果
  static Future<HealthAnomalyResult> analyzeHealthData(
    Map<String, dynamic> currentData,
    List<Map<String, dynamic>> historicalData,
  ) async {
    final anomalies = <HealthAnomaly>[];
    final riskScore = _calculateRiskScore(currentData, historicalData);

    // 心率異常檢測
    if (currentData['heart_rate'] != null) {
      final hrAnomaly = _detectHeartRateAnomaly(
        currentData['heart_rate'],
        historicalData,
      );
      if (hrAnomaly != null) anomalies.add(hrAnomaly);
    }

    // 活動量異常檢測
    if (currentData['steps'] != null) {
      final stepsAnomaly = _detectActivityAnomaly(
        currentData['steps'],
        historicalData,
      );
      if (stepsAnomaly != null) anomalies.add(stepsAnomaly);
    }

    // 睡眠質量異常檢測
    if (currentData['sleep_quality'] != null) {
      final sleepAnomaly = _detectSleepAnomaly(
        currentData['sleep_quality'],
        historicalData,
      );
      if (sleepAnomaly != null) anomalies.add(sleepAnomaly);
    }

    // 卡路里異常檢測
    if (currentData['calories'] != null) {
      final calorieAnomaly = _detectCalorieAnomaly(
        currentData['calories'],
        historicalData,
      );
      if (calorieAnomaly != null) anomalies.add(calorieAnomaly);
    }

    return HealthAnomalyResult(
      anomalies: anomalies,
      riskScore: riskScore,
      timestamp: DateTime.now(),
      overallStatus: _getOverallStatus(riskScore, anomalies.length),
    );
  }

  /// 心率異常檢測
  static HealthAnomaly? _detectHeartRateAnomaly(
    int currentHR,
    List<Map<String, dynamic>> history,
  ) {
    if (currentHR < 50) {
      return HealthAnomaly(
        type: 'heart_rate_low',
        title: '心率過低',
        description: '心率 $currentHR BPM（低於 50）',
        severity: 'high',
        recommendation: '如有頭暈症狀，請立即就醫',
      );
    }

    if (currentHR > 120) {
      return HealthAnomaly(
        type: 'heart_rate_high',
        title: '心率過高',
        description: '心率 $currentHR BPM（高於 120）',
        severity: 'high',
        recommendation: '保持冷靜，避免劇烈活動',
      );
    }

    // 檢測心率突變（與歷史平均值比較）
    if (history.isNotEmpty) {
      final avgHR = _calculateAverage(
        history.map((h) => (h['heart_rate'] as num).toInt()).toList(),
      );
      final deviation = (currentHR - avgHR).abs();

      if (deviation > 30) {
        return HealthAnomaly(
          type: 'heart_rate_spike',
          title: '心率異常波動',
          description: '心率相比平均值偏高 ${deviation.toInt()} BPM',
          severity: 'medium',
          recommendation: '建議稍作休息，監測心率變化',
        );
      }
    }

    return null;
  }

  /// 活動量異常檢測
  static HealthAnomaly? _detectActivityAnomaly(
    int steps,
    List<Map<String, dynamic>> history,
  ) {
    if (steps < 500) {
      return HealthAnomaly(
        type: 'activity_very_low',
        title: '活動量極低',
        description: '今日步數 $steps（建議 8000+）',
        severity: 'high',
        recommendation: '長時間不動易造成健康問題，建議散步活動',
      );
    }

    if (history.isNotEmpty) {
      final avgSteps = _calculateAverage(
        history.map((h) => (h['steps'] as num).toInt()).toList(),
      );
      final changePercent = ((steps - avgSteps) / avgSteps * 100).abs();

      // 活動量突然下降超過 50%
      if (changePercent > 50 && steps < avgSteps * 0.5) {
        return HealthAnomaly(
          type: 'activity_sudden_drop',
          title: '活動量大幅下降',
          description: '步數相比平均值下降 ${changePercent.toStringAsFixed(0)}%',
          severity: 'medium',
          recommendation: '活動量異常下降，建議檢查身體狀況',
        );
      }
    }

    return null;
  }

  /// 睡眠質量異常檢測
  static HealthAnomaly? _detectSleepAnomaly(
    double sleepQuality,
    List<Map<String, dynamic>> history,
  ) {
    if (sleepQuality < 40) {
      return HealthAnomaly(
        type: 'sleep_very_poor',
        title: '睡眠質量極差',
        description: '睡眠質量 ${sleepQuality.toStringAsFixed(0)}%',
        severity: 'high',
        recommendation: '建議調整作息，考慮諮詢醫生',
      );
    }

    if (sleepQuality < 60) {
      return HealthAnomaly(
        type: 'sleep_poor',
        title: '睡眠質量不佳',
        description: '睡眠質量 ${sleepQuality.toStringAsFixed(0)}%（低於 60%）',
        severity: 'medium',
        recommendation: '建議改善睡眠環境和作息習慣',
      );
    }

    return null;
  }

  /// 卡路里異常檢測
  static HealthAnomaly? _detectCalorieAnomaly(
    int calories,
    List<Map<String, dynamic>> history,
  ) {
    if (calories < 800) {
      return HealthAnomaly(
        type: 'calorie_too_low',
        title: '熱量攝取不足',
        description: '今日卡路里 $calories（低於 1200）',
        severity: 'medium',
        recommendation: '建議增加進食量，確保營養攝取',
      );
    }

    if (calories > 3500) {
      return HealthAnomaly(
        type: 'calorie_too_high',
        title: '熱量攝取過高',
        description: '今日卡路里 $calories（超過 3000）',
        severity: 'low',
        recommendation: '建議控制飲食量',
      );
    }

    return null;
  }

  /// 計算綜合風險評分（0-100）
  static int _calculateRiskScore(
    Map<String, dynamic> current,
    List<Map<String, dynamic>> history,
  ) {
    int score = 0;

    // 心率風險（0-25 分）
    final hr = current['heart_rate'] as int?;
    if (hr != null) {
      if (hr < 50 || hr > 120) {
        score += 25;
      } else if (hr < 60 || hr > 100) {
        score += 15;
      }
    }

    // 活動量風險（0-25 分）
    final steps = current['steps'] as int?;
    if (steps != null) {
      if (steps < 500) {
        score += 25;
      } else if (steps < 3000) {
        score += 15;
      }
    }

    // 睡眠質量風險（0-25 分）
    final sleep = current['sleep_quality'] as double?;
    if (sleep != null) {
      if (sleep < 40) {
        score += 25;
      } else if (sleep < 60) {
        score += 15;
      }
    }

    // 卡路里風險（0-25 分）
    final cal = current['calories'] as int?;
    if (cal != null) {
      if (cal < 800 || cal > 3500) {
        score += 20;
      }
    }

    return (score).clamp(0, 100);
  }

  /// 獲取整體健康狀態
  static String _getOverallStatus(int riskScore, int anomalyCount) {
    if (riskScore > 70 || anomalyCount > 2) return 'critical';
    if (riskScore > 50 || anomalyCount > 1) return 'warning';
    if (riskScore > 30) return 'caution';
    return 'healthy';
  }

  /// 計算平均值
  static double _calculateAverage(List<int> values) {
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a + b) / values.length;
  }
}

/// 健康異常資料類
class HealthAnomaly {
  final String type;
  final String title;
  final String description;
  final String severity; // 'high', 'medium', 'low'
  final String recommendation;

  HealthAnomaly({
    required this.type,
    required this.title,
    required this.description,
    required this.severity,
    required this.recommendation,
  });

  /// 獲取嚴重程度顏色
  String getSeverityColor() {
    switch (severity) {
      case 'high':
        return '#EF4444'; // 紅色
      case 'medium':
        return '#F59E0B'; // 橙色
      case 'low':
        return '#FBBF24'; // 黃色
      default:
        return '#10B981'; // 綠色
    }
  }

  /// 獲取嚴重程度圖標
  String getSeverityIcon() {
    switch (severity) {
      case 'high':
        return '🚨';
      case 'medium':
        return '⚠️';
      case 'low':
        return 'ℹ️';
      default:
        return '✅';
    }
  }
}

/// 健康異常檢測結果
class HealthAnomalyResult {
  final List<HealthAnomaly> anomalies;
  final int riskScore; // 0-100
  final DateTime timestamp;
  final String overallStatus; // 'healthy', 'caution', 'warning', 'critical'

  HealthAnomalyResult({
    required this.anomalies,
    required this.riskScore,
    required this.timestamp,
    required this.overallStatus,
  });

  /// 是否有重大異常
  bool get hasAnomalies => anomalies.isNotEmpty;

  /// 獲取狀態顏色
  String getStatusColor() {
    switch (overallStatus) {
      case 'critical':
        return '#DC2626'; // 深紅
      case 'warning':
        return '#F59E0B'; // 橙色
      case 'caution':
        return '#FBBF24'; // 黃色
      case 'healthy':
      default:
        return '#10B981'; // 綠色
    }
  }

  /// 獲取狀態說明
  String getStatusMessage() {
    switch (overallStatus) {
      case 'critical':
        return '🚨 健康狀態需要立即關注';
      case 'warning':
        return '⚠️ 健康狀態需要注意';
      case 'caution':
        return 'ℹ️ 健康狀態需要改善';
      case 'healthy':
      default:
        return '✅ 健康狀態良好';
    }
  }
}
