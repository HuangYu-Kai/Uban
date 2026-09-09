# 室內定位系統與區域停留分析 (Indoor Positioning System - IPS) 技術設計與實作紀錄

* 建立日期：2026-09-09
* 最近更新：2026-09-09
* 適用版本：v2.4.0+
* 負責組件：[後端/AI 視覺/前端/家屬即時感知]

---

## 1. 元數據 (Metadata Header)

| 屬性 | 規格與定義 |
| :--- | :--- |
| **模組名稱** | 室內定位系統 (Indoor Positioning System - IPS) 與區域停留分析 |
| **後端路徑** | `uban-api/routers/ips.py`, `uban-api/services/indoor_position.py` |
| **前端路徑** | `mobile_app/lib/screens/family/home/widgets/home_zone_card.dart`, `mobile_app/lib/services/api/cctv_alert_api.dart` |
| **技術依賴** | 監視機影像、YOLO 姿態與人體檢測、射線法多邊形幾何判定 (Ray-Casting Point-in-Polygon) |
| **安全要求** | 依賴 `user_id` 與 `device_id` 配對關係校驗（無權存取回傳 404 避免列舉） |

---

## 2. 功能背景與設計初衷 (Objectives & Background)

* **痛點分析**：
  家屬無法 24 小時盯著監視器畫面，但又迫切想知道長輩當前身處何處（例如：是在客廳沙發看電視、在臥室休息、還是在浴室待了過長時間）。傳統 GPS 在室內訊號極差且誤差高達數十公尺，無法分辨具體房間。
* **照護價值與 UX 考量**：
  1. **零穿戴無感定位**：利用既有之守護監視機與 YOLO 視覺感知，長輩無需隨身配戴任何手環或 Beacon。
  2. **自由區域多邊形劃分**：支援自訂多邊形標記（如：客廳、臥室、陽台、浴室）。
  3. **異常停留預警 (Dwell Time Analysis)**：即時統計長輩在各區域的停留秒數。若長輩在浴室超過設定門檻（例如 45 分鐘），可即時通報家屬，及早防範滑倒或昏迷風險。

---

## 3. 系統架構與資料流向 (System Architecture & Data Flow)

### 3.1 IPS 空間感知流程 (Architecture Diagram)

```mermaid
graph TD
    Camera[AI 守護監視機] -->|推送即時影格| Ingest[POST /api/cctv/frame]
    Ingest --> YOLO[YOLO 人體邊界框檢測]
    YOLO --> BBox[計算人體底部中心點 P(x,y)]
    BBox --> PolyJudge[射線法多邊形判定 Classify Zone]
    PolyJudge --> ZoneDB[(區域狀態與停留計時快取)]
    
    FamilyApp[家屬端 App / HomeZoneCard] -->|GET /api/ips/current/{elderId}| Query[查詢目前所在區域與秒數]
    ZoneDB -->|回傳目前區域與停留時間| Query
    Query -->|渲染即時卡片與時間軸| FamilyApp
```

### 3.2 資料傳輸規格 (REST Endpoints)

* `GET /api/ips/zones/{elder_id}?user_id=&device_id=`：
  取得監視機校準的多邊形區域列表（座標為 `[0.0, 1.0]` 的正規化浮點數）。
* `PUT /api/ips/zones/{elder_id}?user_id=&device_id=`：
  全量儲存多邊形區域設定。Payload 格式：
  ```json
  {
    "zones": [
      {
        "name": "客廳",
        "polygon": [[0.1, 0.2], [0.8, 0.2], [0.8, 0.9], [0.1, 0.9]]
      }
    ]
  }
  ```
* `GET /api/ips/current/{elder_id}?user_id=&device_id=`：
  查詢長輩當前所在區域與停留時間。回應格式：
  ```json
  {
    "status": "success",
    "data": {
      "zone": "客廳",
      "dwell_seconds": 1840,
      "last_seen": "2026-09-09T18:30:00Z"
    }
  }
  ```

---

## 4. 代碼修改與路徑定義 (Implementation & File References)

