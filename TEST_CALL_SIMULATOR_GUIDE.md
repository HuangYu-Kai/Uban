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

> ⚠️ **房間號 = 長輩的 `elder_id`（如 "1142"），不是 `user_id`！**

| 欄位 | 說明 | 範例 |
|------|------|------|
| `user_id` | 帳號主鍵（整數），長輩和家屬共用 | 17, 6 |
| `elder_id` | 長輩檔案 ID（字串） | "1142" |
| **Room ID** | 使用 `elder_id` | **"1142"** |

### 資料庫結構

```
user_account_data (所有帳號)
├── user_id: 6  (家屬 zakevin)
└── user_id: 17 (長輩帳號)

elder_profile (長輩檔案)
├── elder_id: "1142" (主鍵，作為房間號)
├── user_id: 17 (FK → user_account_data)
└── elder_name: "測試長輩"

family_elder_relationship (配對關係)
├── elder_id: "1142"
└── family_id: 6
```

### 查詢房間號

```sql
-- 查詢指定家屬配對的長輩
SELECT ep.elder_id AS room_id, ep.user_id, ep.elder_name
FROM elder_profile ep
JOIN family_elder_relationship fer ON ep.elder_id = fer.elder_id
WHERE fer.family_id = 6;  -- 替換為你的家屬 user_id
```

---

## 測試帳號資訊

| 項目 | 值 |
|------|-----|
| 家屬 user_id | 6 (zakevin) |
| 長輩 user_id | 17 |
| 長輩 elder_id | **1142** |
| 長輩名稱 | 測試長輩 |
| **房間號** | **1142** |

---

## 測試步驟

### 模式一：家屬 → 長輩

#### 步驟 1：啟動長輩端 App

1. 以長輩身份登入（輸入 elder_id: 1142）
2. 確保 App 連線到 SocketIO 伺服器
3. App 會自動加入房間（房間號 = elder_id）

#### 步驟 2：執行測試腳本

```bash
cd C:\Users\kevin\Desktop\115207\Uban
python test_call_simulator.py

# 選擇模式 [1/2]: 1
# 請輸入你模擬的家屬 user_id [預設 6]: 6
# 請輸入房間 ID (= 長輩的 elder_id): 1142
```

#### 步驟 3：發送通話請求

輸入 `1` 發送 call-request，長輩端會收到來電彈窗。

---

### 模式二：長輩 → 家屬

#### 步驟 1：啟動家屬端 App

1. 以家屬身份登入
2. 選擇長輩（會自動加入該長輩的房間）
3. 進入 AI 中樞頁面（FamilyDashboardView）

#### 步驟 2：執行測試腳本

```bash
cd C:\Users\kevin\Desktop\115207\Uban
python test_call_simulator.py

# 選擇模式 [1/2]: 2
# 請輸入長輩的 elder_id (房間號，如 1142) [預設 1142]: 1142
# 請輸入長輩的 user_id (帳號ID，如 17) [預設 17]: 17
```

#### 步驟 3：發送通話請求

輸入 `1` 發送 call-request，家屬端會收到來電彈窗。

---

## 操作選單

腳本啟動後會顯示操作選單：

```
──────────────────────────────────
  [1] 📞 發送 call-request（一般通話）
  [2] 🚨 發送 emergency-call（緊急通話）
  [3] 🔕 發送 cancel-call（取消呼叫）
  [4] 📡 查詢設備列表
  [5] 📴 掛斷 (end-call)
  [q] 離開
──────────────────────────────────
```

---

## 信令流程圖

### 家屬 → 長輩

```
家屬端 (模擬器)                    伺服器                     長輩端 (App)
     |                              |                            |
     |--- join (room="1142") ------>|                            |
     |                              |<--- join (room="1142") ----|
     |                              |                            |
     |------ call-request --------->|                            |
     |                              |------- call-request ------>|
     |                              |                            |
     |                              |<------ call-accept --------|
     |<------- call-accept ---------|                            |
     |                              |                            |
     |========= WebRTC 通話中 ====================================|
```

### 長輩 → 家屬

```
長輩端 (模擬器)                    伺服器                     家屬端 (App)
     |                              |                            |
     |--- join (room="1142") ------>|                            |
     |                              |<--- join (room="1142") ----|
     |                              |                            |
     |------ call-request --------->|                            |
     |      (role: elder)           |------- call-request ------>|
     |                              |                            |
     |                              |<------ call-accept --------|
     |<------- call-accept ---------|                            |
```

---

## 常見問題排解

### Q1: 連線失敗

```
❌ 無法連線: ...
```

**解決方案：**
1. 確認後端伺服器運行中
2. 檢查 `SERVER_URL` 是否正確
3. 確認 Tailscale VPN 連線正常

### Q2: 對方沒收到來電

**可能原因：**
1. 房間號錯誤（確認使用 `elder_id` 而非 `user_id`）
2. App 未連線到同一房間
3. App 的 SocketIO 連線斷開

**解決方案：**
1. 確認使用正確的房間號（長輩的 `elder_id`）
2. 在腳本中輸入 `4` 查詢設備列表
3. 如果列表為空，表示對方未連線

### Q3: 家屬端沒有來電彈窗

**可能原因：**
1. `selected_elder_room_id` 未儲存（需重新選擇長輩）
2. 家屬端未在 FamilyDashboardView 頁面

**解決方案：**
1. 家屬重新登入並選擇長輩
2. 確認停留在 AI 中樞頁面

---

## 修改伺服器地址

編輯 `test_call_simulator.py` 第 24 行：

```python
SERVER_URL = "https://你的伺服器地址"
```

---

## 相關檔案

| 檔案 | 說明 |
|------|------|
| `Uban/test_call_simulator.py` | 測試腳本 |
| `Uban/server/app.py` | Flask SocketIO 伺服器 |
| `uban-api/services/socket_app.py` | FastAPI SocketIO 伺服器 |
| `mobile_app/lib/services/signaling.dart` | Flutter 端 SocketIO 客戶端 |
| `mobile_app/lib/screens/family_dashboard_view.dart` | 家屬 AI 中樞（接收來電） |
| `mobile_app/lib/screens/elder_screen.dart` | 長輩通話畫面 |

---

## 快速測試指令

```bash
# 模式一：家屬打給長輩（互動式）
python test_call_simulator.py
# → 選 1 → 輸入家屬 ID → 輸入房間號

# 模式二：長輩打給家屬（互動式）  
python test_call_simulator.py
# → 選 2 → 輸入 elder_id → 輸入 user_id
```

---

*文件更新日期：2026-04-07*
