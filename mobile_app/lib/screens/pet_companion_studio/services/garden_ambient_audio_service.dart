import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// 🎵 田園大自然白噪音與互動音效服務
class GardenAmbientAudioService {
  final AudioPlayer _bgmPlayer = AudioPlayer();
  final AudioPlayer _sfxPlayer = AudioPlayer();

  bool _isMuted = false;
  bool get isMuted => _isMuted;

  Future<void> initAndStartAmbience() async {
    try {
      await _bgmPlayer.setReleaseMode(ReleaseMode.loop);
      await _bgmPlayer.setVolume(0.32); // 輕柔自然白噪音音量
      await _bgmPlayer.play(AssetSource('sounds/garden_ambient_breeze.wav'));
    } catch (e) {
      debugPrint('GardenAmbientAudioService bgm error: $e');
    }
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    if (_isMuted) {
      _bgmPlayer.setVolume(0.0);
    } else {
      _bgmPlayer.setVolume(0.32);
    }
  }

  Future<void> playHarvest() async {
    if (_isMuted) return;
    try {
      await _sfxPlayer.stop();
      await _sfxPlayer.setVolume(0.55);
      await _sfxPlayer.play(AssetSource('sounds/pop_harvest.wav'));
    } catch (e) {
      debugPrint('GardenAmbientAudioService sfx error: $e');
    }
  }

  void dispose() {
    _bgmPlayer.dispose();
    _sfxPlayer.dispose();
  }
}
