import 'package:flutter/foundation.dart';
import '../models/emotion_data.dart';
import 'emotion_storage_service.dart';

/// 🚨 預測性警示系統
/// 
/// 根據歷史數據預測風險並發送警報
class PredictiveAlertService {
  final EmotionStorageService _emotionService = EmotionStorageService();
  
  /// 檢查並生成所有警示
  Future<List<Alert>> checkAllAlerts({
    required Map<String, dynamic> healthData,
    int lookbackDays = 7,
  }) async {
    final alerts = <Alert>[];
    
    // 獲取歷史情緒數據
    final emotions = await _emotionService.getEmotionsByDateRange(
      DateTime.now().subtract(Duration(days: lookbackDays)),
      DateTime.now(),
    );
    
    // 1. 情緒異常警示
    alerts.addAll(await _checkEmotionAlerts(emotions));
    
    // 2. 生命徵象警示
    alerts.addAll(_checkVitalSignsAlerts(healthData));
    
    // 3. 活動量警示
    alerts.addAll(_checkActivityAlerts(healthData));
    
    // 4. 趨勢預測警示
    alerts.addAll(_checkTrendAlerts(healthData, emotions));
    
    // 按優先級和時間排序
    alerts.sort((a, b) {
      final priorityCompare = b.priority.index.compareTo(a.priority.index);
      if (priorityCompare != 0) return priorityCompare;
      return b.timestamp.compareTo(a.timestamp);
    });
    
    return alerts;
  }

  /// 檢查情緒異常警示
  Future<List<Alert>> _checkEmotionAlerts(List<EmotionData> emotions) async {
    final alerts = <Alert>[];
    
    if (emotions.isEmpty) return alerts;
    
    // 1. 連續負面情緒
    final recentEmotions = emotions.take(5).toList();
    final negativeCount = recentEmotions.where((e) => 
      e.type == EmotionType.sad || e.type == EmotionType.anxious
    ).length;
    
    if (negativeCount >= 4) {
      alerts.add(Alert(
        id: 'emotion_negative_streak',
        title: '連續負面情緒警示',
        description: '長輩近期持續出現悲傷或焦慮情緒，建議立即關心',
        type: AlertType.emotionAbnormal,
        priority: AlertPriority.high,
        timestamp: DateTime.now(),
        actionRequired: true,
        recommendedActions: [
          '立即撥打視訊電話關心',
          '詢問近期生活狀況',
          '必要時尋求專業心理諮詢',
        ],
      ));
    }
    
    // 2. 情緒劇烈波動
    if (emotions.length >= 3) {
      final recent3 = emotions.take(3).toList();
      final emotionTypes = recent3.map((e) => e.type).toSet();
      
      if (emotionTypes.length == 3) {
        alerts.add(Alert(
          id: 'emotion_volatile',
          title: '情緒波動劇烈',
          description: '長輩情緒在短時間內多次變化，可能心理狀態不穩定',
          type: AlertType.emotionAbnormal,
          priority: AlertPriority.medium,
          timestamp: DateTime.now(),
          actionRequired: false,
          recommendedActions: [
            '增加關心頻率',
            '觀察是否有特定觸發因素',
          ],
        ));
      }
    }
    
    // 3. 高置信度異常情緒
    final abnormalEmotions = emotions.where((e) => 
      e.isAbnormal && e.isHighConfidence
    ).toList();
    
    if (abnormalEmotions.length >= 3) {
      alerts.add(Alert(
        id: 'emotion_high_confidence_abnormal',
        title: '多次高置信度異常情緒',
        description: '系統偵測到多次明確的異常情緒訊號',
        type: AlertType.emotionAbnormal,
        priority: AlertPriority.medium,
        timestamp: DateTime.now(),
        actionRequired: true,
        recommendedActions: [
          '查看情緒時間軸詳細資訊',
          '與長輩溝通了解原因',
        ],
      ));
    }
    
    return alerts;
  }

