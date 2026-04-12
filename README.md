# Uban - AI 跨世代感知照護系統

> 🏠 **AI 生成式長照陪伴生態系** - 讓科技成為連結世代的橋樑

本文件整合了 Uban 系統的完整說明，包含功能列表、安裝指南與開發文檔。

---

## 📖 目錄

- [專案簡介](#專案簡介)
- [系統架構](#系統架構)
- [核心功能](#核心功能)
- [快速開始](#快速開始)
- [開發指南](#開發指南)
- [更新日誌](#更新日誌)

---

## 專案簡介

Uban 是一套專為銀髮族設計的 AI 陪伴照護系統，包含：

- **長輩端 App**：語音優先的 AI 對話介面
- **家屬端 App**：遠端照護管理與視訊通話
- **AI 後端**：Ollama + Flask 驅動的智慧陪伴引擎

---

## 系統架構

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   長輩端 App    │────▶│   FastAPI 後端   │◀────│   家屬端 App    │
│   (Flutter)     │     │   (uban-api)    │     │   (Flutter)     │
└─────────────────┘     └────────┬────────┘     └─────────────────┘
                                 │
                    ┌────────────┴────────────┐
                    ▼                         ▼
           ┌───────────────┐         ┌───────────────┐
           │  Ollama AI    │         │   MySQL DB    │
           │ (qwen2.5:1.5b)│         │               │
           └───────────────┘         └───────────────┘
```

**連線資訊**：

| 服務 | 地址 |
|------|------|
| FastAPI 後端 | `https://localhost-0.tail5abf5e.ts.net` |
| Ollama AI | `https://boyo-t.tail531c8a.ts.net` |

---

## 核心功能

### 一、AI 核心引擎

#### 1. 雙軌 AI 引擎

- **Ollama（主要）**：使用 `qwen2.5:1.5b` 模型，支援 Tool Calling
- **Gemini（備用）**：Google Gemini 2.5 Flash API

#### 2. AI Agent 人格系統 (`server/agent/`)

| 檔案 | 用途 |
|------|------|
| **SOUL.md** | 靈魂核心：語言限制（繁體中文）、對話原則、絕對邊界 |
| **IDENTITY.md** | 角色設定：名稱「小優 (Uni)」、性格、形象 |
| **MEMORY.md** | 長期記憶庫：自動追加長輩的生活事實 |
| **USER.md** | 長輩基本資訊：姓名、年齡、喜好、用藥 |
| **HEARTBEAT.md** | 主動關懷任務：早晨問候、服藥提醒等 |
| **AGENTS.md** | 運作流程：啟動順序、記憶更新原則 |

#### 3. 記憶機制

- **短期記憶**：最近 5 輪對話（10筆）
- **長期記憶**：透過 `save_elder_memory` 永久記錄至 MEMORY.md
- **自動摘要**：每 10 筆對話自動濃縮為 100 字狀態報告

#### 4. Heartbeat 主動關懷

- 每 20 分鐘自動檢查在線長輩
- 觸發條件：早晨問候、服藥提醒、久坐提醒、家屬留言通知
- 透過 Socket.io `heartbeat-message` 即時推送

### 二、AI 技能系統（共 12 項）

| 技能 | 描述 | 模組 |
|------|------|------|
| `get_current_time` | 獲取台灣時間 | common_skills |
| `get_weather_info` | 天氣查詢與穿衣建議 | common_skills |
| `save_elder_memory` | 🆕 記錄長輩生活事實 | common_skills |
| `search_youtube_video` | YouTube 影片/音樂搜尋 | common_skills |
| `search_web` | 🆕 Google 搜尋 | common_skills |
| `get_music_recommendations` | 🆕 歌手熱門歌曲 | common_skills |
| `get_elder_context` | 讀取長輩背景 | elder_skills |
| `notify_family_SOS` | 緊急通知家屬 | elder_skills |
| `suggest_activity` | 推薦日常活動 | elder_skills |
| `get_family_messages` | 讀取家屬留言 | comm_skills |
| `initiate_video_call` | 發起視訊通話 | comm_skills |
| `record_elder_activity` | 記錄活動與心情 | health_skills |

### 三、長輩端 App (Flutter)

- **語音對話**：STT/TTS、連續對話、打斷機制
- **Markdown 渲染**：自動轉換影片/圖片卡片
- **快捷問題卡片**：一鍵發問常見問題

### 四、家屬端管理

- **配對機制**：PIN 碼 + QR Code 雙軌認領
- **GPS 快速選址**：一鍵帶入行政區域
- **陪伴大腦設定**：自訂 AI 人格與長輩資料

### 五、視訊通話

- **WebRTC P2P**：高品質視訊、STUN + coturn TURN 雙重 NAT 穿透
- **三層備援**：Socket.IO 即時 → FCM 推播 → Cold Start 冷啟動
- **緊急模式**：CCTV 監控 / 自動接聽
- **通話控制**：麥克風靜音、鏡頭開關、前後鏡頭切換、揚聲器、通話計時
- **語音模式**：支援純語音通話（不啟動攝影機）
- **TURN 伺服器**：coturn 中繼，支援跨 NAT（4G ↔ WiFi）場景

---

## 快速開始

### 環境需求

| 工具 | 版本 | 說明 |
|------|------|------|
| Python | 3.12 | ⚠️ 不支援 3.13+（eventlet 相容性） |
| Flutter | Latest | 執行 `flutter doctor` 確認 |
| Ollama | - | 遠端已部署，或本地 `ollama pull qwen2.5:1.5b` |

### 一鍵啟動

```bash
# macOS / Linux
chmod +x run.sh
./run.sh

# Windows PowerShell
.\run.ps1
```

### 啟動選單

| 選項 | 功能 |
|------|------|
| **[1] 🚀 一鍵啟動** | 自動檢測模擬器、連接後端 + Ollama、啟動 App |
| **[2] 🔄 熱重啟** | 快速重啟（不重新編譯） |
| **[3] 🔍 檢查後端** | 測試 FastAPI + Ollama 連線 |
| **[4] 🧹 清理程序** | 停止所有 Flutter 進程 |
| **[5] ⚙️ 自訂網址** | 使用自訂伺服器啟動 |

### 命令行參數

```bash
./run.sh -s              # 直接啟動
./run.sh -c              # 檢查後端
./run.sh -r              # 熱重啟
./run.sh -h              # 顯示幫助
```

---

## 開發指南

### 專案結構

```
Uban/
├── mobile_app/              # Flutter 前端
│   └── lib/
│       ├── services/        # API、Signaling (WebRTC + Socket.IO)
│       ├── screens/         # UI 頁面
│       │   ├── elder_screen.dart        # 長輩端通話
│       │   ├── video_call_screen.dart   # 家屬端通話
│       │   ├── family_main_screen.dart  # 家屬主畫面 (來電監聽)
│       │   └── elder_tabs/             # 長輩端分頁
│       └── globals.dart     # 全域狀態
├── server/                  # ⚠️ Legacy Flask (已棄用，勿修改)
├── webrtc_test.html         # 瀏覽器版 WebRTC 測試工具 (v1.1)
├── test_call_simulator.py   # Socket.IO 信令測試腳本
├── run.sh                   # macOS/Linux 啟動腳本
├── run.ps1                  # Windows 啟動腳本
├── .geminirules             # Gemini AI 開發規範
└── CLAUDE.md                # Claude AI 開發規範

uban-api/                    # FastAPI 後端 (獨立 Repo)
├── main.py                  # FastAPI 入口 + Socket.IO ASGI
├── services/socket_app.py   # 信令轉發伺服器
├── services/ollama_service.py # AI 引擎
└── routers/                 # REST API 路由
```

### 關鍵檔案

| 檔案 | 用途 |
|------|------|
| `lib/services/signaling.dart` | Socket.IO + WebRTC 信令 (Singleton) |
| `lib/main.dart` | App 入口 + FCM + CallKit 全域監聽 |
| `lib/globals.dart` | `pendingAcceptedCall` 全域狀態 |
| `lib/screens/elder_screen.dart` | 長輩端通話 (含 CCTV/緊急/語音模式) |
| `lib/screens/video_call_screen.dart` | 家屬端通話 (含控制列) |
| `uban-api/services/socket_app.py` | 後端信令轉發伺服器 |

### 視訊通話測試

#### 方法 1：瀏覽器測試（推薦，不需 Android 設備）

直接開啟 `webrtc_test.html` (v1.1)，支援：
- ✅ 連接 Socket.IO 信令伺服器
- ✅ 模擬 family/elder 雙角色
- ✅ TURN 伺服器獨立驗證（一鍵測試 relay candidate）
- ✅ ICE candidate 實時統計
- ✅ 強制 relay 模式（同網路也能測 TURN）
- ✅ ICE candidate 排隊機制（解決影像黑屏問題）
- ✅ ontrack fallback（保證遠端影像正確顯示）

#### 方法 2：Socket.IO 信令腳本

```bash
python3 -m venv /tmp/uban_test_venv
/tmp/uban_test_venv/bin/pip install "python-socketio[asyncio_client]" websockets
/tmp/uban_test_venv/bin/python3 test_call_simulator.py
```

> 📖 詳細說明請參考 [TEST_CALL_SIMULATOR_GUIDE.md](./TEST_CALL_SIMULATOR_GUIDE.md)

### TURN 伺服器配置

視訊通話在跨網路環境（4G ↔ WiFi）需要 TURN 伺服器中繼。

```bash
# 在伺服器安裝 coturn
sudo apt install coturn

# 設定 /etc/turnserver.conf
# listening-port=3478
# realm=uban.turn
# user=uban:password
# fingerprint
# lt-cred-mech
```

Flutter 端透過 `--dart-define` 注入：
```bash
flutter run \
  --dart-define=SERVER_IP=your-server \
  --dart-define=TURN_SERVER=your-server:3478 \
  --dart-define=TURN_USER=uban \
  --dart-define=TURN_PASS=password
```

---

## 常見問題

| 問題 | 解決方案 |
|------|----------|
| 連線失敗 | 確認 IP 匹配，使用選項 [3] 檢查 |
| 權限報錯 | 執行 `Set-ExecutionPolicy RemoteSigned` |
| Port 被佔用 | `run.ps1` 會自動清理殘留程序 |

---

## 遊戲化系統 (Feed Gawa)

### 造型分配與排行榜架構

#### 管理者端

- **UI**: `mobile_app/lib/screens/admin_appearance_screen.dart`
  - 排程設定：下次全服隨機派發時間
  - 單獨分配：指定 `elder_id` 與 `gawa_id` 強制覆寫
  - 長輩查詢：累積步數、造型清單、加成比例

- **API**: `server/routes/game_logic.py`
  - `set_distribution_time`: 寫入 `schedule_config.json`
  - `assign_appearance`: 手動指派（備份→重置步數→寫入新造型）
  - `get_admin_elder_info`: 統整長輩資料

#### 使用者端

- **UI**: `mobile_app/lib/screens/leaderboard_screen.dart`
  - 收集進度：顯示已擁有造型與總加成倍率
  - 好友排行榜：前 10 名 + 自己排名

#### 步數偵測實作建議

**推薦方案：`pedometer` 套件**（輕量、即時）

```dart
import 'package:pedometer/pedometer.dart';

late Stream<StepCount> _stepCountStream;

void initPedometer() {
  _stepCountStream = Pedometer.stepCountStream;
  _stepCountStream.listen(
    (StepCount event) {
      print("目前總步數: ${event.steps}");
      // 更新到伺服器 elder_profile.step_total
    },
    onError: (error) => print("計步器錯誤: $error"),
  );
}
```

**權限設定**：

- Android: `AndroidManifest.xml` 加入 `ACTIVITY_RECOGNITION`
- iOS: `Info.plist` 加入 `NSMotionUsageDescription`

---

## 更新日誌

### 2026-04-12 🐛 修復 WebRTC 雙向影像傳輸問題
**修復 WebRTC 通話時遠端影像顯示黑屏的問題**

#### 🔧 修改內容

**webrtc_test.html (v1.0 → v1.1, 3 處核心修正)**
1. **ICE Candidate 排隊機制** — 新增 `candidateQueue` 和 `hasRemoteDescription` 狀態追蹤，解決 ICE candidate 在 `setRemoteDescription` 之前到達時被靜默丟棄的問題
2. **ontrack fallback 處理** — 當 `e.streams` 為空時，使用 fallback `MediaStream` 手動將 track 加入，確保遠端影像正確顯示
3. **增強診斷日誌** — 新增 track 狀態、SDP 大小、negotiationneeded 事件等詳細日誌，方便排查問題

**根因分析**
- WebRTC 的 Offer/Answer 和 ICE candidate 交換是異步的
- 當 ICE candidate 在 `setRemoteDescription()` 完成前到達時，`addIceCandidate()` 會拋出錯誤
- 原始代碼沒有排隊機制，這些候選項被靜默丟棄
- 缺少足夠的 ICE candidate 導致 P2P 連線無法建立，遠端影像為黑屏

---

### 2026-04-11 🎥 視訊功能完整實裝 + TURN 配置 + 測試工具
**7 個檔案修改，補完視訊通話所有缺失功能**

#### 🔧 修改內容

**新增檔案**
- `webrtc_test.html` — 瀏覽器版 WebRTC 測試工具（含 TURN 驗證）
- `CLAUDE.md` × 2 — Claude AI 開發指引（前端 + 後端）

**signaling.dart (4 處修改)**
1. **TURN 伺服器配置** — 新增 coturn ICE server（含 TCP 備援）
2. **移除 VoidCallback 重定義** — 避免與 Flutter 內建衝突
3. **openUserMedia 支援純語音** — 新增 `videoEnabled` 參數
4. **防止重複 Offer** — `call-accept` handler 改為條件觸發

**video_call_screen.dart (完整重寫)**
- ✅ 麥克風靜音/取消靜音
- ✅ 鏡頭開關
- ✅ 前後鏡頭切換
- ✅ 揚聲器切換
- ✅ 通話計時器 (mm:ss)
- ✅ Glassmorphism 底部控制列
- ✅ 單一 createOffer 入口（防止重複）

**elder_screen.dart** — 新增 `isVideoCall` 參數（語音模式不啟動攝影機）
**elder_home_tab.dart** — 傳遞 `isVideo` 給 ElderScreen
**socket_app.py** — 修正 `debugPrint()` → `print()`
**requirements.txt** — 合併 `python-socketio[asgi,asyncio_client]`
**.geminirules** × 2 — 全面更新（含通話流程、角色差異、ICE 配置）

---

### 2026-04-09 🎙️ WebRTC 信令流程完整修復
**修復內容：自動媒體協商 + 精準信令轉發 + 完整資源釋放**

#### 🔧 修改內容（共 8 處改進）

**signaling.dart (5 處修改)**
1. **call-accept 自動啟動 Offer** — 接聽後觸發 `createOffer`
2. **answer 精準指定 targetId** — 確保精準指向發起者
3. **ICE Candidate 完整轉發** — 添加 `senderId` 和驗證
4. **增強媒體資源清理** — 主動移除 track

**socket_app.py (3 處改進)**
1. **offer/answer/candidate 精準轉發** — `to=target` 替代廣播

#### 🧪 驗證狀態
- ✅ Dart 語法檢查通過
- ✅ Python 語法檢查通過

---

### 2026-04-07

#### 🎉 今日智能建議功能上線
- **[Feature]** 家屬端 AI 中樞新增「今日智能建議」功能
  - ✅ 基於真實對話情緒分析（焦慮、孤單、疼痛關鍵詞）
  - ✅ 整合運動記錄追蹤（7天活動量統計）
  - ✅ 整合用藥記錄監控（3天用藥完整性）
  - ✅ 6 種建議類型：情緒、社交、健康、活動、用藥、鼓勵
  - ✅ 優先級自動排序（高/中/低）與顏色編碼
- **[API]** 新增後端端點 `GET /api/ai/daily-suggestions/{elder_id}`
  - 數據來源：`activity_log` 表（chat/exercise/medication）
  - 算法：關鍵詞統計 + 頻率閾值判斷
  - 部署：GitHub Actions 自動部署到生產環境
- **[Fix]** 修復 API 數據訪問錯誤
  - 修正 `fetch_as_dict()` 返回列表處理
  - 修正 `cursor.fetchone()` 字典鍵訪問
  - 修正 `cursor.fetchall()` 字典列表遍歷
- **[DevOps]** 建立完整 CI/CD 流程
  - GitHub Actions + Tailscale + Podman
  - 自動測試、構建、部署
  - 提交 commit: `5adb905`

#### 其他更新
- **[Feature]** 視訊通話模擬器支援雙向通話（長輩 → 家屬）
- **[Fix]** 修正房間號統一使用 `user_id`（長輩端與家屬端一致）
- **[Fix]** 修正 `ApiService.getPairedElders()` API 格式解析問題
- **[Feature]** 家屬端自動獲取配對長輩並連線到正確房間
- **[Docs]** 更新 `TEST_CALL_SIMULATOR_GUIDE.md` 測試指南

### 2026-04-02

- **[Docs]** 文檔整合：合併 CLAUDE.md、feedgawa_intro.md

### 2026-04-01

- **[AI] Ollama 整合**：新增 `qwen2.5:7b` 模型支援
- **[AI] Agent 人格系統**：SOUL.md、IDENTITY.md、MEMORY.md 等 6 個設定檔
- **[AI] Heartbeat 機制**：每 20 分鐘主動關懷
- **[AI] 新增技能**：`save_elder_memory`、`search_web`、`get_music_recommendations`
- **[DevOps] run.sh/run.ps1**：新增 Ollama 連線檢測

### 2026-03-31

- **[Security]** CORS 限制、JWT 認證、密碼安全
- **[Performance]** N+1 查詢優化、API 分頁
- **[DevOps]** GitHub Actions CI

---

## 功能與資料路徑對照表

### AI 核心功能

| 功能 | 描述 | 資料路徑 |
|------|------|----------|
| Ollama AI 引擎 | 主要 AI，使用 qwen2.5 模型 | `uban-api/services/ollama_service.py` |
| Gemini 備用引擎 | Google Gemini 2.5 Flash | `uban-api/services/gemini_service.py` |
| AI 工具服務 | Tool Calling 整合 | `uban-api/services/tools_service.py` |
| Agent 人格系統 | 6 個設定檔定義 AI 性格 | `server/agent/*.md` |
| Heartbeat 關懷 | 每分鐘檢查主動推播 | `uban-api/main.py` → `heartbeat_job()` |

### AI 技能（12 項）

| 技能 | 功能 | 資料路徑 |
|------|------|----------|
| `get_current_time` | 查詢台灣時間 | `server/skills/common_skills.py` |
| `get_weather_info` | 天氣查詢 | `server/skills/common_skills.py` |
| `save_elder_memory` | 記錄長輩記憶 | `server/skills/common_skills.py` |
| `search_youtube_video` | YouTube 搜尋 | `server/skills/common_skills.py` |
| `search_web` | Google 搜尋 | `server/skills/common_skills.py` |
| `get_music_recommendations` | 音樂推薦 | `server/skills/common_skills.py` |
| `get_elder_context` | 讀取長輩背景 | `server/skills/elder_skills.py` |
| `notify_family_SOS` | 緊急通知家屬 | `server/skills/elder_skills.py` |
| `suggest_activity` | 推薦日常活動 | `server/skills/elder_skills.py` |
| `get_family_messages` | 讀取家屬留言 | `server/skills/comm_skills.py` |
| `initiate_video_call` | 發起視訊通話 | `server/skills/comm_skills.py` |
| `record_elder_activity` | 記錄活動心情 | `server/skills/health_skills.py` |

### API 路由模組

| 模組 | 端點前綴 | 資料路徑 |
|------|----------|----------|
| 認證 | `/api/auth` | `uban-api/routers/auth.py` |
| 用戶 | `/api/user` | `uban-api/routers/user.py` |
| 配對 | `/api/pairing` | `uban-api/routers/pairing.py` |
| AI | `/api/ai` | `uban-api/routers/ai.py` |
| 關係 | `/api/relationship` | `uban-api/routers/relationship.py` |
| 活動 | `/api/activity` | `uban-api/routers/activity.py` |
| 遊戲 | `/api/game` | `uban-api/routers/game.py` |
| 語音 | `/api/voice` | `uban-api/routers/voice.py` |

### 長輩端 App 頁面

| 頁面 | 功能 | 資料路徑 |
|------|------|----------|
| AI 聊天 | 語音對話主介面 | `mobile_app/lib/screens/ai_chat_screen.dart` |
| 重設計聊天 | 新版 UI 聊天介面 | `mobile_app/lib/screens/redesigned_ai_chat_screen.dart` |
| 長輩首頁 | 主功能選單 | `mobile_app/lib/screens/elder_home_screen.dart` |
| 長輩 Tabs | 分頁導航 | `mobile_app/lib/screens/elder_tabs/` |
| 天氣頁面 | 天氣資訊顯示 | `mobile_app/lib/screens/weather_screen.dart` |
| 廣播電台 | 音樂播放 | `mobile_app/lib/screens/radio_station_screen.dart` |
| 聯絡人 | 通訊錄 | `mobile_app/lib/screens/contacts_screen.dart` |
| 視訊通話 | WebRTC 視訊 | `mobile_app/lib/screens/video_call_screen.dart` |
| 配對顯示 | PIN 碼展示 | `mobile_app/lib/screens/elder_pairing_display_screen.dart` |

### 家屬端 App 頁面

| 頁面 | 功能 | 資料路徑 |
|------|------|----------|
| 家屬儀表板 | 主控制台 | `mobile_app/lib/screens/family_dashboard_screen.dart` |
| 家屬 AI 聊天 | 代理 AI 對話 | `mobile_app/lib/screens/family_ai_chat_screen.dart` |
| 增強版聊天 | 進階聊天介面 | `mobile_app/lib/screens/enhanced_family_ai_chat_screen.dart` |
| 陪伴大腦編輯 | 自訂 AI 腳本 | `mobile_app/lib/screens/family_script_editor_screen.dart` |
| 腳本管理 | 腳本列表 | `mobile_app/lib/screens/family_scripts_view.dart` |
| 通話紀錄 | 歷史通話 | `mobile_app/lib/screens/family_call_history_screen.dart` |
| 新手導引 | 配對流程 | `mobile_app/lib/screens/family_onboarding_screen.dart` |
| 配對頁面 | 輸入 PIN 碼 | `mobile_app/lib/screens/caregiver_pairing_screen.dart` |
| QR 掃描 | QR Code 配對 | `mobile_app/lib/screens/qr_scanner_screen.dart` |
| 長輩選擇 | 多長輩切換 | `mobile_app/lib/screens/elder_selection_screen.dart` |
| 長輩檔案編輯 | 編輯長輩資料 | `mobile_app/lib/screens/elder_profile_edit_screen.dart` |
| Agent 檢視 | AI 代理狀態 | `mobile_app/lib/screens/family_agent_view.dart` |

### 遊戲化系統 (Feed Gawa)

| 功能 | 描述 | 資料路徑 |
|------|------|----------|
| 排行榜 | 好友步數排名 | `mobile_app/lib/screens/leaderboard_screen.dart` |
| 管理員造型 | 發放/指派造型 | `mobile_app/lib/screens/admin_appearance_screen.dart` |
| 步數儲存 | 計步數據同步 | `uban-api/routers/game.py` → `save_steps` |
| 等級計算 | 1-8 級階梯 | `uban-api/routers/game.py` → `get_level()` |
| 造型 CRUD | 寵物外觀管理 | `uban-api/routers/game.py` → appearance endpoints |
| 好友系統 | Fellowship 關係 | `uban-api/routers/game.py` → fellowship endpoints |
| 遊戲服務 | 前端整合 | `mobile_app/lib/services/game_service.dart` |

### 智慧服務層

| 服務 | 功能 | 資料路徑 |
|------|------|----------|
| API 服務 | 後端通訊 | `mobile_app/lib/services/api_service.dart` |
| 認證服務 | 登入/Token | `mobile_app/lib/services/auth_service.dart` |
| Signaling | Socket.IO + WebRTC | `mobile_app/lib/services/signaling.dart` |
| AI 建議 | 智慧推薦 | `mobile_app/lib/services/ai_suggestion_service.dart` |
| 情緒儲存 | 情緒記錄 | `mobile_app/lib/services/emotion_storage_service.dart` |
| 語音情緒 ML | 語音情感分析 | `mobile_app/lib/services/voice_emotion_ml_service.dart` |
| 健康異常 | 異常偵測 | `mobile_app/lib/services/health_anomaly_detector.dart` |
| 預測警報 | 風險預警 | `mobile_app/lib/services/predictive_alert_service.dart` |
| 健康報告 | 報告生成 | `mobile_app/lib/services/health_report_service.dart` |
| 智慧通知 | 推播管理 | `mobile_app/lib/services/smart_notification_service.dart` |
| 家屬同步 | 資料同步 | `mobile_app/lib/services/family_sync_service.dart` |
| 貢獻服務 | 數據統計 | `mobile_app/lib/services/contribution_service.dart` |
| 資料匯出 | 匯出功能 | `mobile_app/lib/services/data_export_service.dart` |
| 任務板 | 任務管理 | `mobile_app/lib/services/task_board_service.dart` |
| 腳本資料 | AI 腳本 | `mobile_app/lib/services/script_data_service.dart` |

### Agent 人格設定檔

| 檔案 | 用途 | 資料路徑 |
|------|------|----------|
| SOUL.md | 語言限制、對話原則、絕對邊界 | `server/agent/SOUL.md` |
| IDENTITY.md | 角色名稱「小優」、性格形象 | `server/agent/IDENTITY.md` |
| MEMORY.md | 長期記憶庫 | `server/agent/MEMORY.md` |
| USER.md | 長輩基本資訊 | `server/agent/USER.md` |
| HEARTBEAT.md | 主動關懷任務設定 | `server/agent/HEARTBEAT.md` |
| AGENTS.md | 運作流程、啟動順序 | `server/agent/AGENTS.md` |

### 資料庫 Schema

| 表格 | 用途 | 文檔位置 |
|------|------|----------|
| user_account_data | 用戶帳號 | `uban-api/DATABASE.md` |
| elder_profile | 長輩檔案 | `uban-api/DATABASE.md` |
| family_elder_relationship | 配對關係 | `uban-api/DATABASE.md` |
| pairing_code | 配對碼 | `uban-api/DATABASE.md` |
| activity_log | 活動日誌 | `uban-api/DATABASE.md` |
| gawa_appearance | 寵物外觀 | `uban-api/DATABASE.md` |

---

## AI 助手指引

> 開發本專案前，請確保 AI 已閱讀此 README.md：
>
> 1. **架構**：Flutter + FastAPI (`uban-api` 獨立 Repo)
> 2. **Legacy**：`server/` 目錄為舊 Flask AI 代碼，勿修改
> 3. **Socket.IO**：必須使用 Singleton Pattern (`lib/services/signaling.dart`)
> 4. **Server URL**：透過 `--dart-define=SERVER_IP=` 注入，禁止寫死
> 5. **TURN 伺服器**：透過 `--dart-define=TURN_SERVER=` / `TURN_USER=` / `TURN_PASS=` 注入
> 6. **長輩端通話**：入口是 `ElderScreen`，不要直接使用 `VideoCallScreen`
> 7. **通話流程**：call-request → call-accept → createOffer → answer → ice-candidate → P2P

### AI 規範文件

| 檔案 | 適用 AI | 位置 |
|------|---------|------|
| `.geminirules` | Gemini / Google AI | `Uban/` 和 `uban-api/` 各一份 |
| `CLAUDE.md` | Claude / Anthropic | `Uban/` 和 `uban-api/` 各一份 |
| `.cursorrules` | Cursor AI | `Uban/` |

---

📝 *最後更新：2026/04/12*
