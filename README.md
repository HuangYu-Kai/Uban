# UBan - AI-Powered Generative Care Ecosystem

UBan 是一個領先的「AI 跨世代感知照護系統」，致力於透過生成式 AI 技術與直覺的數位工具，打造一個充滿溫度、能主動感知的智慧守護平台。

---

## 📂 專案核心架構 (System Architecture)

本專案採用現代化的多模組架構，將行動端、AI 核心與通訊服務進行解耦，提供「長輩端被動陪伴，子女端主動守護」的雙向體驗：

### 📱 [Mobile App](./mobile_app) (Flutter)

這是系統的門面，主要分為 **長輩端 (Elder Client)** 與 **家屬端 (Guardian Client)** 兩大終端體驗。

* **技術棧**: Flutter, Dart, `flutter_webrtc`, `speech_to_text`, `flutter_tts`, `socket_io_client`.
* **長輩端亮點**:
  * 極簡大字級介面、多輪氣泡對話清單。
  * 支援被動式 WebRTC 視訊接聽。
  * 實體觸感懷舊收音機設計。
* **家屬端亮點**:
  * 陪伴劇本視覺化設計中心。
  * 遠端實體守護中心（動態設備偵測與單向居家監控）。
  * 每日健康日誌與互動趨勢分析。

### 🤖 AI Agent 核心 (Gemini 2.0) & [Server](./server)

這是系統的「大腦」與後端樞紐，負責解析長輩語意並執行家屬設定的劇本。

* **模型**: Google Gemini 2.5 Flash Lite。
* **功能**:
  * **AI 溫暖語音陪伴**: 在後台濾除技術標籤，並將冷靜數據轉化為溫暖叮嚀語音。
  * **Agentic 工具聯動**: 透過函數調用 (Function Calling) 即時查詢天氣、農曆與長輩的健康日誌（RAG 記憶）。
  * **劇本執行引擎**: 驅動由子女端設計的自訂對話流程與任務。

### 📡 點對點連線 (WebRTC Signaling)

* 透過 Python Flask 與 Socket.IO 實作的信令伺服器 (Signaling Server)。
* 支援低延遲視訊串流，提供長輩環境的單向監控與雙向通訊，具備自動重連邏輯以適應不穩定的家用網路。

---

## 🌟 核心功能亮點 (Key Features)

### 1. AI 溫暖語音陪伴 (Unified Voice Companion)

系統不只朗讀文字，而是具備情感轉譯能力的語音伴侶。

* **原生 STT 辨識**: 高精確度語音轉文字，支援錄音預覽與一鍵取消。
* **自動 TTS 朗讀**: 回覆生成後自動轉換為適合長輩語速的自然語音。
* **主動式劇本引導**: AI 會根據家屬設定的劇本節點，主動向長輩發起對話。

### 2. 多功能懷舊與生活介面 (Tactile & Dashboard)

針對長輩操作習慣設計的直覺 UI。

* **懷舊收音機**: 實體感大按鈕與類比頻道切換介面。
* **智慧生活看板**: 一鍵快問天氣、農曆與安全防詐諮詢，並採用 StarPanda 手寫藝術字體播報新聞。

### 3. 家屬端遠端護理 (Remote Guardian)

讓子女能輕易掌握長輩近況並設定 AI 行為。

* **陪伴劇本設計中心**: 畫布式視覺編輯器，自由編排 AI 對話流程。
* **遠端實體監控**: WebRTC 單向影像接收，不干擾長輩作息即可查看環境安全。
* **快速配對管理**: 透過 6 位數 PIN 碼或 QR Code 雙邊掃描綁定帳號。

---

## ⚙️ 技術規格 (Tech Stack)

| 領域 | 技術 / 工具 |
| :--- | :--- |
| **前端開發App** | Flutter, Dart |
| **後端框架** | Python, Flask, Flask-SQLAlchemy, Socket.IO |
| **AI 模型** | Google Gemini 2.5 Flash Lite (Generative AI) |
| **語音技術** | `speech_to_text` (原生 STT), `flutter_tts` (原生 TTS) |
| **即時通訊** | WebRTC (`flutter_webrtc`) |
| **資料庫** | SQLite (自動關聯 User, ElderConfig, ActivityLog) |

---

## 🚀 未來開發藍圖 (Roadmap)

1. **健康週報匯總**: 透過 AI 每週自動分析 `ActivityLog` 並產出護理建議。
2. **防詐騙雷達進階版**: 即時監測語音中的可疑字眼並主動通報子女。
3. **劇本市集**: 允許使用者上傳、分享與下載常用的陪伴劇本模板。

---

## 🛠️ 安裝與啟動 (Getting Started)

### 行動端 (Mobile)

```bash
cd mobile_app
flutter clean
flutter pub get
flutter run
```

### 伺服器 (Server)

需進入 server 目錄：`cd server`

#### 1. 安裝依賴環境

```bash
pip install -r requirements.txt
```

#### 2. 設定環境變數

在 `server` 目錄下建立 `.env` 檔案並填入 Gemini API 金鑰：

```env
GEMINI_API_KEY=your_gemini_api_key_here
```

#### 3. 啟動伺服器與信令服務

```bash
python app.py
```

*(預設將開啟 5000 埠提供 API 服務，與 5001 埠提供 WebRTC 信令與 Socket 服務)*

#### 4. (可選) 檢查資料庫狀態

```bash
python inspect_db.py
```

---
*UBan - 用生成式 AI 填補距離，讓關心無所不在。*
