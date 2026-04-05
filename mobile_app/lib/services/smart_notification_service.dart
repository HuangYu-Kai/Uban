import 'package:flutter/foundation.dart';
import '../models/emotion_data.dart';
import '../services/predictive_alert_service.dart';
import '../services/emotion_storage_service.dart';

/// 🔔 智能通知引擎
/// 
/// 根據用戶行為、情緒狀態和時間模式智能推送通知
class SmartNotificationService {
  final EmotionStorageService _emotionService = EmotionStorageService();
  final PredictiveAlertService _alertService = PredictiveAlertService();
  
  /// 檢查是否應該發送通知
  Future<List<SmartNotification>> checkAndGenerateNotifications({
    required String userId,
    required int elderId,
    required Map<String, dynamic> healthData,
  }) async {
    final notifications = <SmartNotification>[];
    final now = DateTime.now();
    
    // 1. 基於時間的智能提醒
    final timeBasedNotifications = await _generateTimeBasedNotifications(
      userId: userId,
      elderId: elderId,
      currentTime: now,
    );
    notifications.addAll(timeBasedNotifications);
    
    // 2. 基於情緒的提醒
    final emotionNotifications = await _generateEmotionBasedNotifications(
      elderId: elderId,
    );
    notifications.addAll(emotionNotifications);
    
    // 3. 基於健康數據的提醒
    final healthNotifications = _generateHealthBasedNotifications(
      healthData: healthData,
    );
    notifications.addAll(healthNotifications);
    
    // 4. 基於活動模式的提醒
    final activityNotifications = await _generateActivityBasedNotifications(
      userId: userId,
      elderId: elderId,
    );
    notifications.addAll(activityNotifications);
    
    // 過濾和優先級排序
    return _filterAndPrioritize(notifications);
  }

  /// 生成基於時間的通知
  Future<List<SmartNotification>> _generateTimeBasedNotifications({
    required String userId,
    required int elderId,
    required DateTime currentTime,
  }) async {
    final notifications = <SmartNotification>[];
    final hour = currentTime.hour;
    final weekday = currentTime.weekday;
    
    // 早晨問候 (7:00-9:00)
    if (hour >= 7 && hour < 9) {
      final lastCallTime = await _getLastCallTime(userId, elderId);
      if (lastCallTime == null || 
          DateTime.now().difference(lastCallTime).inHours > 24) {
        notifications.add(SmartNotification(
          id: 'morning_greeting_${currentTime.millisecondsSinceEpoch}',
          title: '早安問候',
          message: '新的一天開始了，打個視訊電話問候長輩吧！',
          type: NotificationType.reminder,
          priority: NotificationPriority.low,
          scheduledTime: currentTime,
          optimalSendTime: DateTime(
            currentTime.year,
            currentTime.month,
            currentTime.day,
            8,
            0,
          ),
          metadata: {
            'action': 'video_call',
            'reason': 'morning_greeting',
          },
        ));
      }
    }
    
    // 晚餐時間提醒 (17:00-19:00)
    if (hour >= 17 && hour < 19) {
      notifications.add(SmartNotification(
        id: 'dinner_time_${currentTime.millisecondsSinceEpoch}',
        title: '晚餐時間',
        message: '關心長輩今天吃了什麼，營養是否均衡',
        type: NotificationType.reminder,
        priority: NotificationPriority.medium,
        scheduledTime: currentTime,
        optimalSendTime: DateTime(
          currentTime.year,
          currentTime.month,
          currentTime.day,
          18,
          0,
        ),
        metadata: {
          'action': 'check_in',
          'reason': 'meal_time',
        },
      ));
    }
    
    // 睡前關懷 (20:00-22:00)
    if (hour >= 20 && hour < 22) {
      notifications.add(SmartNotification(
        id: 'bedtime_care_${currentTime.millisecondsSinceEpoch}',
        title: '睡前關懷',
        message: '提醒長輩按時服藥，祝福好夢',
        type: NotificationType.reminder,
        priority: NotificationPriority.medium,
        scheduledTime: currentTime,
        optimalSendTime: DateTime(
          currentTime.year,
          currentTime.month,
          currentTime.day,
          21,
          0,
        ),
        metadata: {
          'action': 'medication_reminder',
          'reason': 'bedtime',
        },
      ));
    }
    
    // 週末特別提醒
    if (weekday >= 6) { // 週六或週日
      notifications.add(SmartNotification(
        id: 'weekend_visit_${currentTime.millisecondsSinceEpoch}',
        title: '週末時光',
        message: '今天有空的話，考慮去探望長輩吧！',
        type: NotificationType.suggestion,
        priority: NotificationPriority.low,
        scheduledTime: currentTime,
        optimalSendTime: DateTime(
          currentTime.year,
          currentTime.month,
          currentTime.day,
          10,
          0,
        ),
        metadata: {
          'action': 'plan_visit',
          'reason': 'weekend',
        },
      ));
    }
    
    return notifications;
  }

