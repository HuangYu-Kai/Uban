#flutter

本專案用於從零開始學習 Flutter。

## 🛠️ Flutter 環境安裝指南 (Windows)

如果您需要在新電腦上重新建置開發環境，請依照以下步驟進行：

### 1. 安裝 Git
*   前往 [Git 官網](https://git-scm.com/download/win) 下載並安裝 Windows 版本。
*   安裝過程中一路按 Next 即可。

### 2. 下載並設定 Flutter SDK
1.  前往 [Flutter 官網](https://docs.flutter.dev/get-started/install/windows/mobile) 下載最新的 Stable SDK zip 檔。
2.  將檔案解壓縮到易於存取的路徑，例如 `C:\flutter` (⚠️ 請避免放在 `Program Files` 或含有中文/空格的路徑)。
3.  **設定環境變數 (Path)**：
    *   在 Windows 搜尋「環境變數」 -> 「編輯系統環境變數」 -> 「環境變數」。
    *   在 **使用者變數** 中找到 `Path`，點擊「編輯」->「新增」。
    *   加入 `C:\flutter\bin` (請依據您的實際路徑調整)。
    *   按下確定儲存。

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

#技術需求分析
手機轉攝像頭、通話:WebRTC、flask + SocketIO or FastAPI + Starlette WebSockets
存mp3檔案的資料庫:MiniO(?)
與mp3檔案對接:flask
SQL資料庫:可以考慮換用Django或MySQL，PostgreSQL有點不好用，Django下學期會教
