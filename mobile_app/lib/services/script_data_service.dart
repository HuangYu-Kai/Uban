import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class ScriptNodeData {
  String id;
  String title;
  String content;
  Offset position;
  IconData icon;
  Color color;
  List<String> childrenIds;

  // Optional fields
  String? triggerType;
  List<String>? keywords;
  double? moodThreshold;
  String? triggerTime;
  String? weatherCondition;
  String? healthMetric;
  double? healthThreshold;
  String? iotDevice;
  String? iotEvent;
  String? voiceTone;
  int delaySeconds;
  String? mediaUrl;
  List<String>? choiceLabels;
  String? personaName;
  String? personaPrompt;
  String? memoryKey;
  String? memoryValue;
  String? timeRange;

  ScriptNodeData({
    required this.id,
    required this.title,
    required this.content,
    required this.position,
    required this.icon,
    required this.color,
    this.childrenIds = const [],
    this.triggerType,
    this.keywords,
    this.moodThreshold,
    this.triggerTime,
    this.weatherCondition,
    this.healthMetric,
    this.healthThreshold,
    this.iotDevice,
    this.iotEvent,
    this.voiceTone,
    this.delaySeconds = 0,
    this.mediaUrl,
    this.choiceLabels,
    this.personaName,
    this.personaPrompt,
    this.memoryKey,
    this.memoryValue,
    this.timeRange,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'position': {'dx': position.dx, 'dy': position.dy},
      'icon': icon.codePoint,
      'color': color.toARGB32(),
      'childrenIds': childrenIds,
      'triggerType': triggerType,
      'keywords': keywords,
      'moodThreshold': moodThreshold,
      'triggerTime': triggerTime,
      'weatherCondition': weatherCondition,
      'healthMetric': healthMetric,
      'healthThreshold': healthThreshold,
      'iotDevice': iotDevice,
      'iotEvent': iotEvent,
      'voiceTone': voiceTone,
      'delaySeconds': delaySeconds,
      'mediaUrl': mediaUrl,
      'choiceLabels': choiceLabels,
      'personaName': personaName,
      'personaPrompt': personaPrompt,
      'memoryKey': memoryKey,
      'memoryValue': memoryValue,
      'timeRange': timeRange,
    };
  }

  factory ScriptNodeData.fromMap(Map<String, dynamic> map) {
    return ScriptNodeData(
      id: map['id'],
      title: map['title'],
      content: map['content'],
      position: Offset(map['position']['dx'], map['position']['dy']),
      icon: IconData(map['icon'], fontFamily: 'MaterialIcons'),
      color: Color(map['color']),
      childrenIds: List<String>.from(map['childrenIds']),
      triggerType: map['triggerType'],
      keywords: map['keywords'] != null
          ? List<String>.from(map['keywords'])
          : null,
      moodThreshold: map['moodThreshold'],
      triggerTime: map['triggerTime'],
      weatherCondition: map['weatherCondition'],
      healthMetric: map['healthMetric'],
      healthThreshold: map['healthThreshold'],
      iotDevice: map['iotDevice'],
      iotEvent: map['iotEvent'],
      voiceTone: map['voiceTone'],
      delaySeconds: map['delaySeconds'] ?? 0,
      mediaUrl: map['mediaUrl'],
      choiceLabels: map['choiceLabels'] != null
          ? List<String>.from(map['choiceLabels'])
          : null,
      personaName: map['personaName'],
      personaPrompt: map['personaPrompt'],
      memoryKey: map['memoryKey'],
      memoryValue: map['memoryValue'],
      timeRange: map['timeRange'],
    );
  }
}

class ScriptMetadata {
  String title;
  String trigger;
  String action;
  String logic;
  bool isActive;
  IconData statusIcon;
  Color statusColor;

  ScriptMetadata({
    required this.title,
    this.trigger = '待設定',
    this.action = '動作：AI 調音流',
    this.logic = '邏輯：等待第一個節點',
    this.isActive = true,
    this.statusIcon = Icons.edit_calendar,
    this.statusColor = Colors.blueAccent,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'trigger': trigger,
      'action': action,
      'logic': logic,
      'isActive': isActive,
      'statusIcon': statusIcon.codePoint,
      'statusColor': statusColor.toARGB32(),
    };
  }

  factory ScriptMetadata.fromMap(Map<String, dynamic> map) {
    return ScriptMetadata(
      title: map['title'],
      trigger: map['trigger'] ?? '待設定',
      action: map['action'] ?? '動作：AI 調音流',
      logic: map['logic'] ?? '邏輯：等待第一個節點',
      isActive: map['isActive'] ?? true,
      statusIcon: IconData(
        map['statusIcon'] ?? Icons.edit_calendar.codePoint,
        fontFamily: 'MaterialIcons',
      ),
      statusColor: Color(map['statusColor'] ?? Colors.blueAccent.toARGB32()),
    );
  }
}

class ScriptDataService {
  static final ScriptDataService _instance = ScriptDataService._internal();
  factory ScriptDataService() => _instance;
  ScriptDataService._internal();

  final List<ScriptMetadata> _scripts = [];
  final Map<String, List<ScriptNodeData>> _scriptNodes = {};
  bool _isLoaded = false;

  Future<void> ensureLoaded() async {
    if (_isLoaded) return;
    await _loadFromDisk();
    _isLoaded = true;
  }

