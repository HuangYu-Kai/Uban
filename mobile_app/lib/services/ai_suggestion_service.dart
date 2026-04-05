import 'package:flutter/material.dart';
import 'dart:math';

/// AI 建議生成服務
/// 
/// 根據長輩的健康數據（睡眠、活動量、心率、情緒）分析生成個人化建議
/// 支援 Mock 數據模式和真實數據模式
/// 
/// 未來整合 Gemini API 說明：
/// 1. 將規則引擎結果作為 context 傳遞給 Gemini
/// 2. 使用 Gemini 生成更自然的建議描述和動作文本
/// 3. API 調用示例：
///    ```dart
///    final prompt = '''
///    基於以下數據生成個人化建議：
///    - 睡眠品質：${sleepQuality}%
///    - 活動量：${steps} 步
///    - 心率：${heartRate} BPM
///    - 情緒狀態：${emotion}
///    規則引擎建議：${ruleBasedSuggestion}
///    請生成更溫暖、個人化的建議文本。
///    ''';
///    final response = await GeminiAPI.generate(prompt);
///    ```
class AiSuggestionService {
  /// 生成 AI 建議列表
  /// 
  /// [elderData] 長輩基本資訊（包含 elder_name, age 等）
  /// [healthData] 健康數據（sleep_quality, steps, heart_rate 等）
  /// [emotionData] 情緒數據列表
  /// [useMockData] 是否使用 Mock 數據（預設 true）
  static Future<List<AiSuggestion>> generateSuggestions({
    required Map<String, dynamic> elderData,
    Map<String, dynamic>? healthData,
    List<Map<String, dynamic>>? emotionData,
    bool useMockData = true,
  }) async {
    if (useMockData) {
      return _generateMockSuggestions(elderData['elder_name'] ?? '長輩');
    }

    final suggestions = <AiSuggestion>[];

    // 睡眠品质分析
    if (healthData != null && healthData['sleep_quality'] != null) {
      final sleepSuggestion = _analyzeSleepQuality(
        healthData['sleep_quality'],
        healthData['sleep_history'],
      );
      if (sleepSuggestion != null) suggestions.add(sleepSuggestion);
    }

    // 活動量分析
    if (healthData != null && healthData['steps'] != null) {
      final activitySuggestion = _analyzeActivityLevel(
        healthData['steps'],
        healthData['steps_history'],
      );
      if (activitySuggestion != null) suggestions.add(activitySuggestion);
    }

    // 心率異常分析
    if (healthData != null && healthData['heart_rate'] != null) {
      final heartRateSuggestion = _analyzeHeartRate(
        healthData['heart_rate'],
        healthData['heart_rate_history'],
      );
      if (heartRateSuggestion != null) suggestions.add(heartRateSuggestion);
    }

    // 情緒狀態分析
    if (emotionData != null && emotionData.isNotEmpty) {
      final emotionSuggestion = _analyzeEmotionState(emotionData);
      if (emotionSuggestion != null) suggestions.add(emotionSuggestion);
    }

    // 按优先级排序
    suggestions.sort((a, b) => _priorityValue(b.priority).compareTo(_priorityValue(a.priority)));

    return suggestions;
  }

