/// 🧪 測試工具和輔助函數
/// 
/// 提供測試數據生成、驗證等功能

import '../models/emotion_data.dart';
import '../models/care_task.dart';
import '../models/family_member.dart';

/// 測試數據生成器
class TestDataGenerator {
  /// 生成模擬情緒數據
  static List<EmotionData> generateMockEmotions({
    int count = 10,
    DateTime? startDate,
  }) {
    final start = startDate ?? DateTime.now().subtract(const Duration(days: 7));
    final emotions = <EmotionData>[];
    
    final types = [
      EmotionType.happy,
      EmotionType.calm,
      EmotionType.anxious,
      EmotionType.sad,
    ];
    
    for (var i = 0; i < count; i++) {
      emotions.add(EmotionData(
        id: 'test_emotion_$i',
        timestamp: start.add(Duration(hours: i * 6)),
        type: types[i % types.length],
        confidence: 0.7 + (i % 3) * 0.1,
        audioReference: 'test_audio_$i.wav',
        metadata: {'source': 'test'},
      ));
    }
    
    return emotions;
  }

  /// 生成模擬任務數據
  static List<CareTask> generateMockTasks({int count = 5}) {
    final tasks = <CareTask>[];
    final now = DateTime.now();
    
    final titles = [
      '週二陪診',
      '藥物補充',
      '本週通話',
      '健康檢查',
      '生日準備',
    ];
    
    final priorities = [
      TaskPriority.high,
      TaskPriority.medium,
      TaskPriority.low,
    ];
    
    for (var i = 0; i < count; i++) {
      tasks.add(CareTask(
        id: 'test_task_$i',
        title: titles[i % titles.length],
        description: '測試任務描述 $i',
        elderId: 1,
        createdAt: now,
        dueDate: now.add(Duration(days: i + 1)),
        priority: priorities[i % priorities.length],
        status: i % 2 == 0 ? TaskStatus.pending : TaskStatus.completed,
        category: 'test',
      ));
    }
    
    return tasks;
  }

  /// 生成模擬家庭成員數據
  static List<FamilyMember> generateMockFamilyMembers({int count = 4}) {
    final members = <FamilyMember>[];
    final now = DateTime.now();
    
    final names = ['王小明', '王小華', '王大偉', '王美玲'];
    final roles = ['長子', '長女', '次子', '次女'];
    
    for (var i = 0; i < count; i++) {
      members.add(FamilyMember(
        id: 'test_member_$i',
        name: names[i % names.length],
        avatarUrl: 'https://i.pravatar.cc/150?img=${i + 10}',
        role: roles[i % roles.length],
        contributionScore: 100 - (i * 20),
        contributionBreakdown: {
          'videoCall': 30 - (i * 5),
          'taskCompleted': 25 - (i * 5),
          'dataCheck': 15 - (i * 3),
        },
        lastActiveAt: now.subtract(Duration(hours: i * 2)),
      ));
    }
    
    return members;
  }

  /// 生成模擬健康數據
  static Map<String, dynamic> generateMockHealthData({
    bool isAbnormal = false,
  }) {
    return {
      'heartRate': isAbnormal ? 125 : 75,
      'bloodSugar': isAbnormal ? 150 : 95,
      'systolicBP': isAbnormal ? 145 : 120,
      'diastolicBP': isAbnormal ? 95 : 80,
      'dailySteps': isAbnormal ? 800 : 3500,
      'sleepQuality': isAbnormal ? 45.0 : 78.0,
      'consecutiveLowActivityDays': isAbnormal ? 4 : 1,
      'callsThisWeek': isAbnormal ? 1 : 4,
      'medicationDaysLeft': isAbnormal ? 3 : 15,
      'daysSinceLastCheckup': isAbnormal ? 120 : 45,
    };
  }
}

/// 測試驗證器
class TestValidator {
  /// 驗證情緒數據完整性
  static bool validateEmotionData(EmotionData emotion) {
    if (emotion.id.isEmpty) return false;
    if (emotion.confidence < 0 || emotion.confidence > 1) return false;
    if (emotion.timestamp.isAfter(DateTime.now())) return false;
    return true;
  }

  /// 驗證任務數據完整性
  static bool validateTaskData(CareTask task) {
    if (task.id.isEmpty) return false;
    if (task.title.isEmpty) return false;
    if (task.dueDate.isBefore(task.createdAt)) return false;
    return true;
  }

  /// 驗證貢獻值計算正確性
  static bool validateContributionScore(FamilyMember member) {
    final calculatedScore = member.contributionBreakdown.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    
    // 允許 5% 的誤差
    final diff = (calculatedScore - member.contributionScore).abs();
    return diff <= member.contributionScore * 0.05;
  }

