# UBan - AI-Powered Generative Care Ecosystem

UBan 是一個領先的「AI 跨世代感知照護系統」，致力於透過生成式 AI 技術與直覺的數位工具，打造一個充滿溫度、能主動感知的智慧守護平台。

---

## 📂 專案核心架構 (System Architecture)

本專案採用現代化的多模組架構，將行動端、AI 核心與通訊服務進行解耦：

### 📱 [Mobile App](./mobile_app) (Flutter)

這是系統的門面，分為 **長輩端 (Elderly)** 與 **家屬端 (Family)** 兩大入口。

* **技術棧**: Flutter, Dart, `flutter_animate`, `fl_chart`, `google_fonts`.
* **關鍵畫面**:
  * **Premium Entry**: 高質感身分選擇頁，具備流暢動態背景。
  * **Visual Script Editor**: 工業級劇本編輯器，支援多維度觸發（語音/天氣/健康/IoT）。
  * **Care Journal**: 視覺化長輩情緒波動趨勢（心情折線圖）。

### 🤖 [TLM (Taiwanese Language Model)](./TLM) (Python/AI)

這是系統的「大腦」，專為台灣語境優化。

* **模型**: 整合 **NVIDIA Llama-Taiwan** (70B/Instruct)，提供道地的繁體中文與台語交流。
* **功能**:
  * **聯網搜尋 (Search)**: 整合 DuckDuckGo Search，即時獲取天氣與市場菜價。
  * **意圖判斷 (Intent)**: 自動判別使用者是要閒聊還是查詢事實。
  * **語音轉換 (TTS)**: 整合 `edge_tts` 提供溫潤的台灣腔語音回饋。

### 📡 [WebRTC](./webrtc) & [Server](./server)

* **WebRTC**: 提供即時的影音視訊對講能力。
* **Server**: 基於 Python Flask 的後端 API（目前架構中，主要邏輯分佈在各模組，此處為擴展預留）。

---

## 🌟 核心功能亮點 (Key Features)

### 1. 視覺化劇本編輯器 2.0 (Visual Script Editor)

家屬可以透過「樂高式」的介面，為長輩定義自動化對話流。

* **多來源觸發器**: 支援 **語音識別**、**定時任務**、**天氣劇變**、**健康指標 (心率/步數)**、**居家感測器 (跌倒偵測)**。
* **智能畫布系統**: 具備 **Auto-Layout (自動排版)**、縮放與全自由滑動。
* **模擬器連動**: 編輯劇本時，右側模擬器會與左側畫布同步高亮，提供即時回饋感。

### 2. 生成式 AI 陪伴者 (Generative Chat)

針對長輩設計的超大字體、超大麥克風介面。

* **貼心陪聊**: AI 不只會回答，還會基於家屬輸入的「家族話題」主動開啟對話（如：傳送一張家庭旅遊照片並發問）。
* **主動語音**: 所有內容皆可透過語音朗讀，減少長輩閱讀負擔。

### 3. 家屬端智慧管理 (Smart Dashboard)

* **AI 情感判讀**: 自動分析長輩對話，提煉出一週心情洞察。
* **多層級方案**: 提供「UBan 訂閱模型」，包含免費版到家庭專業版的完整介面。

---

## �️ 技術規格 (Tech Stack)

| 領域 | 技術 / 工具 |
| :--- | :--- |
| **前端開發** | Flutter, Dart |
| **動畫引擎** | `flutter_animate` |
| **數據圖表** | `fl_chart` |
| **AI 模型** | NVIDIA yentinglin/llama-3-taiwan (Llama 3 Taiwan) |
| **語音技術** | Microsoft Edge TTS |
| **後端框架** | Python Flask (Pygame for audio testing) |
| **實時通訊** | WebRTC (Twilio/Metered) |

---

## 🚀 未來開發藍圖 (Roadmap)

1. **後端數據持久化 (Phase 1)**: 將劇本 JSON 存入資料庫，實作家屬與長輩的正式帳套與配對碼機制。
2. **AI 人格客製化 (Phase 2)**: 讓家屬能透過 UI 設定 AI 的「人設」（如：慈母、頑童、醫師）。
3. **邊緣感應接入 (Phase 3)**: 與實體手環（如 Fitbit/Garmin）及門窗感測器串接，讓「跌倒偵測」真正具備緊急通知能力。

---

## � 安裝與啟動 (Getting Started)

### 行動端 (Mobile)

```bash
cd mobile_app
flutter pub get
flutter run
```

### 伺服器 (Server)

需進入 server 目錄：`cd server`

#### 1. 安裝依賴

pip install -r requirements.txt

#### 2. 啟動伺服器

python app.py

#### 3. 檢查資料庫

python inspect_db.py

### AI 核心 (AI Core)

```bash
pip install openai edge_tts pygame duckduckgo_search
python TaiwaneseLM.py
```

---
*UBan - 用生成式 AI 填補距離，讓關心無所不在。*
