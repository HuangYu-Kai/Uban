import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/family_member.dart';

/// 🏆 貢獻值計算服務
/// 
/// 追蹤和計算家庭成員對長輩照護的貢獻度
class ContributionService {
  static const String _membersKey = 'family_members';
  static const String _activitiesKey = 'contribution_activities';
  
  /// 記錄貢獻活動
  Future<void> recordContribution({
    required String userId,
    required ContributionType type,
    Map<String, dynamic>? metadata,
  }) async {
    final now = DateTime.now();
    
    // 計算分數（基礎分 + 時間加成）
    int score = type.baseScore;
    
    // 夜間或週末加成 20%
    if (_isOffPeakTime(now)) {
      score = (score * 1.2).round();
    }
    
    // 連續活動加成
    final streakBonus = await _calculateStreakBonus(userId, type);
    score += streakBonus;
    
    // 記錄活動
    await _saveActivity(userId, type, score, metadata);
    
    // 更新成員貢獻值
    await _updateMemberScore(userId, type, score);
  }

  /// 獲取所有家庭成員
  Future<List<FamilyMember>> getAllMembers() async {
    final prefs = await SharedPreferences.getInstance();
    final membersJson = prefs.getString(_membersKey);
    
    if (membersJson == null) {
      // 返回模擬數據
      return _getMockMembers();
    }
    
    final List<dynamic> membersList = json.decode(membersJson);
    return membersList.map((json) => FamilyMember.fromJson(json)).toList();
  }

  /// 獲取成員排行榜
  Future<List<FamilyMember>> getLeaderboard({int limit = 10}) async {
    final members = await getAllMembers();
    members.sort((a, b) => b.contributionScore.compareTo(a.contributionScore));
    return members.take(limit).toList();
  }

  /// 獲取本週貢獻統計
  Future<Map<String, dynamic>> getWeeklyStats() async {
    final activities = await _getActivities();
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final weeklyActivities = activities.where((a) => 
      DateTime.parse(a['timestamp'] as String).isAfter(weekAgo)
    ).toList();

    final stats = <String, dynamic>{
      'totalContributions': weeklyActivities.length,
      'totalScore': weeklyActivities.fold<int>(0, (sum, a) => sum + (a['score'] as int)),
      'activeMembers': weeklyActivities.map((a) => a['userId']).toSet().length,
      'byType': <String, int>{},
    };

    for (final activity in weeklyActivities) {
      final type = activity['type'] as String;
      stats['byType'][type] = (stats['byType'][type] ?? 0) + 1;
    }

    return stats;
  }

  /// 獲取個人統計
  Future<Map<String, dynamic>> getUserStats(String userId) async {
    final activities = await _getActivities();
    final userActivities = activities.where((a) => a['userId'] == userId).toList();

    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final weeklyActivities = userActivities.where((a) => 
      DateTime.parse(a['timestamp'] as String).isAfter(weekAgo)
    ).toList();

    return {
      'totalScore': userActivities.fold<int>(0, (sum, a) => sum + (a['score'] as int)),
      'weeklyScore': weeklyActivities.fold<int>(0, (sum, a) => sum + (a['score'] as int)),
      'totalActivities': userActivities.length,
      'weeklyActivities': weeklyActivities.length,
      'streak': await _getCurrentStreak(userId),
      'byType': _groupByType(userActivities),
    };
  }

  /// 判斷是否為非高峰時間（夜間或週末）
  bool _isOffPeakTime(DateTime time) {
    final hour = time.hour;
    final isWeekend = time.weekday >= 6;
    final isNight = hour < 8 || hour >= 22;
    
    return isWeekend || isNight;
  }

  /// 計算連續活動加成
  Future<int> _calculateStreakBonus(String userId, ContributionType type) async {
    final streak = await _getCurrentStreak(userId);
    
    if (streak >= 7) return 5; // 連續7天 +5分
    if (streak >= 3) return 3; // 連續3天 +3分
    return 0;
  }

  /// 獲取當前連續天數
  Future<int> _getCurrentStreak(String userId) async {
    final activities = await _getActivities();
    final userActivities = activities
      .where((a) => a['userId'] == userId)
      .map((a) => DateTime.parse(a['timestamp'] as String))
      .toList();
    
    if (userActivities.isEmpty) return 0;
    
    userActivities.sort((a, b) => b.compareTo(a));
    
    int streak = 1;
    DateTime current = DateTime.now();
    
    for (final activityDate in userActivities) {
      final daysDiff = current.difference(activityDate).inDays;
      
      if (daysDiff <= 1) {
        if (daysDiff == 1) streak++;
        current = activityDate;
      } else {
        break;
      }
    }
    
    return streak;
  }

