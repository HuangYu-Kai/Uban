# Uban 視訊通話模擬器測試指南

## 概述

`test_call_simulator.py` 是一個 SocketIO 測試腳本，支援雙向通話測試：
1. **家屬 → 長輩**：模擬家屬端撥打給長輩端
2. **長輩 → 家屬**：模擬長輩端撥打給家屬端

---

## 前置準備

### 1. 安裝依賴

```bash
pip install python-socketio[asyncio_client] websockets
```

### 2. 確認後端伺服器運行中

- Flask 後端 (`Uban/server/app.py`) 或
- FastAPI 後端 (`uban-api/main.py`)

預設伺服器地址：`https://localhost-0.tail5abf5e.ts.net`

---

## 重要概念：房間號 (Room ID)

> ⚠️ **房間號 = 長輩的 `user_id`（整數，如 17）**

| 欄位 | 說明 | 範例 |
|------|------|------|
| `user_id` | 帳號主鍵（整數），**作為房間號** | 17, 16 |
| `elder_id` | 長輩檔案 ID（字串，4碼） | "1142", "4288" |
| **Room ID** | 使用 **`user_id`** | **"17"** |

### 測試帳號

| 長輩名稱 | user_id (房間號) | elder_id |
|----------|------------------|----------|
| 測試長輩 | **17** | 1142 |
| gawafat | **16** | 4288 |

---

## 測試步驟

### 模式一：家屬 → 長輩

1. **啟動長輩端 App**（以長輩身份登入）
2. **執行測試腳本**：
   ```bash
   python test_call_simulator.py
   # 選擇 [1]
   # 輸入家屬 user_id: 6
   # 輸入房間 ID: 17（長輩的 user_id）
   ```
3. **輸入 `1` 發送 call-request**，長輩端會收到來電彈窗

### 模式二：長輩 → 家屬 ✅ 已驗證

1. **啟動家屬端 App**（以家屬身份登入，如 zakevin）
2. **執行測試腳本**：
   ```bash
   python test_call_simulator.py
   # 選擇 [2]
   # 輸入長輩 user_id: 17（這同時是房間號）
   ```
3. **輸入 `1` 發送 call-request**，家屬端會收到來電彈窗

---

## 操作選單

```
[1] 📞 發送 call-request（一般通話）
[2] 🚨 發送 emergency-call（緊急通話）
[3] 🔕 發送 cancel-call（取消呼叫）
[4] 📡 查詢設備列表
[5] 📴 掛斷 (end-call)
[q] 離開
```

---

## 常見問題排解

### Q1: 對方沒收到來電

**最常見原因：房間號不一致**

確認步驟：
1. 查看 Flutter debug console，找 `連線到房間: XX` 的日誌
2. 模擬器使用相同的房間號

### Q2: 連線失敗

1. 確認後端伺服器運行中
2. 確認 Tailscale VPN 連線正常

---

## 信令流程圖

```
發話端 (模擬器)                    伺服器                     接聽端 (App)
     |                              |                            |
     |--- join (room="17") -------->|                            |
     |                              |<--- join (room="17") ------|
     |                              |                            |
     |------ call-request --------->|                            |
     |                              |------- call-request ------>|
     |                              |                            |
     |                              |<------ call-accept --------|
     |<------- call-accept ---------|                            |
```

---

## 相關檔案

| 檔案 | 說明 |
|------|------|
| `test_call_simulator.py` | 測試腳本 |
| `server/app.py` | Flask SocketIO 伺服器 |
| `mobile_app/lib/screens/family_main_screen.dart` | 家屬主頁（連線 & 接收來電） |
| `mobile_app/lib/screens/elder_home_screen.dart` | 長輩首頁（連線 & 接收來電） |
| `mobile_app/lib/services/signaling.dart` | SocketIO 客戶端 |

---

*文件更新日期：2026-04-07*
