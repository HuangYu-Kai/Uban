import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/emotion_data.dart';
import '../models/care_task.dart';
import '../services/emotion_storage_service.dart';
import '../services/task_board_service.dart';
import '../services/contribution_service.dart';

/// 📤 數據導出服務
/// 
/// 支援多種格式的數據導出和分享
class DataExportService {
  final EmotionStorageService _emotionService = EmotionStorageService();
  final TaskBoardService _taskService = TaskBoardService();
  final ContributionService _contributionService = ContributionService();

  /// 導出情緒數據為 JSON
  Future<File> exportEmotionsAsJson({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final start = startDate ?? DateTime.now().subtract(const Duration(days: 30));
    final end = endDate ?? DateTime.now();
    
    final emotions = await _emotionService.getEmotionsByDateRange(start, end);
    
    final data = {
      'exportDate': DateTime.now().toIso8601String(),
      'startDate': start.toIso8601String(),
      'endDate': end.toIso8601String(),
      'totalRecords': emotions.length,
      'emotions': emotions.map((e) => e.toJson()).toList(),
    };
    
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/emotions_export_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(json.encode(data));
    
    return file;
  }

  /// 導出情緒數據為 CSV
  Future<File> exportEmotionsAsCsv({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final start = startDate ?? DateTime.now().subtract(const Duration(days: 30));
    final end = endDate ?? DateTime.now();
    
    final emotions = await _emotionService.getEmotionsByDateRange(start, end);
    
    final csv = StringBuffer();
    csv.writeln('日期時間,情緒類型,信心度,音訊參考,備註');
    
    for (final emotion in emotions) {
      csv.writeln(
        '${emotion.timestamp.toIso8601String()},'
        '${_getEmotionLabel(emotion.type)},'
        '${(emotion.confidence * 100).toStringAsFixed(1)}%,'
        '${emotion.audioReference ?? ""},'
        '"${emotion.metadata?['note'] ?? ""}"'
      );
    }
    
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/emotions_export_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(csv.toString());
    
    return file;
  }

  /// 導出任務數據
  Future<File> exportTasksAsJson({int? elderId}) async {
    final tasks = await _taskService.getAllTasks(elderId: elderId);
    
    final data = {
      'exportDate': DateTime.now().toIso8601String(),
      'elderId': elderId,
      'totalTasks': tasks.length,
      'tasks': tasks.map((t) => t.toJson()).toList(),
      'statistics': {
        'pending': tasks.where((t) => t.status == TaskStatus.pending).length,
        'inProgress': tasks.where((t) => t.status == TaskStatus.inProgress).length,
        'completed': tasks.where((t) => t.status == TaskStatus.completed).length,
        'cancelled': tasks.where((t) => t.status == TaskStatus.cancelled).length,
      },
    };
    
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/tasks_export_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(json.encode(data));
    
    return file;
  }

  /// 導出家庭協作數據
  Future<File> exportContributionData() async {
    final members = await _contributionService.getAllMembers();
    final weeklyStats = await _contributionService.getWeeklyStats();
    
    final data = {
      'exportDate': DateTime.now().toIso8601String(),
      'members': members.map((m) => m.toJson()).toList(),
      'weeklyStats': weeklyStats,
      'leaderboard': members
        .map((m) => {
          'name': m.name,
          'role': m.role,
          'score': m.contributionScore,
        })
        .toList()
        ..sort((a, b) => (b['score'] as int).compareTo(a['score'] as int)),
    };
    
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/contribution_export_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(json.encode(data));
    
    return file;
  }

  /// 導出完整健康報告（所有數據）
  Future<File> exportCompleteHealthData({
    required String elderName,
    int? elderId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final start = startDate ?? DateTime.now().subtract(const Duration(days: 30));
    final end = endDate ?? DateTime.now();
    
    final emotions = await _emotionService.getEmotionsByDateRange(start, end);
    final tasks = await _taskService.getAllTasks(elderId: elderId);
    final members = await _contributionService.getAllMembers();
    final emotionStats = await _emotionService.getStatistics(start, end);
    
    final data = {
      'elderName': elderName,
      'elderId': elderId,
      'exportDate': DateTime.now().toIso8601String(),
      'reportPeriod': {
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'days': end.difference(start).inDays,
      },
      'emotionData': {
        'total': emotions.length,
        'statistics': emotionStats,
        'records': emotions.map((e) => e.toJson()).toList(),
      },
      'taskData': {
        'total': tasks.length,
        'completed': tasks.where((t) => t.status == TaskStatus.completed).length,
        'pending': tasks.where((t) => t.status == TaskStatus.pending).length,
        'records': tasks.map((t) => t.toJson()).toList(),
      },
      'familyData': {
        'totalMembers': members.length,
        'members': members.map((m) => m.toJson()).toList(),
      },
    };
    
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/complete_health_data_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(json.encode(data));
    
    return file;
  }

  /// 分享文件
  Future<void> shareFile(File file, {String? subject}) async {
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: subject ?? '健康數據導出',
    );
  }

  /// 導出並分享情緒數據
  Future<void> exportAndShareEmotions({
    DateTime? startDate,
    DateTime? endDate,
    ExportFormat format = ExportFormat.json,
  }) async {
    File file;
    
    switch (format) {
      case ExportFormat.json:
        file = await exportEmotionsAsJson(startDate: startDate, endDate: endDate);
        break;
      case ExportFormat.csv:
        file = await exportEmotionsAsCsv(startDate: startDate, endDate: endDate);
        break;
    }
    
    await shareFile(file, subject: '情緒數據導出');
  }

  /// 導出並分享任務數據
  Future<void> exportAndShareTasks({int? elderId}) async {
    final file = await exportTasksAsJson(elderId: elderId);
    await shareFile(file, subject: '任務數據導出');
  }

  /// 導出並分享完整報告
  Future<void> exportAndShareCompleteReport({
    required String elderName,
    int? elderId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final file = await exportCompleteHealthData(
      elderName: elderName,
      elderId: elderId,
      startDate: startDate,
      endDate: endDate,
    );
    await shareFile(file, subject: '$elderName 健康數據完整報告');
  }

  /// 匯入情緒數據
  Future<int> importEmotionsFromJson(File file) async {
    final jsonString = await file.readAsString();
    final data = json.decode(jsonString) as Map<String, dynamic>;
    
    final emotionsJson = data['emotions'] as List;
    final emotions = emotionsJson.map((e) => EmotionData.fromJson(e as Map<String, dynamic>)).toList();
    
    await _emotionService.saveEmotions(emotions);
    
    return emotions.length;
  }

  /// 清理舊的導出文件（保留最近10個）
  Future<void> cleanupOldExports() async {
    final directory = await getApplicationDocumentsDirectory();
    final files = directory.listSync()
      .whereType<File>()
      .where((f) => f.path.contains('_export_'))
      .toList();
    
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    
    if (files.length > 10) {
      for (var i = 10; i < files.length; i++) {
        await files[i].delete();
      }
    }
  }

  String _getEmotionLabel(EmotionType type) {
    switch (type) {
      case EmotionType.happy:
        return '開心';
      case EmotionType.calm:
        return '平靜';
      case EmotionType.anxious:
        return '焦慮';
      case EmotionType.sad:
        return '悲傷';
    }
  }
}

/// 導出格式
enum ExportFormat {
  json,
  csv,
}
