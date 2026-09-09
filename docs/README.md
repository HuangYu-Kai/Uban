# Uban 系統全功能說明文件目錄導覽 (System Documentation Catalog)

本目錄 (`Uban/docs/`) 為 **Uban (有伴) 智慧跨世代長輩陪伴與照護系統** 的核心規格與說明文件庫，涵蓋系統所有已完成之功能設計、架構拓撲、API 規格、UI/UX 無障礙美學與測試驗證規範。

---

## 📚 目錄結構 (Directory Structure)

```text
Uban/docs/
├── README.md                           # 【本文件】全功能文檔總導覽與功能矩陣
├── general/                            # 【通用與產品指南】設計風格、角色概念、操作手冊
│   ├── ART_STYLE_GUIDE_PIGLET.md       # 小豬伴侶視覺美學與手繪風格指南
│   ├── ULTIMATE_PET_PROPOSAL.md        # 桌面陪伴寵物功能提案書
│   ├── feedgawa_intro.md               # 小豬 Gawa 角色背景與互動模式介紹
│   ├── mascot_guide.md                 # 系統吉祥物與插畫風格規範
│   ├── monitor_device_guide.md         # AI 守護監視機設備操作手冊
│   ├── proposal.md                     # 專案初始架構與照護願景提案
│   ├── ai_work_log.md                  # AI 模組開發紀錄日誌
│   └── walkthrough.md                  # 專案演進與各階段 Walkthrough 總結
└── technical/                          # 【詳細技術架構文件】嚴格遵循 8 大章節標準
    ├── DOCUMENTATION_GUIDELINE.md      # 技術文檔撰寫標準與結構規範
    ├── LIFE_STORY_CAPSULE.md           # 🌟 人生故事時光膠囊與自傳繪本館架構 (v2.4.0)
    ├── REMOTE_REMINDERS_AND_TASKS.md   # 🌟 遠端排程提醒與長輩用藥手帳架構 (v2.4.0)
    ├── INDOOR_POSITIONING_SYSTEM.md    # 🌟 室內定位系統 (IPS) 與區域停留分析 (v2.4.0)
    ├── MODULARIZATION_AND_API_FACADE.md# 🌟 專案架構模組化與 API 門面模式 (v2.4.0)
    ├── PET_COMPANION_BLUEPRINT.md      # 小豬伴侶寵物藍圖與數值演算法
    ├── YUNI_CHAT_MANUAL.md             # Yuni AI 語音/串流陪伴助理技術手冊
    ├── COMMUNITY_ARCHITECTURE.md       # 家庭溫馨社群貼文、點讚與留言架構
    ├── NEWS_LISTEN_PLAYER.md           # 長輩即時新聞廣播與 TTS 播放器架構
    ├── INSTITUTION_PORTAL.md           # 機構管理後台技術架構
    ├── SUBSCRIPTION_ARCHITECTURE.md    # 商業多層級訂閱與配額控管架構
    ├── OLLAMA_LATENCY_REPORT.md        # 本地/遠端 Ollama 延遲與降級評測報告
    └── CALL_FIX_LOG.md                 # WebRTC 與來電通訊修復紀錄 (另見 CLAUDE_call-monitor.md)
```

---

## 🗺️ 系統已完成功能與說明文件對應矩陣 (Feature Matrix)