  /// 生成基於情緒的通知
  Future<List<SmartNotification>> _generateEmotionBasedNotifications({
    required int elderId,
  }) async {
    final notifications = <SmartNotification>[];
    final now = DateTime.now();
    
    // 獲取最近的情緒數據
    final recentEmotions = await _emotionService.getEmotionsByDateRange(
      now.subtract(const Duration(hours: 6)),
      now,
    );
    
    if (recentEmotions.isEmpty) return notifications;
    
    // 檢查連續負面情緒
    final negativeCount = recentEmotions.where((e) => 
      e.type == EmotionType.sad || e.type == EmotionType.anxious
    ).length;
    
    if (negativeCount >= 3) {
      notifications.add(SmartNotification(
        id: 'emotion_concern_${now.millisecondsSinceEpoch}',
        title: '情緒關懷提醒',
        message: '長輩最近情緒似乎不太好，建議主動關心',
        type: NotificationType.alert,
        priority: NotificationPriority.high,
        scheduledTime: now,
        optimalSendTime: _calculateOptimalCallTime(now),
        metadata: {
          'action': 'emotional_support',
          'reason': 'negative_emotion_pattern',
          'emotionCount': negativeCount,
        },
      ));
    }
    
    // 檢查異常情緒高峰
    final lastEmotion = recentEmotions.first;
    if (lastEmotion.isAbnormal && lastEmotion.isHighConfidence) {
      notifications.add(SmartNotification(
        id: 'emotion_alert_${now.millisecondsSinceEpoch}',
        title: '異常情緒偵測',
        message: '偵測到長輩情緒異常，建議立即確認狀況',
        type: NotificationType.urgent,
        priority: NotificationPriority.urgent,
        scheduledTime: now,
        optimalSendTime: now, // 立即發送
        metadata: {
          'action': 'immediate_check',
          'reason': 'abnormal_emotion',
          'emotionType': lastEmotion.type.name,
          'confidence': lastEmotion.confidence,
        },
      ));
    }
    
    return notifications;
  }

  /// 生成基於健康數據的通知
  List<SmartNotification> _generateHealthBasedNotifications({
    required Map<String, dynamic> healthData,
  }) {
    final notifications = <SmartNotification>[];
    final now = DateTime.now();
    
    // 心率異常
    final heartRate = healthData['heartRate'] as int?;
    if (heartRate != null && (heartRate < 50 || heartRate > 120)) {
      notifications.add(SmartNotification(
        id: 'health_heart_rate_${now.millisecondsSinceEpoch}',
        title: '心率異常警報',
        message: '長輩心率異常（$heartRate BPM），請立即確認',
        type: NotificationType.urgent,
        priority: NotificationPriority.urgent,
        scheduledTime: now,
        optimalSendTime: now,
        metadata: {
          'action': 'emergency_check',
          'reason': 'abnormal_heart_rate',
          'value': heartRate,
        },
      ));
    }
    
    // 活動量過低
    final dailySteps = healthData['dailySteps'] as int?;
    if (dailySteps != null && dailySteps < 1000 && now.hour >= 16) {
      notifications.add(SmartNotification(
        id: 'health_activity_${now.millisecondsSinceEpoch}',
        title: '活動量提醒',
        message: '今日活動量偏低（$dailySteps 步），鼓勵長輩多活動',
        type: NotificationType.suggestion,
        priority: NotificationPriority.low,
        scheduledTime: now,
        optimalSendTime: DateTime(now.year, now.month, now.day, 16, 30),
        metadata: {
          'action': 'encourage_activity',
          'reason': 'low_daily_steps',
          'value': dailySteps,
        },
      ));
    }
    
    return notifications;
  }

