# 代誌報給你知 (News Listen Player Screen) 技術設計與實作紀錄

* 建立日期：2026-05-26
* 最近更新：2026-05-26
* 適用版本：v2.1.0
* 負責組件：前端 (Flutter Mobile App) / 後端 (FastAPI API Service)

---

## 1. 功能背景與設計初衷 (Objectives & Background)

### ❶ 解決什麼痛點
隨著長輩年齡增長，視力退化與黃斑部病變常使閱讀繁瑣的新聞文字變得異常吃力。傳統新聞 App 雖有語音朗讀功能，但缺乏實時字詞同步（Karaoke-style subtitle synchronization），長輩在聆聽時容易因為分神或外界干擾而跟不上進度。此外，大眾新聞的字句往往生硬、冗長，長輩在缺乏背景知識的情況下，難以快速理解其內容重點。

### ❷ 照護價值與 UX 考量
本功能專為銀髮族設計「沉浸式聽新聞」體驗：
* **語音與視覺雙重同步**：大字體字幕與合成語音精準同步，播報到的字詞以顯眼顏色點亮，提供極佳的視聽融合反饋，增強專注力與資訊獲取效率。
* **兩段式翻頁設計**：採用簡潔的垂直滑動翻頁，第一頁為極簡播放器與全螢幕滾動字幕，第二頁為大圖大卡片的新聞瀏覽清單，避免多重複雜層級選單對長輩造成認知負擔。
* **貼心小豬總結專家**：在播放介面右上方常駐 AI 伴侶小豬。當長輩聽完新聞或遇到難解之處，點擊小豬即可觸發 LLM 將新聞內容大白話濃縮為 60 字以內、3 個重點的摘要，並以溫馨語意同步播報，宛如貼身秘書為長輩講解時事。

---

## 2. 系統架構與資料流向 (System Architecture & Data Flow)

### ❶ 架構拓撲 (Mermaid)

```mermaid
flowchart TD
    subgraph Backend ["⚡ 後端 API 與背景任務 (FastAPI + MySQL)"]
        Crawler["新聞爬蟲服務<br/>(CNA RSS Feeds)"] -->|今日新聞寫入| DB[(MySQL Database)]
        BackgroundJob["背景語音預生成線程<br/>(pre_generate_news_audio_background)"] -->|掃描未生成音檔新聞| DB
        BackgroundJob -->|呼叫 TTS| XTTS["語音合成服務<br/>(XTTS/CosyVoice)"]
        XTTS -->|生成 WAV 音檔| Disk["本機儲存空間<br/>(/uploads/news_audio/)"]
        XTTS -->|生成字詞標記字幕| BackgroundJob
        BackgroundJob -->|回寫音檔 URL 與字幕 JSON| DB
        API["REST API 路由<br/>(routers/news.py)"] -->|查詢新聞列表| DB
    end

    subgraph Frontend ["📱 長輩端行動 App (Flutter)"]
        NewsScreen["新聞播放器介面<br/>(NewsListenPlayerScreen)"] -->|載入新聞與音檔| API
        NewsScreen -->|音訊串流播放| AudioPlayer["AudioPlayer 引擎"]
        AudioPlayer -->|即時播放毫秒進度| SubtitleSync["字幕同步 & 置中捲動運算"]
        NewsScreen -->|點擊小豬總結| MascotButton["小豬總結觸發器"]
        MascotButton -->|請求總結 API<br/>(user_id 隔離)| API
        API -->|LLM 生成大白話總結| MascotButton
        MascotButton -->|總別 TTS 播報| AiPlayer["AI 專屬 AudioPlayer"]
    end
```

### ❷ 資料傳輸規格

#### 1. 取得新聞列表 API
* **路由與方法**：`GET /api/news`
* **Port / 逾時限制**：`443 (HTTPS)` / `15 秒`
* **Query 參數**：
  * `category` (string, 預設 "politics"): 新聞分類金鑰（支援 `all` 或具體類別如 `finance`、`technology` 等）。
  * `limit` (int, 預設 10): 限制返回數量（範圍為 1 至 50）。
  * `data_date` (string, 可選): 指定日期（格式為 YYYY-MM-DD，預設為今日）。
