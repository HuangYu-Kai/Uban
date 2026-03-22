# 造型分配與排行榜系統架構 (Feed Gawa Intro)

這份文件標示了「造型分配、專屬排行榜與收集系統」中，所有相關的使用者端 (Flutter App) 與管理者端 (Flask Server) 程式碼位置與負責功能。

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
使用者主要查看自己與好友的排行榜排名，以及目前擁有的造型進度與加成。

- **[前端 UI] `mobile_app/lib/screens/leaderboard_screen.dart` (已升級為專屬儀表板)**
  - **功能**: 長輩排行榜與收集品介面。
    1. **我的收集進度區塊**: 呼叫 API 顯示已擁有的不同造型，並計算並顯示總加成倍率 (`bonus`)。
    2. **好友排行榜**: 顯示包含自己在內的前10名好友排名。若使用者不在前10名，自動將使用者的數據置於清單最下方，方便檢視自身與前段班的差距。顯示長輩真實名稱 (`elder_name`)。
- **[後端 API] `server/routes/game_logic.py`**
  - **`get_leaderboard`**: 處理「前10名 + 自己」的排名邏輯。
  - **`get_elder_collection`**: 回傳長輩在歷史紀錄中持有的所有不重複外觀與對應加成。

### 核心共用元件 (Shared Core Components)
- **`mobile_app/lib/services/game_service.dart`**: 前端與後端溝通的橋樑，包含所有發送 HTTP Request 的方法。
- **`server/models.py`**: 資料庫定義
  - `GawaAppearance` (造型基本資料，包含新增的 `bonus` 欄位)
  - `ElderProfile` (長輩當前狀態，包含 `step_total`, `gawa_id`, `feed_starttime`)
  - `GetAppearanceList` (歷史分配紀錄網，也是判斷「該長輩永久擁有過哪些造型」的依據)

---

## 2. 關於「透過實體走路偵測來累積步數」的實作方法

**這件事絕對有辦法做到！** 在 Flutter 開發中，若希望透過手機內建感測器或是系統級別的健康資料來計算「實體步數」，主要有以下兩種主流方法：

### 方法一：直接讀取硬體計步感測器 (推薦: `pedometer` 套件)
這是最輕量且即時的方法。現代智慧型手機都內建硬體計步感測器 (Hardware Step Counter Senssor)。
- **Flutter 套件**: [`pedometer`](https://pub.dev/packages/pedometer)
- **運作原理**: 程式會在背景監聽硬體感測器的 `StepCount` 事件串流 (Stream)。這能直接取得從手機開機至今的總步數，透過自己記錄每日初始步數相減，即可算出當日累積步數。
- **設定要求**: 
  - Android 需要在 `AndroidManifest.xml` 中加入 `ACTIVITY_RECOGNITION` 權限。
  - iOS 需要在 `Info.plist` 中加入 `NSMotionUsageDescription`。
- **實作概念**:
  ```dart
  import 'package:pedometer/pedometer.dart';

  late Stream<StepCount> _stepCountStream;

  void initPedometer() {
    _stepCountStream = Pedometer.stepCountStream;
    _stepCountStream.listen(
      (StepCount event) {
        print("目前總步數: ${event.steps}");
        // 將步數更新到伺服器 (elder_profile.step_total)
      },
      onError: (error) => print("計步器錯誤: $error"),
    );
  }
  ```

### 方法二：讀取系統健康資料庫 (較為全面: `health` 套件)
如果希望資料來源更具公信力 (例如能同步 Apple Watch 或其他智慧手環的步數)，則需向作業系統的健康中心索取資料。
- **Flutter 套件**: [`health`](https://pub.dev/packages/health)
- **運作原理**: 直接向 Apple Health (iOS) 或 Google Fit / Health Connect (Android) 發出授權請求，讀取特定日期範圍內的步數(`Steps`)。
- **優缺點**: 
  - 優點：步數最精準、能跨裝置同步(如手環)。
  - 缺點：設定極為繁瑣，需要向 Google / Apple 申請特別權限與驗證，且資料更新可能有幾分鐘的延遲。

**結論與建議**：
若只是為了配合這個專案的造型機制與排行榜，強烈建議先採用 **方法一 (`pedometer`)**。設定簡單、即時回饋感強，能快速將實體步行與遊戲化 (Gamification) 特性結合，讓長輩更有動力持續運動。