  Future<void> _loadFromDisk() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/scripts_registry.json');
      debugPrint('Loading scripts from: ${file.path}');
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        _scripts.clear();
        for (var item in jsonList) {
          _scripts.add(ScriptMetadata.fromMap(item));
        }
      }

      // Load individual nodes for each script
      for (var script in _scripts) {
        final nodeFile = File('${directory.path}/nodes_${script.title}.json');
        if (await nodeFile.exists()) {
          final nodeContent = await nodeFile.readAsString();
          final List<dynamic> nodeJsonList = jsonDecode(nodeContent);
          _scriptNodes[script.title] = nodeJsonList
              .map((e) => ScriptNodeData.fromMap(e))
              .toList();
        }
      }

      if (_scripts.isEmpty) {
        _scripts.addAll([
          ScriptMetadata(
            title: '每日血壓藥提醒',
            trigger: '每天 08:00',
            action: '動作：發出警報 + AI 語音',
            logic: '邏輯：若 15分 未按 -> Line 通知',
            statusIcon: Icons.check_circle,
            statusColor: Colors.green,
          ),
          ScriptMetadata(
            title: '週三下午茶話題 (京劇)',
            trigger: '週三 14:00',
            action: 'RAG 搜尋 "最新京劇演出"',
            logic: '邏輯：自動推送到廣播站',
            statusIcon: Icons.check_circle,
            statusColor: Colors.green,
          ),
        ]);
        await _saveToDisk();
      }
    } catch (e) {
      debugPrint('Error loading scripts from disk: $e');
    }
  }

  Future<void> _saveToDisk() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/scripts_registry.json');
      await file.writeAsString(
        jsonEncode(_scripts.map((e) => e.toMap()).toList()),
      );
    } catch (e) {
      debugPrint('Error saving scripts to disk: $e');
    }
  }

  List<ScriptMetadata> getAllScripts() => List.unmodifiable(_scripts);

  Future<void> addScript(ScriptMetadata script) async {
    if (!_scripts.any((s) => s.title == script.title)) {
      _scripts.add(script);
      await _saveToDisk();
    }
  }

  Future<void> deleteScript(String title) async {
    _scripts.removeWhere((s) => s.title == title);
    _scriptNodes.remove(title);
    await _saveToDisk();

    try {
      final directory = await getApplicationDocumentsDirectory();
      final nodeFile = File('${directory.path}/nodes_$title.json');
      if (await nodeFile.exists()) {
        await nodeFile.delete();
      }
    } catch (e) {
      debugPrint('Error deleting node file: $e');
    }
  }

  Future<void> updateScriptTitle(String oldTitle, String newTitle) async {
    final index = _scripts.indexWhere((s) => s.title == oldTitle);
    if (index != -1) {
      _scripts[index].title = newTitle;
      if (_scriptNodes.containsKey(oldTitle)) {
        _scriptNodes[newTitle] = _scriptNodes.remove(oldTitle)!;
      }
      await _saveToDisk();

      try {
        final directory = await getApplicationDocumentsDirectory();
        final oldFile = File('${directory.path}/nodes_$oldTitle.json');
        if (await oldFile.exists()) {
          final newFile = File('${directory.path}/nodes_$newTitle.json');
          await oldFile.rename(newFile.path);
        }
      } catch (e) {
        debugPrint('Error renaming node file: $e');
      }
    }
  }

  Future<void> toggleScriptActive(String title, bool isActive) async {
    final index = _scripts.indexWhere((s) => s.title == title);
    if (index != -1) {
      _scripts[index].isActive = isActive;
      await _saveToDisk();
    }
  }

  List<ScriptNodeData> getNodes(String scriptTitle) {
    return _scriptNodes[scriptTitle] ?? [];
  }

  Future<void> saveNodes(String scriptTitle, List<ScriptNodeData> nodes) async {
    _scriptNodes[scriptTitle] = List.from(nodes);

    // Auto-update metadata based on nodes
    final index = _scripts.indexWhere((s) => s.title == scriptTitle);
    if (index != -1) {
      final triggerNode = nodes
          .where((n) => n.title == '觸發' || n.triggerType != null)
          .firstOrNull;
      final actionNodes = nodes
          .where((n) => n.title == '動作' || n.voiceTone != null)
          .toList();

      if (triggerNode != null) {
        _scripts[index].trigger = _getTriggerSummary(triggerNode);
      }
      if (actionNodes.isNotEmpty) {
        _scripts[index].action = '動作：${actionNodes.length} 個步驟聯動';
      }
      await _saveToDisk();
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      final nodeFile = File('${directory.path}/nodes_$scriptTitle.json');
      debugPrint('Saving nodes to: ${nodeFile.path}');
      await nodeFile.writeAsString(
        jsonEncode(nodes.map((e) => e.toMap()).toList()),
      );
    } catch (e) {
      debugPrint('Error saving nodes file: $e');
    }
  }

  String _getTriggerSummary(ScriptNodeData node) {
    switch (node.triggerType) {
      case 'voice':
        return '語音：${(node.keywords ?? []).join(', ')}';
      case 'time':
        return '定時：${node.triggerTime ?? '未設定'}';
      case 'weather':
        return '天氣：${node.weatherCondition ?? '雨天'}';
      case 'health':
        return '健康：${node.healthMetric ?? '數值異常'}';
      case 'iot':
        return '感測：${node.iotDevice ?? '居家設備'}';
      default:
        return '待設定觸發';
    }
  }
}
