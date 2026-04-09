import 'package:flutter/foundation.dart';

/// 情緒類型枚舉
/// 
/// 定義五種基本情緒類型，用於情緒識別和分類
/// - happy: 快樂/開心的情緒狀態
/// - calm: 平靜/放鬆的情緒狀態
/// - anxious: 焦慮/緊張的情緒狀態
/// - sad: 悲傷/低落的情緒狀態
/// - angry: 生氣/憤怒的情緒狀態
enum EmotionType {
  happy,
  calm,
  anxious,
  sad,
  angry,
}

/// 情緒類型擴展方法
/// 
/// 提供情緒類型的顯示名稱和顏色標識等輔助功能
extension EmotionTypeExtension on EmotionType {
  /// 獲取情緒類型的中文顯示名稱
  String get displayName {
    switch (this) {
      case EmotionType.happy:
        return '快樂';
      case EmotionType.calm:
        return '平靜';
      case EmotionType.anxious:
        return '焦慮';
      case EmotionType.sad:
        return '悲傷';
      case EmotionType.angry:
        return '生氣';
    }
  }

  /// 獲取情緒類型的英文名稱（用於序列化）
  String get value => toString().split('.').last;

  /// 從字符串解析情緒類型
  static EmotionType fromString(String value) {
    return EmotionType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => EmotionType.calm,
    );
  }
}

/// 情緒數據模型
/// 
/// 核心設計理念：
/// 1. 時序性：每個情緒記錄都有準確的時間戳，支持歷史追蹤和趨勢分析
/// 2. 置信度：記錄AI識別的信心程度，用於過濾低質量數據
/// 3. 可追溯性：通過audioSnippetRef可以回溯到原始音頻片段
/// 4. 擴展性：metadata支持存儲額外的分析數據（如語速、音調變化等）
/// 5. 關聯性：通過elderId關聯到特定長者，支持多用戶場景
/// 
/// 數據存儲策略：
/// - 本地存儲：使用Hive進行高效本地緩存，支持離線查詢
/// - 雲端同步：通過Firebase Firestore實現多設備同步和備份
/// - 數據清理：建議定期歸檔超過3個月的歷史數據
@immutable
class EmotionData {
  /// 唯一標識符
  /// 格式建議：UUID或時間戳+隨機數，確保跨設備唯一性
  final String id;

  /// 關聯的長者ID
  /// 用於多用戶場景下區分不同長者的情緒數據
  final int elderId;

  /// 記錄時間戳
  /// 記錄情緒數據的準確時間，用於時序分析和趨勢圖表
  final DateTime timestamp;

  /// 情緒類型
  /// 識別出的情緒分類（快樂、平靜、焦慮、悲傷、生氣）
  final EmotionType emotionType;

  /// 置信度分數
  /// 範圍：0.0 - 1.0
  /// - 0.0-0.5: 低置信度，建議人工複核
  /// - 0.5-0.7: 中等置信度，可作為參考
  /// - 0.7-1.0: 高置信度，可直接使用
  final double confidenceScore;

  /// 音頻片段引用（可選）
  /// 存儲音頻文件的路徑或URL，用於回溯和人工複核
  /// 格式建議：本地路徑或雲端存儲URL
  final String? audioSnippetRef;

  /// 元數據（可選）
  /// 存儲額外的分析信息，例如：
  /// - speechRate: 語速（字/分鐘）
  /// - pitchVariance: 音調變化幅度
  /// - volumeLevel: 音量等級
  /// - pauseDuration: 停頓時長
  /// - detectionMethod: 檢測方法（AI模型版本）
  /// - contextInfo: 上下文信息（對話內容摘要等）
  final Map<String, dynamic>? metadata;

  /// 構造函數
  const EmotionData({
    required this.id,
    required this.elderId,
    required this.timestamp,
    required this.emotionType,
    required this.confidenceScore,
    this.audioSnippetRef,
    this.metadata,
  }) : assert(confidenceScore >= 0.0 && confidenceScore <= 1.0,
            'confidenceScore must be between 0.0 and 1.0');

