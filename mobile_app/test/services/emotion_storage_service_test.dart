import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_1/models/emotion_data.dart';
import 'package:flutter_application_1/services/emotion_storage_service.dart';

/// EmotionStorageService 服務單元測試
/// 
/// 測試覆蓋：
/// 1. 服務初始化
/// 2. 儲存和讀取情緒數據
/// 3. 按日期查詢
/// 4. 按日期範圍查詢
/// 5. 異常情緒篩選
/// 6. 統計功能
/// 7. 導入/導出功能
/// 8. 刪除和清空功能
void main() {
  group('EmotionStorageService Tests', () {
    late EmotionStorageService service;

    setUp(() async {
      // 每個測試前重置 SharedPreferences
      SharedPreferences.setMockInitialValues({});
      service = EmotionStorageService();
      await service.initialize();
    });

    test('應該正確初始化服務', () async {
      final newService = EmotionStorageService();
      await newService.initialize();
      // 如果初始化成功，不應拋出異常
      expect(newService, isNotNull);
    });

    test('未初始化時應拋出異常', () async {
      final uninitializedService = EmotionStorageService();
      
      // saveEmotion 會捕獲異常並返回 false，而不是拋出異常
      final result = await uninitializedService.saveEmotion(
        EmotionData(
          id: 'test-001',
          elderId: 1,
          timestamp: DateTime.now(),
          emotionType: EmotionType.happy,
          confidenceScore: 0.8,
        ),
      );
      
      expect(result, false);
    });

    test('應該成功儲存情緒數據', () async {
      final emotion = EmotionData(
        id: 'test-001',
        elderId: 1,
        timestamp: DateTime.now(),
        emotionType: EmotionType.happy,
        confidenceScore: 0.85,
      );

      final result = await service.saveEmotion(emotion);
      expect(result, true);
    });

    test('應該成功更新已存在的情緒數據', () async {
      final emotion1 = EmotionData(
        id: 'test-002',
        elderId: 1,
        timestamp: DateTime.now(),
        emotionType: EmotionType.happy,
        confidenceScore: 0.75,
      );

      await service.saveEmotion(emotion1);

      // 更新相同ID的記錄
      final emotion2 = emotion1.copyWith(
        emotionType: EmotionType.calm,
        confidenceScore: 0.85,
      );

      final result = await service.saveEmotion(emotion2);
      expect(result, true);

      // 驗證數據已更新
      final emotions = await service.getEmotionsByDate(DateTime.now(), elderId: 1);
      expect(emotions.length, 1);
      expect(emotions[0].emotionType, EmotionType.calm);
      expect(emotions[0].confidenceScore, 0.85);
    });

    test('應該按日期正確查詢情緒數據', () async {
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));

      // 儲存今天的數據
      await service.saveEmotion(EmotionData(
        id: 'today-001',
        elderId: 1,
        timestamp: today,
        emotionType: EmotionType.happy,
        confidenceScore: 0.8,
      ));

      // 儲存昨天的數據
      await service.saveEmotion(EmotionData(
        id: 'yesterday-001',
        elderId: 1,
        timestamp: yesterday,
        emotionType: EmotionType.calm,
        confidenceScore: 0.75,
      ));

      // 查詢今天的數據
      final todayEmotions = await service.getEmotionsByDate(today, elderId: 1);
      expect(todayEmotions.length, 1);
      expect(todayEmotions[0].id, 'today-001');

      // 查詢昨天的數據
      final yesterdayEmotions = await service.getEmotionsByDate(yesterday, elderId: 1);
      expect(yesterdayEmotions.length, 1);
      expect(yesterdayEmotions[0].id, 'yesterday-001');
    });

    test('應該按日期範圍正確查詢情緒數據', () async {
      final today = DateTime.now();
      final threeDaysAgo = today.subtract(const Duration(days: 3));
      final sevenDaysAgo = today.subtract(const Duration(days: 7));

      // 儲存不同日期的數據
      await service.saveEmotion(EmotionData(
        id: 'recent-001',
        elderId: 1,
        timestamp: today,
        emotionType: EmotionType.happy,
        confidenceScore: 0.8,
      ));

      await service.saveEmotion(EmotionData(
        id: 'recent-002',
        elderId: 1,
        timestamp: threeDaysAgo,
        emotionType: EmotionType.calm,
        confidenceScore: 0.75,
      ));

      await service.saveEmotion(EmotionData(
        id: 'old-001',
        elderId: 1,
        timestamp: sevenDaysAgo,
        emotionType: EmotionType.anxious,
        confidenceScore: 0.7,
      ));

      // 查詢最近5天的數據
      final recentEmotions = await service.getEmotionsByDateRange(
        today.subtract(const Duration(days: 5)),
        today,
        elderId: 1,
      );

      expect(recentEmotions.length, 2);
      expect(recentEmotions.any((e) => e.id == 'recent-001'), true);
      expect(recentEmotions.any((e) => e.id == 'recent-002'), true);
      expect(recentEmotions.any((e) => e.id == 'old-001'), false);
    });

    test('應該正確篩選異常情緒', () async {
      final now = DateTime.now();

      // 儲存各種情緒
      await service.saveEmotion(EmotionData(
        id: 'normal-001',
        elderId: 1,
        timestamp: now,
        emotionType: EmotionType.happy,
        confidenceScore: 0.85,
      ));

      await service.saveEmotion(EmotionData(
        id: 'abnormal-001',
        elderId: 1,
        timestamp: now,
        emotionType: EmotionType.anxious,
        confidenceScore: 0.75,
      ));

      await service.saveEmotion(EmotionData(
        id: 'abnormal-002',
        elderId: 1,
        timestamp: now,
        emotionType: EmotionType.sad,
        confidenceScore: 0.80,
      ));

      await service.saveEmotion(EmotionData(
        id: 'low-confidence',
        elderId: 1,
        timestamp: now,
        emotionType: EmotionType.angry,
        confidenceScore: 0.50, // 低置信度
      ));

      // 查詢異常情緒（默認閾值 0.6）
      final abnormalEmotions = await service.getAbnormalEmotions(
        elderId: 1,
      );

      expect(abnormalEmotions.length, 2);
      expect(abnormalEmotions.any((e) => e.id == 'abnormal-001'), true);
      expect(abnormalEmotions.any((e) => e.id == 'abnormal-002'), true);
      expect(abnormalEmotions.any((e) => e.id == 'normal-001'), false);
      expect(abnormalEmotions.any((e) => e.id == 'low-confidence'), false);
    });

    test('應該正確按長者ID過濾數據', () async {
      final now = DateTime.now();

      // 儲存不同長者的數據
      await service.saveEmotion(EmotionData(
        id: 'elder1-001',
        elderId: 1,
        timestamp: now,
        emotionType: EmotionType.happy,
        confidenceScore: 0.8,
      ));

      await service.saveEmotion(EmotionData(
        id: 'elder2-001',
        elderId: 2,
        timestamp: now,
        emotionType: EmotionType.calm,
        confidenceScore: 0.75,
      ));

      // 查詢長者1的數據
      final elder1Emotions = await service.getEmotionsByDate(now, elderId: 1);
      expect(elder1Emotions.length, 1);
      expect(elder1Emotions[0].elderId, 1);

      // 查詢長者2的數據
      final elder2Emotions = await service.getEmotionsByDate(now, elderId: 2);
      expect(elder2Emotions.length, 1);
      expect(elder2Emotions[0].elderId, 2);
    });

    test('應該正確生成情緒統計數據', () async {
      final today = DateTime.now();

      // 儲存多個情緒數據
      await service.saveEmotion(EmotionData(
        id: 'stat-001',
        elderId: 1,
        timestamp: today,
        emotionType: EmotionType.happy,
        confidenceScore: 0.8,
      ));

      await service.saveEmotion(EmotionData(
        id: 'stat-002',
        elderId: 1,
        timestamp: today,
        emotionType: EmotionType.happy,
        confidenceScore: 0.85,
      ));

      await service.saveEmotion(EmotionData(
        id: 'stat-003',
        elderId: 1,
        timestamp: today,
        emotionType: EmotionType.calm,
        confidenceScore: 0.75,
      ));

      await service.saveEmotion(EmotionData(
        id: 'stat-004',
        elderId: 1,
        timestamp: today,
        emotionType: EmotionType.anxious,
        confidenceScore: 0.7,
      ));

      // 獲取統計數據
      final statistics = await service.getEmotionStatistics(
        today,
        today,
        elderId: 1,
      );

      expect(statistics[EmotionType.happy], 2);
      expect(statistics[EmotionType.calm], 1);
      expect(statistics[EmotionType.anxious], 1);
      expect(statistics[EmotionType.sad], 0);
      expect(statistics[EmotionType.angry], 0);
    });

    test('應該成功刪除指定的情緒記錄', () async {
      final emotion = EmotionData(
        id: 'delete-001',
        elderId: 1,
        timestamp: DateTime.now(),
        emotionType: EmotionType.happy,
        confidenceScore: 0.8,
      );

      await service.saveEmotion(emotion);

      // 刪除記錄
      final result = await service.deleteEmotion('delete-001');
      expect(result, true);

      // 驗證已刪除
      final emotions = await service.getEmotionsByDate(DateTime.now(), elderId: 1);
      expect(emotions.isEmpty, true);
    });

    test('應該正確處理刪除不存在的記錄', () async {
      final result = await service.deleteEmotion('non-existent');
      expect(result, false);
    });

    test('應該成功清空所有數據', () async {
      final now = DateTime.now();

      // 儲存多筆數據
      await service.saveEmotion(EmotionData(
        id: 'clear-001',
        elderId: 1,
        timestamp: now,
        emotionType: EmotionType.happy,
        confidenceScore: 0.8,
      ));

      await service.saveEmotion(EmotionData(
        id: 'clear-002',
        elderId: 1,
        timestamp: now,
        emotionType: EmotionType.calm,
        confidenceScore: 0.75,
      ));

      // 清空數據
      final result = await service.clearAllEmotions();
      expect(result, true);

      // 驗證已清空
      final emotions = await service.getEmotionsByDate(now, elderId: 1);
      expect(emotions.isEmpty, true);
    });

    test('應該成功導出數據為 JSON', () async {
      final now = DateTime.now();

      await service.saveEmotion(EmotionData(
        id: 'export-001',
        elderId: 1,
        timestamp: now,
        emotionType: EmotionType.happy,
        confidenceScore: 0.8,
      ));

      final jsonString = await service.exportEmotionsAsJson();
      expect(jsonString, isNotEmpty);
      expect(jsonString.contains('export-001'), true);
      expect(jsonString.contains('happy'), true);
    });

    test('應該成功從 JSON 導入數據', () async {
      final now = DateTime.now();
      final emotion = EmotionData(
        id: 'import-001',
        elderId: 1,
        timestamp: now,
        emotionType: EmotionType.happy,
        confidenceScore: 0.8,
      );

      final jsonString = '[${emotion.toJson()}]'.replaceAll('(', '{').replaceAll(')', '}');
      
      // 構建正確的 JSON
      final correctJsonString = '''
      [{
        "id": "import-001",
        "elderId": 1,
        "timestamp": "${now.toIso8601String()}",
        "emotionType": "happy",
        "confidenceScore": 0.8,
        "audioSnippetRef": null,
        "metadata": null
      }]
      ''';

      final count = await service.importEmotionsFromJson(
        correctJsonString,
        mergeWithExisting: false,
      );

      expect(count, 1);

      // 驗證數據已導入
      final emotions = await service.getEmotionsByDate(now, elderId: 1);
      expect(emotions.length, 1);
      expect(emotions[0].id, 'import-001');
    });

    test('導入時應該正確處理合併模式', () async {
      final now = DateTime.now();

      // 先儲存一筆數據
      await service.saveEmotion(EmotionData(
        id: 'existing-001',
        elderId: 1,
        timestamp: now,
        emotionType: EmotionType.happy,
        confidenceScore: 0.8,
      ));

      // 導入新數據（合併模式）
      final importJson = '''
      [{
        "id": "import-002",
        "elderId": 1,
        "timestamp": "${now.toIso8601String()}",
        "emotionType": "calm",
        "confidenceScore": 0.75,
        "audioSnippetRef": null,
        "metadata": null
      }]
      ''';

      final count = await service.importEmotionsFromJson(
        importJson,
        mergeWithExisting: true,
      );

      expect(count, 1);

      // 驗證兩筆數據都存在
      final emotions = await service.getEmotionsByDate(now, elderId: 1);
      expect(emotions.length, 2);
    });

    test('批量儲存應該正確處理多筆數據', () async {
      final now = DateTime.now();
      final emotions = [
        EmotionData(
          id: 'batch-001',
          elderId: 1,
          timestamp: now,
          emotionType: EmotionType.happy,
          confidenceScore: 0.8,
        ),
        EmotionData(
          id: 'batch-002',
          elderId: 1,
          timestamp: now,
          emotionType: EmotionType.calm,
          confidenceScore: 0.75,
        ),
        EmotionData(
          id: 'batch-003',
          elderId: 1,
          timestamp: now,
          emotionType: EmotionType.anxious,
          confidenceScore: 0.7,
        ),
      ];

      final count = await service.saveEmotions(emotions);
      expect(count, 3);

      // 驗證數據已儲存
      final savedEmotions = await service.getEmotionsByDate(now, elderId: 1);
      expect(savedEmotions.length, 3);
    });
  });
}
