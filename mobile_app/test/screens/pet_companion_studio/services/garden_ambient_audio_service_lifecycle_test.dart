// 背景音樂自動暫停／恢復邏輯測試（第五十二輪，任務 B＋任務 C）。
//
// 背景（任務 B）：見 garden_ambient_audio_service.dart 類別開頭的說明——
// 修復前這裡完全沒有生命週期處理，App 被切到背景（長輩按 Home 鍵、切到
// 別的 App）之後，背景音樂會一直播下去，直到使用者自己回來手動靜音。
//
// 背景（任務 C）：任務 B 只解決「整個 App 被系統切到背景」，沒解決「App
// 仍在前景、只是長輩在 App 內部切去了通話畫面」——長輩在「我的」分頁聽著
// 背景音樂時撥打或接聽電話，`ElderScreen` 一律用 `Navigator.push` 疊上去，
// 底下持有本服務的分頁不會被 dispose、`AppLifecycleState` 全程停在
// `resumed`，背景音樂會在通話全程持續播放、跟通話語音疊在一起。任務 C
// 額外監聽 `global_assistant_button.dart` 既有的 `assistantHiddenDepthNotifier`
// （通話房／CCTV／來電響鈴／語音助理面板共用的「音訊敏感畫面」計數），並把
// 「要不要恢復播放」的判斷擴充成同時檢查「背景生命週期」與「音訊敏感畫面」
// 兩個獨立來源，避免其中一個來源誤判成「該恢復了」卻沒發現另一個來源其實
// 還要求暫停（例如：通話中又被系統切到背景，回到前景時通話其實還沒掛斷）。
//
// ⚠️ 為什麼只測純邏輯、不直接 pump 真正的 AudioPlayer／ValueNotifier 監聽：
// `audioplayers` 在 `flutter_test` 沙箱裡沒有真正的平台實作，
// `_bgmPlayer.play()`/`pause()` 等呼叫會被既有程式碼的 try/catch 吞掉例外，
// `_bgmPlayer.state` 也會一直停在初始值——用真正的 [GardenAmbientAudioService]
// 實例走一次完整流程，測不出「決策邏輯本身對不對」，只測得出「沒有炸掉」。
// 因此生產程式碼把「該不該暫停」「該不該恢復」抽成兩個不碰 AudioPlayer 的
// 靜態純函式（[GardenAmbientAudioService.shouldPauseAutomatically]／
// [GardenAmbientAudioService.shouldResumeAutomatically]，皆標了
// `@visibleForTesting`），本檔直接窮舉真值表逐一驗證；`_handleHiddenZoneChanged`
// 監聽器本身（是否真的在 depth 0↔非 0 的邊界正確觸發）留待實機驗證，理由與
// 下方「不建構真正實例」那段說明相同。
//
// 「系統自動暫停」與「使用者主動停止」分開記錄是任務 B 的核心，任務 C 沿用
// 同一組區分、只是把「系統自動暫停」的觸發來源從一個擴充成兩個——服務內部
// 用 `_isMuted`（使用者自己的靜音偏好，會寫回 SharedPreferences）與
// `_pausedAutomatically`（純執行期狀態，代表「這次暫停是背景或音訊敏感畫面
// 其中一個自動來源造成的」，任務 C 之前叫 `_pausedForBackground`）兩個獨立
// 欄位，本檔測的三個純函式就是這些欄位之間唯一有邏輯關係的地方。
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/screens/pet_companion_studio/services/garden_ambient_audio_service.dart';