  /// 從JSON反序列化
  /// 
  /// 用於從本地存儲或網絡API讀取數據
  factory EmotionData.fromJson(Map<String, dynamic> json) {
    return EmotionData(
      id: json['id'] as String,
      elderId: json['elderId'] as int,
      timestamp: DateTime.parse(json['timestamp'] as String),
      emotionType: EmotionTypeExtension.fromString(json['emotionType'] as String),
      confidenceScore: (json['confidenceScore'] as num).toDouble(),
      audioSnippetRef: json['audioSnippetRef'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  /// 轉換為JSON
  /// 
  /// 用於存儲到本地數據庫或發送到網絡API
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'elderId': elderId,
      'timestamp': timestamp.toIso8601String(),
      'emotionType': emotionType.value,
      'confidenceScore': confidenceScore,
      'audioSnippetRef': audioSnippetRef,
      'metadata': metadata,
    };
  }

  /// 複製並修改部分字段
  /// 
  /// 用於創建修改後的副本，保持不可變性
  EmotionData copyWith({
    String? id,
    int? elderId,
    DateTime? timestamp,
    EmotionType? emotionType,
    double? confidenceScore,
    String? audioSnippetRef,
    Map<String, dynamic>? metadata,
  }) {
    return EmotionData(
      id: id ?? this.id,
      elderId: elderId ?? this.elderId,
      timestamp: timestamp ?? this.timestamp,
      emotionType: emotionType ?? this.emotionType,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      audioSnippetRef: audioSnippetRef ?? this.audioSnippetRef,
      metadata: metadata ?? this.metadata,
    );
  }

  /// 便捷屬性：情緒類型別名（為了向後兼容）
  EmotionType get type => emotionType;

  /// 便捷屬性：置信度別名（為了向後兼容）
  double get confidence => confidenceScore;

  /// 便捷屬性：音頻片段引用別名（為了向後兼容）
  String? get audioReference => audioSnippetRef;

  /// 判斷是否為異常情緒
  /// 
  /// 異常情緒定義：
  /// - 焦慮、悲傷、生氣等負面情緒
  /// - 置信度大於閾值（默認0.6）
  /// 
  /// 返回true表示該情緒記錄需要關注
  bool get isAbnormal {
    if (confidenceScore < 0.6) {
      return false;
    }
    return emotionType == EmotionType.anxious ||
        emotionType == EmotionType.sad ||
        emotionType == EmotionType.angry;
  }

  /// 是否為異常情緒（可自訂置信度閾值）
  bool isAbnormalWithThreshold({double confidenceThreshold = 0.6}) {
    if (confidenceScore < confidenceThreshold) {
      return false;
    }
    return emotionType == EmotionType.anxious ||
        emotionType == EmotionType.sad ||
        emotionType == EmotionType.angry;
  }

  /// 判斷是否為高置信度記錄
  /// 
  /// 高置信度閾值默認為0.7
  bool get isHighConfidence => confidenceScore >= 0.7;

  /// 是否為高置信度記錄（可自訂閾值）
  bool isHighConfidenceWithThreshold({double threshold = 0.7}) {
    return confidenceScore >= threshold;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is EmotionData &&
        other.id == id &&
        other.elderId == elderId &&
        other.timestamp == timestamp &&
        other.emotionType == emotionType &&
        other.confidenceScore == confidenceScore &&
        other.audioSnippetRef == audioSnippetRef &&
        mapEquals(other.metadata, metadata);
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      elderId,
      timestamp,
      emotionType,
      confidenceScore,
      audioSnippetRef,
      metadata,
    );
  }

  @override
  String toString() {
    return 'EmotionData(id: $id, elderId: $elderId, timestamp: $timestamp, '
        'emotionType: ${emotionType.displayName}, confidenceScore: $confidenceScore, '
        'audioSnippetRef: $audioSnippetRef, metadata: $metadata)';
  }
}
