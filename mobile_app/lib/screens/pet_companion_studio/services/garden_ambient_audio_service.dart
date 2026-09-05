import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 🎼 田園小豬背景音樂曲目定義
class GardenTrack {
  final String id;
  final String title;
  final String description;
  final String assetPath;
  final String emoji;
  final String durationText;

  const GardenTrack({
    required this.id,
    required this.title,
    required this.description,
    required this.assetPath,
    required this.emoji,
    required this.durationText,
  });
}

/// 🎵 田園大自然背景音樂與互動音效服務
class GardenAmbientAudioService {
  static const String kPrefBgmEnabled = 'pet_bgm_enabled';
  static const String kPrefBgmTrackId = 'pet_bgm_track_id';
  static const String kPrefBgmVolume = 'pet_bgm_volume';

  static const List<GardenTrack> availableTracks = [
    GardenTrack(
      id: 'piano_calm',
      title: '寧靜晨光鋼琴',
      description: '柔和舒緩古典鋼琴（Erik Satie - 裸體歌舞第一號）',
      assetPath: 'sounds/pastoral_calm_bgm.mp3',
      emoji: '🎹',
      durationText: '3分07秒',
    ),
    GardenTrack(
      id: 'acoustic_pastoral',
      title: '悠閒田園吉他',
      description: '溫暖鄉村木吉他與輕柔笛聲（Cattails 田園民謠）',
      assetPath: 'sounds/cattails_pastoral.mp3',
      emoji: '🌾',
      durationText: '3分32秒',
    ),
  ];

  final AudioPlayer _bgmPlayer = AudioPlayer();
  final AudioPlayer _sfxPlayer = AudioPlayer();

  bool _isMuted = false;
  bool get isMuted => _isMuted;

  double _volume = 0.28;
  double get volume => _volume;

  String _currentTrackId = 'piano_calm';
  String get currentTrackId => _currentTrackId;

  GardenTrack get currentTrack => availableTracks.firstWhere(
        (t) => t.id == _currentTrackId,
        orElse: () => availableTracks.first,
      );

  Future<void> initAndStartAmbience() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isMuted = !(prefs.getBool(kPrefBgmEnabled) ?? true);
      _currentTrackId = prefs.getString(kPrefBgmTrackId) ?? 'piano_calm';
      _volume = (prefs.getDouble(kPrefBgmVolume) ?? 0.28).clamp(0.05, 1.0);

      await _bgmPlayer.setReleaseMode(ReleaseMode.loop);
      await _bgmPlayer.setVolume(_isMuted ? 0.0 : _volume);

      if (!_isMuted) {
        await _bgmPlayer.play(AssetSource(currentTrack.assetPath));
      }
    } catch (e) {
      debugPrint('GardenAmbientAudioService init error: $e');
    }
  }

  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kPrefBgmEnabled, !_isMuted);

      if (_isMuted) {
        await _bgmPlayer.setVolume(0.0);
        await _bgmPlayer.pause();
      } else {
        await _bgmPlayer.setVolume(_volume);
        final state = _bgmPlayer.state;
        if (state == PlayerState.paused) {
          await _bgmPlayer.resume();
        } else {
          await _bgmPlayer.play(AssetSource(currentTrack.assetPath));
        }
      }
    } catch (e) {
      debugPrint('GardenAmbientAudioService toggleMute error: $e');
    }
  }

  Future<void> setTrack(String trackId) async {
    if (_currentTrackId == trackId) return;
    _currentTrackId = trackId;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kPrefBgmTrackId, trackId);

      await _bgmPlayer.stop();
      await _bgmPlayer.setReleaseMode(ReleaseMode.loop);
      await _bgmPlayer.setVolume(_isMuted ? 0.0 : _volume);
      if (!_isMuted) {
        await _bgmPlayer.play(AssetSource(currentTrack.assetPath));
      }
    } catch (e) {
      debugPrint('GardenAmbientAudioService setTrack error: $e');
    }
  }

  Future<void> setVolume(double vol) async {
    _volume = vol.clamp(0.0, 1.0);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(kPrefBgmVolume, _volume);

      if (!_isMuted) {
        await _bgmPlayer.setVolume(_volume);
      }
    } catch (e) {
      debugPrint('GardenAmbientAudioService setVolume error: $e');
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