  /// 睡眠品質分析
  /// 規則：如果下降 > 30% → 建議調整飲食
  static AiSuggestion? _analyzeSleepQuality(
    dynamic sleepQuality,
    List<Map<String, dynamic>>? history,
  ) {
    final currentQuality = (sleepQuality is int) ? sleepQuality.toDouble() : (sleepQuality as double);

    // 睡眠品質極差（< 40%）
    if (currentQuality < 40) {
      return AiSuggestion(
        icon: Icons.bed_rounded,
        title: '睡眠品質極差',
        description: '睡眠品質僅 ${currentQuality.toStringAsFixed(0)}%，建議調整作息時間，避免睡前使用 3C 產品，可嘗試熱牛奶或聽輕音樂助眠。',
        action: '設定睡眠提醒',
        priority: SuggestionPriority.high,
      );
    }

    // 檢查是否下降超過 30%
    if (history != null && history.isNotEmpty) {
      final avgQuality = history.map((h) => h['sleep_quality'] as num).reduce((a, b) => a + b) / history.length;
      final changePercent = ((avgQuality - currentQuality) / avgQuality * 100).abs();

      if (changePercent > 30) {
        return AiSuggestion(
          icon: Icons.nightlight_round,
          title: '睡眠品質下降',
          description: '近期睡眠品質下降 ${changePercent.toStringAsFixed(0)}%，建議調整飲食，避免晚餐過飽或過晚進食，睡前 2 小時避免咖啡因。',
          action: '查看飲食建議',
          priority: SuggestionPriority.medium,
        );
      }
    }

    // 睡眠品質良好
    if (currentQuality >= 70) {
      return AiSuggestion(
        icon: Icons.bedtime_rounded,
        title: '睡眠品質良好',
        description: '睡眠品質達 ${currentQuality.toStringAsFixed(0)}%，維持得很好！繼續保持規律作息，有助於身體健康。',
        action: '查看詳情',
        priority: SuggestionPriority.low,
      );
    }

    return null;
  }

  /// 活動量分析
  /// 規則：連續 3 天未外出 → 建議播放音樂
  static AiSuggestion? _analyzeActivityLevel(
    dynamic steps,
    List<Map<String, dynamic>>? history,
  ) {
    final currentSteps = steps as int;

    // 檢查連續低活動量
    if (history != null && history.length >= 3) {
      final recentDays = history.take(3).toList();
      final allLowActivity = recentDays.every((day) => (day['steps'] as int) < 500);

      if (allLowActivity && currentSteps < 500) {
        return AiSuggestion(
          icon: Icons.music_note_rounded,
          title: '連續 3 天活動量不足',
          description: '長輩已連續 3 天幾乎沒有外出活動，步數低於 500 步。建議播放輕快音樂，鼓勵在房屋內做簡單運動或到附近散步。',
          action: '播放音樂',
          priority: SuggestionPriority.high,
        );
      }
    }

    // 單日活動量極低
    if (currentSteps < 500) {
      return AiSuggestion(
        icon: Icons.directions_walk_rounded,
        title: '活動量極低',
        description: '今日步數僅 $currentSteps 步，建議鼓勵長輩到戶外走走，或在房屋內做簡單的伸展運動。',
        action: '發送鼓勵',
        priority: SuggestionPriority.medium,
      );
    }

    // 活動量突然大幅下降
    if (history != null && history.isNotEmpty) {
      final avgSteps = history.map((h) => h['steps'] as int).reduce((a, b) => a + b) / history.length;
      final changePercent = (avgSteps - currentSteps) / avgSteps * 100;

      if (changePercent > 50 && currentSteps < avgSteps * 0.5) {
        return AiSuggestion(
          icon: Icons.trending_down_rounded,
          title: '活動量大幅下降',
          description: '活動量較平日減少 ${changePercent.toStringAsFixed(0)}%，可能需要關注是否有身體不適或情緒低落的情況。',
          action: '視訊關心',
          priority: SuggestionPriority.medium,
        );
      }
    }

    // 活動量達標
    if (currentSteps >= 8000) {
      return AiSuggestion(
        icon: Icons.emoji_events_rounded,
        title: '活動量達標',
        description: '今日步數 $currentSteps 步，已達到每日建議目標！繼續保持，健康生活從運動開始。',
        action: '發送鼓勵',
        priority: SuggestionPriority.low,
      );
    }

    return null;
  }

