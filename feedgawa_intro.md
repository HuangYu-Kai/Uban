# 走路養小豬 — 造型分配與排行榜系統架構 (Feed Gawa Intro)

這份文件標示了「走路養小豬」遊戲化模組中，造型分配、計步排行榜與收集系統的所有相關程式碼位置、等級機制與負責功能。

> 📝 *文件最後更新時間：2026/04/02*

---

## 0. 等級與步數門檻對照表

小豬的成長等級由長輩的累積步數 (`step_total`) 決定，前後端邏輯一致（見 `leaderboard_screen.dart` 的 `getLevelFromSteps()` 與 `game_logic.py` 的 `get_level()`）。

| 等級 (Level) | 累積步數門檻 (≤) | 小豬縮放比例 | 說明 |
|:---:|---:|:---:|------|
| Lv.1 | 1,000 步 | 1.0x | 🐣 剛孵化的小豬 |
| Lv.2 | 20,000 步 | 1.2x | 🐷 初來乍到 |
| Lv.3 | 50,000 步 | 1.4x | 🐷 穩步成長 |
| Lv.4 | 150,000 步 | 1.6x | 🐷 活力充沛 |
| Lv.5 | 300,000 步 | 1.8x | 🐷 健步如飛 |
| Lv.6 | 700,000 步 | 2.0x | 💪 體能達人 |
| Lv.7 | 1,000,000 步 | 2.2x | 🏆 傳奇行者 |
| Lv.8 | > 1,000,000 步 | 2.4x | 👑 步行之王 |

> **縮放公式**：`scale = 0.8 + (level × 0.2)`，Lv.1 為 1.0 倍，每升一級增大 0.2 倍至 Lv.8 的 2.4 倍。

### 相關程式碼位置
- **前端**：[`leaderboard_screen.dart`](file:///e:/114Project/UniFlow/mobile_app/lib/screens/leaderboard_screen.dart) — `getLevelFromSteps()` (L243)、`getLevelSteps()` (L254)、`getLevelScale()` (L267)
- **後端**：[`game_logic.py`](file:///e:/114Project/UniFlow/server/routes/game_logic.py) — `get_level()` (L28)

---

## 1. 系統架構與相關檔案總覽

### 管理者端 (Administrator side)
管理者負責設定發放時間、強制分配特定造型，以及查看個別長輩的收集狀況。

- **[前端 UI] `mobile_app/lib/screens/admin_appearance_screen.dart`**
  - **功能**: 管理者專用介面。提供三個主要區塊：
    1. **排程設定**: 透過時間選擇器設定下次全服隨機派發造型的時間。
    2. **單獨分配**: 透過輸入 `elder_id` 與 `gawa_id`，強制覆寫指定長輩的當前造型與開始時間。
    3. **長輩資訊查詢**: 查詢指定 `elder_id` 的累積步數、擁有的所有造型清單及當前總加成比例。
- **[後端 API] `server/routes/game_logic.py`**
  - **`set_distribution_time`**: 接收前端時間並寫入 `schedule_config.json`。
  - **`assign_appearance`**: 執行手動指派邏輯 (備份舊紀錄 -> 重置步數 -> 寫入新造型)。
  - **`get_admin_elder_info`**: 統整特定長輩的所有資料 (包含歷史 `get_appearance_list` 紀錄) 並回傳。
- **[後端背景] `server/app.py`**
  - **`APScheduler` 排程器**: 每分鐘自動檢查 `schedule_config.json`，若時間到達，則呼叫 `do_distribute_appearances()` 進行全服發放。

### 使用者端 / 長輩端 (User / Elder side)
使用者主要查看自己的小豬成長、好友排行榜排名，以及目前擁有的造型進度與加成。

- **[前端 UI] `mobile_app/lib/screens/leaderboard_screen.dart`**
  - **功能**: 走路養小豬儀表板與排行榜介面。
    1. **小豬成長區塊**: 顯示當前等級、小豬圖片（依等級縮放）、成長進度條、行走狀態（行走中/靜止）。
    2. **計步系統（已實作）**: 整合硬體 `pedometer` 計步感測器，即時追蹤步數，支援：
       - 硬體基準值 (`_hardwareBaseSteps`) 差值計算，避免重複計數
       - 本地未同步步數緩衝 (`_unsyncedSteps`)，以 `SharedPreferences` 持久化
       - 每 50 步或每 1 分鐘自動批量上傳後端 (`_flushSteps`)
       - 3 秒內無新步數自動判定為靜止，觸發排行榜刷新
       - 雙向同步（Bi-directional sync）：本地與伺服器取較大值，確保步數不倒退
    3. **好友排行榜**: 依 `step_total` 降序排列前 10 名好友，顯示長輩名稱與等級。若使用者不在前 10 名，自動附加於清單末尾。
- **[後端 API] `server/routes/game_logic.py`**
  - **`get_leaderboard`**: 處理「前10名 + 自己」的排名邏輯。
  - **`update_steps`**: 接收 `elder_id` 與 `delta_steps`，增量累加至 `step_total`。
  - **`get_elder_collection`**: 回傳長輩在歷史紀錄中持有的所有不重複外觀與對應加成。

### 核心共用元件 (Shared Core Components)
- **`mobile_app/lib/services/game_service.dart`**: 前端與後端溝通的橋樑，包含所有發送 HTTP Request 的方法（`getLeaderboard`、`getElderStatus`、`updateSteps` 等）。
- **`server/models.py`**: 資料庫定義
  - `GawaAppearance` (造型基本資料，包含 `bonus` 欄位)
  - `ElderProfile` (長輩當前狀態，包含 `step_total`, `gawa_id`, `feed_starttime`)
  - `GetAppearanceList` (歷史分配紀錄，判斷「該長輩永久擁有過哪些造型」的依據)

---

## 2. 計步器技術實作說明

### 目前採用方案：硬體計步感測器 (`pedometer` 套件) ✅ 已完成

利用手機內建硬體計步感測器，接收即時步數串流，零延遲反映於 UI。

- **Flutter 套件**: [`pedometer`](https://pub.dev/packages/pedometer)
- **運作原理**: 監聽 `Pedometer.stepCountStream`，取得自手機開機起的硬體累計步數，與上次記錄值求差值得出新增步數。
- **權限需求**:
  - Android: `ACTIVITY_RECOGNITION` (AndroidManifest.xml)
  - iOS: `NSMotionUsageDescription` (Info.plist)
- **同步策略**:
  ```
  [硬體感測器] → 差值計算 → _unsyncedSteps (本地緩衝)
       ↓                              ↓
  即時更新 UI                每50步 / 每1分鐘 → POST /elder/update_steps → DB
       ↓                                                    ↓
  停止行走 (3秒判定) → 強制 flush + 重新 fetch 排行榜 (雙向取 max)
  ```

### 備選方案：系統健康資料庫 (`health` 套件) 📋 規劃中

若需更高精度或跨穿戴裝置同步（Apple Watch、智慧手環），可改用 OS 健康中心 API。

- **Flutter 套件**: [`health`](https://pub.dev/packages/health)
- **資料來源**: Apple Health (iOS) / Health Connect (Android)
- **優點**: 步數最精準、能跨裝置同步
- **缺點**: 設定繁瑣（需向 Google/Apple 申請權限），資料更新有數分鐘延遲
