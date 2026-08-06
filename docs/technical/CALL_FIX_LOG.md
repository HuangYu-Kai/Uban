# 視訊通話邏輯修復紀錄

> ⚠️ **這是 2026-07-05 的歷史快照，不是現行說明。**
> 之後又進行了 10 輪修復（最新為 2026-08-02 第十四輪），本檔多處已與程式碼不符。
>
> 🚨 **要修改通話／來電通知／監控程式碼，請先讀 `../../CLAUDE_call-monitor.md`**
> （唯一權威；完整年表見其 §8，護欄見 §7）。本檔僅供追溯當時的決策脈絡。

> 修復日期：2026-07-05
> 修復範圍：家屬端／長輩端 APP 外（背景／鎖屏／被殺死）接聽與拒接流程
> 相關檔案：Flutter 前端 3 個檔案 + FastAPI 後端 1 個檔案

---

## 修復前的五個問題

| # | 問題描述 | 根因 |
|---|----------|------|
| 1 | 家屬端在 APP 外接聽一般通話後，WebRTC 連線一秒即斷 | 長輩端被冷啟動 → SocketId 變更 → call-accept 送不到 → WebRTC 逾時 |
| 2 | 長輩端在 APP 外收到 call-request 後，不等確認就進入視訊房間 | BG handler 預先儲存 pendingAcceptedCall + action.MAIN 冷啟動 |
| 3 | 長輩端與家屬端結束通話後，家屬端直接黑屏 | VideoCallScreen 用 Navigator.pop() 但冷啟動進入時無上一頁 |
| 4 | 家屬端拒聽後，長輩端繼續在視訊房間等待接聽 | 後端 call-busy 未發 cancel-call FCM 關閉長輩 CallKit |
| 5 | 任一端拒接後，另一端 APP 外 CallKit 通知未消失 | 同 #4，缺少 cancel-call FCM 推送 |

---

## 修復內容

### 1. Uban/mobile_app/lib/main.dart — 問題 2, 4, 5

#### A. 長輩端背景 FCM handler（問題 2）

舊行為：收到 call-request 即預存 pendingAcceptedCall + action.MAIN 冷啟動 App。
新行為：只顯示 CallKit 通知，pendingAcceptedCall 僅在使用者點擊接聽後才設定。

#### B. 背景 FCM handler 新增 cancel-call 處理（問題 4/5）

收到 type=cancel-call 時立即 FlutterCallkitIncoming.endAllCalls() 關閉 CallKit。

#### C. 前景 FCM handler 新增 cancel-call 處理（問題 5）

收到 type=cancel-call 時關閉 APP 內來電彈窗 + 系統 CallKit 通知。

---

### 2. Uban/mobile_app/lib/screens/video_call_screen.dart — 問題 3

- 新增 import globals.dart 和 family_main_screen.dart
- onCallEnded / onCallBusy / onConnectionLost 改用 safeNavigateBack(context, _buildFallbackHome())
- 新增 _safeHangUp() 方法（呼叫 hangUp + 安全導航）
- 掛斷按鈕改用 _safeHangUp
- _buildFallbackHome() 返回 FamilyMainScreen 作為冷啟動 fallback

---

### 3. Uban/mobile_app/lib/screens/elder_home_screen.dart — 問題 4

- _restoreSignalingCallbacks 新增 onCancelCall 回調：家屬取消來電時關閉長輩的來電彈窗
- dispose() 清理 onCancelCall = null

---

### 4. uban-api/services/socket_app.py — 問題 4, 5

on_call_busy 新增：
- 拒接前先從 active_ringing_calls 查詢 target_room
- emit call-busy 後加發 cancel-call FCM 給 room_fcm_tokens 中的所有設備
- FCM 為 data-only + high priority（與 call-request 規則一致）

---

## 通話流程對照

### 情境 A：家屬打給長輩（長輩在 APP 外）

| 步驟 | 修復前 | 修復後 |
|------|--------|--------|
| 1. 發起 | sendCallRequest → Socket + FCM | 同左 |
| 2. 長輩收 FCM | 預存 pendingAcceptedCall + 冷啟動 | 只顯示 CallKit |
| 3. 長輩 App | SplashScreen → 自動進 ElderScreen | 保持原畫面 |
| 4. 接聽 | CallKit → 已在 ElderScreen | CallKit → ElderHomeScreen → ElderScreen |
| 5. WebRTC | sendCallAccept(舊socketId) → 斷線 | sendCallAccept(有效socketId) → 正常 |

### 情境 B：任一端拒接

| 步驟 | 修復前 | 修復後 |
|------|--------|--------|
| 1. 拒接 | call-busy → Socket | 同左 |
| 2. 後端 | emit call-busy only | emit call-busy + FCM cancel-call |
| 3. 對方(APP內) | 退出通話畫面 | 退出 ✅ |
| 4. 對方(APP外) | CallKit 繼續響鈴 ❌ | CallKit 關閉 ✅ |

---

## 注意事項

- 長輩端 pendingAcceptedCall 只在使用者點擊 CallKit「接聽」後才設定
- 長輩端不再用 action.MAIN 冷啟動，避免 SplashScreen 丟失 listener
- VideoCallScreen 退出統一走 safeNavigateBack，確保冷啟動有 fallback
- 後端 on_call_busy 必須先從 active_ringing_calls 取 room，再 _clear_active_call
- cancel-call FCM 是 data-only + high priority，不可加 notification 區塊
