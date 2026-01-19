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
    *   進入方式: 在身分選擇畫面點擊「我是長輩」後進入。

## 4. 關鍵檔案結構 (Key File Structure)
```
lib/
├── main.dart                  # 程式入口，設定 Theme 與 Home (IdentificationScreen)
└── screens/
    ├── identification_screen.dart  # 身分選擇頁
    ├── login_screen.dart           # 登入頁
    └── elder_pairing_screen.dart   # 長輩配對頁
```

## 5. 待辦事項/未來規劃 (Next Steps)
*   串接後端 API 進行實際登入與配對碼驗證。
*   實作長輩聊天介面 (Chat Interface)。
*   實作家屬管理介面 (Dashboard)。
