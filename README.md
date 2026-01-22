# Flutter 練習專案

本專案用於從零開始學習 Flutter。

## 🛠️ Flutter 環境安裝指南 (Windows)

如果您需要在新電腦上重新建置開發環境，請依照以下步驟進行：

### 1. 安裝 Git
*   前往 [Git 官網](https://git-scm.com/download/win) 下載並安裝 Windows 版本。
*   安裝過程中一路按 Next 即可。

### 2. 安裝開發工具 (VS Code)
1.  安裝 [Visual Studio Code](https://code.visualstudio.com/)。
2.  開啟 VS Code，前往左側擴充功能 (Extensions) 分頁。
3.  搜尋並安裝 **"Flutter"** (這會自動安裝 Dart 套件)。

### 3. 安裝 Android 模擬器 (Android Studio)
為了執行 Android APP，需要安裝 Android Studio：
1.  下載並安裝 [Android Studio](https://developer.android.com/studio)。
2.  回到終端機，執行 `flutter doctor --android-licenses` 並全部同意授權 (按 `y`)。

### 4. 驗證安裝
開啟終端機 (PowerShell 或 CMD)(crtl + shift + `)，輸入以下指令檢查環境：

```bash
flutter doctor
```

如果看到全綠的勾勾 ✅，代表環境已就緒！

---

## 🚀 如何執行本專案

1.  確認 VS Code右下角已選擇裝置 (Windows 或 Android Emulator)。
2. ```bash
flutter clean
```
3. ```bash
flutter pub get
 ```
4. ```bash
 flutter run
 ```


---

### 相關資源
- [Flutter 官方文件](https://docs.flutter.dev/)
- [Dart 語言導覽](https://dart.dev/guides)
