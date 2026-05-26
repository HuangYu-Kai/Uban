# 🐟 魚你聊聊 (Yuni Chat) 系統開發與維護手冊

* 建立日期：2026-05-21
* 最近更新：2026-05-26
* 適用版本：v1.2.0
* 負責組件：前端 App (Flutter)、後端 API (FastAPI)、信令服務 (Socket.IO)、記憶庫 (Pinecone)

---

## 1. 核心理念與定位

「魚你聊聊」是專門針對銀髮族設計的**非壓力型 AI 互動與溫馨通知介面**。本產品旨在解決傳統文字列表對話對長輩造成的科技焦慮感：
* **去介面化設計 (Interface-less)**：摒棄冷冰冰的聊天框架與密密麻麻的通知條。我們將系統通知、子女留言與 AI 回憶話題，具象化為水面上游動的「錦鯉」與悠閒飄落的「落葉」，讓互動如同在池塘散步與養魚般放鬆。
* **語音優先與認知減載**：配合大字體 (24pt) 與一鍵 TTS 朗讀，降低長輩的閱讀疲勞與操作障礙，塑造平靜、溫暖的陪伴場景。

---

## 2. 系統架構與資料流向 (Architecture & Data Flow)

### 2.1 系統連結架構圖
```mermaid
graph TD
    subgraph Client [Flutter App (長輩端)]
        UI[魚你聊聊 UI - zen_pond_screen.dart]
        Diary[時光日記 - widgets/diary_dialog.dart]
        STT[語音錄音與 TTS 播放]
        Ctrl[狀態控制器 - zen_pond_controller.dart]
    end

    subgraph Backend [FastAPI Server]
        API[REST API /api/ai/chat]
        SocketIO[Socket.IO 信令中心]
        Scheduler[APScheduler 定時任務]
    end

    subgraph Storage [數據中心]
        MySQL[(MySQL 資料庫)]
        Pinecone[(Pinecone 向量庫)]
        Ollama[Ollama / Gemini LLM]
    end

    %% 前端內部交互
    UI <--> Ctrl
    Diary <--> Ctrl
    UI --> STT

    %% 前後端互動
    UI <-->|Socket.IO: join & new-pond-leaf| SocketIO
    STT <-->|POST /api/ai/chat & TTS| API
    Ctrl -->|POST /api/ai/generate_pond_leaf| API

    %% 後端與儲存互動
    API <-->|寫入對話/留言| MySQL
    API <-->|長期記憶檢索| Pinecone
    API <-->|提示詞合成話題| Ollama
    Scheduler -->|08:00 / 15:00 定時觸發| Pinecone
    Scheduler -->|推播話題落葉| SocketIO
```

### 2.2 核心通訊介面與 JSON Payload 規格

#### A. Socket.IO 信令事件：在線長輩加入房間
* **事件名稱**：`join`
* **發送端**：長輩端 App 啟動時發送
* **Payload 格式**：
  ```json
  {
    "room": "1",
    "role": "elder",
    "userId": 1,
    "fcmToken": "fcm_token_string..."
  }
  ```
