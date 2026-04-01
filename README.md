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

- **WebRTC P2P**：高品質視訊、自動 NAT 穿透
- **三層備援**：Socket.io + FCM + Cold Start
- **緊急模式**：CCTV/自動接聽功能

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
├── mobile_app/          # Flutter 前端
│   └── lib/
│       ├── services/    # API、Signaling
│       └── screens/     # UI 頁面
├── server/              # Flask AI 後端
│   ├── agent/           # AI 人格設定 (*.md)
│   ├── services/        # ollama_service, heartbeat_manager
│   ├── skills/          # 12 項 AI 技能
│   └── routes/          # API 路由
├── run.sh               # macOS/Linux 啟動腳本
└── run.ps1              # Windows 啟動腳本
```

### 關鍵檔案

| 檔案 | 用途 |
|------|------|
| `lib/services/signaling.dart` | Socket.IO + WebRTC |
| `lib/main.dart` | App 入口 + 全域監聽器 |
| `server/services/ollama_service.py` | Ollama 整合 |
| `server/services/heartbeat_manager.py` | 主動關懷引擎 |
| `server/skills/__init__.py` | 12 項技能匯出 |

### 視訊通話測試

```bash
# 建立測試環境
python3 -m venv /tmp/uban_test_venv
/tmp/uban_test_venv/bin/pip install "python-socketio[asyncio_client]" websockets

# 執行測試腳本
/tmp/uban_test_venv/bin/python3 test_call_simulator.py
```

---

## 常見問題

| 問題 | 解決方案 |
|------|----------|
| 連線失敗 | 確認 IP 匹配，使用選項 [3] 檢查 |
| 權限報錯 | 執行 `Set-ExecutionPolicy RemoteSigned` |
| Port 被佔用 | `run.ps1` 會自動清理殘留程序 |

---

## 更新日誌

### 2026-04-01
- **[AI] Ollama 整合**：新增 `qwen2.5:1.5b` 模型支援
- **[AI] Agent 人格系統**：SOUL.md、IDENTITY.md、MEMORY.md 等 6 個設定檔
- **[AI] Heartbeat 機制**：每 20 分鐘主動關懷
- **[AI] 新增技能**：`save_elder_memory`、`search_web`、`get_music_recommendations`
- **[DevOps] run.sh/run.ps1**：新增 Ollama 連線檢測
- **[Docs] 文檔整合**：合併 features_list.md 至 README.md

### 2026-03-31
- **[Security]** CORS 限制、JWT 認證、密碼安全
- **[Performance]** N+1 查詢優化、API 分頁
- **[DevOps]** GitHub Actions CI

---

📝 *最後更新：2026/04/01*
