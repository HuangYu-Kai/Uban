import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
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
///
/// ★ 第五十二輪（任務 B）：新增 [WidgetsBindingObserver]，讓每一顆實例自己
/// 感知 App 生命週期——修復前這裡完全沒有生命週期處理，App 被切到背景
/// （長輩去接電話、按 Home 鍵、切到別的 App）之後，`AudioPlayer` 完全不知情、
/// 背景音樂會繼續播放，直到使用者自己回來手動靜音。
///
/// 沒有做成真正的單例（每個畫面各自 `GardenAmbientAudioService()` 持有一顆
/// 實例、各自的 `initAndStartAmbience()`/`dispose()` 成對呼叫，見
/// `pet_corner_actions.dart`／`pet_studio_screen.dart`），但這不影響本次修復
/// ——把生命週期感知放進這個類別本身，每顆實例各自註冊/移除自己的
/// observer，天然對稱，呼叫端完全不用改。`pet_hero_stage.dart` 雖然也
/// import 了這個檔案，但它只讀靜態的 [nowPlayingNotifier] 顯示跑馬燈、
/// 從未建立自己的實例，因此不需要（也不應該）在那裡註冊 observer。
class GardenAmbientAudioService with WidgetsBindingObserver {
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

  /// 是否已把自己註冊為 [WidgetsBindingObserver]。`initAndStartAmbience()`
  /// 目前只會被呼叫端在 `initState` 呼叫一次，理論上不會重複註冊，這裡加
  /// 旗標防禦性避免萬一被呼叫第二次時，同一個實例被註冊兩次、導致
  /// [didChangeAppLifecycleState] 對同一次系統事件被呼叫兩次。
  bool _observerAttached = false;

  /// 目前的暫停是不是「App 進背景」自動造成的——跟 [_isMuted] 分開記錄，
  /// 兩者語意不同、不可混用：
  /// - [_isMuted] = 使用者自己想不想聽，會寫回 SharedPreferences、跨 App
  ///   重啟持續有效，只有 [toggleMute] 這個「使用者主動停止」的入口會改它。
  /// - [_pausedForBackground] = 純粹因為畫面現在看不到而暫停播放，只是
  ///   執行期狀態、不寫入 SharedPreferences，回到前景後應該自動還原，
  ///   不需要（也不應該）使用者自己再按一次播放。
  /// 只有這個旗標是 true，回到前景時才需要恢復播放；使用者自己按過靜音
  /// （[_isMuted] 為 true）的話，不論這個旗標為何都不應該自作主張恢復。
  bool _pausedForBackground = false;

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
    // ★ 第五十二輪（任務 B）：註冊生命週期 observer，讓這顆實例自己知道
    // App 進背景／回前景。與 [dispose] 的 `removeObserver` 對稱成對，
    // 呼叫端（`pet_corner_actions.dart`／`pet_studio_screen.dart`）
    // 既有的 initState/dispose 呼叫順序完全不用改。
    if (!_observerAttached) {
      WidgetsBinding.instance.addObserver(this);
      _observerAttached = true;
    }
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