| 核心領域 | 功能模組名稱 | 涵蓋重點與特色 | 對應說明文件 | 狀態 |
| :--- | :--- | :--- | :--- | :---: |
| **人生記憶** | **人生故事時光膠囊 / 自傳繪本館** | AI 主動提問、口述錄音即成故事、四象限時光膠囊、自傳繪本擬真翻頁閱讀、家屬原聲收聽與溫馨留言、委託 AI 提問 | [LIFE_STORY_CAPSULE.md](technical/LIFE_STORY_CAPSULE.md) | 🟢 完整 |
| **健康照護** | **遠端排程提醒 / 用藥打卡手帳** | 家屬遠端排程、FCM 背景高優先級 Heads-up 橫幅、長輩米白便籤風格今日排程手帳、大字級一鍵打卡完成 | [REMOTE_REMINDERS_AND_TASKS.md](technical/REMOTE_REMINDERS_AND_TASKS.md) | 🟢 完整 |
| **安全守護** | **室內定位 (IPS) / 區域停留分析** | 監視機無感 YOLO 人體檢測、射線法多邊形空間判定、客廳/臥室/浴室即時位置辨識、超時異常預警、動態雷達卡片 | [INDOOR_POSITIONING_SYSTEM.md](technical/INDOOR_POSITIONING_SYSTEM.md) | 🟢 完整 |
| **核心架構** | **專案模組化 / API 門面架構** | 單體檔案縮減 70~94%、按單一職責拆分 25+ 個獨立元件、API 門面 (Facade Pattern) 8 大領域模組拆解、零回歸保障 | [MODULARIZATION_AND_API_FACADE.md](technical/MODULARIZATION_AND_API_FACADE.md) | 🟢 完整 |
| **情感陪伴** | **長輩小豬伴侶寵物系統** | 繪本風生活舞台、PetMood 心情狀態、撫摸戳戳互動、愛心噴發自繪粒子效果、好感度與進化數值模型 | [PET_COMPANION_BLUEPRINT.md](technical/PET_COMPANION_BLUEPRINT.md)<br/>[ART_STYLE_GUIDE_PIGLET.md](general/ART_STYLE_GUIDE_PIGLET.md) | 🟢 完整 |
| **AI 助理** | **Yuni AI 語音陪伴與助理** | 串流 SSE 逐字輸出 (aiChatStream)、長輩自訂稱謂、Whisper 語音轉文字 (ASR)、Edge-TTS 語音合成、每日智能建議 | [YUNI_CHAT_MANUAL.md](technical/YUNI_CHAT_MANUAL.md)<br/>[OLLAMA_LATENCY_REPORT.md](technical/OLLAMA_LATENCY_REPORT.md) | 🟢 完整 |
| **家庭互動** | **家庭溫馨社群** | 家庭私密圈貼文、長輩拍立得心情蓋章、家屬愛心「關心 ❤️」點讚、多媒體圖片與語音留言 | [COMMUNITY_ARCHITECTURE.md](technical/COMMUNITY_ARCHITECTURE.md) | 🟢 完整 |
| **日常資訊** | **長輩即時新聞廣播電台** | 即時新聞爬取與重點精簡摘要、長輩大字大按鈕語音播放介面、早午晚時令新聞推送 | [NEWS_LISTEN_PLAYER.md](technical/NEWS_LISTEN_PLAYER.md) | 🟢 完整 |
| **安全守護** | **守護監視機與 YOLO 跌倒偵測** | 監視機配對綁定、CCTV 即時推幀分析、YOLOv8 異常跌倒預警推播、30 分鐘音頻安全橋 (Audio Bridge) | [monitor_device_guide.md](general/monitor_device_guide.md)<br/>[CLAUDE_call-monitor.md](../CLAUDE_call-monitor.md) | 🟢 完整 |
| **通訊守護** | **WebRTC 視訊通話與 CallKit 來電** | 雙向 WebRTC 影音、全螢幕原生 CallKit、背景 Isolate 喚醒、救護車雙音提示、無狀態 HTTP 拒接備援與防毒 Prefs 護欄 | [CALL_FIX_LOG.md](technical/CALL_FIX_LOG.md)<br/>[CLAUDE_call-monitor.md](../CLAUDE_call-monitor.md) | 🟢 完整 |
| **機構管理** | **機構照護門戶後台** | 多床位/多長輩集中監控看板、照護員派工排班、異常告警中心與長輩健康歷史報表 | [INSTITUTION_PORTAL.md](technical/INSTITUTION_PORTAL.md) | 🟢 完整 |
| **商業體系** | **多層級訂閱收費架構** | 免費版/進階版/機構版層級權限控制、監視設備連線上限管控、安全通話配額與歷史帳單 | [SUBSCRIPTION_ARCHITECTURE.md](technical/SUBSCRIPTION_ARCHITECTURE.md) | 🟢 完整 |
| **資料架構** | **全系統資料庫架構 (Database Schema)** | SQLite / PostgreSQL 資料表結構、外部鍵關聯、索引設計與關聯圖譜 | [DATABASE.md](../../Uban-api/docs/DATABASE.md) | 🟢 完整 |

---

## 🛠️ 技術文檔撰寫規範指南

專案所有技術文檔均遵循 [DOCUMENTATION_GUIDELINE.md](technical/DOCUMENTATION_GUIDELINE.md) 所定義之八大核心章節：
1. **元數據 (Metadata Header)**
2. **功能背景與設計初衷 (Objectives & Background)**
3. **系統架構與資料流向 (System Architecture & Data Flow)**
4. **代碼修改與路徑定義 (Implementation & File References)**
5. **核心數學公式與物理演算法 (Core Mathematical Models)**
6. **UI/UX 視覺美學與無障礙規範 (Aesthetics & Accessibility)**
7. **安全性防護與防誤觸機制 (Safety & Debouncing)**
8. **測試與驗證計畫 (Test Plan & Checklist)**