* **回應格式 (JSON)**：
```json
{
  "status": "success",
  "data": {
    "category": "politics",
    "count": 1,
    "data_date": "2026-05-26",
    "generated_at": "2026-05-26T09:30:00+08:00",
    "items": [
      {
        "category_key": "politics",
        "category": "政治",
        "title": "立法院三讀通過感知照護特別條例",
        "content": "立法院今日三讀通過感知照護特別條例，旨在結合AI與WebRTC技術提升長照便利性...",
        "image_url": "https://localhost-0.tail5abf5e.ts.net/static/images/news1.jpg",
        "source_url": "https://www.cna.com.tw/news/aipl/202605260001.aspx",
        "published_at": "2026-05-26T09:00:00",
        "published_at_raw": "Tue, 26 May 2026 09:00:00 +0800",
        "updated_at": "2026-05-26T09:30:00",
        "audio_url": "/uploads/news_audio/news_2026-05-26_123.wav",
        "subtitles": [
          {
            "start_ms": 0,
            "duration_ms": 1500,
            "text": "以下為您播報政治新聞"
          },
          {
            "start_ms": 1500,
            "duration_ms": 2800,
            "text": "立法院三讀通過感知照護特別條例"
          }
        ]
      }
    ]
  }
}
```

#### 2. 新聞分類列表 API
* **路由與方法**：`GET /api/news/categories`
* **回應格式 (JSON)**：
```json
{
  "status": "success",
  "data": {
    "categories": [
      {"key": "politics", "label": "政治"},
      {"key": "international", "label": "國際"},
      {"key": "finance", "label": "財經"}
    ]
  }
}
```

---

## 3. 代碼修改與路徑定義 (Implementation & File References)

### ❶ 涉及代碼變動

* `[NEW] [news_listen_player_screen.dart](file:///c:/Users/tung0/Desktop/Uban/Uban/mobile_app/lib/screens/news_listen_player/news_listen_player_screen.dart)`：前端控制主畫面（原 `lib/screens/news_listen_player_screen.dart` 已刪除並搬移至此），調用與重組模組化元件。
* `[NEW] [news_sound_wave_indicator.dart](file:///c:/Users/tung0/Desktop/Uban/Uban/mobile_app/lib/screens/news_listen_player/widgets/news_sound_wave_indicator.dart)`：前端音波條動畫元件，自我管理跳動定時器與波形高度狀態。
* `[NEW] [news_subtitle_viewer.dart](file:///c:/Users/tung0/Desktop/Uban/Uban/mobile_app/lib/screens/news_listen_player/widgets/news_subtitle_viewer.dart)`：前端卡拉 OK 字幕滾動與置中定位運算元件，自我管理 `ScrollController` 與 `GlobalKey` 串列。
* `[NEW] [news_category_selector.dart](file:///c:/Users/tung0/Desktop/Uban/Uban/mobile_app/lib/screens/news_listen_player/widgets/news_category_selector.dart)`：前端分類標籤水平滾動選擇元件。
* `[NEW] [news_selection_list.dart](file:///c:/Users/tung0/Desktop/Uban/Uban/mobile_app/lib/screens/news_listen_player/widgets/news_selection_list.dart)`：前端新聞大卡片清單列表元件。
* `[NEW] [news_summary_dialog.dart](file:///c:/Users/tung0/Desktop/Uban/Uban/mobile_app/lib/screens/news_listen_player/widgets/news_summary_dialog.dart)`：前端小豬 AI 總結對話框樣式與動畫元件。
* `[MODIFY] [elder_home_tab.dart](file:///c:/Users/tung0/Desktop/Uban/Uban/mobile_app/lib/screens/elder_tabs/elder_home_tab.dart)`：更新 `NewsListenPlayerScreen` 的引進路徑。
* `[MODIFY] [api_service.dart](file:///c:/Users/tung0/Desktop/Uban/Uban/mobile_app/lib/services/api_service.dart)`：後端 API 連接方法（如 `ApiService.getNews`、`ApiService.petGreeting`、`ApiService.synthesizeTts` 等）。
* `[MODIFY] [news.py](file:///c:/Users/tung0/Desktop/Uban/Uban-api/routers/news.py)`：後端 REST API 路由，暴露獲取新聞列表、語音生成進度、崩潰日誌及手動觸發爬蟲等端點。
* `[MODIFY] [news_crawler_service.py](file:///c:/Users/tung0/Desktop/Uban/Uban-api/services/news_crawler_service.py)`：後端爬蟲擷取（CNA JSON-LD 擷取）、資料庫 MySQL 讀寫隔離、多線程背景語音音檔與字幕對齊生成。

---

## 4. 核心數學公式與物理演算法 (Core Mathematical Models)

在新聞播報過程中，為了確保字幕能精準追隨語音進度，並能滑順地將當前播放行滾動置中，實作了以下數學模型：

