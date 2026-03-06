# Uban - AI 跨世代感知照護系統：使用教學 (Tutorial)

本文件將引導您從零開始架設並執行 **Uban** 系統。Uban 是一個結合 Gemini 2.5 Agentic RAG 技術與 WebRTC 實時通訊的照護平台，旨在連接近端長輩與遠端家屬。

---

## 🛠️ 第一部分：後端環境架設 (Server Setup)

後端基於 Python Flask 構建，負責處理 AI 記憶、配對邏輯與 WebRTC 信令。

### 1. 準備環境

建議使用虛擬環境以保持系統乾淨：

```bash
cd server
python -m venv venv
# Windows:
venv\Scripts\activate
# macOS/Linux:
source venv/bin/activate
```

### 2. 安裝依賴項

安裝 Flask、SQLAlchemy 與 SocketIO 等核心套件：

```bash
pip install -r requirements.txt
```

### 3. 配置環境變數

在 `server/` 目錄下建立 `.env` 檔案，並填入您的 Gemini API Key：

```env
GEMINI_API_KEY=您的_GEMINI_API_金鑰
```

### 4. 初始化與啟動

首次啟動時，系統會自動在 `instance/` 資料夾建立 SQLite 資料庫 (`uban.db`)：

```bash
python app.py
```

* **API 服務**：預設運行於 `5000` 埠。
* **Socket.IO/信令服務**：預設運行於 `5001` 埠。

---

## 📱 第二部分：行動端架設 (Mobile App Setup)

App 使用 Flutter 開發，支援長輩端與家屬端兩種模式。

### 1. 取得套件

確保您已安裝 Flutter SDK，並在 `mobile_app` 目錄執行：

```bash
cd mobile_app
flutter pub get
```

### 2. 啟動 App

您可以啟動模擬器或連接實體手機：

```bash
flutter run
```

---

## 🚀 第三部分：核心操作指南 (Core Tutorial)

### 1. 角色選擇 (Role Selection)

App 啟動後，請選擇您的身份：

* **長輩端 (Elder)**：通常安裝在平板或放置於長輩家中。
* **家屬端 (Family)**：安裝在家屬的手機中。

### 2. 雙向配對流程 (Pairing Flow)

這是系統運作的核心步驟：

1. **長輩端取得代碼**：在長輩端介面點擊「顯示配對碼」，系統會從伺服器取得一組 **4 位數 PIN 碼**。
2. **家屬端認領**：家屬登入後，點擊「新增長輩」，輸入上述的 **PIN 碼**，並填寫長輩的稱呼（如：外公）。
3. **自動註冊**：伺服器會自動為該長輩建立專屬帳號，並將家屬與長輩進行「強綁定」。
4. **成功連線**：配對完成後，長輩端會自動進入主畫面，顯示對話介面與懷舊收音機。

### 3. AI 陪伴與記憶系統

* **語音互動**：點擊麥克風即可開始說話。後端 Gemini Agent 會根據 `ElderProfile`（居住地、興趣、病史）提供個人化的回覆。
* **自動總結**：系統每 10 次對話會自動產出「健康摘要」，讓家屬隨時掌握長輩的心情與身體狀況。

### 4. 遠端監控與視訊 (WebRTC)

* **單向監控**：家屬端可選擇「查看環境」，此時長輩端會自動建立 P2P 連線並回傳影像（具備被動接聽邏輯），這讓家屬在不打擾長輩的情況下確認居家安全。
* **雙向通訊**：支援低延遲的語音與視訊通話。

---

## ⚠️ 常見問題 (Troubleshooting)

* **連線失敗**：請確認手機與伺服器是否在同一個網路網段，或將 App 中的 API URL 設定為伺服器的區域 IP 地址（例如 `192.168.x.x`）。
* **AI 無回應**：請檢查 `.env` 中的金鑰是否有效，並確認伺服器終端機是否有出現「Quota Exceeded」錯誤。
