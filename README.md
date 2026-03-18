# Uban - AI 跨世代感知照護系統：完整安裝指南

本文件引導您從環境架設到正式執行 **Uban** 系統。請務必按照順序完成以下三個階段。

---

## 🛠️ 第一階段：開發環境準備 (Prerequisites)

在執行任何腳本前，請確保您的開發電腦已完成以下配置。

### 1. Python 3.12 (後端基礎)
>
> [!IMPORTANT]
> **必須安裝 Python 3.12**。由於 `eventlet` 套件在 3.13+ 版本有相容性問題，請勿使用更高版本。

1. 前往 [Python 官網](https://www.python.org/downloads/windows/) 下載並安裝。
2. 安裝時務必勾選 **"Add Python to PATH"**。
3. 提示：您可以手動在 `server/.env` 填入 `GEMINI_API_KEY`。

### 2. Flutter SDK (前端基礎)

1. 下載並安裝 [Flutter SDK](https://docs.flutter.dev/get-started/install)。
2. 將 `flutter\bin` 加入系統 **環境變數 (PATH)**。
3. 執行 `flutter doctor` 並完成所有 Android 憑證與 SDK 安裝。

### 3. ngrok (對外連線支援)

1. 下載 [ngrok](https://ngrok.com/) 並完成安裝。
2. 執行：`ngrok config add-authtoken <您的Token>`。這能讓您使用啟動腳本中的「自動隧道」功能。

---

## 🚀 第二階段：一鍵啟動 (Quick Start)

當環境準備就緒，請使用我們提供的智慧型腳本，它會自動處理虛擬環境、套件安裝與 IP 對接：

```powershell
# 在專案根目錄執行 (Windows PowerShell)
.\run.ps1
```

```bash
# 在專案根目錄執行 (macOS)
chmod +x run.sh
./run.sh
```

### 啟動選單說明

- **[1] 區域網路開發 (Auto IP)**：自動偵測 `192.168.*` 位址。適合家屬與長輩在同一個 Wi-Fi 下使用。
- **[2] 手動輸入 IP (Manual IP)**：直接輸入公網 IP。適合已手動設定 Port Forwarding 的用戶。
- **[3] 使用 ngrok 隧道 (Auto ngrok)**：**推薦選項**。自動啟動隧道並抓取隨機網址，適合遠端協作。

---

## 🌐 第三階段：外部存取補充 (進階設定)

如果您不使用 ngrok 而想透過實體公網連線：

### 1. 通訊埠轉發 (Port Forwarding)

請在路由器將 **Port 5001 (TCP)** 指向您電腦的內部 IP。
> 目前 API 與 Socket 服務已統一整合在 **5001** 埠口。

### 2. 防火牆規則

確保 Windows 防火牆已開啟 **TCP 5001** 的「輸入規則 (Inbound Rule)」。

---

## � 第四階段：核心功能教學 (Core Tutorial)

1. **角色選擇**：App 啟動後可選擇長輩端 (Elder) 或家屬端 (Family)。
2. **配對流程**：長輩端顯示 PIN 碼 -> 家屬端輸入 PIN 碼認領 -> 系統自動完成註冊與綁定。
3. **AI 互動**：Gemini Agent 會根據長輩的興趣與病史提供個人化對話，並產出健康指標。
4. **即時監控**：支援 WebRTC 低延遲視訊與單向遠端查看功能。

---

## ⚠️ 常見問題 (Troubleshooting)

- **連線失敗**：請確認手機與伺服器 IP 匹配，或改用 `.\run.ps1` 選項 [3]。
- **權限報錯**：若無法執行腳本，請執行：`Set-ExecutionPolicy RemoteSigned`。
- **WinError 10048**：這代表 Port 被佔用，`run.ps1` 現在會自動清理這些殘留程序。
