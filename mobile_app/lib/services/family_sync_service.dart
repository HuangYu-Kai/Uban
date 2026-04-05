import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/family_member.dart';
import '../models/care_task.dart';
import '../models/emotion_data.dart';

/// 🔄 Firebase 實時同步服務
/// 
/// 管理多用戶間的數據同步（準備整合 Firebase）
class FamilySyncService {
  static const String _syncStatusKey = 'sync_status';
  static const String _lastSyncKey = 'last_sync_time';
  
  /// 同步家庭成員數據
  Future<SyncResult> syncFamilyMembers(List<FamilyMember> localMembers) async {
    try {
      // TODO: 整合 Firebase Realtime Database
      // final ref = FirebaseDatabase.instance.ref('families/$familyId/members');
      
      // 模擬同步延遲
      await Future.delayed(const Duration(milliseconds: 500));
      
      // 模擬從雲端獲取數據
      final cloudMembers = localMembers; // 實際應從 Firebase 獲取
      
      // 合併本地和雲端數據
      final mergedMembers = _mergeMemberData(localMembers, cloudMembers);
      
      await _updateLastSyncTime();
      
      return SyncResult(
        success: true,
        syncedCount: mergedMembers.length,
        conflicts: 0,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      return SyncResult(
        success: false,
        syncedCount: 0,
        conflicts: 0,
        timestamp: DateTime.now(),
        error: e.toString(),
      );
    }
  }

  /// 同步任務數據
  Future<SyncResult> syncTasks(List<CareTask> localTasks) async {
    try {
      // TODO: 整合 Firebase
      await Future.delayed(const Duration(milliseconds: 300));
      
      final cloudTasks = localTasks;
      final mergedTasks = _mergeTaskData(localTasks, cloudTasks);
      
      await _updateLastSyncTime();
      
      return SyncResult(
        success: true,
        syncedCount: mergedTasks.length,
        conflicts: 0,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      return SyncResult(
        success: false,
        syncedCount: 0,
        conflicts: 0,
        timestamp: DateTime.now(),
        error: e.toString(),
      );
    }
  }

  /// 同步情緒數據
  Future<SyncResult> syncEmotions(List<EmotionData> localEmotions) async {
    try {
      // TODO: 整合 Firebase
      await Future.delayed(const Duration(milliseconds: 400));
      
      await _updateLastSyncTime();
      
      return SyncResult(
        success: true,
        syncedCount: localEmotions.length,
        conflicts: 0,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      return SyncResult(
        success: false,
        syncedCount: 0,
        conflicts: 0,
        timestamp: DateTime.now(),
        error: e.toString(),
      );
    }
  }

  /// 實時監聽家庭成員變化
  Stream<List<FamilyMember>> watchFamilyMembers(String familyId) async* {
    // TODO: 實際實現使用 Firebase
    // FirebaseDatabase.instance.ref('families/$familyId/members').onValue.listen((event) {
    //   final data = event.snapshot.value;
    //   yield parseMembersFromFirebase(data);
    // });
    
    // 模擬實時更新
    yield* Stream.periodic(const Duration(seconds: 5), (count) {
      return <FamilyMember>[];
    });
  }

  /// 實時監聽任務變化
  Stream<List<CareTask>> watchTasks(String familyId) async* {
    // TODO: 實際實現使用 Firebase
    yield* Stream.periodic(const Duration(seconds: 5), (count) {
      return <CareTask>[];
    });
  }

  /// 推送成員活動更新
  Future<void> pushMemberActivity({
    required String userId,
    required String familyId,
    required String activityType,
    Map<String, dynamic>? metadata,
  }) async {
    // TODO: 推送到 Firebase
    final activity = {
      'userId': userId,
      'familyId': familyId,
      'type': activityType,
      'timestamp': DateTime.now().toIso8601String(),
      'metadata': metadata,
    };
    
    // 模擬推送
    await Future.delayed(const Duration(milliseconds: 100));
  }

  /// 檢查同步狀態
  Future<bool> isSynced() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getString(_lastSyncKey);
    
    if (lastSync == null) return false;
    
    final lastSyncTime = DateTime.parse(lastSync);
    final diff = DateTime.now().difference(lastSyncTime);
    
    // 如果超過5分鐘未同步，視為未同步
    return diff.inMinutes < 5;
  }

  /// 獲取最後同步時間
  Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getString(_lastSyncKey);
    
    if (lastSync == null) return null;
    return DateTime.parse(lastSync);
  }

  /// 強制全量同步
  Future<SyncResult> forceSyncAll(String familyId) async {
    try {
      // TODO: 實現全量同步邏輯
      await Future.delayed(const Duration(seconds: 1));
      
      await _updateLastSyncTime();
      
      return SyncResult(
        success: true,
        syncedCount: 0,
        conflicts: 0,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      return SyncResult(
        success: false,
        syncedCount: 0,
        conflicts: 0,
        timestamp: DateTime.now(),
        error: e.toString(),
      );
    }
  }

  /// 合併成員數據
  List<FamilyMember> _mergeMemberData(
    List<FamilyMember> local,
    List<FamilyMember> cloud,
  ) {
    final Map<String, FamilyMember> merged = {};
    
    // 添加本地數據
    for (final member in local) {
      merged[member.id] = member;
    }
    
    // 合併雲端數據（雲端優先）
    for (final member in cloud) {
      final existing = merged[member.id];
      
      if (existing == null) {
        merged[member.id] = member;
      } else {
        // 取最新的數據
        if (member.lastActiveAt.isAfter(existing.lastActiveAt)) {
          merged[member.id] = member;
        }
      }
    }
    
    return merged.values.toList();
  }

  /// 合併任務數據
  List<CareTask> _mergeTaskData(
    List<CareTask> local,
    List<CareTask> cloud,
  ) {
    final Map<String, CareTask> merged = {};
    
    for (final task in local) {
      merged[task.id] = task;
    }
    
    for (final task in cloud) {
      final existing = merged[task.id];
      
      if (existing == null) {
        merged[task.id] = task;
      } else {
        // 以狀態變更時間較晚的為準
        // 這裡簡化處理，實際應該比較修改時間戳
        merged[task.id] = task;
      }
    }
    
    return merged.values.toList();
  }

  /// 更新最後同步時間
  Future<void> _updateLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());
  }

  /// 清除同步狀態
  Future<void> clearSyncStatus() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_syncStatusKey);
    await prefs.remove(_lastSyncKey);
  }
}

/// 同步結果
class SyncResult {
  final bool success;
  final int syncedCount;
  final int conflicts;
  final DateTime timestamp;
  final String? error;

  SyncResult({
    required this.success,
    required this.syncedCount,
    required this.conflicts,
    required this.timestamp,
    this.error,
  });

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'syncedCount': syncedCount,
      'conflicts': conflicts,
      'timestamp': timestamp.toIso8601String(),
      'error': error,
    };
  }
}

/// 同步衝突
class SyncConflict {
  final String id;
  final dynamic localData;
  final dynamic cloudData;
  final ConflictResolution resolution;

  SyncConflict({
    required this.id,
    required this.localData,
    required this.cloudData,
    this.resolution = ConflictResolution.useCloud,
  });
}

/// 衝突解決策略
enum ConflictResolution {
  useLocal,   // 使用本地數據
  useCloud,   // 使用雲端數據
  merge,      // 合併數據
  manual,     // 手動解決
}