* **[NEW] [home_zone_card.dart](file:///c:/Users/tung0/Desktop/Uban/Uban/mobile_app/lib/screens/family/home/widgets/home_zone_card.dart)**：
  家屬首頁室內定位卡片，展示長輩當前位置標籤（客廳、臥室等）、停留時長計時與動態雷達掃描波紋。
* **[NEW] [cctv_alert_api.dart](file:///c:/Users/tung0/Desktop/Uban/Uban/mobile_app/lib/services/api/cctv_alert_api.dart)**：
  提供 `getZoneConfig`、`saveZoneConfig`、`getCurrentZone` 與 `zoneSnapshotUrl` 之 API Client 封裝。
* **[BACKEND] [ips.py](file:///c:/Users/tung0/Desktop/Uban/Uban-api/routers/ips.py)**：
  FastAPI 路由層，處理權限檢查、參數校驗與 HTTP 例外回傳。
* **[BACKEND] [indoor_position.py](file:///c:/Users/tung0/Desktop/Uban/Uban-api/services/indoor_position.py)**：
  核心室內定位服務，包含空間多邊形判定、座標正規化與停留時間滑動窗口。

---

## 5. 核心數學公式與空間幾何演算法 (Core Mathematical Models)

### 5.1 人體接觸地面定位點計算

根據 YOLO 檢測出之包圍盒 $(x_1, y_1, x_2, y_2)$，取下緣水平中點作為長輩與地面之接觸位置點 $P(x_c, y_b)$：

$$x_c = \frac{x_1 + x_2}{2 \cdot W}, \quad y_b = \frac{y_2}{H}$$

其中 $W, H$ 為監視機影像之像素寬度與高度。

### 5.2 射線交叉演算法 (Ray-Casting Algorithm)

給定定位點 $P(x, y)$ 與頂點集合 $V = \{v_1, v_2, \dots, v_n\}$ 之多邊形，從點 $P$ 向右發射一條水平半無限射線，計算射線與多邊形各邊之交點數量：

$$x_{\text{intersection}} = v_i.x + \frac{y - v_i.y}{v_{i+1}.y - v_i.y} \cdot (v_{i+1}.x - v_i.x)$$

若交點總數為**奇數**，則點 $P$ 位於多邊形內部；若為**偶數**，則在多邊形外部。

### 5.3 First-Match-Wins 優先序判定

當空間存在巢狀或相鄰區域時（例如「客廳」中的「沙發區」），後端依照陣列配置順序採用第一命中原則（First-Match-Wins），因此較小、較精準之特徵區域應配置於清單前列。

---

## 6. UI/UX 視覺美學與無障礙規範 (Aesthetics & Accessibility)

* **空間感知視覺設計**：
  * 當長輩在線且在已知區域時，卡片以晨曦草綠 (`#E8F5E9`) 點綴，並伴隨低頻慢速之波紋動畫，帶給家屬「長輩安好在客廳」的平靜感。
  * 若處於未覆蓋或未辨識區域，平滑顯示「移動中」或「尚無資料」，絕不顯示突兀的錯誤紅字。
* **字級與排版**：
  * 當前區域文字採用 **18-20pt 粗體**，停留時間以時分（如「已停留 45 分鐘」）親切呈現。

---

## 7. 安全性防護與防誤觸機制 (Safety & Debouncing)

1. **防列舉安全策略**：若請求者與長輩非合法配對關係，後端一律回傳 404（Not Found）而非 403（Forbidden），防範惡意掃描探索系統長輩 ID。
2. **多邊形合法性校驗**：多邊形頂點必須大於等於 3 個點，且所有點之座標值必須滿足 $0.0 \le x, y \le 1.0$，否則拋出 400 Bad Request。

---

## 8. 測試與驗證計畫 (Test Plan & Checklist)

* [x] **API 端點驗證**：測試 `GET /api/ips/current/{elderId}` 回傳格式正常。
* [x] **UI 渲染驗證**：`HomeZoneCard` 正確於家屬主頁展示區域資訊。
* [x] **空資料容錯**：當無推論資料或相機離線時，卡片優雅展示預設佔位狀態，不引發異常。
