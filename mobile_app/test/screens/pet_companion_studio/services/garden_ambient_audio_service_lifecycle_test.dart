// 背景音樂 App 生命週期邏輯測試（第五十二輪，任務 B）。
//
// 背景：見 garden_ambient_audio_service.dart 類別開頭的說明——修復前這裡
// 完全沒有生命週期處理，App 被切到背景（長輩去接電話、按 Home 鍵、切到
// 別的 App）之後，背景音樂會一直播下去，直到使用者自己回來手動靜音。
//
// ⚠️ 為什麼只測純邏輯、不直接 pump 真正的 AudioPlayer：
// `audioplayers` 在 `flutter_test` 沙箱裡沒有真正的平台實作，
// `_bgmPlayer.play()`/`pause()` 等呼叫會被既有程式碼的 try/catch 吞掉例外，
// `_bgmPlayer.state` 也會一直停在初始值——用真正的 [GardenAmbientAudioService]
// 實例走一次完整流程，測不出「決策邏輯本身對不對」，只測得出「沒有炸掉」。
// 因此生產程式碼把「該不該暫停」「該不該恢復」抽成兩個不碰 AudioPlayer 的
// 靜態純函式（[GardenAmbientAudioService.shouldPauseForBackground]／
// [GardenAmbientAudioService.shouldResumeFromBackground]，皆標了
// `@visibleForTesting`），本檔直接窮舉真值表逐一驗證。
//
// 「系統自動暫停」與「使用者主動停止」分開記錄是本次修復的核心——服務內部
// 用 `_isMuted`（使用者自己的靜音偏好，會寫回 SharedPreferences）與
// `_pausedForBackground`（純執行期狀態，只代表「這次暫停是因為看不到畫面」）
// 兩個獨立欄位，本檔測的兩個純函式就是這兩個欄位之間唯一有邏輯關係的地方
// ——`shouldResumeFromBackground` 只有 `_pausedForBackground` 為 true**且**
// `_isMuted` 為 false 才會恢復，任何一邊不成立都不該自作主張動使用者的
// 音樂開關。
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/screens/pet_companion_studio/services/garden_ambient_audio_service.dart';

void main() {
  group('shouldPauseForBackground（App 進背景時要不要暫停）', () {
    test('使用者想聽、播放器正在播放 → 應該暫停', () {
      expect(
        GardenAmbientAudioService.shouldPauseForBackground(
          isMuted: false,
          isCurrentlyPlaying: true,
        ),
        isTrue,
      );
    });

    test('使用者想聽、但播放器目前沒在播放 → 不應該動作', () {
      // 沒在播放（例如還在初始化、或已經自然停止）就沒有東西好暫停，
      // 更不該把 _pausedForBackground 誤設為 true——那會讓回到前景時
      // 無中生有地把音樂打開。
      expect(
        GardenAmbientAudioService.shouldPauseForBackground(
          isMuted: false,
          isCurrentlyPlaying: false,
        ),
        isFalse,
      );
    });

    test('使用者已經靜音，即使播放器仍回報在播放 → 不應該動作', () {
      // 正常情況下靜音時播放器不會是 playing 狀態，這裡是防禦性驗證：
      // 就算兩個輸入互相矛盾，_isMuted 為 true 也必須讓結果恆為 false，
      // 不能因為 isCurrentlyPlaying 剛好是 true 就誤觸「系統自動暫停」
      // 這條路徑（那會連帶讓回到前景時被誤判為該恢復播放）。
      expect(
        GardenAmbientAudioService.shouldPauseForBackground(
          isMuted: true,
          isCurrentlyPlaying: true,
        ),
        isFalse,
      );
    });

    test('使用者已經靜音、播放器也沒在播放 → 不應該動作', () {
      expect(
        GardenAmbientAudioService.shouldPauseForBackground(
          isMuted: true,
          isCurrentlyPlaying: false,
        ),
        isFalse,
      );
    });
  });

  group('shouldResumeFromBackground（回到前景時要不要恢復播放）', () {
    test('剛剛是被背景事件暫停、使用者也還沒靜音 → 應該恢復', () {
      expect(
        GardenAmbientAudioService.shouldResumeFromBackground(
          pausedForBackground: true,
          isMuted: false,
        ),
        isTrue,
      );
    });

    test('剛剛是被背景事件暫停，但使用者在這之間已經靜音 → 不應該恢復', () {
      // 這條是「系統自動暫停」與「使用者主動停止」分開記錄的存在意義：
      // 即使 _pausedForBackground 為 true，只要使用者已經表態不想聽
      // （_isMuted），回到前景就不可以自作主張把音樂打開。
      expect(
        GardenAmbientAudioService.shouldResumeFromBackground(
          pausedForBackground: true,
          isMuted: true,
        ),
        isFalse,
      );
    });

    test('這次暫停不是背景事件造成的（使用者自己按停止） → 不應該恢復', () {
      // pausedForBackground 為 false 代表播放器原本就處於「使用者自己選擇
      // 的靜音／停止」狀態，回到前景不該把它打開。
      expect(
        GardenAmbientAudioService.shouldResumeFromBackground(
          pausedForBackground: false,
          isMuted: false,
        ),
        isFalse,
      );
    });

    test('沒有被背景事件暫停、使用者也是靜音狀態 → 不應該恢復', () {
      expect(
        GardenAmbientAudioService.shouldResumeFromBackground(
          pausedForBackground: false,
          isMuted: true,
        ),
        isFalse,
      );
    });
  });

  // ⚠️ 刻意不在這裡另外建構真正的 GardenAmbientAudioService() 實例做「型別
  // 有沒有混入 WidgetsBindingObserver」「didChangeAppLifecycleState 呼叫
  // 會不會拋例外」這類煙霧測試——實測發現光是 `AudioPlayer()`
  // 建構子本身就會觸發 `audioplayers` 套件內部的
  // `GlobalAudioScope.ensureInitialized()`，在 `flutter_test` 沙箱裡對
  // `xyz.luan/audioplayers.global` 這個平台通道丟出
  // `MissingPluginException`，且是在建構子的非同步縫隙中丟出、不在任何
  // 呼叫端的 try/catch 保護範圍內，會讓測試在「已經回報通過」之後才失敗
  // （"This test failed after it had already completed"）。要讓這類測試
  // 穩定，得先對 `audioplayers` 好幾個平台通道注入 mock handler，這些
  // 通道名稱／方法都是套件內部實作細節、不是公開 API，耦合下去在套件版本
  // 升級時容易無聲失效。「型別是否混入 WidgetsBindingObserver」與
  // 「覆寫方法簽章是否正確」這兩件事，`flutter analyze`／編譯期已經會
  // 擋下明顯錯誤（mixin 打錯字、@override 簽章不符都無法通過編譯），
  // 真正需要驗證的是本檔已經覆蓋的決策邏輯本身；observer 註冊/移除是否
  // 真的在畫面生命週期上正確觸發，留待實機驗證（見任務回報）。
}
