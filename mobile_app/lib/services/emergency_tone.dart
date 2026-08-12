import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// ★ 2026-08-12 第二十三輪：緊急通話提示音（救護車雙音）的**全域單一擁有者**。
///
/// 為什麼要抽成單例（而不是留在 `ElderScreen` 裡）：
///
/// 緊急通話會從三條互不相干的通路抵達長輩端——
///   1. Socket `emergency-call`（APP 在前景／背景但存活）
///   2. FCM 前景備援（Socket 掉線或慢了）
///   3. FCM 背景 isolate（APP 被殺死 → 寫 prefs + Intent 喚醒 → 冷啟動）
/// 使用者要求「緊急通話音效**不論 APP 狀況皆須播放**」，所以提示音必須在
/// **收到緊急通話的當下**就響，而不是等 `ElderScreen` 被建構出來才響。
/// 但三條通路都可能先後觸發同一通通話，各自 new 一個 `AudioPlayer` 會疊音、
/// 而且 `ElderScreen.onPeerConnected` 只停得掉自己那一個 —— 剩下的會一直響到
/// 檔案播完，這正是護欄 G77「提示音必須停得掉」要防的事。
/// 收斂成單例後：先到者播放，後到者是 no-op，任何一處 `stop()` 都停得掉。
///
/// ⚠️ 刻意**不呼叫** `player.setAudioContext(...)`：全域已在 `main.dart` 設為
/// `AndroidAudioFocus.none`（護欄 G27）。在這裡覆寫成搶焦點會壓掉剛接通的通話
/// 語音，也會打斷長輩端常駐的語音喚醒監聽。
///
/// ⚠️ **不要**在 FCM 背景 isolate 呼叫本類別：背景 isolate 與主 isolate 的
/// plugin 實例是分開的，那裡播出來的音主 isolate 停不掉（違反 G77）。
/// 被殺死的情境改由冷啟動後 `ElderScreen._handleEmergencyAccept()` 補播。
class EmergencyTone {
  EmergencyTone._();

  static final EmergencyTone instance = EmergencyTone._();

  /// 救護車雙音（960Hz／770Hz 交替，7 秒）。
  /// 檔案由 `assets/sounds/` 整個目錄註冊（見 `pubspec.yaml`）。
  static const String assetPath = 'sounds/emergency_siren.wav';

  AudioPlayer? _player;
  StreamSubscription<void>? _completeSub;

  /// 每次 [play]／[stop] 都會遞增。用來讓「還在 await 中的舊 play()」自我作廢——
  /// 否則 `stop()` 在 `play()` 尚未把 player 存進 `_player` 前呼叫，會停不掉。
  int _generation = 0;

  bool get isPlaying => _player != null;

  /// 播放提示音。已經在響就直接返回（不重頭播、不疊音）。
  /// 播放失敗一律吞掉——提示音只是輔助，**絕不可**讓它擋住自動接聽流程。
  Future<void> play() async {
    if (_player != null) return;
    final int gen = ++_generation;
    AudioPlayer? player;
    try {
      player = AudioPlayer();
      await player.setReleaseMode(ReleaseMode.stop);
      await player.play(AssetSource(assetPath));
      if (gen != _generation) {
        // 播放期間已經被 stop() 取消（例如通話瞬間就接通了）
        await player.stop();
        await player.dispose();
        return;
      }
      _player = player;
      // 自然播完也要把狀態清乾淨，否則 isPlaying 會永遠是 true、下一通就播不出來。
      _completeSub = player.onPlayerComplete.listen((_) {
        if (gen == _generation) stop();
      });
      debugPrint('🚨 [EmergencyTone] 緊急提示音開始播放');
    } catch (e) {
      debugPrint('⚠️ [EmergencyTone] 播放失敗（不影響接聽）: $e');
      if (identical(_player, player)) _player = null;
      try {
        await player?.dispose();
      } catch (_) {}
    }
  }

  /// 停止並釋放。接通、離開通話畫面、來電被取消時都必須呼叫（護欄 G77）。
  Future<void> stop() async {
    _generation++;
    final sub = _completeSub;
    _completeSub = null;
    final player = _player;
    _player = null;
    try {
      await sub?.cancel();
    } catch (_) {}
    if (player == null) return;
    try {
      await player.stop();
      await player.dispose();
      debugPrint('🔇 [EmergencyTone] 緊急提示音已停止');
    } catch (e) {
      debugPrint('⚠️ [EmergencyTone] 停止失敗（忽略）: $e');
    }
  }
}
