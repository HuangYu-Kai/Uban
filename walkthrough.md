# Database Connection### 1. 造型分配邏輯優化 (Appearance Distribution)
- **3 步驟執行順序**：
    1. **備份與紀錄**：將長輩當前狀態（ID、造型、步數、開始時間）完整紀錄至 `get_appearance_list` 歷史表，`feed_endtime` 設為目前執行時間。
    2. **步數重置**：清空長輩當前的 `step_total`。
    3. **更新分配**：隨機挑選一個尚未擁有（或從全部中隨機）的新造型，分配給長輩，並更新 `feed_starttime` 為目前時間。
- **資料庫擴充**：在 `elder_profile` 成功新增 `feed_starttime` 欄位以支援此時序管理。

### 2. 測試介面簡化與增強 (Mobile App UI)
- **功能精簡**：移除開發中的測試按鈕，僅保留「全部長輩分配造型」與「排行榜查詢」。
- **使用者測試卡片**：新增「依 ID 查詢」功能，輸入長輩 ID 後即可即時查看該長輩的名稱、目前步數及當前造型 ID，大幅提升測試效率。

### 3. 專案清理與維護 (Clean up & Documentation)
- **環境清理**：刪除所有開發過程中的 `debug`, `inspect`, `verify` 以及 `dump` 相關腳本與暫存 Log，保持專案目錄整潔。
- **程式碼文件化**：修復了 `app.py` 因為編碼問題導致的亂碼註解，現在所有 Socket 服務與 API 邏輯均已同步為高品質的繁體中文註解。

---
**驗證狀態**：伺服器目前運行穩定（Threading 模式），所有 API 回應正常。

### 4. Admin Interface Update (管理員介面升級)
- **新介面 `admin_appearance_screen.dart`**：
  - **自動派發排程設定**：整合後端 `APScheduler`，管理員可指定未來時間，伺服器將在時間抵達時全自動執行全服造型派發。
  - **單一指定分配**：支援輸入 `elder_id` 與 `gawa_id`，立即手動強制指派造型 (支援舊紀錄備份機制)。
  - **進度查詢**：可直接查看特定長輩的目前的累積步數、擁有的造型精靈與對應的總加成。

### 5. User Dashboard (使用者儀表板升級)
- **專屬儀表板整合**：
  - 更新了 `/leaderboard/<elder_id>` 排行邏輯：回傳前10名好友，若使用者名落孫山，則自動將其名次貼在最後以凸顯排名差。全域均使用 `elder_name` 顯示。
  - **我的收集進度區**：在排行榜上方，直觀展示該名長輩擁有的歷史不重複造型縮圖，並動態累加計算 `bonus` 總和 (%) 給使用者看。

### 6. Pedometer Integration & Documents (計步器設計與架構導覽)
- **設計文件 `feedgawa_intro.md`**：建立專屬說明文件，清楚定義前端與後端的檔案關聯，並針對您要求的「實體走路偵測累積步數」功能，撰寫了採用 `pedometer` 硬體感測方案的技術建議與實作指南。

### 7. Real-Time Step Tracking (實體步數偵測實作)
- **硬體權限開通**：已在 `AndroidManifest.xml` 加入 `ACTIVITY_RECOGNITION`，並在 `Info.plist` 中配置 `NSMotionUsageDescription`，允許應用程式存取作業系統底層的健康與運動感測器。
- **後端同步 API**：在 `game_logic.py` 中新增 `POST /elder/update_steps` 端點，負責接收前端傳來的步數增量 (`delta_steps`) 並安全地穩定累加到資料庫的 `step_total` 內。
- **前端串接與防暴衝機制**：
  - 在 `leaderboard_screen.dart` (長輩專屬儀表板) 載入時自動請求權限並實作 `Pedometer.stepCountStream` 的串流監聽。
  - 結合 `SharedPreferences` 暫存本地上次硬體的總步數基準，精準計算出真實的「新增步數 (Delta)」。
  - 導入了 **10秒定時緩衝 (Sync Timer)** 機制。若長輩連續走動，會先將增加的步數緩存在本地即時更新 UI 排名，每隔 10 秒才統一將累積的這段步數一次性送回後端伺服器，大幅節省 API 負載並保留高流暢度的互動体验。即便是離開頁面，也會在 `dispose()` 時進行最後一次強制安全同步。

### 8. Pedometer Fallback & UI Enhancement (最佳相容性步數方案)
- **架構降級與相容性修復**：因部分 Android 廠牌 (如老舊的 Xiaomi / MIUI) 出廠並未正確搭載 Google Health Connect 的核心元件，導致原先 the `health` 作業系統層級 API 無法彈出授權視窗。為此，我們依據您的指示切回了相容性 100% 的 **硬體層感測器 (`pedometer`)** 方案 (Option 2)。
- **前端數字增加視覺化加強**：
  - **痛點解決**：直接讀取硬體計步感測器雖然不會有授權失敗的問題，但由於現代 Android 系統省電機制，每走十幾步硬體才會每「10 秒左右」整包吐出一次積累的步數去更新，造成 UI 視覺上會有「走很久才跳 10 步」的卡頓感。
  - **UI 強化實作**：為了掩蓋這個硬體延遲，在 `pedometer_test_screen.dart` 中我們導入了 `TweenAnimationBuilder` 進行 **1.5秒的平滑過渡滾動動畫**。當底層每 10 秒傳來增加了 15 步的訊號時，畫面的巨大數字會像吃角子老虎機一樣，滑順地連續滾動上升 (例如: 100 -> 103 -> 108 -> ... -> 115)！這樣便能大幅增加您在走動時看著螢幕的真實「增長感」。

### 9. 桌面小豬「賽博伴侶進化」第一階段：【養成基礎】實作
- **資料庫擴充**：在 `elder_profile` 新增 `hunger` 與 `intimacy` 欄位（預設值為 `50`），並更新白名單以支持安全的動態更新。
- **後端 API 實作**：
  - 新增 `POST /api/game/update_pet_status` 路由，安全限制數值在 `0-100` 之間後更新寫入資料庫。
  - 修改 `GET /api/game/elder_status/{elder_id}` 端點以返回 `hunger` 和 `intimacy` 數值。
- **前端小豬入口與轉場**：
  - 修改 `desktop_pet.dart` 中 `_onPetTap()` 邏輯，點擊桌面小豬後改為透過 Hero 動畫流暢轉場進入 `PetProfileScreen`。返回時自動重新加載最新狀態。
- **全新暗黑霓虹賽博養成介面 (`pet_profile_screen.dart`)**：
  - **視覺風格**：採用 `#0F172A` 到 `#020617` 的霓虹漸層背景，搭載高階毛玻璃 (Glassmorphism) 卡片面板，以發光進度條顯示肚子值與愛心值。
  - **滑動投餵蘋果 (Flick-to-Feed)**：實作拖曳蘋果的手勢回饋（包含亮青色虛線拉力軌跡），並在手指釋放後，依據速度向量與重力模擬二維拋物線物理飛行與碰撞判定。
  - **粒子與對話氣泡**：投餵成功後觸發向外擴散淡出的 $16$ 顆紅藍雙色霓虹愛心粒子特效，並隨機顯示「菲比語」魔性疊字對話氣泡，飽食度 $+15$、親密度 $+5$ 實時同步至後端。
  - **3D 空間導航**：在 AppBar 與右上角新增「傳送至 3D 空間」發光按鈕，引導長輩順利傳送至 `PetInteractionScreen` (3D 客廳)。
