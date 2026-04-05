import 'package:flutter/material.dart';

/// 👨‍👩‍👧‍👦 家庭成員模型
class FamilyMember {
  final String id;
  final String name;
  final String avatarUrl;
  final String role; // '父親', '母親', '長女', '次子' 等
  final int contributionScore;
  final Map<String, int> contributionBreakdown; // 各類貢獻分數
  final DateTime lastActiveAt;
  final List<String> badges;

  FamilyMember({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.role,
    required this.contributionScore,
    required this.contributionBreakdown,
    required this.lastActiveAt,
    this.badges = const [],
  });

  /// 本週是否活躍（7天內有活動）
  bool get isActiveThisWeek {
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    return lastActiveAt.isAfter(weekAgo);
  }

  /// 根據貢獻值獲取排名顏色
  Color get rankColor {
    if (contributionScore >= 100) return const Color(0xFFEF4444); // 紅色 - 頂尖
    if (contributionScore >= 50) return const Color(0xFFF59E0B); // 橙色 - 優秀
    if (contributionScore >= 20) return const Color(0xFF3B82F6); // 藍色 - 良好
    return const Color(0xFF6B7280); // 灰色 - 一般
  }

  /// 貢獻顏色（與 rankColor 相同）
  Color get contributionColor => rankColor;

  /// 模擬活動記錄（實際應從服務層獲取）
  Map<String, int> get activities => contributionBreakdown;

  /// 貢獻度百分比（相對於最高分）
  double getContributionPercentage(int maxScore) {
    if (maxScore == 0) return 0;
    return (contributionScore / maxScore * 100).clamp(0, 100);
  }

  FamilyMember copyWith({
    String? id,
    String? name,
    String? avatarUrl,
    String? role,
    int? contributionScore,
    Map<String, int>? contributionBreakdown,
    DateTime? lastActiveAt,
    List<String>? badges,
  }) {
    return FamilyMember(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      contributionScore: contributionScore ?? this.contributionScore,
      contributionBreakdown: contributionBreakdown ?? this.contributionBreakdown,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      badges: badges ?? this.badges,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatarUrl': avatarUrl,
      'role': role,
      'contributionScore': contributionScore,
      'contributionBreakdown': contributionBreakdown,
      'lastActiveAt': lastActiveAt.toIso8601String(),
      'badges': badges,
    };
  }

  factory FamilyMember.fromJson(Map<String, dynamic> json) {
    return FamilyMember(
      id: json['id'] as String,
      name: json['name'] as String,
      avatarUrl: json['avatarUrl'] as String,
      role: json['role'] as String,
      contributionScore: json['contributionScore'] as int,
      contributionBreakdown: Map<String, int>.from(json['contributionBreakdown'] as Map),
      lastActiveAt: DateTime.parse(json['lastActiveAt'] as String),
      badges: List<String>.from(json['badges'] as List? ?? []),
    );
  }
}

/// 📊 貢獻類型
enum ContributionType {
  videoCall,      // 視訊通話
  taskCompleted,  // 任務完成
  dataCheck,      // 健康數據查看
  emergency,      // 緊急處理
  chatMessage,    // 聊天訊息
}

extension ContributionTypeExtension on ContributionType {
  String get label {
    switch (this) {
      case ContributionType.videoCall:
        return '視訊通話';
      case ContributionType.taskCompleted:
        return '任務完成';
      case ContributionType.dataCheck:
        return '數據查看';
      case ContributionType.emergency:
        return '緊急處理';
      case ContributionType.chatMessage:
        return '聊天互動';
    }
  }

  IconData get icon {
    switch (this) {
      case ContributionType.videoCall:
        return Icons.videocam_rounded;
      case ContributionType.taskCompleted:
        return Icons.task_alt_rounded;
      case ContributionType.dataCheck:
        return Icons.health_and_safety_rounded;
      case ContributionType.emergency:
        return Icons.warning_amber_rounded;
      case ContributionType.chatMessage:
        return Icons.chat_bubble_rounded;
    }
  }

  int get baseScore {
    switch (this) {
      case ContributionType.videoCall:
        return 10;
      case ContributionType.taskCompleted:
        return 15;
      case ContributionType.dataCheck:
        return 5;
      case ContributionType.emergency:
        return 30;
      case ContributionType.chatMessage:
        return 3;
    }
  }
}
