import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/emotion_data.dart';

/// 情緒數據存儲服務
/// 
/// 核心設計理念：
/// 1. 雙層存儲架構：本地存儲（快速訪問）+ 雲端存儲（數據備份同步）
/// 2. 離線優先：本地操作不依賴網絡，支持離線場景
/// 3. 懶加載：按需加載數據，避免一次性載入大量歷史記錄
/// 4. 數據分層：熱數據（近期）本地緩存，冷數據（歷史）雲端存儲
/// 
/// 存儲策略：
/// - 本地存儲使用 SharedPreferences（輕量級）或 Hive（高性能）
/// - 雲端使用 Firebase Firestore（未來擴展）
/// - 定期同步：後台同步本地數據到雲端
/// - 數據清理：本地保留最近30天，雲端永久保存
class EmotionStorageService {
  static const String _storageKey = 'emotion_data_storage';

  
  /// SharedPreferences實例
  SharedPreferences? _prefs;

  /// 是否啟用雲端同步（未來擴展）
  final bool enableCloudSync;

  /// 構造函數
  EmotionStorageService({this.enableCloudSync = false});

  /// 初始化服務
  /// 
  /// 必須在使用服務前調用此方法
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// 確保已初始化
  void _ensureInitialized() {
    if (_prefs == null) {
      throw StateError(
        'EmotionStorageService not initialized. Call initialize() first.',
      );
    }
  }

  /// 儲存情緒數據
  /// 
  /// 存儲流程：
  /// 1. 驗證數據有效性
  /// 2. 序列化為JSON
  /// 3. 存儲到本地
  /// 4. 如果啟用雲端同步，異步上傳到Firestore
  /// 
  /// 參數：
  /// - emotion: 要保存的情緒數據
  /// 
  /// 返回：
  /// - true: 保存成功
  /// - false: 保存失敗
  Future<bool> saveEmotion(EmotionData emotion) async {
    try {
      _ensureInitialized();

      // 獲取現有數據
      final List<EmotionData> existingData = await _getAllEmotions();

      // 檢查是否已存在相同ID的記錄
      final existingIndex = existingData.indexWhere((e) => e.id == emotion.id);
      if (existingIndex != -1) {
        // 更新現有記錄
        existingData[existingIndex] = emotion;
      } else {
        // 添加新記錄
        existingData.add(emotion);
      }

      // 按時間戳排序（最新的在前）
      existingData.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      // 序列化並保存
      final jsonList = existingData.map((e) => e.toJson()).toList();
      final jsonString = jsonEncode(jsonList);
      final success = await _prefs!.setString(_storageKey, jsonString);

      // 如果啟用雲端同步，異步上傳（未來實現）
      if (enableCloudSync && success) {
        _syncToCloud(emotion);
      }

      return success;
    } catch (e) {
      debugPrint('Error saving emotion data: $e');
      return false;
    }
  }

  /// 批量儲存情緒數據
  /// 
  /// 用於批量導入或同步場景
  /// 
  /// 參數：
  /// - emotions: 要保存的情緒數據列表
  /// 
  /// 返回：成功保存的記錄數量
  Future<int> saveEmotions(List<EmotionData> emotions) async {
    try {
      _ensureInitialized();

      int successCount = 0;
      for (final emotion in emotions) {
        final success = await saveEmotion(emotion);
        if (success) successCount++;
      }

      return successCount;
    } catch (e) {
      debugPrint('Error saving emotions batch: $e');
      return 0;
    }
  }

  /// 獲取所有情緒數據（內部使用）
  Future<List<EmotionData>> _getAllEmotions() async {
    try {
      _ensureInitialized();

      final jsonString = _prefs!.getString(_storageKey);
      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }

      final jsonList = jsonDecode(jsonString) as List<dynamic>;
      return jsonList
          .map((json) => EmotionData.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error loading all emotions: $e');
      return [];
    }
  }

  /// 獲取某日的情緒數據
  /// 
  /// 查詢指定日期（00:00:00 - 23:59:59）的所有情緒記錄
  /// 
  /// 參數：
  /// - date: 要查詢的日期
  /// - elderId: 可選的長者ID過濾
  /// 
  /// 返回：符合條件的情緒數據列表，按時間戳降序排列
  Future<List<EmotionData>> getEmotionsByDate(
    DateTime date, {
    int? elderId,
  }) async {
    try {
      _ensureInitialized();

      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final allEmotions = await _getAllEmotions();

      return allEmotions.where((emotion) {
        // 時間範圍過濾
        final isInDateRange = emotion.timestamp.isAfter(startOfDay) &&
            emotion.timestamp.isBefore(endOfDay);

        // 長者ID過濾（如果指定）
        final matchesElder = elderId == null || emotion.elderId == elderId;

        return isInDateRange && matchesElder;
      }).toList();
    } catch (e) {
      debugPrint('Error getting emotions by date: $e');
      return [];
    }
  }

