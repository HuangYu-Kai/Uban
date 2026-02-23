import 'package:flutter/material.dart';

class ScriptNode {
  final String id;
  String title;
  String content;
  Offset position;
  final IconData icon;
  final Color color;
  final List<String> childrenIds;

  // Trigger Settings
  String triggerType; // 'voice', 'time', 'weather', 'health', 'iot'
  List<String>? keywords;
  double? moodThreshold;
  String? triggerTime;
  String? weatherCondition;
  String? healthMetric;
  double? healthThreshold;
  String? iotDevice;
  String? iotEvent;

  // Action Settings
  String? voiceTone;
  int delaySeconds;
  String? mediaUrl;

  // Condition Settings
  String? timeRange;

  // Choice Settings
  List<String>? choiceLabels; // For branching

  // Persona Settings
  String? personaName;
  String? personaPrompt;

  // Memory Settings
  String? memoryKey;
  String? memoryValue;

  ScriptNode({
    required this.id,
    required this.title,
    required this.content,
    required this.position,
    required this.icon,
    required this.color,
    List<String>? childrenIds,
    this.triggerType = 'voice',
    this.keywords,
    this.moodThreshold = 0.5,
    this.triggerTime,
    this.weatherCondition = '雨天',
    this.healthMetric = '心率',
    this.healthThreshold = 100,
    this.iotDevice = '門窗感測器',
    this.iotEvent = '開啟',
    this.voiceTone = '溫暖',
    this.delaySeconds = 0,
    this.mediaUrl,
    this.timeRange = '全天',
    this.choiceLabels,
    this.personaName,
    this.personaPrompt,
    this.memoryKey,
    this.memoryValue,
  }) : childrenIds = childrenIds ?? [];
}