  /// App 生命週期變化回呼（[WidgetsBindingObserver]）。
  ///
  /// ★ 第五十二輪（任務 B）：只處理「進背景」（`paused`／`hidden`）與
  /// 「回前景」（`resumed`）——`inactive`（下拉通知列、系統音量調整彈窗、
  /// 來電短暫覆蓋等）刻意不處理：這些情境使用者幾乎立刻就會回來，若在這裡
  /// 暫停會讓音樂斷斷續續，比完全不管更打擾。`detached` 也不處理，App 即將
  /// 終止，沒有「回前景恢復」的下文，處理了也沒有意義。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _pauseForBackground();
    } else if (state == AppLifecycleState.resumed) {
      _resumeFromBackground();
    }
  }

  /// 純邏輯：App 進背景時「要不要暫停」的判斷。
  ///
  /// 刻意獨立成不牽涉 [AudioPlayer]／平台通道的靜態方法——`audioplayers`
  /// 在 `flutter_test` 環境沒有真正的平台實作，`play()`/`pause()` 等呼叫
  /// 會被既有的 try/catch 吞掉例外，導致 `_bgmPlayer.state` 在測試裡永遠
  /// 停在初始值，沒辦法驗證「決策邏輯本身」對不對。把決策（該不該暫停／
  /// 該不該恢復）抽成純函式後，[garden_ambient_audio_service_lifecycle_test]
  /// 可以直接餵各種 `isMuted`／`isCurrentlyPlaying`／`pausedForBackground`
  /// 組合驗證分支，不需要假的 player 或平台通道 mock。
  ///
  /// 回傳 true 代表：使用者本來就想聽（`!isMuted`）而且播放器目前真的在
  /// 播放中——只有這種情況才需要因為進背景而暫停，並記下
  /// [_pausedForBackground]，回到前景後才知道要自動恢復。使用者自己已經
  /// 靜音的情況下播放器本來就不是 playing 狀態，天然就不會誤觸。
  @visibleForTesting
  static bool shouldPauseForBackground({
    required bool isMuted,
    required bool isCurrentlyPlaying,
  }) {
    return !isMuted && isCurrentlyPlaying;
  }

  /// 純邏輯：回到前景時「要不要恢復播放」的判斷（理由與可測性說明見
  /// [shouldPauseForBackground]）。
  ///
  /// 回傳 true 代表：這次暫停確實是背景事件自動造成的
  /// （[_pausedForBackground]），而且使用者沒有在這之間變成靜音——只有
  /// 這種情況才應該自動恢復播放；使用者自己按過停止的話，不應該因為螢幕
  /// 重新亮起就被自作主張打開音樂。「系統自動暫停」（[_pausedForBackground]）
  /// 與「使用者主動停止」（[_isMuted]）分開記錄、分開判斷，正是這兩個純
  /// 函式存在的理由。
  @visibleForTesting
  static bool shouldResumeFromBackground({
    required bool pausedForBackground,
    required bool isMuted,
  }) {
    return pausedForBackground && !isMuted;
  }

  /// App 進背景時的自動暫停。決策交給 [shouldPauseForBackground]，這裡只
  /// 負責實際呼叫播放器與更新 [_pausedForBackground]。
  Future<void> _pauseForBackground() async {
    final bool isCurrentlyPlaying = _bgmPlayer.state == PlayerState.playing;
    if (!GardenAmbientAudioService.shouldPauseForBackground(
      isMuted: _isMuted,
      isCurrentlyPlaying: isCurrentlyPlaying,
    )) {
      return;
    }
    try {
      await _bgmPlayer.pause();
      _pausedForBackground = true;
    } catch (e) {
      debugPrint('GardenAmbientAudioService pauseForBackground error: $e');
    }
  }

  /// 回到前景時的自動恢復。決策交給 [shouldResumeFromBackground]，這裡只
  /// 負責實際呼叫播放器。不論要不要恢復，這次背景事件都視為已處理完畢，
  /// 一律清掉 [_pausedForBackground]，避免這個旗標跨到下一次背景／前景
  /// 循環繼續生效。
  Future<void> _resumeFromBackground() async {
    final bool shouldResume = GardenAmbientAudioService.shouldResumeFromBackground(
      pausedForBackground: _pausedForBackground,
      isMuted: _isMuted,
    );
    _pausedForBackground = false;
    if (!shouldResume) return;
    try {
      await _bgmPlayer.setVolume(_volume);
      final state = _bgmPlayer.state;
      if (state == PlayerState.paused) {
        await _bgmPlayer.resume();
      } else {
        await _bgmPlayer.play(AssetSource(currentTrack.assetPath));
      }
    } catch (e) {
      debugPrint('GardenAmbientAudioService resumeFromBackground error: $e');
    }
  }

  void dispose() {
    // ★ 第五十二輪（任務 B）：與 [initAndStartAmbience] 的 `addObserver`
    // 對稱移除，否則 observer 會一直掛在 WidgetsBinding 上造成洩漏
    // （本專案其他畫面已有前例，見 family_settings_view.dart）。
    if (_observerAttached) {
      WidgetsBinding.instance.removeObserver(this);
      _observerAttached = false;
    }
    // ⚠️ 這顆實例（通常是 PetCornerActions 持有的那顆）真正在播放背景音樂，
    // 一旦被 dispose 就不會再有聲音——把靜態的 nowPlayingNotifier 收回 null，
    // 讓跑馬燈同步隱藏，避免使用者看到「還在播放」的過期假象（例如切走小豬
    // 之家分頁又切回來，畫面重建出新實例前的短暫空窗期）。
    nowPlayingNotifier.value = null;
    _bgmPlayer.dispose();
    _sfxPlayer.dispose();
  }
}