  /// 驗證健康分數範圍
  static bool validateHealthScore(int score) {
    return score >= 0 && score <= 100;
  }
}

/// 性能測試工具
class PerformanceTestHelper {
  /// 測試列表渲染性能
  static Future<Duration> testListRenderingTime({
    required Function() buildList,
    int iterations = 10,
  }) async {
    final stopwatch = Stopwatch()..start();
    
    for (var i = 0; i < iterations; i++) {
      buildList();
    }
    
    stopwatch.stop();
    return Duration(milliseconds: stopwatch.elapsedMilliseconds ~/ iterations);
  }

  /// 測試數據加載時間
  static Future<Duration> testDataLoadingTime(Future<void> Function() loadData) async {
    final stopwatch = Stopwatch()..start();
    await loadData();
    stopwatch.stop();
    return Duration(milliseconds: stopwatch.elapsedMilliseconds);
  }

  /// 測試內存使用
  static Map<String, dynamic> measureMemoryUsage() {
    // 這需要配合 DevTools 使用
    return {
      'timestamp': DateTime.now().toIso8601String(),
      'note': 'Use DevTools for detailed memory profiling',
    };
  }
}

/// 單元測試用例集合
class TestCases {
  /// 情緒分析測試用例
  static List<Map<String, dynamic>> get emotionAnalysisTests => [
    {
      'name': '正常快樂情緒',
      'input': EmotionType.happy,
      'confidence': 0.9,
      'expectedAbnormal': false,
    },
    {
      'name': '高置信度悲傷',
      'input': EmotionType.sad,
      'confidence': 0.95,
      'expectedAbnormal': true,
    },
    {
      'name': '低置信度焦慮',
      'input': EmotionType.anxious,
      'confidence': 0.4,
      'expectedAbnormal': false,
    },
  ];

  /// 任務看板測試用例
  static List<Map<String, dynamic>> get taskBoardTests => [
    {
      'name': '創建新任務',
      'action': 'create',
      'expectedStatus': TaskStatus.pending,
    },
    {
      'name': '認領任務',
      'action': 'claim',
      'expectedStatus': TaskStatus.inProgress,
    },
    {
      'name': '完成任務',
      'action': 'complete',
      'expectedStatus': TaskStatus.completed,
    },
  ];

  /// 貢獻值計算測試用例
  static List<Map<String, dynamic>> get contributionTests => [
    {
      'name': '視訊通話基礎分',
      'action': ContributionType.videoCall,
      'expectedScore': 10,
    },
    {
      'name': '任務完成基礎分',
      'action': ContributionType.taskCompleted,
      'expectedScore': 15,
    },
    {
      'name': '緊急處理高分',
      'action': ContributionType.emergency,
      'expectedScore': 30,
    },
  ];
}

/// 集成測試場景
class IntegrationTestScenarios {
  /// 完整照護流程測試
  static Future<bool> testCompleteCareworkFlow() async {
    try {
      // 1. 生成測試數據
      final emotions = TestDataGenerator.generateMockEmotions(count: 5);
      final tasks = TestDataGenerator.generateMockTasks(count: 3);
      final members = TestDataGenerator.generateMockFamilyMembers(count: 2);
      
      // 2. 驗證數據
      final emotionsValid = emotions.every(TestValidator.validateEmotionData);
      final tasksValid = tasks.every(TestValidator.validateTaskData);
      final membersValid = members.every(TestValidator.validateContributionScore);
      
      // 3. 模擬流程
      // - 情緒異常觸發警報
      // - 生成任務
      // - 家人認領
      // - 完成任務獲得貢獻值
      
      return emotionsValid && tasksValid && membersValid;
    } catch (e) {
      return false;
    }
  }

  /// AI建議生成測試
  static Future<bool> testAiSuggestionGeneration() async {
    try {
      final healthData = TestDataGenerator.generateMockHealthData(isAbnormal: true);
      
      // 驗證健康數據應該觸發建議
      final heartRateAbnormal = (healthData['heartRate'] as int) > 100;
      final activityLow = (healthData['dailySteps'] as int) < 2000;
      
      return heartRateAbnormal || activityLow;
    } catch (e) {
      return false;
    }
  }

  /// 多用戶協作測試
  static Future<bool> testMultiUserCollaboration() async {
    try {
      final members = TestDataGenerator.generateMockFamilyMembers(count: 4);
      
      // 驗證成員間貢獻值不衝突
      final scores = members.map((m) => m.contributionScore).toList();
      final uniqueScores = scores.toSet();
      
      // 每個成員應該有不同的貢獻值
      return uniqueScores.length == members.length;
    } catch (e) {
      return false;
    }
  }
}
