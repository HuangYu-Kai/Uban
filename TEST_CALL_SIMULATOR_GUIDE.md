# Uban 視訊通話模擬器測試指南

## 概述

`test_call_simulator.py` 是一個 SocketIO 測試腳本，用於模擬家屬端撥打視訊電話給長輩端，測試通話信令流程。

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

> ⚠️ **房間號 = 長輩的 `user_id`，不是 `elder_id`！**

| 欄位 | 說明 | 範例 |
|------|------|------|
| `user_id` | 帳號主鍵（整數） | 17 |
| `elder_id` | 長輩檔案 ID（4 字元字串） | "1142" |
| **Room ID** | 使用 `user_id` | **17** |

### 查詢正確的房間號

```sql
-- 查詢指定家屬配對的長輩
SELECT ep.user_id AS room_id, ep.elder_id, ep.elder_name
FROM elder_profile ep
JOIN family_elder_relationship fer ON ep.elder_id = fer.elder_id
WHERE fer.family_id = 6;  -- 替換為你的家屬 user_id
```

---

## 測試帳號資訊

| 項目 | 值 |
|------|-----|
| 家屬 user_id | 6 (zakevin) |
| 長輩 user_id | **17** |
| 長輩 elder_id | 1142 |
| 長輩名稱 | 測試長輩 |
| **房間號** | **17** |

---

## 測試步驟

### 步驟 1：啟動長輩端 App

在 Flutter App 或 Android 模擬器上：
1. 以長輩身份登入
2. 確保 App 連線到 SocketIO 伺服器
3. App 會自動加入房間（房間號 = 長輩的 user_id）

### 步驟 2：執行測試腳本

```bash
cd C:\Users\kevin\Desktop\115207\Uban

# 方法 1：直接指定房間號
python test_call_simulator.py 17

# 方法 2：互動式輸入
python test_call_simulator.py
# 然後輸入房間號：17
```

### 步驟 3：發送通話請求

腳本啟動後會顯示操作選單：

```
──────────────────────────────────
  [1] 📞 發送 call-request（一般通話）
  [2] 🚨 發送 emergency-call（緊急通話）
  [3] 🔕 發送 cancel-call（取消呼叫）
  [4] 📡 查詢長輩設備列表
  [5] 📴 掛斷 (end-call)
  [q] 離開
──────────────────────────────────
```

輸入 `1` 發送一般通話請求。

### 步驟 4：觀察結果

**成功情況：**
- 長輩端 App 收到來電彈窗
- 腳本顯示 `✅ 已發送！等待對方回應...`
- 如果長輩接聽，腳本會收到 `🎉🎉🎉 對方已接聽！`

**失敗情況：**
- 連線失敗：檢查伺服器是否運行
- 沒有收到回應：檢查房間號是否正確

---

## 信令流程圖

```
家屬端 (模擬器)                    伺服器                     長輩端 (App)
     |                              |                            |
     |-------- join (room=17) ----->|                            |
     |                              |<----- join (room=17) ------|
     |                              |                            |
     |------ call-request --------->|                            |
     |                              |------- call-request ------>|
     |                              |                            |
     |                              |<------ call-accept --------|
     |<------- call-accept ---------|                            |
     |                              |                            |
     |========= WebRTC 通話中 ====================================|
     |                              |                            |
     |-------- end-call ----------->|                            |
     |                              |--------- end-call -------->|
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

### Q2: 長輩端沒收到來電

**可能原因：**
1. 房間號錯誤（使用了 `elder_id` 而非 `user_id`）
2. 長輩端 App 未連線到同一房間
3. 長輩端 App 的 SocketIO 連線斷開

**解決方案：**
1. 確認使用正確的房間號（長輩的 `user_id`）
2. 在腳本中輸入 `4` 查詢長輩設備列表
3. 如果列表為空，表示長輩端未連線

### Q3: 房間號應該是多少？

執行以下 SQL 查詢：

```sql
SELECT ep.user_id AS room_id, ep.elder_name
FROM elder_profile ep
JOIN family_elder_relationship fer ON ep.elder_id = fer.elder_id
WHERE fer.family_id = <你的家屬ID>;
```

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

---

## 快速測試指令

```bash
# 測試房間 17（測試長輩）
python test_call_simulator.py 17

# 測試房間 16（gawafat）
python test_call_simulator.py 16
```

---

*文件更新日期：2026-04-06*