void main() {
  group('shouldPauseAutomatically（自動來源要不要暫停；背景與音訊敏感畫面共用）', () {
    // ★ 任務 C：這顆函式原名 shouldPauseForBackground，只有「App 進背景」
    // 一個呼叫端；現在 [_handleHiddenZoneChanged]（音訊敏感畫面 depth
    // 0→非 0，例如通話開始）也呼叫同一顆函式——判斷式本身只在乎「使用者
    // 想不想聽」與「播放器現在是不是真的在播」，跟觸發暫停的具體原因無關，
    // 因此下面幾個測項同時涵蓋兩種觸發來源，不需要為音訊敏感畫面另外複製
    // 一份幾乎一樣的真值表。
    test('使用者想聽、播放器正在播放 → 應該暫停（App 進背景／通話開始皆適用）', () {
      expect(
        GardenAmbientAudioService.shouldPauseAutomatically(
          isMuted: false,
          isCurrentlyPlaying: true,
        ),
        isTrue,
      );
    });

    test('使用者想聽、但播放器目前沒在播放 → 不應該動作', () {
      // 沒在播放（例如還在初始化、已經自然停止、或已經被另一個自動來源
      // 暫停過）就沒有東西好暫停，更不該把 _pausedAutomatically 誤設為
      // true——那會讓之後被誤判為「該恢復」。這正是兩個來源疊加時
      // （例如通話中又被切到背景）不會互相干擾的關鍵。
      expect(
        GardenAmbientAudioService.shouldPauseAutomatically(
          isMuted: false,
          isCurrentlyPlaying: false,
        ),
        isFalse,
      );
    });

    test('使用者已經靜音，即使播放器仍回報在播放 → 不應該動作', () {
      // 正常情況下靜音時播放器不會是 playing 狀態，這裡是防禦性驗證：
      // 就算兩個輸入互相矛盾，_isMuted 為 true 也必須讓結果恆為 false，
      // 不能因為 isCurrentlyPlaying 剛好是 true 就誤觸「自動暫停」這條
      // 路徑（那會連帶讓之後被誤判為該恢復播放）。
      expect(
        GardenAmbientAudioService.shouldPauseAutomatically(
          isMuted: true,
          isCurrentlyPlaying: true,
        ),
        isFalse,
      );
    });

    test('使用者已經靜音、播放器也沒在播放 → 不應該動作', () {
      expect(
        GardenAmbientAudioService.shouldPauseAutomatically(
          isMuted: true,
          isCurrentlyPlaying: false,
        ),
        isFalse,
      );
    });
  });

  group('shouldResumeAutomatically（要不要恢復播放；同時檢查兩個自動暫停來源）', () {
    // ★ 任務 C：這顆函式原本只有兩個參數（pausedForBackground／isMuted，
    // 對應舊名 shouldResumeFromBackground）。現在多了 isAppInForeground／
    // isHiddenZoneActive 兩個參數，把「要不要恢復播放」收斂成同時檢查
    // 「背景生命週期」與「音訊敏感畫面」兩個獨立來源的單一判斷——不論是
    // 哪一邊變化觸發了這次檢查，四個條件都要同時成立才會真的恢復。
    //
    // 前四個測項（isAppInForeground: true, isHiddenZoneActive: false）就是
    // 舊版兩參數真值表的等價延伸，證明擴充參數後既有的背景恢復邏輯沒有
    // 退步；後面的測項才是任務 C 真正新增的情境。
    test('全部安全（有自動暫停紀錄、未靜音、在前景、沒有音訊敏感畫面）→ 應該恢復', () {
      expect(
        GardenAmbientAudioService.shouldResumeAutomatically(
          pausedAutomatically: true,
          isMuted: false,
          isAppInForeground: true,
          isHiddenZoneActive: false,
        ),
        isTrue,
      );
    });

    test('這次暫停不是自動來源造成的（使用者自己按停止） → 不應該恢復', () {
      // pausedAutomatically 為 false 代表播放器原本就處於「使用者自己
      // 選擇的靜音／停止」狀態，其餘條件再怎麼安全也不該把它打開。
      expect(
        GardenAmbientAudioService.shouldResumeAutomatically(
          pausedAutomatically: false,
          isMuted: false,
          isAppInForeground: true,
          isHiddenZoneActive: false,
        ),
        isFalse,
      );
    });

    test('使用者已經靜音（不論是背景恢復還是通話結束觸發）→ 不應該自己播起來', () {
      // 這條是「系統自動暫停」與「使用者主動停止」分開記錄的存在意義，
      // 也直接對應「使用者主動停止後，depth 變化不會讓它自己播起來」這個
      // 驗收項目：即使 pausedAutomatically 為 true、App 在前景、也沒有
      // 音訊敏感畫面，只要使用者已經表態不想聽（isMuted），就不可以
      // 自作主張把音樂打開——不論是背景回前景、還是
      // [_handleHiddenZoneChanged] 偵測到通話結束觸發了這次檢查都一樣。
      expect(
        GardenAmbientAudioService.shouldResumeAutomatically(
          pausedAutomatically: true,
          isMuted: true,
          isAppInForeground: true,
          isHiddenZoneActive: false,
        ),
        isFalse,
      );
    });

    test('沒有被自動來源暫停、使用者也是靜音狀態 → 不應該恢復', () {
      expect(
        GardenAmbientAudioService.shouldResumeAutomatically(
          pausedAutomatically: false,
          isMuted: true,
          isAppInForeground: true,
          isHiddenZoneActive: false,
        ),
        isFalse,
      );
    });

    test('App 還在背景（isAppInForeground: false）→ 即使其餘條件都安全，也不應該恢復', () {
      expect(
        GardenAmbientAudioService.shouldResumeAutomatically(
          pausedAutomatically: true,
          isMuted: false,
          isAppInForeground: false,
          isHiddenZoneActive: false,
        ),
        isFalse,
      );
    });

    test('通話中（depth>0）＋App 剛回到前景 → 仍然不應該恢復播放', () {
      // ★ 這是任務 C 要修的核心情境，也是本檔最重要的一條新測項：長輩
      // 通話全程 App 都在前景（音訊敏感畫面 isHiddenZoneActive 為 true），
      // 中途又被系統切去背景再切回來——回到前景時 isAppInForeground 變回
      // true，但通話其實還沒掛斷。若只看舊版兩參數（pausedAutomatically
      // && !isMuted）會誤判為「該恢復」，加上 isHiddenZoneActive 這個
      // 額外條件之後，只要通話還在，就不會被回前景這個事件誤觸恢復播放。
      expect(
        GardenAmbientAudioService.shouldResumeAutomatically(
          pausedAutomatically: true,
          isMuted: false,
          isAppInForeground: true,
          isHiddenZoneActive: true,
        ),
        isFalse,
      );
    });

    test('通話中（depth>0）且 App 仍在背景 → 不應該恢復（兩個來源同時擋）', () {
      expect(
        GardenAmbientAudioService.shouldResumeAutomatically(
          pausedAutomatically: true,
          isMuted: false,
          isAppInForeground: false,
          isHiddenZoneActive: true,
        ),
        isFalse,
      );
    });

    test('通話剛結束（depth 1→0）、App 本來就在前景、也沒有靜音 → 應該恢復', () {
      // 對應「1→0 恢復」這個驗收項目：[_handleHiddenZoneChanged] 偵測到
      // 音訊敏感畫面 depth 歸零時觸發這次檢查，此時若背景那一側本來就是
      // 前景、使用者也沒靜音，兩個來源都不再要求暫停，應該真的恢復播放。
      expect(
        GardenAmbientAudioService.shouldResumeAutomatically(
          pausedAutomatically: true,
          isMuted: false,
          isAppInForeground: true,
          isHiddenZoneActive: false,
        ),
        isTrue,
      );
    });
  });

  // ⚠️ 刻意不在這裡另外建構真正的 GardenAmbientAudioService() 實例做「型別
  // 有沒有混入 WidgetsBindingObserver」「didChangeAppLifecycleState／
  // _handleHiddenZoneChanged 呼叫會不會拋例外」這類煙霧測試——實測發現光是
  // `AudioPlayer()` 建構子本身就會觸發 `audioplayers` 套件內部的
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
  // 真正需要驗證的是本檔已經覆蓋的決策邏輯本身；observer／監聽器的註冊與
  // 移除是否真的在畫面生命週期上正確觸發、通話期間背景音樂實際上聽不聽得
  // 到，留待實機驗證（見任務回報）。
}
