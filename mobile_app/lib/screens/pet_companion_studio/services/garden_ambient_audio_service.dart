import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:shared_preferences/shared_preferences.dart';

// ★ 第五十二輪（任務 C）：只借用這顆既有的 [ValueNotifier<int>]，不引入
// `global_assistant_button.dart` 其餘的浮動鈕 UI 程式碼（見下方類別註解與
// [_handleHiddenZoneChanged] 的完整理由）。
import '../../../widgets/global_assistant_button.dart'
    show assistantHiddenDepthNotifier;

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
///
/// ★ 第五十二輪（任務 C）：任務 B 的生命週期暫停只解決「整個 App 被系統
/// 切到背景」，沒解決「App 仍在前景、只是長輩在 App 內部切去了另一個畫面」
/// ——最典型的情境就是撥打／接聽電話：`ElderScreen` 一律用 `Navigator.push`
/// 疊上去，底下持有本服務的「我的」分頁不會被 dispose，`AppLifecycleState`
/// 全程停在 `resumed`，背景音樂會在通話全程持續播放、跟通話語音疊在一起。
/// 修法是額外監聽 `global_assistant_button.dart` 既有的
/// [assistantHiddenDepthNotifier]（詳見 [_handleHiddenZoneChanged]），並把
/// 「該不該恢復播放」收斂成同時檢查兩個獨立自動暫停來源（背景生命週期、
/// 音訊敏感畫面）的單一函式 [shouldResumeAutomatically]，避免其中一個來源
/// 誤判成「該恢復了」卻沒發現另一個來源其實還要求暫停——完整推演見該函式
/// 的文件註解。
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

  /// 是否已把 [_handleHiddenZoneChanged] 掛上 [assistantHiddenDepthNotifier]
  /// ——與 [_observerAttached] 同樣的防重複註冊理由，見該欄位說明。
  bool _hiddenZoneListenerAttached = false;

  /// 目前的暫停是不是「自動」造成的（不是使用者自己按停止）——跟 [_isMuted]
  /// 分開記錄，兩者語意不同、不可混用：
  /// - [_isMuted] = 使用者自己想不想聽，會寫回 SharedPreferences、跨 App
  ///   重啟持續有效，只有 [toggleMute] 這個「使用者主動停止」的入口會改它。
  /// - [_pausedAutomatically] = 純粹因為「App 被切到背景」或「目前在一個
  ///   音訊敏感畫面上」（見 [_isHiddenZoneActive]）而暫停播放，只是執行期
  ///   狀態、不寫入 SharedPreferences，兩個條件都解除後應該自動還原，不需要
  ///   （也不應該）使用者自己再按一次播放。
  /// ★ 第五十二輪（任務 C）：這個欄位原名 `_pausedForBackground`，只有背景
  /// 生命週期一個觸發來源；現在改成兩個來源共用同一個旗標（見類別開頭的
  /// 任務 C 說明），語意從「因為進背景而暫停」放寬成「因為某個自動來源而
  /// 暫停」。只有這個旗標是 true，才需要考慮恢復播放；使用者自己按過靜音
  /// （[_isMuted] 為 true）的話，不論這個旗標為何都不應該自作主張恢復。
  bool _pausedAutomatically = false;

  /// 目前 App 是不是在前景（[didChangeAppLifecycleState] 維護）。預設
  /// `true`——本服務只會在畫面 `initState` 時才會被建立，而 Flutter widget
  /// 能夠 build，代表 App 當下必然在前景，這個初始值不會有誤判空窗期。
  bool _isAppInForeground = true;

  /// 目前 [assistantHiddenDepthNotifier] 是不是 > 0，也就是畫面上是不是有
  /// 一個「音訊敏感畫面」（通話房／CCTV／來電響鈴／語音助理面板，見
  /// [_handleHiddenZoneChanged] 的完整說明）。由該回呼維護。
  bool _isHiddenZoneActive = false;

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
    // ★ 第五十二輪（任務 C）：與上面 observer 對稱，掛上音訊敏感畫面的
    // 監聽（見類別開頭與 [_handleHiddenZoneChanged] 的完整說明）。順便讀一次
    // notifier 目前的值——理論上本服務建立時不會有音訊敏感畫面疊在上面
    // （「我的」分頁在 `ElderHomeScreen` 的 `IndexedStack` 下與其他分頁一起
    // 早早建立，遠早於任何通話），但防禦性地同步一次目前值，不假設一定是
    // false。
    if (!_hiddenZoneListenerAttached) {
      assistantHiddenDepthNotifier.addListener(_handleHiddenZoneChanged);
      _hiddenZoneListenerAttached = true;
      _isHiddenZoneActive = assistantHiddenDepthNotifier.value > 0;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      _isMuted = !(prefs.getBool(kPrefBgmEnabled) ?? true);
      _currentTrackId = prefs.getString(kPrefBgmTrackId) ?? 'piano_calm';
      _volume = (prefs.getDouble(kPrefBgmVolume) ?? 0.28).clamp(0.05, 1.0);

      await _bgmPlayer.setReleaseMode(ReleaseMode.loop);
      await _bgmPlayer.setVolume(_isMuted ? 0.0 : _volume);

      if (!_isMuted) {
        if (_isHiddenZoneActive) {
          // 極少數情況：本服務是在音訊敏感畫面已經疊在上面時才第一次建立。
          // 不開始播放，並記成「自動暫停」，讓 [_resumeAutomatically] 之後
          // 離開該畫面時能接手播放——否則 [_pausedAutomatically] 停在預設值
          // false，之後永遠不會自動開始播放。
          _pausedAutomatically = true;
        } else {
          await _bgmPlayer.play(AssetSource(currentTrack.assetPath));
        }
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
      _isAppInForeground = false;
      _pauseAutomatically();
    } else if (state == AppLifecycleState.resumed) {
      _isAppInForeground = true;
      _resumeAutomatically();
    }
  }

  /// [assistantHiddenDepthNotifier] 變化時的回呼（第五十二輪任務 C）。
  ///
  /// ★ 重用這顆既有的 [ValueNotifier<int>]，而不是自己在通話相關檔案裡
  /// 新發明一個「是否在通話中」的全域旗標，理由有二：
  /// ① 依護欄 G199，它已經掛在 `elder_screen.dart`（通話房／CCTV）、
  /// `camera_screen.dart`（監控）、`elder_home_screen.dart` 與 `main.dart`
  /// 的來電響鈴 dialog、以及 `google_assistant_overlay.dart`（語音助理面板
  /// 自己）身上——這些正是「背景音樂應該安靜」的畫面全集，一次重用全部
  /// 涵蓋，不必逐一去改通話相關檔案（本服務全程沒有 import 任何一個）；
  /// ② `CLAUDE_call-monitor-ui-map.md` §5.4 把通話畫面的 initState/dispose
  /// 順序列為不可碰的禁區，本服務完全不需要碰它們。
  ///
  /// ⚠️ 這顆 notifier 原始語意是「浮動助理鈕該不該讓位」，這裡借來讀成
  /// 「目前是不是在一個音訊敏感畫面上」——目前兩者剛好是同一組畫面，但如果
  /// 日後有人替 [AssistantHiddenZone] 新增一個「不影響音訊」的掛載點（例如
  /// 純視覺的引導教學遮罩），本服務會被連帶觸發暫停。目前沒有這種畫面、暫不
  /// 處理，但下一個改動 [AssistantHiddenZone] 掛載點的人請留意本檔這個依賴。
  ///
  /// `assistantHiddenDepthNotifier` 是計數（可能有通話房 + 助理面板同時疊加
  /// 到 2），只在「0 ↔ 非 0」這個邊界觸發暫停／恢復嘗試，2→1 這種深度變化
  /// 不重複觸發。
  void _handleHiddenZoneChanged() {
    final bool isActive = assistantHiddenDepthNotifier.value > 0;
    if (isActive == _isHiddenZoneActive) return;
    _isHiddenZoneActive = isActive;
    if (isActive) {
      _pauseAutomatically();
    } else {
      _resumeAutomatically();
    }
  }

  /// 純邏輯：「自動暫停」來源（背景生命週期／音訊敏感畫面，見類別開頭任務 C
  /// 說明）觸發時「要不要暫停」的判斷。兩個來源共用同一個函式——判斷式本身
  /// 只在乎「使用者想不想聽」與「播放器現在是不是真的在播」，跟觸發暫停的
  /// 具體原因無關。
  ///
  /// 刻意獨立成不牽涉 [AudioPlayer]／平台通道的靜態方法——`audioplayers`
  /// 在 `flutter_test` 環境沒有真正的平台實作，`play()`/`pause()` 等呼叫
  /// 會被既有的 try/catch 吞掉例外，導致 `_bgmPlayer.state` 在測試裡永遠
  /// 停在初始值，沒辦法驗證「決策邏輯本身」對不對。把決策（該不該暫停／
  /// 該不該恢復）抽成純函式後，[garden_ambient_audio_service_lifecycle_test]
  /// 可以直接餵各種組合驗證分支，不需要假的 player 或平台通道 mock。
  ///
  /// 回傳 true 代表：使用者本來就想聽（`!isMuted`）而且播放器目前真的在
  /// 播放中——只有這種情況才需要因為自動來源而暫停，並記下
  /// [_pausedAutomatically]，之後才知道要自動恢復。使用者自己已經靜音的
  /// 情況下播放器本來就不是 playing 狀態，天然就不會誤觸。
  @visibleForTesting
  static bool shouldPauseAutomatically({
    required bool isMuted,
    required bool isCurrentlyPlaying,
  }) {
    return !isMuted && isCurrentlyPlaying;
  }

  /// 純邏輯：「要不要恢復播放」的判斷（理由與可測性說明見
  /// [shouldPauseAutomatically]）。
  ///
  /// ★ 第五十二輪（任務 C）：這裡是兩個自動暫停來源真正「收斂成單一判斷」
  /// 的地方——不論是背景回前景、還是音訊敏感畫面關閉觸發了這次檢查，都要
  /// 同時再檢查一次「現在」兩個來源各自的即時狀態（[isAppInForeground]／
  /// [isHiddenZoneActive]），任何一個仍然要求暫停，就不能恢復。這正是為了
  /// 避免「通話中（音訊敏感畫面仍在）又被系統切到背景」這種情境：回到前景
  /// 時，若只看 `pausedAutomatically && !isMuted` 這組舊條件，會誤判為該
  /// 恢復，但通話其實還沒掛斷——加上兩個來源都要檢查之後，只有兩者都不再
  /// 要求暫停時才會真的播放。
  ///
  /// 回傳 true 代表：這次暫停確實是自動來源造成的（[_pausedAutomatically]），
  /// 使用者沒有在這之間變成靜音，而且此刻 App 在前景、也沒有音訊敏感畫面
  /// 疊在上面——四個條件同時成立才應該恢復播放；使用者自己按過停止的話，
  /// 不應該因為螢幕重新亮起或通話結束就被自作主張打開音樂。
  @visibleForTesting
  static bool shouldResumeAutomatically({
    required bool pausedAutomatically,
    required bool isMuted,
    required bool isAppInForeground,
    required bool isHiddenZoneActive,
  }) {
    if (!pausedAutomatically || isMuted) return false;
    return isAppInForeground && !isHiddenZoneActive;
  }

  /// 自動暫停的實際執行（呼叫端：[didChangeAppLifecycleState] 與
  /// [_handleHiddenZoneChanged]）。決策交給 [shouldPauseAutomatically]，這裡
  /// 只負責實際呼叫播放器與更新 [_pausedAutomatically]。
  ///
  /// 不論哪個來源呼叫，若播放器此刻已經不是 playing（例如已經被另一個來源
  /// 暫停過），[shouldPauseAutomatically] 會回傳 false、提早 return——不會
  /// 把 [_pausedAutomatically] 洗回 true 或做任何多餘的事，兩個來源疊加觸發
  /// 不會互相干擾。
  Future<void> _pauseAutomatically() async {
    final bool isCurrentlyPlaying = _bgmPlayer.state == PlayerState.playing;
    if (!GardenAmbientAudioService.shouldPauseAutomatically(
      isMuted: _isMuted,
      isCurrentlyPlaying: isCurrentlyPlaying,
    )) {
      return;
    }
    try {
      await _bgmPlayer.pause();
      _pausedAutomatically = true;
    } catch (e) {
      debugPrint('GardenAmbientAudioService pauseAutomatically error: $e');
    }
  }

  /// 自動恢復的實際執行（呼叫端同上）。決策交給 [shouldResumeAutomatically]。
  ///
  /// ⚠️ 與修復前的單來源版本最大的差異：只有「真的執行了恢復」才清掉
  /// [_pausedAutomatically]；被 [shouldResumeAutomatically] 擋下時**保留**
  /// 這個旗標，讓之後「另一個來源」解除封鎖時還能接手恢復播放。例如：通話中
  /// （音訊敏感畫面 depth>0）又被切到背景，回前景時這裡會被擋下（因為
  /// `isHiddenZoneActive` 仍是 true）——若這時把旗標清掉，之後通話真的結束、
  /// depth 歸零時，[shouldResumeAutomatically] 會因為 `pausedAutomatically`
  /// 已經是 false 而誤判成「不需要恢復」，音樂就再也不會自動播放。保留旗標
  /// 直到真正恢復為止，兩個來源才能正確接力。
  Future<void> _resumeAutomatically() async {
    final bool shouldResume = GardenAmbientAudioService.shouldResumeAutomatically(
      pausedAutomatically: _pausedAutomatically,
      isMuted: _isMuted,
      isAppInForeground: _isAppInForeground,
      isHiddenZoneActive: _isHiddenZoneActive,
    );
    if (!shouldResume) return;
    _pausedAutomatically = false;
    try {
      await _bgmPlayer.setVolume(_volume);
      final state = _bgmPlayer.state;
      if (state == PlayerState.paused) {
        await _bgmPlayer.resume();
      } else {
        await _bgmPlayer.play(AssetSource(currentTrack.assetPath));
      }
    } catch (e) {
      debugPrint('GardenAmbientAudioService resumeAutomatically error: $e');
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
    // ★ 第五十二輪（任務 C）：與上面 observer 對稱移除，理由相同。
    if (_hiddenZoneListenerAttached) {
      assistantHiddenDepthNotifier.removeListener(_handleHiddenZoneChanged);
      _hiddenZoneListenerAttached = false;
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