  /// 心率分析
  /// 規則：超過正常範圍 → 建議視訊確認
  static AiSuggestion? _analyzeHeartRate(
    dynamic heartRate,
    List<Map<String, dynamic>>? history,
  ) {
    final currentHR = heartRate as int;

    // 心率過低（< 50 BPM）
    if (currentHR < 50) {
      return AiSuggestion(
        icon: Icons.favorite_rounded,
        title: '心率過低',
        description: '當前心率 $currentHR BPM，低於正常範圍。如長輩有頭暈、乏力症狀，建議立即視訊確認狀況或就醫。',
        action: '立即視訊',
        priority: SuggestionPriority.high,
      );
    }

    // 心率過高（> 120 BPM）
    if (currentHR > 120) {
      return AiSuggestion(
        icon: Icons.favorite_rounded,
        title: '心率過高',
        description: '當前心率 $currentHR BPM，高於正常範圍。建議視訊確認長輩是否剛運動完畢，或有其他不適症狀。',
        action: '立即視訊',
        priority: SuggestionPriority.high,
      );
    }

    // 心率異常波動
    if (history != null && history.isNotEmpty) {
      final avgHR = history.map((h) => h['heart_rate'] as int).reduce((a, b) => a + b) / history.length;
      final deviation = (currentHR - avgHR).abs();

      if (deviation > 30) {
        return AiSuggestion(
          icon: Icons.monitor_heart_rounded,
          title: '心率異常波動',
          description: '心率較平時波動達 ${deviation.toStringAsFixed(0)} BPM，建議視訊確認長輩狀況是否正常。',
          action: '視訊確認',
          priority: SuggestionPriority.medium,
        );
      }
    }

    // 心率正常
    if (currentHR >= 60 && currentHR <= 100) {
      return AiSuggestion(
        icon: Icons.favorite_border_rounded,
        title: '心率正常',
        description: '當前心率 $currentHR BPM，處於正常範圍內，繼續保持健康的生活習慣。',
        action: '查看詳情',
        priority: SuggestionPriority.low,
      );
    }

    return null;
  }

  /// 情緒狀態分析
  /// 規則：焦慮/悲傷持續 → 建議關心問候
  static AiSuggestion? _analyzeEmotionState(List<Map<String, dynamic>> emotionData) {
    if (emotionData.isEmpty) return null;

    // 統計最近情緒分布
    final recentEmotions = emotionData.take(6).map((e) => e['emotion'] as String).toList();
    
    // 檢查負面情緒持續
    final negativeCount = recentEmotions.where((e) => e == '焦慮' || e == '悲傷').length;
    final anxietyCount = recentEmotions.where((e) => e == '焦慮').length;
    final sadnessCount = recentEmotions.where((e) => e == '悲傷').length;

    // 焦慮持續
    if (anxietyCount >= 3) {
      return AiSuggestion(
        icon: Icons.psychology_rounded,
        title: '情緒焦慮持續',
        description: '長輩近期多次出現焦慮情緒，建議主動關心問候，了解是否有煩心事，給予情感支持。',
        action: '發送關心',
        priority: SuggestionPriority.high,
      );
    }

    // 悲傷持續
    if (sadnessCount >= 3) {
      return AiSuggestion(
        icon: Icons.sentiment_very_dissatisfied_rounded,
        title: '情緒悲傷持續',
        description: '長輩近期多次出現悲傷情緒，可能需要更多陪伴與傾聽，建議視訊或電話聊天，給予溫暖關懷。',
        action: '立即通話',
        priority: SuggestionPriority.high,
      );
    }

    // 負面情緒頻繁
    if (negativeCount >= 4) {
      return AiSuggestion(
        icon: Icons.mood_bad_rounded,
        title: '負面情緒較多',
        description: '長輩近期負面情緒較為頻繁，建議增加互動陪伴時間，或分享一些正面、有趣的內容。',
        action: '發送趣事',
        priority: SuggestionPriority.medium,
      );
    }

    // 情緒穩定良好
    final positiveCount = recentEmotions.where((e) => e == '開心').length;
    if (positiveCount >= 4) {
      return AiSuggestion(
        icon: Icons.sentiment_very_satisfied_rounded,
        title: '情緒狀態良好',
        description: '長輩近期心情愉悅，情緒穩定！繼續保持良好的互動關係，讓溫暖陪伴每一天。',
        action: '查看詳情',
        priority: SuggestionPriority.low,
      );
    }

    return null;
  }