  /// 保存活動記錄
  Future<void> _saveActivity(
    String userId, 
    ContributionType type, 
    int score,
    Map<String, dynamic>? metadata,
  ) async {
    final activities = await _getActivities();
    
    activities.add({
      'userId': userId,
      'type': type.name,
      'score': score,
      'timestamp': DateTime.now().toIso8601String(),
      'metadata': metadata,
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activitiesKey, json.encode(activities));
  }

  /// 獲取活動記錄
  Future<List<Map<String, dynamic>>> _getActivities() async {
    final prefs = await SharedPreferences.getInstance();
    final activitiesJson = prefs.getString(_activitiesKey);
    
    if (activitiesJson == null) return [];
    
    return List<Map<String, dynamic>>.from(json.decode(activitiesJson));
  }

  /// 更新成員分數
  Future<void> _updateMemberScore(String userId, ContributionType type, int score) async {
    final members = await getAllMembers();
    final index = members.indexWhere((m) => m.id == userId);
    
    if (index != -1) {
      final member = members[index];
      final newBreakdown = Map<String, int>.from(member.contributionBreakdown);
      newBreakdown[type.name] = (newBreakdown[type.name] ?? 0) + score;
      
      members[index] = member.copyWith(
        contributionScore: member.contributionScore + score,
        contributionBreakdown: newBreakdown,
        lastActiveAt: DateTime.now(),
      );

      await _saveMembers(members);
    }
  }

  /// 保存成員列表
  Future<void> _saveMembers(List<FamilyMember> members) async {
    final prefs = await SharedPreferences.getInstance();
    final membersJson = json.encode(members.map((m) => m.toJson()).toList());
    await prefs.setString(_membersKey, membersJson);
  }

  /// 按類型分組
  Map<String, int> _groupByType(List<Map<String, dynamic>> activities) {
    final grouped = <String, int>{};
    
    for (final activity in activities) {
      final type = activity['type'] as String;
      grouped[type] = (grouped[type] ?? 0) + 1;
    }
    
    return grouped;
  }

  /// 獲取模擬成員數據
  List<FamilyMember> _getMockMembers() {
    final now = DateTime.now();
    
    return [
      FamilyMember(
        id: 'user1',
        name: '王小明',
        avatarUrl: 'https://i.pravatar.cc/150?img=12',
        role: '長子',
        contributionScore: 125,
        contributionBreakdown: {
          'videoCall': 50,
          'taskCompleted': 45,
          'dataCheck': 20,
          'chatMessage': 10,
        },
        lastActiveAt: now.subtract(const Duration(hours: 2)),
        badges: ['first_task', 'task_master'],
      ),
      FamilyMember(
        id: 'user2',
        name: '王小華',
        avatarUrl: 'https://i.pravatar.cc/150?img=45',
        role: '長女',
        contributionScore: 98,
        contributionBreakdown: {
          'videoCall': 40,
          'taskCompleted': 30,
          'dataCheck': 18,
          'chatMessage': 10,
        },
        lastActiveAt: now.subtract(const Duration(hours: 5)),
        badges: ['first_task'],
      ),
      FamilyMember(
        id: 'user3',
        name: '王大偉',
        avatarUrl: 'https://i.pravatar.cc/150?img=33',
        role: '次子',
        contributionScore: 76,
        contributionBreakdown: {
          'videoCall': 30,
          'taskCompleted': 30,
          'dataCheck': 10,
          'emergency': 6,
        },
        lastActiveAt: now.subtract(const Duration(days: 1)),
        badges: ['first_task', 'team_player'],
      ),
      FamilyMember(
        id: 'user4',
        name: '王美玲',
        avatarUrl: 'https://i.pravatar.cc/150?img=48',
        role: '次女',
        contributionScore: 54,
        contributionBreakdown: {
          'videoCall': 20,
          'taskCompleted': 15,
          'dataCheck': 12,
          'chatMessage': 7,
        },
        lastActiveAt: now.subtract(const Duration(days: 2)),
      ),
    ];
  }

  /// 清除所有數據（測試用）
  Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_membersKey);
    await prefs.remove(_activitiesKey);
  }
}