### ❶ 字幕行判定與字元染色進度 (Karaoke Color Interpolation)
設 $t$ 為 `AudioPlayer` 當前回傳的播放位置（毫秒），對於第 $i$ 句字幕，其時間範圍由 $[\text{start\_ms}_i, \text{start\_ms}_i + \text{duration\_ms}_i)$ 定義。
1. **行級判定**：遍歷字幕陣列，尋找滿足下式的索引 $i$ 作為當前作用行 $\text{ActiveIndex}$：
   $$t \ge \text{start\_ms}_i \quad \land \quad t < \text{start\_ms}_i + \text{duration\_ms}_i$$

2. **字元級染色進度百分比**：作用行的染色百分比 $P_{\text{subtitle}}$ 計算公式如下：
   $$P_{\text{subtitle}} = \max\left(0.0, \min\left(1.0, \frac{t - \text{start\_ms}_i}{\text{duration\_ms}_i}\right)\right)$$
   前端依據 $P_{\text{subtitle}}$ 計算出已染色的字元數量 $N_{\text{colored}}$：
   $$N_{\text{colored}} = \text{round}(L_i \times P_{\text{subtitle}})$$
   其中 $L_i$ 為第 $i$ 句字幕的總字元長度。前 $N_{\text{colored}}$ 個字元渲染為金色，剩餘字元渲染為白色。

### ❷ 視窗「瞬移置中」滾動定位數學模型 (Centering Alignment math)
當前字幕行切換時，為了使其保持在字幕滾動容器的中心，必須動態計算 `ScrollController` 的目標位移 $y_{\text{target}}$：
$$y_{\text{target}} = y_{\text{index}} - \frac{H_{\text{viewport}} - H_{\text{item}}}{2}$$

* **變數定義**：
  * $y_{\text{index}}$: 當前播放行元件（RenderBox）頂部相對於滾動容器的累積垂直位移。其計算公式為：
    $$y_{\text{index}} = y_{\text{scroll\_offset}} + \Delta y_{\text{relative}}$$
    其中 $y_{\text{scroll\_offset}}$ 為當前滾動位移 `_subtitleScrollController.offset`，$\Delta y_{\text{relative}}$ 為元件相對於視窗容器頂部的相對位移（`relativeOffset.dy`）。
  * $H_{\text{viewport}}$: 滾動視窗容器的實體高度（`container.size.height`）。
  * $H_{\text{item}}$: 當前播放行元件的實體高度（`box.size.height`）。

* **邊界限制 (Clamping)**：
  目標滾動位移必須被限制在有效滾動區間內，以防止反彈或超出限制：
  $$y_{\text{target\_clamped}} = \max\left(0.0, \min\left(y_{\text{target}}, y_{\text{maxScrollExtent}}\right)\right)$$
  其中 $y_{\text{maxScrollExtent}}$ 為字幕容器的最大滾動極限。計算完成後，直接調用 `jumpTo(y_{\text{target\_clamped}})` 實現無延遲置中。

---

## 5. UI/UX 視覺美學與無障礙規範 (Aesthetics & Accessibility)

為符合本專案的「莫蘭迪禪意暖色調」與銀髮族無障礙使用體驗，我們定義了以下視覺與動作規範：

### ❶ 配色系統 (Color Palette)
* **背景漸層**：使用綠意調和雙色漸層，營造放鬆、無壓力的視聽環境：
  * 頂部起點色：`#8BAF88` (橄欖綠)
  * 底部終點色：`#56B59F` (禪意碧綠)
* **字幕容器**：
  * 背景色：`#000000` (透明度 30%，以確保高對比度文字可讀性)
  * 邊框：`#FFFFFF` (透明度 10%，圓角設定 `24.0`，搭配 `1.0` 寬度)
* **字體染色**：
  * 作用中文字（已播報）：`#FFD700` (亮金色，提供極佳的卡拉 OK 同步軌跡)
  * 作用中文字（未播報）：`#FFFFFF` (純白)
  * 非作用中文字：`#FFFFFF` (透明度 40%，呈現呼吸燈漸褪效果)
* **控制面板**：
  * 按鈕背景：`#FFFFFF` (透明度 95%)，附帶 `0.18` 透明度的擴散陰影
  * 圖標主色：`#59B294` (青綠色)

