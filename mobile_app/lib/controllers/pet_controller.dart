import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import '../models/pet_status.dart';

/// 3D 場景中的目標位置
class PetTargetPosition {
  final double x;
  final double y;
  final double z;
  final double confidence;

  const PetTargetPosition({
    required this.x,
    required this.y,
    required this.z,
    this.confidence = 0,
  });
}

/// 寵物邏輯與狀態控制器 (ChangeNotifier)
/// 負責管理寵物狀態、互動訊息與場景點擊事件
class PetController extends ChangeNotifier {
  final PetStatus status = PetStatus();

  String currentDialog = '嘎挖！我在這裡，點一下房間裡的物件看看～🐷';
  String targetArea = '客廳中央';
  PetTargetPosition targetPosition = const PetTargetPosition(x: 0, y: 0, z: 0);
  String currentAnimation = 'idle';
  String currentGoal = '在大廳閒逛';
  int pigWalkFrame = 0;
  bool isAiEnabled = true;

  Timer? _dialogResetTimer;
  Timer? _aiTimer;
  Timer? _animationTimer;
  Timer? _walkFrameTimer;

  final Map<String, Map<String, double>> _zones = {
    'table': {'x': -1.2, 'z': -0.8, 'y': 0.05},
    'sofa': {'x': 0.4, 'z': 0.4, 'y': 0.05},
    'tv': {'x': 1.2, 'z': -0.6, 'y': 0.05},
    'center': {'x': 0.0, 'z': 0.0, 'y': 0.05},
  };

  // 用於通知 UI 呼叫 JS 的回呼
  void Function(double x, double z, double y, String state)? onMoveRequested;

  void play() {
    status.update(happinessDelta: 12, energyDelta: -8);
    _setDialog('嘎挖！太好玩了！😆');
    playAnimation('play', const Duration(seconds: 3));
  }

  void feed() {
    status.update(hungerDelta: 15, happinessDelta: 5);
    _setDialog('嘎挖！好吃！謝謝你餵我～😋');
    playAnimation('eating', const Duration(seconds: 3));
  }

  void rest() {
    status.update(energyDelta: 20, hungerDelta: -6);
    _setDialog('Zzz... 我先休息一下～😴');
    playAnimation('sleep', const Duration(seconds: 3));
  }

  void playAnimation(String name, Duration duration) {
    _animationTimer?.cancel();
    currentAnimation = name;
    notifyListeners();

    _animationTimer = Timer(duration, () {
      currentAnimation = 'idle';
      notifyListeners();
    });
  }

  void startAiLoop() {
    _aiTimer?.cancel();
    _aiTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (isAiEnabled) _decideNextAction();
    });
  }

  void stopAiLoop() {
    _aiTimer?.cancel();
  }

  String _resolveTargetAreaName(String key) {
    switch (key) {
      case 'table': return '餐桌';
      case 'sofa': return '沙發';
      case 'tv': return '電視';
      case 'center': return '客廳中央';
      default: return '未知區域';
    }
  }

  void _decideNextAction() {
    final random = DateTime.now().millisecond % 4;
    String zoneKey;
    String state;
    
    switch (random) {
      case 0:
        zoneKey = 'table';
        state = 'happy';
        currentGoal = '去餐桌等飯';
        break;
      case 1:
        zoneKey = 'sofa';
        state = 'sleep';
        currentGoal = '去沙發睡覺';
        break;
      case 2:
        zoneKey = 'tv';
        state = 'idle';
        currentGoal = '去電視前發呆';
        break;
      default:
        zoneKey = 'center';
        state = 'idle';
        currentGoal = '在大廳閒逛';
        break;
    }

    final zone = _zones[zoneKey]!;
    targetArea = _resolveTargetAreaName(zoneKey);
    onMoveRequested?.call(zone['x']!, zone['z']!, zone['y']!, state);
    
    // 啟動步行動畫計時器
    _walkFrameTimer?.cancel();
    _walkFrameTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      pigWalkFrame = (pigWalkFrame == 0) ? 1 : 0;
      notifyListeners();
      // 如果停止走路了，關閉計時器 (暫定10秒)
      if (t.tick > 20) t.cancel();
    });

    notifyListeners();
  }

  /// 接收 ModelViewer JavaScriptChannel 回傳的 JSON
  /// 預期資料：
  /// {"x":0,"y":0,"z":0,"zone":"sofa","name":"sofa_mat","hit":true,"confidence":0.9}
  void handleModelTapPayload(String payload) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(payload) as Map<String, dynamic>;
    } on FormatException {
      _setDialog('我剛剛沒看清楚你點到哪裡，再點一次試試看～');
      return;
    }

    final double x = (data['x'] as num?)?.toDouble() ?? 0;
    final double y = (data['y'] as num?)?.toDouble() ?? 0;
    final double z = (data['z'] as num?)?.toDouble() ?? 0;
    final bool hit = data['hit'] as bool? ?? false;
    final double confidence = (data['confidence'] as num?)?.toDouble() ?? 0;
    final String zone = (data['zone'] as String? ?? 'living_room').toLowerCase();
    final String name = (data['name'] as String? ?? 'object').toLowerCase();

    if (!hit) {
      _setDialog('這次沒有點到可互動區域，試著點沙發或食盆附近～');
      return;
    }

    targetPosition = PetTargetPosition(x: x, y: y, z: z, confidence: confidence);
    targetArea = _resolveTargetArea(
      zone: zone,
      name: name,
      x: x,
      z: z,
    );
    _setDialog('收到！我要前往「$targetArea」(x:${x.toStringAsFixed(2)}, z:${z.toStringAsFixed(2)})');
  }

  String _resolveTargetArea({
    required String zone,
    required String name,
    required double x,
    required double z,
  }) {
    if (zone.contains('sofa') || name.contains('sofa')) {
      return '沙發';
    }
    if (zone.contains('bowl') ||
        zone.contains('food') ||
        name.contains('bowl') ||
        name.contains('food')) {
      return '食盆';
    }

    // 當模型材質名稱不足時，退回以 3D 座標做區域判斷，提升命中穩定度
    if (x >= -1.8 && x <= -0.3 && z >= -1.6 && z <= -0.2) {
      return '沙發';
    }
    if (x >= 0.2 && x <= 1.6 && z >= -0.9 && z <= 0.5) {
      return '食盆';
    }
    return '客廳區域';
  }

  void _setDialog(String message) {
    _dialogResetTimer?.cancel();
    currentDialog = message;
    notifyListeners();

    _dialogResetTimer = Timer(const Duration(seconds: 4), () {
      currentDialog = '嘎挖！隨時可以跟我互動喔！🐷';
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _dialogResetTimer?.cancel();
    _aiTimer?.cancel();
    _animationTimer?.cancel();
    _walkFrameTimer?.cancel();
    super.dispose();
  }
}