  /// 檢查生命徵象警示
  List<Alert> _checkVitalSignsAlerts(Map<String, dynamic> healthData) {
    final alerts = <Alert>[];
    
    // 1. 心率異常
    final heartRate = healthData['heartRate'] as int?;
    if (heartRate != null) {
      if (heartRate < 50) {
        alerts.add(Alert(
          id: 'vital_heart_rate_low',
          title: '心率過低警示',
          description: '當前心率 $heartRate BPM，低於正常範圍',
          type: AlertType.vitalSignAbnormal,
          priority: AlertPriority.high,
          timestamp: DateTime.now(),
          actionRequired: true,
          recommendedActions: [
            '立即確認長輩狀況',
            '必要時撥打緊急聯絡電話',
            '記錄異常時間和活動',
          ],
        ));
      } else if (heartRate > 120) {
        alerts.add(Alert(
          id: 'vital_heart_rate_high',
          title: '心率過高警示',
          description: '當前心率 $heartRate BPM，高於正常範圍',
          type: AlertType.vitalSignAbnormal,
          priority: AlertPriority.high,
          timestamp: DateTime.now(),
          actionRequired: true,
          recommendedActions: [
            '確認是否正在運動或激動',
            '若休息狀態仍高需立即關注',
            '記錄並觀察後續變化',
          ],
        ));
      }
    }
    
    // 2. 血糖異常
    final bloodSugar = healthData['bloodSugar'] as int?;
    if (bloodSugar != null) {
      if (bloodSugar < 70) {
        alerts.add(Alert(
          id: 'vital_blood_sugar_low',
          title: '低血糖警示',
          description: '當前血糖 $bloodSugar mg/dL，有低血糖風險',
          type: AlertType.vitalSignAbnormal,
          priority: AlertPriority.high,
          timestamp: DateTime.now(),
          actionRequired: true,
          recommendedActions: [
            '提醒長輩立即補充糖分',
            '確認用藥是否正常',
            '監測後續血糖變化',
          ],
        ));
      } else if (bloodSugar > 180) {
        alerts.add(Alert(
          id: 'vital_blood_sugar_high',
          title: '高血糖警示',
          description: '當前血糖 $bloodSugar mg/dL，血糖偏高',
          type: AlertType.vitalSignAbnormal,
          priority: AlertPriority.medium,
          timestamp: DateTime.now(),
          actionRequired: true,
          recommendedActions: [
            '注意飲食控制',
            '確認是否按時服藥',
            '建議增加活動量',
          ],
        ));
      }
    }
    
    // 3. 血壓異常
    final systolic = healthData['systolicBP'] as int?;
    final diastolic = healthData['diastolicBP'] as int?;
    
    if (systolic != null && diastolic != null) {
      if (systolic > 140 || diastolic > 90) {
        alerts.add(Alert(
          id: 'vital_blood_pressure_high',
          title: '血壓偏高警示',
          description: '當前血壓 $systolic/$diastolic mmHg',
          type: AlertType.vitalSignAbnormal,
          priority: AlertPriority.medium,
          timestamp: DateTime.now(),
          actionRequired: false,
          recommendedActions: [
            '注意情緒穩定',
            '避免高鹽飲食',
            '記錄血壓變化趨勢',
          ],
        ));
      }
    }
    
    return alerts;
  }

  /// 檢查活動量警示
  List<Alert> _checkActivityAlerts(Map<String, dynamic> healthData) {
    final alerts = <Alert>[];
    
    final dailySteps = healthData['dailySteps'] as int?;
    final consecutiveLowActivityDays = healthData['consecutiveLowActivityDays'] as int? ?? 0;
    
    // 1. 連續多日活動量過低
    if (consecutiveLowActivityDays >= 3) {
      alerts.add(Alert(
        id: 'activity_consecutive_low',
        title: '活動量持續偏低',
        description: '已連續 $consecutiveLowActivityDays 天活動量不足',
        type: AlertType.activityAbnormal,
        priority: AlertPriority.medium,
        timestamp: DateTime.now(),
        actionRequired: true,
        recommendedActions: [
          '鼓勵長輩增加室內外活動',
          '建議陪同散步',
          '檢查是否有身體不適',
        ],
      ));
    }
    
    // 2. 今日活動量極低
    if (dailySteps != null && dailySteps < 500) {
      final now = DateTime.now();
      // 只在下午後提醒
      if (now.hour >= 14) {
        alerts.add(Alert(
          id: 'activity_today_very_low',
          title: '今日活動量極低',
          description: '今日步數僅 $dailySteps 步，建議增加活動',
          type: AlertType.activityAbnormal,
          priority: AlertPriority.low,
          timestamp: DateTime.now(),
          actionRequired: false,
          recommendedActions: [
            '提醒長輩適度活動',
            '可能需要協助行動',
          ],
        ));
      }
    }
    
    return alerts;
  }

