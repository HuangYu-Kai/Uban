import 'package:flutter/material.dart';

/// 📋 照護任務模型
class CareTask {
  final String id;
  final String title;
  final String description;
  final int elderId;
  final String? assignedToId;
  final String? assignedToName;
  final DateTime createdAt;
  final DateTime dueDate;
  final TaskPriority priority;
  final TaskStatus status;
  final String? category;
  final Map<String, dynamic>? metadata;

  CareTask({
    required this.id,
    required this.title,
    required this.description,
    required this.elderId,
    this.assignedToId,
    this.assignedToName,
    required this.createdAt,
    required this.dueDate,
    required this.priority,
    this.status = TaskStatus.pending,
    this.category,
    this.metadata,
  });

  bool get isOverdue => DateTime.now().isAfter(dueDate) && status != TaskStatus.completed;
  bool get isDueSoon => dueDate.difference(DateTime.now()).inDays <= 2;
  bool get isCompleted => status == TaskStatus.completed;
  String? get assignedTo => assignedToName;
  
  Color get priorityColor {
    switch (priority) {
      case TaskPriority.high:
        return const Color(0xFFEF4444);
      case TaskPriority.medium:
        return const Color(0xFFF59E0B);
      case TaskPriority.low:
        return const Color(0xFF3B82F6);
    }
  }

  String get priorityLabel {
    switch (priority) {
      case TaskPriority.high:
        return '重要';
      case TaskPriority.medium:
        return '普通';
      case TaskPriority.low:
        return '一般';
    }
  }

  IconData get categoryIcon {
    switch (category) {
      case 'medical':
        return Icons.local_hospital_rounded;
      case 'medication':
        return Icons.medication_rounded;
      case 'communication':
        return Icons.phone_rounded;
      case 'activity':
        return Icons.directions_walk_rounded;
      default:
        return Icons.task_alt_rounded;
    }
  }

  CareTask copyWith({
    String? id,
    String? title,
    String? description,
    int? elderId,
    String? assignedToId,
    String? assignedToName,
    DateTime? createdAt,
    DateTime? dueDate,
    TaskPriority? priority,
    TaskStatus? status,
    String? category,
    Map<String, dynamic>? metadata,
  }) {
    return CareTask(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      elderId: elderId ?? this.elderId,
      assignedToId: assignedToId ?? this.assignedToId,
      assignedToName: assignedToName ?? this.assignedToName,
      createdAt: createdAt ?? this.createdAt,
      dueDate: dueDate ?? this.dueDate,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      category: category ?? this.category,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'elderId': elderId,
      'assignedToId': assignedToId,
      'assignedToName': assignedToName,
      'createdAt': createdAt.toIso8601String(),
      'dueDate': dueDate.toIso8601String(),
      'priority': priority.name,
      'status': status.name,
      'category': category,
      'metadata': metadata,
    };
  }

  factory CareTask.fromJson(Map<String, dynamic> json) {
    return CareTask(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      elderId: json['elderId'] as int,
      assignedToId: json['assignedToId'] as String?,
      assignedToName: json['assignedToName'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      dueDate: DateTime.parse(json['dueDate'] as String),
      priority: TaskPriority.values.firstWhere((e) => e.name == json['priority']),
      status: TaskStatus.values.firstWhere((e) => e.name == json['status']),
      category: json['category'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
}

enum TaskPriority { high, medium, low }

enum TaskStatus { pending, inProgress, completed, cancelled }

/// 🏆 任務完成徽章
class TaskBadge {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final int requiredCount;

  TaskBadge({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.requiredCount,
  });

  static List<TaskBadge> get allBadges => [
    TaskBadge(
      id: 'first_task',
      name: '初心者',
      description: '完成第一個任務',
      icon: Icons.star_rounded,
      color: const Color(0xFFF59E0B),
      requiredCount: 1,
    ),
    TaskBadge(
      id: 'task_master',
      name: '任務達人',
      description: '完成 10 個任務',
      icon: Icons.workspace_premium_rounded,
      color: const Color(0xFF3B82F6),
      requiredCount: 10,
    ),
    TaskBadge(
      id: 'care_champion',
      name: '照護冠軍',
      description: '完成 50 個任務',
      icon: Icons.emoji_events_rounded,
      color: const Color(0xFFEF4444),
      requiredCount: 50,
    ),
    TaskBadge(
      id: 'team_player',
      name: '團隊合作',
      description: '與家人一起完成 5 個任務',
      icon: Icons.people_rounded,
      color: const Color(0xFF8B5CF6),
      requiredCount: 5,
    ),
  ];
}
