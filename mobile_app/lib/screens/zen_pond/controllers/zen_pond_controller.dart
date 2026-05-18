import 'package:flutter/material.dart';
import 'dart:async';

class ZenPondController extends ChangeNotifier {
  // SOS 相關狀態
  int _tapCount = 0;
  Timer? _tapTimer;
  bool isSOSMode = false;

  // 通知相關狀態
  String? currentNotification;
  bool isKoiVisible = false;
  bool isLotusVisible = false;

  void showNotification(String message) {
    currentNotification = message;
    isKoiVisible = true;
    isLotusVisible = false;
    notifyListeners();
  }

  void tapKoi() {
    isKoiVisible = false;
    isLotusVisible = true;
    notifyListeners();
  }

  void dismissLotus() {
    isLotusVisible = false;
    currentNotification = null;
    notifyListeners();
  }

  void handleTap() {
    // 增加點擊次數
    _tapCount++;
    
    // 如果計時器存在則重置
    _tapTimer?.cancel();
    
    // 如果達到 5 次，觸發 SOS
    if (_tapCount >= 5) {
      _triggerSOS();
      _tapCount = 0; // 重置
      return;
    }

    // 啟動 1 秒的重置計時器 (1秒內沒有再次點擊就會歸零)
    _tapTimer = Timer(const Duration(seconds: 1), () {
      _tapCount = 0;
    });
    
    notifyListeners();
  }

  void _triggerSOS() {
    isSOSMode = true;
    notifyListeners();
    
    print('🚨 觸發緊急 SOS 求救！(連續點擊 5 次)');
    // 這裡未來可以實作呼叫後端 API 的邏輯
    // ApiService.triggerSOS();
    
    // 模擬 5 秒後恢復正常狀態
    Timer(const Duration(seconds: 5), () {
      isSOSMode = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _tapTimer?.cancel();
    super.dispose();
  }
}