  /// 生成基於活動模式的通知
  Future<List<SmartNotification>> _generateActivityBasedNotifications({
    required String userId,
    required int elderId,
  }) async {
    final notifications = <SmartNotification>[];
    final now = DateTime.now();
    
    // 檢查最近通話頻率
    final recentCalls = await _getRecentCallCount(userId, elderId, days: 7);
    if (recentCalls < 3) {
      notifications.add(SmartNotification(
        id: 'activity_call_frequency_${now.millisecondsSinceEpoch}',
        title: '互動頻率提醒',
        message: '本週僅通話 $recentCalls 次，建議增加與長輩的聯繫',
        type: NotificationType.reminder,
        priority: NotificationPriority.medium,
        scheduledTime: now,
        optimalSendTime: _calculateOptimalCallTime(now),
        metadata: {
          'action': 'increase_communication',
          'reason': 'low_call_frequency',
          'callCount': recentCalls,
        },
      ));
    }
    
    return notifications;
  }

  /// 過濾和優先級排序通知
  List<SmartNotification> _filterAndPrioritize(List<SmartNotification> notifications) {
    // 移除重複類型的通知（保留優先級高的）
    final Map<NotificationType, SmartNotification> uniqueNotifications = {};
    
    for (final notification in notifications) {
      final existing = uniqueNotifications[notification.type];
      if (existing == null || 
          notification.priority.index > existing.priority.index) {
        uniqueNotifications[notification.type] = notification;
      }
    }
    
    // 按優先級排序
    final result = uniqueNotifications.values.toList();
    result.sort((a, b) => b.priority.index.compareTo(a.priority.index));
    
    return result;
  }

  /// 計算最佳通話時間
  DateTime _calculateOptimalCallTime(DateTime baseTime) {
    final hour = baseTime.hour;
    
    // 避開睡眠時間和用餐時間
    if (hour < 8) {
      return DateTime(baseTime.year, baseTime.month, baseTime.day, 9, 0);
    } else if (hour >= 11 && hour < 13) {
      return DateTime(baseTime.year, baseTime.month, baseTime.day, 14, 0);
    } else if (hour >= 17 && hour < 19) {
      return DateTime(baseTime.year, baseTime.month, baseTime.day, 19, 30);
    } else if (hour >= 22) {
      return DateTime(baseTime.year, baseTime.month, baseTime.day + 1, 9, 0);
    }
    
    return baseTime;
  }

  /// 獲取最後通話時間（模擬）
  Future<DateTime?> _getLastCallTime(String userId, int elderId) async {
    // TODO: 從資料庫獲取
    return null;
  }

  /// 獲取最近通話次數（模擬）
  Future<int> _getRecentCallCount(String userId, int elderId, {int days = 7}) async {
    // TODO: 從資料庫獲取
    return 2; // 模擬數據
  }
}

/// 通知類型
enum NotificationType {
  urgent,      // 緊急通知
  alert,       // 警報通知
  reminder,    // 提醒通知
  suggestion,  // 建議通知
}

/// 通知優先級
enum NotificationPriority {
  low,
  medium,
  high,
  urgent,
}

/// 智能通知模型
class SmartNotification {
  final String id;
  final String title;
  final String message;
  final NotificationType type;
  final NotificationPriority priority;
  final DateTime scheduledTime;
  final DateTime optimalSendTime;
  final Map<String, dynamic>? metadata;

  SmartNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.priority,
    required this.scheduledTime,
    required this.optimalSendTime,
    this.metadata,
  });

  /// 是否應該立即發送
  bool get shouldSendImmediately {
    return type == NotificationType.urgent ||
           priority == NotificationPriority.urgent;
  }

  /// 是否在最佳時間範圍內
  bool get isOptimalTime {
    final now = DateTime.now();
    final diff = now.difference(optimalSendTime).inMinutes.abs();
    return diff <= 30; // 在最佳時間的 30 分鐘內
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'message': message,
      'type': type.name,
      'priority': priority.name,
      'scheduledTime': scheduledTime.toIso8601String(),
      'optimalSendTime': optimalSendTime.toIso8601String(),
      'metadata': metadata,
    };
  }

  factory SmartNotification.fromJson(Map<String, dynamic> json) {
    return SmartNotification(
      id: json['id'] as String,
      title: json['title'] as String,
      message: json['message'] as String,
      type: NotificationType.values.firstWhere((e) => e.name == json['type']),
      priority: NotificationPriority.values.firstWhere((e) => e.name == json['priority']),
      scheduledTime: DateTime.parse(json['scheduledTime'] as String),
      optimalSendTime: DateTime.parse(json['optimalSendTime'] as String),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
}
