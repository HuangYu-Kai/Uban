import 'package:flutter/material.dart';
import 'dart:async';
import '../models/pet_status.dart';

/// 寵物邏輯與狀態控制器 (ChangeNotifier)
/// 負責管理寵物的互動行為、3D 動畫狀態與對話內容
class PetController extends ChangeNotifier {
  /// 寵物數值狀態
  final PetStatus status = PetStatus();
  
  /// 當前 3D 模型的動畫名稱
  String currentAnimation = 'idle';
  
  /// 當前顯示的對話內容
  String currentDialog = '嘎挖！我在這裡！快轉動房間找找我～🐷';
  
  /// 2D 寵物圖片路徑 (作為備援或特定 UI 顯示)
  String petAssetPath = 'assets/images/pig_2d_idle_v4.png';
  
  /// 是否正在執行互動動畫 (防止重複觸發)
  bool isAnimating = false;

  /// 執行「玩耍」互動
  void play() {
    if (isAnimating) return;
    status.update(happinessDelta: 12, energyDelta: -8);
    _triggerInteraction(
      animationName: 'play', 
      dialog: '嘎挖！太好玩了！我們要一直玩下去喔！😆', 
      assetPath: 'assets/images/pig_2d_happy_v4.png',
      duration: const Duration(seconds: 4),
    );
  }

  /// 執行「餵食」互動
  void feed() {
    if (isAnimating) return;
    status.update(hungerDelta: 15, happinessDelta: 5);
    _triggerInteraction(
      animationName: 'eating', 
      dialog: '嘎挖！這真的超好吃的！謝謝你～😋', 
      assetPath: 'assets/images/pig_2d_happy_v4.png',
      duration: const Duration(seconds: 3),
    );
  }

  /// 執行「休息」互動
  void sleep() {
    if (isAnimating) return;
    status.update(energyDelta: 20, hungerDelta: -5);
    _triggerInteraction(
      animationName: 'sleep', 
      dialog: 'Zzz... 嘎挖想睡了... 晚安～😴', 
      assetPath: 'assets/images/pig_2d_idle_v4.png',
      duration: const Duration(seconds: 5),
    );
  }

  /// 處理 3D 場景中的點擊事件
  /// [nodeName] 來自 JavaScript Channel 傳回的點擊物件名稱
  void handleModelClick(String nodeName) {
    String message = '嘎挖！你點擊了房間的：$nodeName！';
    
    // 根據點擊的物件名稱提供差異化反應
    final lowerNode = nodeName.toLowerCase();
    if (lowerNode.contains('sofa')) {
      message = '嘎挖！這沙發好軟喔，好想在那裡滾來滾去～🛋️';
    } else if (lowerNode.contains('table') || lowerNode.contains('desk')) {
      message = '嘎挖！這裡是吃飯的地方嗎？我肚子餓了！😋';
    } else if (lowerNode.contains('bed')) {
      message = '嘎挖！那是你的床嗎？看起來好舒服～💤';
    } else if (lowerNode.contains('window')) {
      message = '嘎挖！外面的天氣看起來不錯耶！☀️';
    }
    
    currentDialog = message;
    notifyListeners();
    
    // 5 秒後自動恢復預設對話
    Timer(const Duration(seconds: 5), () {
      if (!isAnimating) {
        currentDialog = '嘎挖！隨時可以跟我互動喔！🐷';
        notifyListeners();
      }
    });
  }

  /// 觸發互動流程：切換動畫 -> 顯示對話 -> 延時恢復
  void _triggerInteraction({
    required String animationName,
    required String dialog,
    required String assetPath,
    required Duration duration,
  }) {
    isAnimating = true;
    currentAnimation = animationName;
    currentDialog = dialog;
    petAssetPath = assetPath;
    notifyListeners();

    // 在指定時間後恢復為閒置狀態
    Timer(duration, () {
      currentAnimation = 'idle';
      currentDialog = '嘎挖！隨時可以跟我互動喔！🐷';
      petAssetPath = 'assets/images/pig_2d_idle_v4.png';
      isAnimating = false;
      notifyListeners();
    });
  }
}
