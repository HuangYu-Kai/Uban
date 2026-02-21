# AI Context & Implementation Status

此檔案旨在協助新的 AI 對話快速理解 `UBan` 專案的目前狀態、技術堆疊與已完成功能。

## 1. 專案概觀 (Project Overview)

* **專案名稱**: UBan (程式碼資料夾沿用 `UniFlow`)
* **目標**: 打造一個連結長輩與家屬的 AI 陪伴應用程式，結合擬物化 UI 與強大 AI 互動邏輯。
* **目前階段**: 前端開發 (Frontend Development) / 部分 AI 邏輯模擬 (Mock AI Logic)
* **當前分支**: `frontend-dev`

## 2. 技術堆疊 (Tech Stack)

* **Framework**: Flutter
* **Language**: Dart
* **Key Packages**:
  * `google_fonts`: UI 字體 (Inter, Noto Sans TC)。
  * `flutter_animate`: 全域動效與進場動畫。
  * `fl_chart`: 用於家屬端「照護日誌」的心情趨勢圖表。
  * `qr_flutter`: 長輩端配對 QR Code 產生。
  * `flutter_tts`: 長輩端主動問候語音。
  * `lunar`: 農曆日期轉換。

## 3. 已完成功能 (Completed Features)

### A. 身分驗證與基礎 (Authentication & Identity)

* **身分選擇 (Identification Screen)**: 使用者選擇「長輩」或「家屬」。
* **登入系統**: 支援家屬登入。

### B. 長輩端 (Elder Interface) - 擬物化 Bento Style

* **首頁 (Elder Home Screen)**: 超大字體、農曆、木質與收音機風格。
* **老友廣播站**: 擬物化收音機 UI。
* **配對系統**: 提供 4 位數配對碼與 QR Code，具備引導語音。

### C. 家屬端 (Family/Caregiver Interface)

* **儀表板 (Dashboard)**:
  * **AI 心情卡**: 顯示長輩即時情緒狀況與互動摘要。
  * **活動動態**: 長輩端互動的 Timeline。
* **視覺化劇本編輯器 (Script Editor)**:
  * **節點式編輯器**: 視覺化「觸發 -> 動作 -> 邏輯」流程。
  * **AI Copilot**: 模擬 AI 協助生成對話分支。
  * **即時模擬器 (Simulator)**: 側邊欄即時預覽長輩端在該劇本下的呈現。
* **照護日誌 (Care Journal)**:
  * **心情趨勢圖**: 週數據視覺化。
  * **AI 深度分析**: 模擬每月大數據分析報告之生成過程。
* **訂閱制管理 (Subscription)**:
  * 實作「免費版 / 個人進階版 / 家庭專業版」三層級方案介面。

## 4. 關鍵檔案結構 (Key File Structure)

```
lib/
├── screens/
│   ├── identification_screen.dart    # App 起點
│   ├── elder_home_screen.dart        # 長輩端 V2
│   ├── family_main_screen.dart       # 家屬端容器 (Bottom Nav)
│   ├── family_dashboard_view.dart    # 家屬儀表板
│   ├── family_scripts_view.dart      # 劇本列表與市場入口
│   ├── family_script_editor_screen.dart # 視覺化編輯器核心
│   ├── family_marketplace_view.dart  # 劇本市場
│   └── family/
│       ├── family_care_journal_view.dart  # 照護日誌 (fl_chart)
│       ├── family_settings_view.dart      # 設定頁面
│       └── family_subscription_screen.dart # 訂閱方案頁
└── main.dart                          # 全域主題與路由控制
```

## 5. 開發原則 (Design Principles)

* **長輩端**: 避免複雜選單，字大、圖大，使用擬物化 (Neumorphism / Skeuomorphism) 連結其既有認知。
* **家屬端**: 專業感的儀表板 (Glassmorphism)，強調「數據洞察」與「主控感」。
* **色彩規範**: 使用溫暖、具信任感的色系（橙、藍、米色基底），避開土黃色。

## 6. 待辦事項 (Backlog)

* [ ] 實作劇本儲存至本地快取的邏輯。
* [ ] 串接 LLM 實際進行劇本對話測試。
* [ ] 優化廣播站音頻播放控制。
* [ ] 實作多人共同照護權限管理。
