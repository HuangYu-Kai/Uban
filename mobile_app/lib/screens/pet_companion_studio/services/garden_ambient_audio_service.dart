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

  /// 「作者－歌曲名稱」單一乾淨字串，供跑馬燈（[PetMusicMarquee]）等只想
  /// 標注出處、不想顯示完整 [description]（含中文風格說明＋全形括號）的地方
  /// 使用。內容與 [description] 括號內的那段一致，只是拆成獨立欄位，不必在
  /// UI 端用正則從 description 挖字串。
  final String attribution;

  const GardenTrack({
    required this.id,
    required this.title,
    required this.description,
    required this.assetPath,
    required this.emoji,
    required this.durationText,
    required this.attribution,
  });
}

/// 🎧 目前播放中曲目的顯示用資訊（僅供 UI 顯示，例如跑馬燈標注出處，不影響
/// 播放邏輯本身）。null 代表目前靜音／尚未開始播放，任何監聽端收到 null
/// 都應該隱藏顯示，不要留著舊值誤導使用者以為還在播放。
class GardenNowPlaying {
  final String title;
  final String attribution;

  const GardenNowPlaying({required this.title, required this.attribution});
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
      attribution: 'Erik Satie - 裸體歌舞第一號',
    ),
    GardenTrack(
      id: 'acoustic_pastoral',
      title: '悠閒田園吉他',
      description: '溫暖鄉村木吉他與輕柔笛聲（Cattails 田園民謠）',
      assetPath: 'sounds/cattails_pastoral.mp3',
      emoji: '🌾',
      durationText: '3分32秒',
      attribution: 'Cattails - 田園民謠',
    ),
  ];

  /// ⚠️ 靜態、跨執行個體共享的「現在播放什麼」廣播管道。
  ///
  /// 真正持有播放器、實際播放音樂的是 [PetCornerActions] 內部建立的那顆
  /// [GardenAmbientAudioService] 實例；但小豬之家上緣的跑馬燈
  /// （[PetMusicMarquee]，見 pet_hero_stage.dart）跟它不是同一顆 widget
  /// 樹、拿不到那個實例。若跑馬燈自己再 new 一顆 [GardenAmbientAudioService]
  /// 讀狀態，會多開一顆 [AudioPlayer]，稍有不慎就會兩顆同時播放、疊出雙重
  /// 人聲。改用這顆 class 層級（不綁定任何一個實例）的 [ValueNotifier]：
  /// 誰在播放就誰負責呼叫 [_publishNowPlaying] 廣播，讀取端只訂閱通知、
  /// 不建立播放器本身。初始值是 null（尚未有任何實例完成初始化），跑馬燈
  /// 收到 null 一律隱藏，不會在正確狀態送達前顯示錯誤的「正在播放」假象。
  static final ValueNotifier<GardenNowPlaying?> nowPlayingNotifier =
      ValueNotifier<GardenNowPlaying?>(null);

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

  /// 廣播「現在播放什麼」給 [nowPlayingNotifier] 的訂閱端（跑馬燈）。
  /// 靜音時發布 null（隱藏），否則發布目前曲目的標題與出處。刻意不管
  /// `_bgmPlayer.play()` 實際有沒有拋例外——這幾個公開方法原本的錯誤處理
  /// 慣例就是失敗只 debugPrint、`_isMuted`/`_currentTrackId` 這兩個欄位不會
  /// 回滾，本欄位只是把既有的「使用者想要的狀態」如實廣播出去，不是新增一層
  /// 播放成功與否的驗證。
  void _publishNowPlaying() {
    nowPlayingNotifier.value = _isMuted
        ? null
        : GardenNowPlaying(
            title: currentTrack.title,
            attribution: currentTrack.attribution,
          );
  }

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
    _publishNowPlaying();
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
    _publishNowPlaying();
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
    _publishNowPlaying();
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
    // ⚠️ 這顆實例（通常是 PetCornerActions 持有的那顆）真正在播放背景音樂，
    // 一旦被 dispose 就不會再有聲音——把靜態的 nowPlayingNotifier 收回 null，
    // 讓跑馬燈同步隱藏，避免使用者看到「還在播放」的過期假象（例如切走小豬
    // 之家分頁又切回來，畫面重建出新實例前的短暫空窗期）。
    nowPlayingNotifier.value = null;
    _bgmPlayer.dispose();
    _sfxPlayer.dispose();
  }
}