  /// 獲取日期範圍內的情緒數據
  /// 
  /// 查詢指定日期範圍內的所有情緒記錄
  /// 適用於：
  /// - 生成週報、月報
  /// - 趨勢分析
  /// - 統計圖表數據
  /// 
  /// 參數：
  /// - startDate: 開始日期（包含）
  /// - endDate: 結束日期（包含）
  /// - elderId: 可選的長者ID過濾
  /// 
  /// 返回：符合條件的情緒數據列表，按時間戳降序排列
  Future<List<EmotionData>> getEmotionsByDateRange(
    DateTime startDate,
    DateTime endDate, {
    int? elderId,
  }) async {
    try {
      _ensureInitialized();

      // 確保 startDate 是當天開始時間
      final start = DateTime(startDate.year, startDate.month, startDate.day);
      // 確保 endDate 是當天結束時間
      final end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);

      final allEmotions = await _getAllEmotions();

      return allEmotions.where((emotion) {
        // 時間範圍過濾
        final isInDateRange = emotion.timestamp.isAfter(start) &&
            emotion.timestamp.isBefore(end.add(const Duration(seconds: 1)));

        // 長者ID過濾（如果指定）
        final matchesElder = elderId == null || emotion.elderId == elderId;

        return isInDateRange && matchesElder;
      }).toList();
    } catch (e) {
      debugPrint('Error getting emotions by date range: $e');
      return [];
    }
  }

  /// 獲取異常情緒記錄
  /// 
  /// 異常情緒定義：
  /// - 情緒類型為：焦慮、悲傷、生氣
  /// - 置信度 >= confidenceThreshold
  /// 
  /// 用途：
  /// - 警報系統：檢測需要關注的情緒狀態
  /// - 健康監測：追蹤長者的心理健康狀況
  /// - 親屬通知：當檢測到異常情緒時發送通知
  /// 
  /// 參數：
  /// - elderId: 可選的長者ID過濾
  /// - startDate: 可選的開始日期
  /// - endDate: 可選的結束日期
  /// - confidenceThreshold: 置信度閾值（默認0.6）
  /// - limit: 返回結果數量限制（默認100）
  /// 
  /// 返回：異常情緒記錄列表，按時間戳降序排列
  Future<List<EmotionData>> getAbnormalEmotions({
    int? elderId,
    DateTime? startDate,
    DateTime? endDate,
    double confidenceThreshold = 0.6,
    int limit = 100,
  }) async {
    try {
      _ensureInitialized();

      List<EmotionData> allEmotions = await _getAllEmotions();

      // 應用過濾條件
      final filtered = allEmotions.where((emotion) {
        // 檢查是否為異常情緒
        if (!emotion.isAbnormalWithThreshold(confidenceThreshold: confidenceThreshold)) {
          return false;
        }

        // 長者ID過濾
        if (elderId != null && emotion.elderId != elderId) {
          return false;
        }

        // 日期範圍過濾
        if (startDate != null && emotion.timestamp.isBefore(startDate)) {
          return false;
        }
        if (endDate != null && emotion.timestamp.isAfter(endDate)) {
          return false;
        }

        return true;
      }).toList();

      // 限制返回數量
      if (filtered.length > limit) {
        return filtered.sublist(0, limit);
      }

      return filtered;
    } catch (e) {
      debugPrint('Error getting abnormal emotions: $e');
      return [];
    }
  }

  /// 刪除指定ID的情緒記錄
  /// 
  /// 參數：
  /// - id: 要刪除的情緒記錄ID
  /// 
  /// 返回：
  /// - true: 刪除成功
  /// - false: 刪除失敗或記錄不存在
  Future<bool> deleteEmotion(String id) async {
    try {
      _ensureInitialized();

      final allEmotions = await _getAllEmotions();
      final initialLength = allEmotions.length;

      // 移除指定ID的記錄
      allEmotions.removeWhere((emotion) => emotion.id == id);

      // 如果沒有變化，說明記錄不存在
      if (allEmotions.length == initialLength) {
        return false;
      }

      // 保存更新後的數據
      final jsonList = allEmotions.map((e) => e.toJson()).toList();
      final jsonString = jsonEncode(jsonList);
      return await _prefs!.setString(_storageKey, jsonString);
    } catch (e) {
      debugPrint('Error deleting emotion: $e');
      return false;
    }
  }

  /// 清空所有情緒數據
  /// 
  /// 警告：此操作不可逆！
  /// 建議在執行前先導出數據備份
  /// 
  /// 返回：
  /// - true: 清空成功
  /// - false: 清空失敗
  Future<bool> clearAllEmotions() async {
    try {
      _ensureInitialized();
      return await _prefs!.remove(_storageKey);
    } catch (e) {
      debugPrint('Error clearing emotions: $e');
      return false;
    }
  }

  /// 獲取情緒統計數據
  /// 
  /// 統計指定日期範圍內各種情緒的分佈情況
  /// 
  /// 參數：
  /// - startDate: 開始日期
  /// - endDate: 結束日期
  /// - elderId: 可選的長者ID過濾
  /// 
  /// 返回：`Map<EmotionType, int>` 各情緒類型的數量統計
  Future<Map<EmotionType, int>> getEmotionStatistics(
    DateTime startDate,
    DateTime endDate, {
    int? elderId,
  }) async {
    try {
      final emotions = await getEmotionsByDateRange(
        startDate,
        endDate,
        elderId: elderId,
      );

      final statistics = <EmotionType, int>{};
      for (final emotionType in EmotionType.values) {
        statistics[emotionType] = 0;
      }

      for (final emotion in emotions) {
        statistics[emotion.emotionType] =
            (statistics[emotion.emotionType] ?? 0) + 1;
      }

      return statistics;
    } catch (e) {
      debugPrint('Error getting emotion statistics: $e');
      return {};
    }
  }

  /// 導出情緒數據為JSON
  /// 
  /// 用於數據備份或跨設備遷移
  /// 
  /// 參數：
  /// - startDate: 可選的開始日期
  /// - endDate: 可選的結束日期
  /// - elderId: 可選的長者ID過濾
  /// 
  /// 返回：JSON字符串
  Future<String> exportEmotionsAsJson({
    DateTime? startDate,
    DateTime? endDate,
    int? elderId,
  }) async {
    try {
      List<EmotionData> emotions;

      if (startDate != null && endDate != null) {
        emotions = await getEmotionsByDateRange(
          startDate,
          endDate,
          elderId: elderId,
        );
      } else {
        emotions = await _getAllEmotions();
        if (elderId != null) {
          emotions = emotions.where((e) => e.elderId == elderId).toList();
        }
      }

      final jsonList = emotions.map((e) => e.toJson()).toList();
      return jsonEncode(jsonList);
    } catch (e) {
      debugPrint('Error exporting emotions: $e');
      return '[]';
    }
  }

  /// 從JSON導入情緒數據
  /// 
  /// 用於數據恢復或跨設備遷移
  /// 
  /// 參數：
  /// - jsonString: JSON格式的情緒數據字符串
  /// - mergeWithExisting: 是否與現有數據合併（默認true）
  /// 
  /// 返回：成功導入的記錄數量
  Future<int> importEmotionsFromJson(
    String jsonString, {
    bool mergeWithExisting = true,
  }) async {
    try {
      _ensureInitialized();

      final jsonList = jsonDecode(jsonString) as List<dynamic>;
      final importedEmotions = jsonList
          .map((json) => EmotionData.fromJson(json as Map<String, dynamic>))
          .toList();

      if (mergeWithExisting) {
        // 合併模式：與現有數據合併，去重
        final existingEmotions = await _getAllEmotions();
        final existingIds = existingEmotions.map((e) => e.id).toSet();

        // 只添加不存在的記錄
        final newEmotions = importedEmotions
            .where((e) => !existingIds.contains(e.id))
            .toList();

        existingEmotions.addAll(newEmotions);
        existingEmotions.sort((a, b) => b.timestamp.compareTo(a.timestamp));

        final jsonList = existingEmotions.map((e) => e.toJson()).toList();
        final jsonString = jsonEncode(jsonList);
        await _prefs!.setString(_storageKey, jsonString);

        return newEmotions.length;
      } else {
        // 替換模式：完全替換現有數據
        final jsonList = importedEmotions.map((e) => e.toJson()).toList();
        final jsonString = jsonEncode(jsonList);
        await _prefs!.setString(_storageKey, jsonString);

        return importedEmotions.length;
      }
    } catch (e) {
      debugPrint('Error importing emotions: $e');
      return 0;
    }
  }

  /// 雲端同步（未來實現）
  /// 
  /// 將本地數據同步到 Firebase Firestore
  /// 
  /// 實現計劃：
  /// 1. 檢查網絡連接
  /// 2. 獲取上次同步時間
  /// 3. 上傳新增/修改的記錄
  /// 4. 下載雲端更新
  /// 5. 解決衝突（以時間戳為準）
  /// 6. 更新同步狀態
  Future<void> _syncToCloud(EmotionData emotion) async {
    if (!enableCloudSync) return;

    try {
      // TODO: 實現 Firestore 同步邏輯
      // 1. 檢查網絡連接
      // 2. 上傳到 Firestore
      // 3. 處理同步錯誤
      debugPrint('Cloud sync not implemented yet for emotion: ${emotion.id}');
    } catch (e) {
      debugPrint('Error syncing to cloud: $e');
    }
  }

  /// 從雲端同步數據（未來實現）
  Future<void> syncFromCloud({int? elderId}) async {
    if (!enableCloudSync) return;

    try {
      // TODO: 實現從 Firestore 下載數據
      // 1. 檢查網絡連接
      // 2. 從 Firestore 下載數據
      // 3. 合併到本地存儲
      // 4. 解決衝突
      debugPrint('Cloud sync from server not implemented yet');
    } catch (e) {
      debugPrint('Error syncing from cloud: $e');
    }
  }
}