  /// 生成 Mock 建議數據（用於開發和演示）
  static Future<List<AiSuggestion>> _generateMockSuggestions(String elderName) async {
    // 模擬 API 延遲
    await Future.delayed(const Duration(milliseconds: 500));

    final suggestions = [
      AiSuggestion(
        icon: Icons.bed_rounded,
        title: '睡眠品質下降',
        description: '$elderName 近 3 天睡眠品質下降 35%，可能是晚餐時間過晚或睡前使用手機導致。建議調整飲食時間，並在睡前播放輕音樂助眠。',
        action: '設定提醒',
        priority: SuggestionPriority.high,
      ),
      AiSuggestion(
        icon: Icons.music_note_rounded,
        title: '連續 3 天活動量不足',
        description: '$elderName 已連續 3 天幾乎沒有外出，步數低於 500 步。建議播放輕快音樂，鼓勵在房屋內做簡單運動或到附近公園散步。',
        action: '播放音樂',
        priority: SuggestionPriority.high,
      ),
      AiSuggestion(
        icon: Icons.favorite_rounded,
        title: '心率波動異常',
        description: '今日上午 10:00 監測到心率達 125 BPM，高於平時水平。建議視訊確認 $elderName 是否有不適，或剛進行過劇烈活動。',
        action: '視訊確認',
        priority: SuggestionPriority.medium,
      ),
      AiSuggestion(
        icon: Icons.psychology_rounded,
        title: '情緒焦慮持續',
        description: '$elderName 近期多次出現焦慮情緒，可能有煩心事未解決。建議主動關心問候，給予情感支持和傾聽。',
        action: '發送關心',
        priority: SuggestionPriority.medium,
      ),
      AiSuggestion(
        icon: Icons.emoji_events_rounded,
        title: '整體狀況良好',
        description: '$elderName 本週各項健康指標表現穩定，情緒愉悅，活動量適中。繼續保持良好的生活習慣和互動頻率！',
        action: '查看報告',
        priority: SuggestionPriority.low,
      ),
    ];

    // 隨機返回 2-4 條建議
    final random = Random();
    final count = 2 + random.nextInt(3);
    suggestions.shuffle();
    return suggestions.take(count).toList();
  }

  /// 優先級數值映射（用於排序）
  static int _priorityValue(SuggestionPriority priority) {
    switch (priority) {
      case SuggestionPriority.high:
        return 3;
      case SuggestionPriority.medium:
        return 2;
      case SuggestionPriority.low:
        return 1;
    }
  }
}

/// AI 建議數據模型
class AiSuggestion {
  final IconData icon;
  final String title;
  final String description;
  final String action;
  final SuggestionPriority priority;

  AiSuggestion({
    required this.icon,
    required this.title,
    required this.description,
    required this.action,
    required this.priority,
  });

  /// 轉換為 Map（用於兼容現有代碼）
  Map<String, dynamic> toMap() {
    return {
      'icon': icon,
      'title': title,
      'description': description,
      'action': action,
      'priority': priority.name,
    };
  }

  /// 从 Map 创建（用于反序列化）
  factory AiSuggestion.fromMap(Map<String, dynamic> map) {
    return AiSuggestion(
      icon: map['icon'] as IconData,
      title: map['title'] as String,
      description: map['description'] as String,
      action: map['action'] as String,
      priority: SuggestionPriority.values.firstWhere(
        (p) => p.name == map['priority'],
        orElse: () => SuggestionPriority.medium,
      ),
    );
  }
}

/// 建議優先級枚舉
enum SuggestionPriority {
  high,
  medium,
  low,
}
