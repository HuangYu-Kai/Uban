# AI Context & Implementation Status

此檔案旨在協助新的 AI 對話快速理解 `CompanionFlow` (UniFlow) 專案的目前狀態、技術堆疊與已完成功能。

## 1. 專案概觀 (Project Overview)
*   **專案名稱**: CompanionFlow (於程式碼中某些地方仍沿用 `UniFlow` 資料夾名稱)
*   **目標**: 打造一個連結長輩與家屬的陪伴應用程式。
*   **目前階段**: 前端開發 (Frontend Development)
*   **當前分支**: `frontend-dev` (主要開發分支)

## 2. 技術堆疊 (Tech Stack)
*   **Framework**: Flutter
*   **Language**: Dart
*   **Key Packages**:
    *   `google_fonts`: 用於 UI 字體 (Inter, Noto Sans TC)。
    *   `font_awesome_flutter`: 用於社群登入與 UI 圖示。
    *   `qr_flutter`: 用於長輩配對畫面產生 QR Code。
    *   `flutter_tts`: 用於長輩配對畫面的語音播報。
    *   `flutter_animate`: 用於 UI 動效 (呼吸燈、進場動畫)。
    *   `lunar`: 用於農曆日期轉換。
    *   `intl`: 用於日期格式化 (zh_TW)。

## 3. 已完成功能 (Completed Features)

### A. 身分驗證 (Identity Verification)
*   **身分選擇 (Identification Screen)**:
    *   位置: `lib/screens/identification_screen.dart`
    *   功能: App 啟動首頁。讓使用者選擇「我是長輩」或「家屬/照護者登入」。
    *   特色: 「我是長輩」按鈕有大笑臉圖示 (已移除外圈)。

### B. 家屬登入 (Caregiver Login)
*   **登入畫面 (Login Screen)**:
    *   位置: `lib/screens/login_screen.dart`
    *   功能: Email/密碼輸入框、密碼隱藏切換、社群登入按鈕 (UI 僅供展示)。

### C. 長輩配對 (Elder Pairing)
*   **配對畫面 (Elder Pairing Screen)**:
    *   位置: `lib/screens/elder_pairing_screen.dart`
    *   功能:
        *   顯示 4 位數配對碼 (目前 Hardcode 為 "0820")。
        *   顯示 QR Code。
        *   **語音播報**: 進入畫面時自動播放「歡迎加入，請將此畫面秀給家人看」。
        *   **隱藏捷徑**: 長按 QR Code 可模擬綁定成功，跳轉至首頁。

### D. 長輩首頁 (Elder Home Screen) - V2 (Polished)
*   **首頁 (Elder Home Screen)**:
    *   位置: `lib/screens/elder_home_screen.dart`
    *   風格: **Bento Grid** 佈局，強調**擬物化**與**大字體**。
    *   功能:
        *   **超大日期顯示**: 80px 國曆日期 + 32px 星期。
        *   **農曆日期**: 顯示農曆 (如：乙巳年 十二月 廿一)。
        *   **老友廣播站**: 復古收音機造型，具備呼吸動畫與 "ON AIR" 燈號 (Placeholder)。
        *   **親友通訊錄**: 木質相框造型 (Placeholder)。
        *   **AI 陪聊**: 機器人造型 (Placeholder)。
        *   **主動問候**: 進入時語音播報「爺爺早安...」。

## 4. 關鍵檔案結構 (Key File Structure)
```
lib/
├── main.dart                  # 程式入口，設定 Theme 與 Home
└── screens/
    ├── identification_screen.dart  # 身分選擇頁
    ├── login_screen.dart           # 登入頁
    ├── elder_pairing_screen.dart   # 長輩配對頁
    ├── elder_home_screen.dart      # 長輩首頁 (主畫面)
    ├── contacts_screen.dart        # 親友通訊錄 (Placeholder)
    ├── ai_chat_screen.dart         # AI 陪聊 (Placeholder)
    └── radio_station_screen.dart   # 老友廣播站 (Placeholder)
```

## 5. 待辦事項/未來規劃 (Next Steps)
*   串接後端 API 進行實際登入與配對碼驗證。
*   **實作功能內頁**:
    *   老友廣播站: 串接音訊串流或模擬電台 UI。
    *   親友通訊錄: 串接聯絡人資料與撥打功能。
    *   AI 陪聊: 串接 LLM API。
*   實作家屬管理介面 (Dashboard)。