### ❷ 銀髮族大字體無障礙
* **字體大小與層級**：
  * 系統大標題："代誌報給你知" 為 `48pt` (套用 'StarPanda' 字體)。
  * 正在播放的新聞標題為 `23pt`，行高設為 `1.3`，字重為 `FontWeight.w600`。
  * 滾動中的作用中字幕文字為 `30pt`，字重 `FontWeight.w900`（極粗體），行高 `1.4`；非作用中字幕文字為 `22pt`，字重 `FontWeight.w600`。
* **點擊熱區**：
  * 播放/暫停按鈕直徑 `74.0`，上一首/下一首按鈕直徑 `60.0`，具備大面積點擊熱區，防手震與點擊偏離。

### ❸ 微互動與動畫引導 (Micro-Animations)
* **動態播放波形條**：當語音播放時，11根音量條以每 280ms 一次的週期動態隨機改變高度，其高度模型為：
  $$Height_i = \left(28 + (i \bmod 2 \times 8) + \text{Random}(0, 50)\right) \times 0.6$$
  使用 `AnimatedContainer` 以 `240ms` 漸變長度平滑過渡，形成起伏波動視覺反饋。
* **小豬吉祥物微調**：當 AI 總結進行中或語音播報時，右上方的小豬圖案使用 `flutter_animate` 執行重複的 `shake` (頻率 3Hz) 與 `scale` (從 1.0 至 1.1 週期 1 秒) 動畫，提醒長輩此按鈕正處於活動狀態。

---

## 6. 安全性防護與防誤觸機制 (Safety & Debouncing)

### ❶ 載入鎖定與狀態隔離
* **防重複點擊 (Debouncing)**：當音檔正在生成或下載時，`_isLoadingAudio` 被設為 `true`。此時上一首/下一首與播放/暫停控制均會鎖定，直至音檔載入完成，防止重複發送 HTTP 請求與音訊串流衝突。
* **AI 總結狀態鎖定**：點擊小豬觸發總結時，`_isAiThinking` 設為 `true`．若重複點擊將直接忽略，防止對 LLM 後端進行暴兵式請求。同時，新聞播放器會被強制暫停 (`_isPlaying = false`)，以防背景聲音干擾 AI 總結語音。

### ❷ 容錯與緊急退回 (Fallback)
* **預生成與實時 TTS 雙軌防護**：
  後端於背景夜間自動預生成音檔。當前端發現資料庫中無預生成音檔時，會自動切換為 fallback 機制：將標題與前 180 字內容發送至後端進行實時 `ApiService.synthesizeTts` 合成，以 Base64 回傳並使用 `BytesSource` 載入，確保離線或新爬取的新聞仍能正常朗讀。
* **崩潰攔截 (Crash Catching)**：
  在滾動置中計算中，若因視窗未繪製完畢或 Context 缺失，可能導致 `RenderBox` 查詢出錯。代碼中使用 `try-catch` 區塊包裹捲動邏輯，崩潰時會安靜退回而不影響 App 的正常播放。

---

## 7. 測試與驗證計畫 (Test Plan & Checklist)

### ❶ 靜態分析與編譯驗證
* **執行命令**：
  ```powershell
  cd c:\Users\tung0\Desktop\Uban\Uban\mobile_app
  flutter analyze
  ```
* **預期結果**：靜態分析 0 錯誤。

### ❷ 功能性測試 Checklist

| 測試情境 | 操作步驟 | 預期結果 |
|---|---|---|
| **新聞空數據處理** | 模擬 API 回傳新聞列表為空。 | 介面無崩潰，顯示大字體提示 "準備播放中..."。 |
| **快速切換軌道** | 在新聞播報時，快速連續點擊 "下一首" 3次。 | 正在播放的 AudioPlayer 實時停止，切換至目標新聞，僅播放最後一次切換的音檔。 |
| **無網路錯誤復原** | 斷開手機網絡並點擊播放。 | 捕捉超時，介面顯示 "語音播放失敗，請點播放再試一次"，重新連網後點擊可正常播放。 |
| **卡拉 OK 字幕同步** | 觀察語音發音與黃色染色字詞進度。 | 語音播報到哪裡，黃色高亮與字幕染色便進行到哪裡，無明顯延遲。 |
| **字幕瞬移置中** | 播報到下一句字幕時。 | 畫面以無動畫跳轉方式 (`jumpTo`) 將當前播放字幕行精準置於滾動框正中央。 |
| **小豬總結與語音** | 播放新聞時點擊右上方小豬。 | 新聞朗讀暫停，彈出小豬總結專屬 Dialog，小豬開始抖動，隨後播放 AI 語音。點擊 "我知道了" 停止語音並關閉 Dialog。 |
