# UniFlow

UniFlow 是一個專為大學生打造的輕量級視覺化自動化平台。透過直觀的節點拖拉介面，使用者能輕鬆串接 Line、Discord 與 Google Sheets 等常用服務，無需編寫複雜程式碼，即可將校園資訊獲取與日常任務處理實現完全自動化。

UniFlow 的設計靈感源自 n8n 等工業級 iPaaS 解決方案，並將其簡化以適應學術與校園場景。無論是當 Google 表單有人報名時自動發送 Discord 通知，或是每天定時抓取課表推送到 Line，UniFlow 都能輕鬆達成。本平台基於 React Flow 與 Node.js 構建，提供了一個友善的視覺化畫布，讓邏輯定義變得直觀可見，成功橋接了零散的校園資訊與學生的數位生活。

## 事前準備 (Prerequisites)

*   **Node.js**: 請確保您的電腦已安裝 Node.js (建議 v18 或更高版本)。
*   **npm**: 通常隨 Node.js 一同安裝。

## 安裝教學

1.  **複製專案 (Clone the repository)**
    ```bash
    git clone https://github.com/HuangYu-Kai/UniFlow/
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
    ```

2.  **安裝依賴 (Install dependencies)**
    
    請分別為前端與後端安裝必要的套件：

    ```bash
    # 安裝前端依賴
    cd frontend
    npm install

    # 安裝後端依賴
    cd ../backend
    npm install
    ```

3.  **環境設定 (Configuration)**

    若您需要更改前端運行的 Port (預設為 5173)，請在 `frontend` 目錄下建立 `.env` 檔案 (可參考 `.env.example`)：

    ```bash
    PORT=您的Port號
    ```

## 啟動方式

若要執行本應用程式，您需要在兩個不同的終端機 (Terminal) 分別啟動前端與後端伺服器。

### 前端 (Frontend)

進入 `frontend` 目錄並啟動開發伺服器：

```bash
cd frontend
npm start
```

前端頁面將在 `http://localhost:5173` 上運行。

### 後端 (Backend)

進入 `backend` 目錄並啟動伺服器：

```bash
cd backend
node index.js
```

後端伺服器將在 `http://localhost:3000` 上運行。

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