  /// 檢查趨勢預測警示
  List<Alert> _checkTrendAlerts(
    Map<String, dynamic> healthData,
    List<EmotionData> emotions,
  ) {
    final alerts = <Alert>[];
    
    // 1. 睡眠品質下降趨勢
    final sleepQualityTrend = healthData['sleepQualityTrend'] as String?;
    if (sleepQualityTrend == 'declining') {
      alerts.add(Alert(
        id: 'trend_sleep_declining',
        title: '睡眠品質下降趨勢',
        description: '近期睡眠品質呈下降趨勢，可能影響整體健康',
        type: AlertType.trendPrediction,
        priority: AlertPriority.low,
        timestamp: DateTime.now(),
        actionRequired: false,
        recommendedActions: [
          '建議調整作息時間',
          '注意睡前飲食',
          '保持臥室環境舒適',
        ],
      ));
    }
    
    // 2. 通話頻率下降
    final callFrequencyTrend = healthData['callFrequencyTrend'] as String?;
    if (callFrequencyTrend == 'declining') {
      alerts.add(Alert(
        id: 'trend_communication_declining',
        title: '互動頻率下降',
        description: '與長輩的通話頻率正在減少',
        type: AlertType.trendPrediction,
        priority: AlertPriority.low,
        timestamp: DateTime.now(),
        actionRequired: false,
        recommendedActions: [
          '主動增加通話次數',
          '安排視訊聊天時間',
          '維持情感聯繫',
        ],
      ));
    }
    
    // 3. 情緒惡化趨勢
    if (emotions.length >= 7) {
      final recent7 = emotions.take(7).toList();
      final negativeRatio = recent7.where((e) => 
        e.type == EmotionType.sad || e.type == EmotionType.anxious
      ).length / 7;
      
      if (negativeRatio > 0.5) {
        alerts.add(Alert(
          id: 'trend_emotion_negative',
          title: '情緒負面趨勢',
          description: '近一週負面情緒佔比 ${(negativeRatio * 100).toStringAsFixed(0)}%',
          type: AlertType.trendPrediction,
          priority: AlertPriority.medium,
          timestamp: DateTime.now(),
          actionRequired: true,
          recommendedActions: [
            '增加陪伴時間',
            '安排愉快的活動',
            '必要時尋求專業協助',
          ],
        ));
      }
    }
    
    return alerts;
  }
}

/// 警示類型
enum AlertType {
  emotionAbnormal,      // 情緒異常
  vitalSignAbnormal,    // 生命徵象異常
  activityAbnormal,     // 活動異常
  trendPrediction,      // 趨勢預測
  medicationReminder,   // 用藥提醒
  appointmentReminder,  // 就診提醒
}

/// 警示優先級
enum AlertPriority {
  low,     // 低優先級
  medium,  // 中優先級
  high,    // 高優先級
  urgent,  // 緊急
}

/// 警示模型
class Alert {
  final String id;
  final String title;
  final String description;
  final AlertType type;
  final AlertPriority priority;
  final DateTime timestamp;
  final bool actionRequired;
  final List<String> recommendedActions;
  final Map<String, dynamic>? metadata;

  Alert({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.priority,
    required this.timestamp,
    this.actionRequired = false,
    this.recommendedActions = const [],
    this.metadata,
  });

  String get priorityLabel {
    switch (priority) {
      case AlertPriority.urgent:
        return '緊急';
      case AlertPriority.high:
        return '重要';
      case AlertPriority.medium:
        return '注意';
      case AlertPriority.low:
        return '提醒';
    }
  }

  String get typeLabel {
    switch (type) {
      case AlertType.emotionAbnormal:
        return '情緒異常';
      case AlertType.vitalSignAbnormal:
        return '生命徵象';
      case AlertType.activityAbnormal:
        return '活動異常';
      case AlertType.trendPrediction:
        return '趨勢預測';
      case AlertType.medicationReminder:
        return '用藥提醒';
      case AlertType.appointmentReminder:
        return '就診提醒';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'type': type.name,
      'priority': priority.name,
      'timestamp': timestamp.toIso8601String(),
      'actionRequired': actionRequired,
      'recommendedActions': recommendedActions,
      'metadata': metadata,
    };
  }

  factory Alert.fromJson(Map<String, dynamic> json) {
    return Alert(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      type: AlertType.values.firstWhere((e) => e.name == json['type']),
      priority: AlertPriority.values.firstWhere((e) => e.name == json['priority']),
      timestamp: DateTime.parse(json['timestamp'] as String),
      actionRequired: json['actionRequired'] as bool? ?? false,
      recommendedActions: List<String>.from(json['recommendedActions'] as List? ?? []),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
}
