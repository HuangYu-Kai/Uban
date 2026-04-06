// lib/models/care_script.dart
import 'dart:convert';
import 'package:flutter/material.dart';

/// 關心劇本數據模型
class CareScript {
  final String id;
  final int elderId;
  final TimeOfDay time;
  final String message;
  final ScriptType type;
  final bool enableVoice;
  final String? customAudioPath;
  final List<String> repeatDays;
  final bool enabled;
  final DateTime createdAt;
  final DateTime? lastExecutedAt;

  CareScript({
    required this.id,
    required this.elderId,
    required this.time,
    required this.message,
    this.type = ScriptType.reminder,
    this.enableVoice = true,
    this.customAudioPath,
    this.repeatDays = const ['週一', '週二', '週三', '週四', '週五'],
    this.enabled = true,
    required this.createdAt,
    this.lastExecutedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'elder_id': elderId,
      'time': '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
      'message': message,
      'type': type.name,
      'enable_voice': enableVoice ? 1 : 0,
      'custom_audio_path': customAudioPath,
      'repeat_days': json.encode(repeatDays),
      'enabled': enabled ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'last_executed_at': lastExecutedAt?.toIso8601String(),
    };
  }

  factory CareScript.fromMap(Map<String, dynamic> map) {
    final timeParts = (map['time'] as String).split(':');
    return CareScript(
      id: map['id'],
      elderId: map['elder_id'],
      time: TimeOfDay(
        hour: int.parse(timeParts[0]),
        minute: int.parse(timeParts[1]),
      ),
      message: map['message'],
      type: ScriptType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => ScriptType.reminder,
      ),
      enableVoice: map['enable_voice'] == 1,
      customAudioPath: map['custom_audio_path'],
      repeatDays: List<String>.from(json.decode(map['repeat_days'])),
      enabled: map['enabled'] == 1,
      createdAt: DateTime.parse(map['created_at']),
      lastExecutedAt: map['last_executed_at'] != null
          ? DateTime.parse(map['last_executed_at'])
          : null,
    );
  }

  CareScript copyWith({
    String? id,
    int? elderId,
    TimeOfDay? time,
    String? message,
    ScriptType? type,
    bool? enableVoice,
    String? customAudioPath,
    List<String>? repeatDays,
    bool? enabled,
    DateTime? createdAt,
    DateTime? lastExecutedAt,
  }) {
    return CareScript(
      id: id ?? this.id,
      elderId: elderId ?? this.elderId,
      time: time ?? this.time,
      message: message ?? this.message,
      type: type ?? this.type,
      enableVoice: enableVoice ?? this.enableVoice,
      customAudioPath: customAudioPath ?? this.customAudioPath,
      repeatDays: repeatDays ?? this.repeatDays,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      lastExecutedAt: lastExecutedAt ?? this.lastExecutedAt,
    );
  }
}

/// 劇本類型
enum ScriptType {
  reminder,   // 提醒類（吃藥、喝水）
  greeting,   // 問候類（早安、晚安）
  activity,   // 活動類（散步、運動）
  caring,     // 關懷類（關心心情）
}

/// 劇本類型擴展
extension ScriptTypeExtension on ScriptType {
  String get displayName {
    switch (this) {
      case ScriptType.reminder:
        return '提醒';
      case ScriptType.greeting:
        return '問候';
      case ScriptType.activity:
        return '活動';
      case ScriptType.caring:
        return '關懷';
    }
  }

  IconData get icon {
    switch (this) {
      case ScriptType.reminder:
        return Icons.alarm;
      case ScriptType.greeting:
        return Icons.waving_hand;
      case ScriptType.activity:
        return Icons.directions_walk;
      case ScriptType.caring:
        return Icons.favorite;
    }
  }

  Color get color {
    switch (this) {
      case ScriptType.reminder:
        return Colors.orange;
      case ScriptType.greeting:
        return Colors.purple;
      case ScriptType.activity:
        return Colors.green;
      case ScriptType.caring:
        return Colors.pink;
    }
  }
}
