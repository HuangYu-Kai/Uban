import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/care_task.dart';

/// 📋 任務看板服務
/// 
/// 管理照護任務的創建、分配、完成等操作
class TaskBoardService {
  static const String _tasksKey = 'care_tasks';
  static const String _badgesKey = 'earned_badges';
  
  /// 獲取所有任務
  Future<List<CareTask>> getAllTasks({int? elderId}) async {
    final prefs = await SharedPreferences.getInstance();
    final tasksJson = prefs.getString(_tasksKey);
    
    if (tasksJson == null) return [];
    
    final List<dynamic> tasksList = json.decode(tasksJson);
    final tasks = tasksList.map((json) => CareTask.fromJson(json)).toList();
    
    if (elderId != null) {
      return tasks.where((t) => t.elderId == elderId).toList();
    }
    
    return tasks;
  }

  /// 獲取待認領任務
  Future<List<CareTask>> getUnassignedTasks({int? elderId}) async {
    final tasks = await getAllTasks(elderId: elderId);
    return tasks.where((t) => 
      t.assignedToId == null && 
      t.status == TaskStatus.pending
    ).toList();
  }

  /// 獲取我的任務
  Future<List<CareTask>> getMyTasks(String userId, {int? elderId}) async {
    final tasks = await getAllTasks(elderId: elderId);
    return tasks.where((t) => t.assignedToId == userId).toList();
  }

  /// 創建新任務
  Future<void> createTask(CareTask task) async {
    final tasks = await getAllTasks();
    tasks.add(task);
    await _saveTasks(tasks);
  }

  /// 認領任務
  Future<void> claimTask(String taskId, String userId, String userName) async {
    final tasks = await getAllTasks();
    final index = tasks.indexWhere((t) => t.id == taskId);
    
    if (index != -1) {
      tasks[index] = tasks[index].copyWith(
        assignedToId: userId,
        assignedToName: userName,
        status: TaskStatus.inProgress,
      );
      await _saveTasks(tasks);
      
      // 檢查並授予徽章
      await _checkAndAwardBadges(userId);
    }
  }

  /// 完成任務
  Future<void> completeTask(String taskId) async {
    final tasks = await getAllTasks();
    final index = tasks.indexWhere((t) => t.id == taskId);
    
    if (index != -1) {
      final userId = tasks[index].assignedToId;
      tasks[index] = tasks[index].copyWith(status: TaskStatus.completed);
      await _saveTasks(tasks);
      
      // 檢查並授予徽章
      if (userId != null) {
        await _checkAndAwardBadges(userId);
      }
    }
  }

  /// 取消任務
  Future<void> cancelTask(String taskId) async {
    final tasks = await getAllTasks();
    final index = tasks.indexWhere((t) => t.id == taskId);
    
    if (index != -1) {
      tasks[index] = tasks[index].copyWith(status: TaskStatus.cancelled);
      await _saveTasks(tasks);
    }
  }

  /// AI 自動生成任務
  Future<List<CareTask>> generateAiTasks(int elderId, Map<String, dynamic> healthData) async {
    final generatedTasks = <CareTask>[];
    final now = DateTime.now();
    
    // 根據健康數據生成任務
    
    // 1. 檢查通話頻率
    if (healthData['callsThisWeek'] != null && (healthData['callsThisWeek'] as int) < 3) {
      generatedTasks.add(CareTask(
        id: 'ai_task_${DateTime.now().millisecondsSinceEpoch}_1',
        title: '本週通話次數不足',
        description: '本週僅通話 ${healthData['callsThisWeek']} 次，建議增加與長輩的互動',
        elderId: elderId,
        createdAt: now,
        dueDate: now.add(const Duration(days: 2)),
        priority: TaskPriority.medium,
        category: 'communication',
        metadata: {'aiGenerated': true},
      ));
    }

    // 2. 檢查藥物狀態
    if (healthData['medicationDaysLeft'] != null && (healthData['medicationDaysLeft'] as int) < 7) {
      generatedTasks.add(CareTask(
        id: 'ai_task_${DateTime.now().millisecondsSinceEpoch}_2',
        title: '藥物即將用完',
        description: '高血壓藥物剩餘 ${healthData['medicationDaysLeft']} 天份，需要及時補充',
        elderId: elderId,
        createdAt: now,
        dueDate: now.add(Duration(days: (healthData['medicationDaysLeft'] as int) - 1)),
        priority: TaskPriority.high,
        category: 'medication',
        metadata: {'aiGenerated': true},
      ));
    }

    // 3. 檢查活動量
    if (healthData['dailySteps'] != null && (healthData['dailySteps'] as int) < 2000) {
      generatedTasks.add(CareTask(
        id: 'ai_task_${DateTime.now().millisecondsSinceEpoch}_3',
        title: '活動量偏低',
        description: '近日活動量僅 ${healthData['dailySteps']} 步，建議鼓勵長輩增加活動',
        elderId: elderId,
        createdAt: now,
        dueDate: now.add(const Duration(days: 1)),
        priority: TaskPriority.low,
        category: 'activity',
        metadata: {'aiGenerated': true},
      ));
    }

    // 4. 檢查定期檢查
    if (healthData['daysSinceLastCheckup'] != null && (healthData['daysSinceLastCheckup'] as int) > 90) {
      generatedTasks.add(CareTask(
        id: 'ai_task_${DateTime.now().millisecondsSinceEpoch}_4',
        title: '定期健康檢查',
        description: '距離上次健康檢查已過 ${healthData['daysSinceLastCheckup']} 天，建議安排門診',
        elderId: elderId,
        createdAt: now,
        dueDate: now.add(const Duration(days: 7)),
        priority: TaskPriority.high,
        category: 'medical',
        metadata: {'aiGenerated': true},
      ));
    }

    // 保存生成的任務
    for (final task in generatedTasks) {
      await createTask(task);
    }

    return generatedTasks;
  }

  /// 獲取已獲得的徽章
  Future<List<String>> getEarnedBadges(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final badgesJson = prefs.getString('${_badgesKey}_$userId');
    
    if (badgesJson == null) return [];
    
    return List<String>.from(json.decode(badgesJson));
  }

  /// 檢查並授予徽章
  Future<List<String>> _checkAndAwardBadges(String userId) async {
    final tasks = await getAllTasks();
    final myCompletedTasks = tasks.where((t) => 
      t.assignedToId == userId && 
      t.status == TaskStatus.completed
    ).length;

    final earnedBadges = await getEarnedBadges(userId);
    final newBadges = <String>[];

    for (final badge in TaskBadge.allBadges) {
      if (!earnedBadges.contains(badge.id) && myCompletedTasks >= badge.requiredCount) {
        earnedBadges.add(badge.id);
        newBadges.add(badge.id);
      }
    }

    if (newBadges.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${_badgesKey}_$userId', json.encode(earnedBadges));
    }

    return newBadges;
  }

  /// 保存任務列表
  Future<void> _saveTasks(List<CareTask> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    final tasksJson = json.encode(tasks.map((t) => t.toJson()).toList());
    await prefs.setString(_tasksKey, tasksJson);
  }

  /// 清除所有任務（測試用）
  Future<void> clearAllTasks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tasksKey);
  }
}
