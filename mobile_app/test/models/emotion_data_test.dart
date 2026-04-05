import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/models/emotion_data.dart';

/// EmotionData 模型單元測試
/// 
/// 測試覆蓋：
/// 1. 基本構造和屬性訪問
/// 2. JSON 序列化/反序列化
/// 3. copyWith 方法
/// 4. 異常情緒判斷
/// 5. 高置信度判斷
/// 6. 相等性比較
void main() {
  group('EmotionData Model Tests', () {
    // 測試數據準備
    final testTimestamp = DateTime(2024, 1, 15, 10, 30, 0);
    final testMetadata = {
      'speechRate': 120.5,
      'pitchVariance': 0.8,
      'volumeLevel': 0.6,
    };

    test('應該正確創建 EmotionData 實例', () {
      final emotion = EmotionData(
        id: 'test-001',
        elderId: 1,
        timestamp: testTimestamp,
        emotionType: EmotionType.happy,
        confidenceScore: 0.85,
        audioSnippetRef: '/audio/snippet_001.mp3',
        metadata: testMetadata,
      );

      expect(emotion.id, 'test-001');
      expect(emotion.elderId, 1);
      expect(emotion.timestamp, testTimestamp);
      expect(emotion.emotionType, EmotionType.happy);
      expect(emotion.confidenceScore, 0.85);
      expect(emotion.audioSnippetRef, '/audio/snippet_001.mp3');
      expect(emotion.metadata, testMetadata);
    });

    test('置信度分數應該在 0.0-1.0 範圍內', () {
      expect(
        () => EmotionData(
          id: 'test-002',
          elderId: 1,
          timestamp: testTimestamp,
          emotionType: EmotionType.calm,
          confidenceScore: 1.5, // 無效值
        ),
        throwsAssertionError,
      );

      expect(
        () => EmotionData(
          id: 'test-003',
          elderId: 1,
          timestamp: testTimestamp,
          emotionType: EmotionType.calm,
          confidenceScore: -0.1, // 無效值
        ),
        throwsAssertionError,
      );
    });

    test('應該正確序列化為 JSON', () {
      final emotion = EmotionData(
        id: 'test-004',
        elderId: 2,
        timestamp: testTimestamp,
        emotionType: EmotionType.anxious,
        confidenceScore: 0.72,
        audioSnippetRef: '/audio/snippet_002.mp3',
        metadata: testMetadata,
      );

      final json = emotion.toJson();

      expect(json['id'], 'test-004');
      expect(json['elderId'], 2);
      expect(json['timestamp'], testTimestamp.toIso8601String());
      expect(json['emotionType'], 'anxious');
      expect(json['confidenceScore'], 0.72);
      expect(json['audioSnippetRef'], '/audio/snippet_002.mp3');
      expect(json['metadata'], testMetadata);
    });

    test('應該正確從 JSON 反序列化', () {
      final json = {
        'id': 'test-005',
        'elderId': 3,
        'timestamp': testTimestamp.toIso8601String(),
        'emotionType': 'sad',
        'confidenceScore': 0.68,
        'audioSnippetRef': '/audio/snippet_003.mp3',
        'metadata': testMetadata,
      };

      final emotion = EmotionData.fromJson(json);

      expect(emotion.id, 'test-005');
      expect(emotion.elderId, 3);
      expect(emotion.timestamp, testTimestamp);
      expect(emotion.emotionType, EmotionType.sad);
      expect(emotion.confidenceScore, 0.68);
      expect(emotion.audioSnippetRef, '/audio/snippet_003.mp3');
      expect(emotion.metadata, testMetadata);
    });

    test('JSON 序列化/反序列化應該保持數據一致性', () {
      final original = EmotionData(
        id: 'test-006',
        elderId: 4,
        timestamp: testTimestamp,
        emotionType: EmotionType.angry,
        confidenceScore: 0.91,
        audioSnippetRef: '/audio/snippet_004.mp3',
        metadata: testMetadata,
      );

      final json = original.toJson();
      final restored = EmotionData.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.elderId, original.elderId);
      expect(restored.timestamp, original.timestamp);
      expect(restored.emotionType, original.emotionType);
      expect(restored.confidenceScore, original.confidenceScore);
      expect(restored.audioSnippetRef, original.audioSnippetRef);
      expect(restored.metadata, original.metadata);
    });

    test('copyWith 應該正確創建修改後的副本', () {
      final original = EmotionData(
        id: 'test-007',
        elderId: 5,
        timestamp: testTimestamp,
        emotionType: EmotionType.calm,
        confidenceScore: 0.75,
      );

      final modified = original.copyWith(
        emotionType: EmotionType.happy,
        confidenceScore: 0.82,
      );

      expect(modified.id, original.id); // 未修改的字段保持不變
      expect(modified.elderId, original.elderId);
      expect(modified.timestamp, original.timestamp);
      expect(modified.emotionType, EmotionType.happy); // 修改的字段
      expect(modified.confidenceScore, 0.82); // 修改的字段
    });

    test('isAbnormal 應該正確識別異常情緒', () {
      // 焦慮情緒，高置信度 -> 異常
      final anxiousEmotion = EmotionData(
        id: 'test-008',
        elderId: 1,
        timestamp: testTimestamp,
        emotionType: EmotionType.anxious,
        confidenceScore: 0.75,
      );
      expect(anxiousEmotion.isAbnormal(), true);

      // 悲傷情緒，高置信度 -> 異常
      final sadEmotion = EmotionData(
        id: 'test-009',
        elderId: 1,
        timestamp: testTimestamp,
        emotionType: EmotionType.sad,
        confidenceScore: 0.80,
      );
      expect(sadEmotion.isAbnormal(), true);

      // 生氣情緒，高置信度 -> 異常
      final angryEmotion = EmotionData(
        id: 'test-010',
        elderId: 1,
        timestamp: testTimestamp,
        emotionType: EmotionType.angry,
        confidenceScore: 0.70,
      );
      expect(angryEmotion.isAbnormal(), true);

      // 快樂情緒 -> 正常
      final happyEmotion = EmotionData(
        id: 'test-011',
        elderId: 1,
        timestamp: testTimestamp,
        emotionType: EmotionType.happy,
        confidenceScore: 0.85,
      );
      expect(happyEmotion.isAbnormal(), false);

      // 平靜情緒 -> 正常
      final calmEmotion = EmotionData(
        id: 'test-012',
        elderId: 1,
        timestamp: testTimestamp,
        emotionType: EmotionType.calm,
        confidenceScore: 0.90,
      );
      expect(calmEmotion.isAbnormal(), false);

      // 焦慮情緒但低置信度 -> 正常
      final lowConfidenceEmotion = EmotionData(
        id: 'test-013',
        elderId: 1,
        timestamp: testTimestamp,
        emotionType: EmotionType.anxious,
        confidenceScore: 0.50, // 低於默認閾值 0.6
      );
      expect(lowConfidenceEmotion.isAbnormal(), false);
    });

    test('isHighConfidence 應該正確識別高置信度記錄', () {
      final highConfidence = EmotionData(
        id: 'test-014',
        elderId: 1,
        timestamp: testTimestamp,
        emotionType: EmotionType.happy,
        confidenceScore: 0.85,
      );
      expect(highConfidence.isHighConfidence(), true);

      final lowConfidence = EmotionData(
        id: 'test-015',
        elderId: 1,
        timestamp: testTimestamp,
        emotionType: EmotionType.happy,
        confidenceScore: 0.65,
      );
      expect(lowConfidence.isHighConfidence(), false);

      // 自定義閾值測試
      expect(lowConfidence.isHighConfidence(threshold: 0.6), true);
    });

    test('相等性比較應該正確工作', () {
      final emotion1 = EmotionData(
        id: 'test-016',
        elderId: 1,
        timestamp: testTimestamp,
        emotionType: EmotionType.happy,
        confidenceScore: 0.85,
      );

      final emotion2 = EmotionData(
        id: 'test-016',
        elderId: 1,
        timestamp: testTimestamp,
        emotionType: EmotionType.happy,
        confidenceScore: 0.85,
      );

      final emotion3 = EmotionData(
        id: 'test-017', // 不同的 ID
        elderId: 1,
        timestamp: testTimestamp,
        emotionType: EmotionType.happy,
        confidenceScore: 0.85,
      );

      expect(emotion1 == emotion2, true);
      expect(emotion1 == emotion3, false);
    });
  });

  group('EmotionType Tests', () {
    test('EmotionType 應該有正確的顯示名稱', () {
      expect(EmotionType.happy.displayName, '快樂');
      expect(EmotionType.calm.displayName, '平靜');
      expect(EmotionType.anxious.displayName, '焦慮');
      expect(EmotionType.sad.displayName, '悲傷');
      expect(EmotionType.angry.displayName, '生氣');
    });

    test('EmotionType 應該正確轉換為字符串', () {
      expect(EmotionType.happy.value, 'happy');
      expect(EmotionType.calm.value, 'calm');
      expect(EmotionType.anxious.value, 'anxious');
      expect(EmotionType.sad.value, 'sad');
      expect(EmotionType.angry.value, 'angry');
    });

    test('應該正確從字符串解析 EmotionType', () {
      expect(EmotionTypeExtension.fromString('happy'), EmotionType.happy);
      expect(EmotionTypeExtension.fromString('calm'), EmotionType.calm);
      expect(EmotionTypeExtension.fromString('anxious'), EmotionType.anxious);
      expect(EmotionTypeExtension.fromString('sad'), EmotionType.sad);
      expect(EmotionTypeExtension.fromString('angry'), EmotionType.angry);
    });

    test('無效字符串應該返回默認值 calm', () {
      expect(EmotionTypeExtension.fromString('invalid'), EmotionType.calm);
      expect(EmotionTypeExtension.fromString(''), EmotionType.calm);
    });
  });
}
