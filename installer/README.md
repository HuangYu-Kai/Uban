# Uban Windows 安裝程式

評審在 PC/NB 執行 `Uban_Setup_1.0.0.exe`，會把 `Uban.apk` 與 adb 工具安裝到電腦，
結束頁再透過 USB 偵錯把 App 裝進手機或模擬器（失敗時可手動傳 APK）。後端連正式站，不在電腦上安裝。

## 檔案
- `Uban_Setup.iss`：Inno Setup 腳本
- `install_app.ps1`：adb 安裝腳本（會裝進 `{app}`）
- `安裝說明.txt`：給評審的說明（安裝前顯示）
- `build_installer.ps1`：一鍵重建
- `ChineseTraditional.isl`、`uban.ico`：語系與圖示

## 重建
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File build_installer.ps1           # 先 flutter build apk --release 再打包
powershell -NoProfile -ExecutionPolicy Bypass -File build_installer.ps1 -SkipApk  # 沿用現有 release APK
```
需要 Inno Setup 6 與 Android SDK platform-tools。產物：`Output\Uban_Setup_1.0.0.exe`。
`payload\` 與 `Output\` 為建置產物，已列入 `.gitignore`。

## 為何不打包 Windows 桌面版
App 依賴 CallKit、FCM、LINE SDK、計步器等手機專用套件，無法在 Windows 桌面執行，因此以 Android APK 為交付物。