* **後端接收邏輯**：[socket_app.py](file:///c:/Users/tung0/Desktop/Uban/Uban-api/services/socket_app.py) 解析後將 `sid` 與 `userId` 綁定，加入對應房號的 `rooms_manager`。

#### B. Socket.IO 話題推送事件：定時/主動推送回憶落葉
* **事件名稱**：`new-pond-leaf`
* **接收端**：長輩端 App 實時監聽
* **Payload 格式**：
  ```json
  {
    "text": "秀珠，您今天有去菜市場買水果嗎？您上次提到愛吃香蕉呢 🍌",
    "colorType": "yellow",
    "timestamp": 1782387520000
  }
  ```

#### C. REST API 對話傳輸：長輩向 AI 說話
* **端點**：`POST /api/ai/chat` (Port 8000)
* **Payload 格式**：
  ```json
  {
    "user_id": 1,
    "message": "我今天在客廳散步了十分鐘，腳有點酸",
    "sender": "user"
  }
  ```
* **處理流程**：後端接收後儲存至 MySQL，隨後啟動背景線程將此訊息轉化為 Embedding 向量存入 Pinecone 記憶庫。

---

## 3. 檔案結構與職責說明 (File Structure)

### 3.1 前端 Flutter 目錄 `mobile_app/lib/screens/zen_pond/`
我們對前端模組進行了高度解耦，降低單一檔案的維護難度：

* **[zen_pond_screen.dart](file:///c:/Users/tung0/Desktop/Uban/Uban/mobile_app/lib/screens/zen_pond/zen_pond_screen.dart)**
  * **職責**：池塘主畫面入口。負責管理 Socket.IO 信令監聽、手勢繪製（漣漪渲染）、背景水流動態，以及處理 debug 模擬面板。
* **[widgets/diary_dialog.dart](file:///c:/Users/tung0/Desktop/Uban/Uban/mobile_app/lib/screens/zen_pond/widgets/diary_dialog.dart) `[NEW]`**
  * **職責**：將日記 Dialog 抽離為單獨 Widget。管理日記目錄按日期分組（`_groupHistoryByDate`）、對話日誌細節渲染、內嵌 Speech-to-Text 語音錄音與 RAG 話題生成按鈕。
* **[widgets/sound_wave_indicator.dart](file:///c:/Users/tung0/Desktop/Uban/Uban/mobile_app/lib/screens/zen_pond/widgets/sound_wave_indicator.dart) `[NEW]`**
  * **職責**：波形律動動畫組件。語音播放或錄音時，顯示具有節奏律動的彩色音符波形。
* **[controllers/zen_pond_controller.dart](file:///c:/Users/tung0/Desktop/Uban/Uban/mobile_app/lib/screens/zen_pond/controllers/zen_pond_controller.dart)**
  * **職責**：對話與池塘狀態控制器。維護 `notifications` (錦鯉) 與 `leaves` (落葉) 的記憶體陣列；呼叫本地 `SharedPreferences` 持久化儲存；驅動 TTS 音訊播放；實作連擊手勢防線。
* **[painters/ripple_painter.dart](file:///c:/Users/tung0/Desktop/Uban/Uban/mobile_app/lib/screens/zen_pond/painters/ripple_painter.dart)**
  * **職責**：水面漣漪畫筆。根據點擊座標與衰減半徑計算同心圓擴散。
* **[painters/water_wave_painter.dart](file:///c:/Users/tung0/Desktop/Uban/Uban/mobile_app/lib/screens/zen_pond/painters/water_wave_painter.dart)**
  * **職責**：動態水波背景畫筆。利用正弦波疊加繪製背景水流。
* **[widgets/koi_fish_notification.dart](file:///c:/Users/tung0/Desktop/Uban/Uban/mobile_app/lib/screens/zen_pond/widgets/koi_fish_notification.dart)**
  * **職責**：錦鯉渲染與物理游動。自訂擺尾動畫與邊界轉向物理引擎。

---

## 4. 各子功能實作技術細節 (Technical Details)

### A. 背景日夜漸層流動
水底色彩依據系統時間 `DateTime.now().hour` 分為晨、晝、昏、夜四種色溫，並結合低頻呼吸運動進行平移。
* **晨 (05:00 - 08:59)**：`Color(0xFFFFFDE7)` ✕ `Color(0xFFE8F5E9)`。
* **晝 (09:00 - 15:59)**：`Color(0xFFE0F2F1)` ✕ `Color(0xFFE3F2FD)`。
* **昏 (16:00 - 18:59)**：`Color(0xFFFCE4EC)` ✕ `Color(0xFFF3E5F5)`。
* **夜 (19:00 - 04:59)**：`Color(0xFFECEFF1)` ✕ `Color(0xFFE8F8F5)`。

#### 漸層平移呼吸方程式 (Pastel Translation Equation)
為了帶來平靜感，漸層的中心點 $(X_{offset}, Y_{offset})$ 隨時間 $t$（毫秒值）沿著橢圓軌道極其緩慢地浮動（週期為 20 秒）：
$$x_{offset} = 0.5 + 0.08 \cdot \sin\left(\frac{t}{20000} \cdot 2\pi\right)$$
$$y_{offset} = 0.5 + 0.08 \cdot \cos\left(\frac{t}{20000} \cdot 2\pi\right)$$
該偏移量隨後傳入 `RadialGradient` 作為漸層的 `center`。

---

### B. 錦鯉物理擺尾與轉向演算法

#### 1. 關節擺擺方程式 (Wiggle Math)
錦鯉身體使用 `CustomPainter` 在畫布上計算並繪製一條由 20 個節點構成的魚身脊椎。尾部擺幅比頭部大，在擺動時呈現自然的阻尼波動。
第 $i$ 個關節的水平偏移 $wiggle_i$（$0 \le i \le 20$）方程式如下：
$$wiggle_i = \sin\left(\frac{i}{20} \cdot 2\pi - \theta_{anim} \cdot 2\pi\right) \cdot \text{maxWiggle} \cdot \left(\frac{i}{20}\right)^{1.8}$$
* $\theta_{anim} \in [0, 1]$：擺尾的時間週期動畫值（週期設定為 1500 毫秒，體現悠閒游動）。
* $\text{maxWiggle}$：最大擺幅限制（為魚體最大寬度的 11%）。
* $\left(\frac{i}{20}\right)^{1.8}$：尾部放大因子（冪次 1.8 確保頭部幾乎不動，擺動完美集中在後半段魚鰭與魚尾）。

#### 2. 平滑轉向物理引擎 (Steering Physics)
錦鯉在隨機產生的多個水面目標點 $P_{target}$ 之間巡游。為了防止魚體在轉彎時發生突兀的硬轉折，我們限制了轉彎角速度限制：
當前朝向角 $\theta_{current}$ 與目標朝向角 $\theta_{target}$ 之間的最大差值 $\Delta\theta$ 限制如下：
$$\Delta\theta_{steered} = \text{clamp}(\Delta\theta, -0.012, 0.012) \text{ rad/frame}$$
魚的前進推力實施「直行前進時，速度隨划水起伏波動；轉彎時，適度慢速以維持平穩」原則：
$$v_{swim} = v_{base} \cdot \left(1.0 + 0.3 \cdot \cos\left(\frac{\text{EpochMillis}}{1200}\right)\right)$$

---

### C. 落葉飄落與水面浮游動畫

#### 1. 登場飄落軌跡 (Entrance Falling)
當新落葉被加入時，會觸發一個 2.5 秒（2500ms）的一次性登場動畫。落葉從屏幕頂部上方（$Y = -100\text{px}$）緩緩飄下，其降落軌跡 $(X_t, Y_t)$ 隨動畫進度 $t \in [0, 1]$ 運算為：
$$Y_{t} = -100 + (Y_{resting} + 100) \cdot t$$
$$X_{t} = X_{resting} + \sin(t \cdot 3\pi) \cdot 35 \cdot (1 - t)$$
* 左右正弦搖擺幅度隨 $1-t$ 線性衰減，當落水時擺幅降為 0，表現落水時空氣阻力的消失。
* 同時落葉在空中自轉：
  $$\text{Rotation}(t) = (1 - t) \cdot 6\pi + \theta_{seed}$$
  （落水前完成 3 圈自轉）。

#### 2. 常態水面浮動 (Bobbing)
落水後，落葉切換為基於 5 秒（5000ms）循環的微小浮游狀態：
$$Y_{bobbing} = Y_{resting} + \sin(\theta_{idle}) \cdot 4.0\text{ px}$$
$$X_{bobbing} = X_{resting} + \cos(\theta_{idle}) \cdot 2.0\text{ px}$$
$$\text{Rotation}_{bobbing} = \sin(\theta_{idle}) \cdot 0.05\text{ rad} + \theta_{seed}$$

---

## 5. 安全性防護與防誤觸機制

* **單擊延遲防禦 (`_singleTapTimer`)**：
  為了防止長輩在緊急狀況下快速點擊求救（連擊 5 次 SOS）時，被誤判為一般的點擊水面聊天。我們設計了點擊延遲分流：
  * 當第一次點擊觸發，系統會啟動一個 $350\text{ms}$ 的單擊延遲計時器。
  * 若長輩正在連續點按，當點擊計數達到 5 次時，系統會**立即取消**該單擊延遲計時器，直接轉入 `_triggerSOS()` 模式，並鎖定螢幕覆蓋紅色遮罩，保障緊急呼叫不被AI聊天視窗打斷。
  * 若 $350\text{ms}$ 內無多餘點擊，則視為普通點按，開啟 AI 對話視窗。
* **SOS 冷卻鎖 (Cooldown)**：
  求救狀態一旦發起，將會覆蓋全螢幕並發送 SOS 事件給家屬，為防止長輩或家屬重複操作，系統會強制鎖定畫布互動 $5.0$ 秒，冷卻時間結束後自動復原。

---

## 6. 測試與驗證計畫 (Test Checklist)

在將代碼合併或發佈時，必須進行以下測試：

* [x] **靜態代碼分析**：執行 `flutter analyze`，確認模組化後的程式碼 0 錯誤、0 警告。
* [x] **時間漸層流動測試**：透過 Debug 面板手動拖曳 `mockHour` 滑桿，觀察水面背景是否在「晨、晝、昏、夜」之間完成絲滑漸層轉變。
* [x] **錦鯉物理游動與邊界測試**：觀察錦鯉在接近螢幕邊緣或鵝卵石時，是否會以圓滑的弧度（角速度小於 0.012 弧度）平滑轉向。
* [x] **SOS求救手勢測試**：在螢幕空白處快速連擊 5 次，確認能在 1 秒內順利呼叫緊急求救遮罩，且期間不會彈出 AI 聊天 Dialog。
