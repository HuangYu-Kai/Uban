# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 1. Common Commands

### Flutter Frontend (`Uban/mobile_app/`)

```bash
cd Uban/mobile_app

# Run the app (SERVER_IP injected via --dart-define; never hardcode)
flutter run --dart-define=SERVER_IP=localhost-0.tail5abf5e.ts.net \
  --dart-define=TURN_SERVER=152.69.196.5:3478 \
  --dart-define=TURN_USER=uban \
  --dart-define=TURN_PASS=115207

# Static analysis
flutter analyze

# Run all tests
flutter test

# Run a specific test file
flutter test test/services/api_service_test.dart
flutter test test/models/emotion_data_test.dart

# Install dependencies
flutter pub get
```

### FastAPI Backend (`uban-api/uban-api/`)

```bash
cd uban-api/uban-api

# Install dependencies (Python 3.12 only, NOT 3.13+)
pip install -r requirements.txt

# Start server
uvicorn main:app --host 0.0.0.0 --port 8000

# Run all tests
pytest tests/

# Run a specific test file
pytest tests/test_auth.py -v

# Syntax check a single file
python -m py_compile routers/pairing.py
```

Prerequisites for running the backend:
- `serviceAccountKey.json` (Firebase) sits at the backend root.
- `.env` defines `PINECONE_API_KEY`, `PINECONE_INDEX_NAME=uban`, and `PINECONE_HOST`.

### One-Click Launchers

| Platform | Command | Notes |
|----------|---------|-------|
| Windows | `cd Uban && .\run.ps1` | Interactive menu. Use `-Start` to skip the menu. |
| macOS / Linux | `cd Uban && ./run.sh` | Interactive menu. Use `-s` to skip the menu. |

Both launchers auto-detect emulators / physical devices and inject `SERVER_IP`.

---

## 2. High-Level Architecture

### 2.1 Dual-Track Design (Critical)

Signaling and media travel on **physically separate hosts** and must never be merged:

| Track | Purpose | Host | Protocol |
|-------|---------|------|----------|
| 1 — Signaling | SDP/ICE text exchange | Tailscale Funnel → local Fedora FastAPI | TCP / WSS |
| 2 — Media | Audio/video relay | Oracle Cloud Coturn (Japan) | UDP |

**Rationale**: Camera access requires HTTPS. Tailscale Funnel provides free HTTPS but is **TCP-only**. Real-time video requires UDP, which needs a dedicated public IP (Oracle Cloud).

Key service addresses:
- Signaling: `https://localhost-0.tail5abf5e.ts.net`
- TURN/STUN: `turn:152.69.196.5:3478`
- Ollama AI: `https://boyo-desktop.tail531c8a.ts.net`
- MySQL: `100.73.39.14:3306` (Tailscale)

### 2.2 Signaling Singleton & WebRTC Flow

`lib/services/signaling.dart` is a **Singleton**. The same instance is shared across the entire app lifecycle. Never instantiate it with `Signaling()`.

The WebRTC call flow spans multiple files and is highly timing-sensitive:

```
main.dart (FCM/CallKit global listeners)
  ↓
globals.dart (pendingAcceptedCall state bridge)
  ↓
signaling.dart (Socket.IO + WebRTC logic)
  ↓
screens/video_call_screen.dart OR screens/elder_screen.dart (UI)
```

**Callee flow** (e.g., Elder receiving a call from Family):
1. FCM background push → CallKit popup
2. Tap Accept → sets `pendingAcceptedCall` in `globals.dart`
3. `MainActivity` re-opens, reads `pendingAcceptedCall`
4. Navigates to `VideoCallScreen` / `ElderScreen`
5. `socket` emits `'call-accept'` (must wait until `socket.connected`; see cold-start note below)
6. Callee awaits `'offer'` from caller

**Caller flow**:
1. Emits `'call-request'`
2. Receives `'call-accept'` (containing callee's `socketId`)
3. `createOffer(targetId: callee_sid)` ← **ONLY entry point for offer creation**
4. Callee receives `'offer'` → `setRemoteDescription` → `createAnswer`
5. Both exchange `'ice-candidate'`
6. P2P established

**Cold-start race condition**: When the app is killed by the system and awakened by FCM, `sendCallAccept` may fire before the socket is connected. The fix polls `socket.connected` for up to 5s before emitting. See `video_call_screen.dart` `_initCall()`.

**ICE candidate queuing**: Candidates arriving before `setRemoteDescription` must be queued. This is handled in `signaling.dart`.

### 2.3 FCM → CallKit → Cold-Start Wake Chain

`main.dart` contains the FCM background handler and CallKit initialization.

```
FCM push (call-request or emergency-call)
  → _firebaseMessagingBackgroundHandler
    → call-request (family): shows CallKit, NO auto-wake
    → call-request (elder): saves pendingRingCall to SharedPreferences,
        then shows CallKit (NO auto-wake — user must explicitly accept)
    → emergency-call: saves pendingAcceptedCall + triggers AndroidIntent to wake
  → CallKit 'accept' event
    → sets pendingAcceptedCall.value
    → wakes MainActivity (if not already active)
    → _navigateToVideoCall triggers navigation
```

CallKit is configured with `isShowFullLockedScreen: true` for lock-screen full-screen display.

#### pendingRingCall 冷啟動補救機制（2026-07 新增）

背景長輩端收到 `call-request` 時，app 可能已被系統殺掉。使用者在 CallKit 點接聽後冷啟動 app，`_setupCallKitListener` 可能尚未註冊而錯過 `actionCallAccept` 事件。

**三層防線**：
1. **背景 handler** — 將 `{roomId, senderId, callId, timestamp}` 存入 SharedPreferences key `pendingRingCall`
2. **`_checkInitialCall()`（第一道防線）** — `initState()` 中檢查 `activeCalls()` 是否有已接聽（`isAnswered=true`）且未結束的通話，匹配 `pendingRingCallData` → 補設定 `pendingAcceptedCall.value`
3. **`SplashScreen._navigateToNext()`（第二道防線）** — 4 秒動畫結束後（CallKit 狀態已穩定），再次檢查 `pendingRingCall` + `activeCalls()` → 補設定 `pendingAcceptedCall.value`

逾時保護：`pendingRingCall` 超過 55 秒自動清除。

#### FCM 前景雙通道備援（2026-07 新增）

來電同時透過 **Socket.IO（主要）** 和 **FCM 前景訊息（備援）** 傳遞。若 Socket 斷線，FCM 仍能送達來電。

去重機制：`Signaling.lastProcessedCallId` + `_fcmCallIdCache` 3 秒時間窗口，防止同一通來電由兩通道重複觸發 dialog。

長輩端 FCM 前景備援：不再忽略，改用去重檢查取代 early return。若 Socket 已在 3 秒內處理過相同 `callId` 則跳過，否則顯示 styled dialog（樣式與 `ElderHomeScreen` 的綠色 dialog 一致）。

### 2.4 Role Differences (Elder vs Family)

**Hard rule**: Elder calls must enter through `ElderScreen`, not `VideoCallScreen`.

| Aspect | Elder (`role: 'elder'`) | Family (`role: 'family'`) |
|--------|--------|--------|
| Entry | `ElderScreen` | `VideoCallScreen` |
| Incoming UI | CallKit full-screen | Dialog in `FamilyMainScreen` |
| Offer logic | Receives `call-accept` → creates offer | Receives `call-accept` → creates offer |
| Video default | Camera on when entering call room (toggleable) | Camera on when entering call room (toggleable) |
| Emergency mode | CCTV / auto-answer, camera forced on | Standard call |

### 2.5 AI Dual-Engine & Pinecone Long-Term Memory

The backend runs two AI engines:
- **Primary**: Ollama (`gemma4:e4b-it-q4_K_M`), local via Tailscale, supports Tool Calling.
- **Fallback**: Google Gemini (`gemini_service.py`), activated when Ollama is unreachable.

**Pinecone Long-Term Memory**:
- Every chat is embedded (nomic-embed-text, 768-dim) and upserted to Pinecone index `uban` in a **background thread**.
- `daily_pond_leaf_job` (scheduled at 08:00 and 15:00 in `main.py`) queries Pinecone for semantic memory recall, generates a conversation topic, and pushes it via Socket.IO `'new-pond-leaf'` event to the Flutter `ZenPondScreen`.
- The AI agent personality is defined in `uban-api/uban-api/server/agent/SOUL.md`, `IDENTITY.md`, etc.

### 2.6 Backend: Raw SQL + Scheduler

No ORM is used. All DB access is via `db_cursor()` context manager with parameterized queries:

```python
from database import db_cursor
with db_cursor() as cursor:
    cursor.execute("SELECT * FROM user_account_data WHERE user_id = %s", (user_id,))
```

Scheduled jobs (defined in `main.py`):
| Job | Frequency | Purpose |
|-----|-----------|---------|
| `check_and_distribute` | Every minute | Pet appearance distribution |
| `heartbeat_job` | Every minute | Proactive care push |
| `daily_news_crawl_job` | Daily 06:00 | CNA news crawl |
| `pre_generate_news_audio_background` | Daily 03:00 | Pre-generate news TTS |
| `daily_pond_leaf_job` | Daily 08:00, 15:00 | Memory topic generation |

---

## 3. Hard Rules

1. **Do not hardcode IPs / server URLs** — always use `--dart-define=SERVER_IP=`
2. **Signaling is a Singleton** — never create a second `Signaling()` instance
3. **Elder calls use `ElderScreen`** — do not route elders to `VideoCallScreen`
4. **No ORM in backend** — use `db_cursor()` with `%s` placeholders
5. **Never merge signaling and media tracks** — they are on separate hosts by design
6. **AI personality must be stable and serious** — no roleplay, pet speak, or impersonation
7. **Git commit messages must be in Traditional Chinese (繁體中文)**
8. **Use `forceDisconnect()` instead of `disconnect()` for Signaling singleton** — To maintain FCM reception capability
9. **Always check socket connection before sending WebRTC signals** — With timeout/retry logic (max 5s) to prevent cold-start disconnections
10. **Use `_isInCall` flag to prevent concurrent calls** — Check in `createOffer()` and `_acceptCall()` methods
11. **Convert SharedPreferences data properly** — When assigning to `pendingAcceptedCall.value`, convert `Map<String, dynamic>` to `Map<String, String?>`
12. **Navigate back to home screen correctly** — Use `pushAndRemoveUntil` instead of `pop()` to return to proper home screen after calls
13. **Do not open user media before creating offer** — must first obtain `localStream` before calling `createOffer`
14. **ICE candidates must be queued** — candidates arriving before `setRemoteDescription` must be queued and flushed after
15. **Do not broadcast SDP (Offer/Answer)** — must send to specific `targetId` using `to=target_sid`
16. **Do not hardcode MySQL host** — in production, use `uban-mysql`; avoid `localhost` or `127.0.0.1`
17. **Do not change the server port** — keep port 8000 for the FastAPI backend
18. **Use Python 3.12** — do not use Python 3.13 or higher

---

## 4. Subproject Reference

For per-subproject details, read:
- **Flutter frontend**: `Uban/mobile_app/` 下的各檔案（無獨立 CLAUDE.md）
- **FastAPI backend**: `uban-api/uban-api/CLAUDE.md`

---

## 5. Appendix: Fix Records

### 2026-07-14 — 來電通知六項修復（分支 `call-fix`）

| Issue | 檔案 | 根因 | 修復 |
|-------|------|------|------|
| 1 — 家屬端來電 dialog 樣式不一致 | `lib/main.dart` | FCM 前景備援用樸素 `AlertDialog`，Socket 路徑用 styled dialog | 重寫 `_showIncomingCallDialog`：綠色/紅色背景、Icon、`ElevatedButton.icon`，與 `FamilyMainScreen` 一致 |
| 2 — 背景家屬端接聽後攝像頭無法開啟 | `lib/screens/video_call_screen.dart` | `_isCameraOff = true` 預設關閉 | `widget.isIncomingCall` 時設 `_isCameraOff = false`；`openUserMedia` 失敗延遲 500ms 重試一次 |
| 3 — 背景長輩端接聽後只進主畫面 | `lib/main.dart` + `lib/screens/splash_screen.dart` | 冷啟動時 `_setupCallKitListener` 錯過 `actionCallAccept` 事件 | 三層防線：背景 handler 儲存 `pendingRingCall` → `_checkInitialCall()` 檢查 `activeCalls()` → `SplashScreen` B4 二次防線 |
| 4 — 前景家屬端接聽後無法進入視訊房間 | `lib/main.dart` | `_navigateToVideoCall` 的 `popUntil(route.isFirst)` 清空導航堆疊 | 只關閉 `_activeCallDialogContext`，改為直接 `Navigator.push(VideoCallScreen)` |
| 5 — 前景長輩端無法接收來電 | `lib/main.dart` | FCM 前景備援對長輩端完全忽略（early return） | 改用去重檢查（`lastProcessedCallId` + 3s 窗口）取代 early return；長輩端也顯示 styled dialog → 接聽導向 `ElderScreen` |
| 6 — 發起方持續等待 | `lib/screens/video_call_screen.dart` | Issue 3/4/5 連鎖效應 + 30s 逾時過長 | 逾時從 30s 縮短至 20s |

### 2026-07-15 — 來電通知第二輪殘留 Bug 修復（分支 `call-fix`）

第一輪（07-14）修復後，Explore agent 診斷出 6 個殘留 bugs，其中 3 個為致命級別（直接導致無法進入視訊房間）。

| Issue | 檔案 | 根因 | 修復 |
|-------|------|------|------|
| 1 — 進入視訊房間鏡頭應預設開啟 | `lib/screens/video_call_screen.dart` | `_isCameraOff = false` 僅限 `isIncomingCall`，撥打方仍預設關閉 | 移除條件，無條件設 `_isCameraOff = false` |
| 2 — APP 背景時長輩端接聽後無法進入視訊房間 | `lib/main.dart` | `_navigateToVideoCall()` 的 dedup guard（`callId == signaling.lastProcessedCallId`）誤殺 CallKit accept | 移除 elder 端 dedup guard，讓 CallKit accept 能正常設定 `pendingAcceptedCall.value` |
| 3 — APP 前景時家屬端接聽後無法進入視訊房間 | `lib/screens/video_call_screen.dart` | incomingCall 路徑直接 `sendCallAccept`，無 socket 輪詢；冷啟動時 socket 未連線 → 發送失敗 | incomingCall 路徑新增 socket 輪詢（50×100ms = max 5s），與 autoStart 路徑一致 |
| 4 — APP 前景時長輩端無法接收來電通知 | `lib/screens/elder_home_screen.dart` | dialog 接聽按鈕建立 `ElderScreen` 時缺 `initialCallData`（senderId/callId/callerName） | 補傳 `initialCallData`；`_restoreSignalingCallbacks` 傳遞 `senderName` 以顯示來電者名稱 |
| 5 — 拒絕來電後畫面異常（黑屏） | `lib/main.dart` | `_setupCallKitListener` 中 decline 路徑仍用 `popUntil(route.isFirst)` 清空堆疊 | 改用 `Navigator.of(currentContext).pop()` + `canPop()` guard，安全返回前頁 |
| 6 — 拒絕/結束通話訊息立即消失 | `lib/screens/video_call_screen.dart` | `onCallBusy`/`onCallEnded` 用 `SnackBar` → `_goHomeAfterCall()` 立即導航 → SnackBar 隨 route 消失 | 改用 `showDialog`（不依附特定 route），顯示 2 秒後自動關閉 → `Future.microtask` 導航回首頁 |

### 2026-07-10 — Socket 通話信令回歸直接轉發（提交 `dbdaa55` / `9c5e430`）

**後端** `socket_app.py`：移除 `call_registry`，回歸確定性直接轉發。`on_join` 新增通話護欄。
**前端** `main.dart`：`_checkInitialCall` 移除未接聽自動導航。`video_call_screen.dart`：`_goHomeAfterCall()` 杜絕冷啟動黑屏。

### 2026-06-07 — 通話/監控十項修復

`singleTask` launchMode、Splash 跳過動畫、pushAndRemoveUntil 黑屏修復、`_isInCall` 防並發、socket 連線輪詢、MonitorViewScreen 建立、降級 UI 移除、全域 watchdog 錯誤復原。

### 2026-06-05/06 — 早期通話信令修復

雙重 room ID prefix、`join-failed` 誤斷線、緊急模式 camera 強制開啟、unbind id/import 型別修正、CallKit 不自動喚醒、cold-start `call-accept` 輪詢等。

### 2026-07-17 — 第三輪：延遲來電、過期來電、前景接聽與同步終止修復

#### A. 已完成更新（後端）

**檔案：** `uban-api/uban-api/services/socket_app.py`

1. `call-request` 新增有效期欄位 — 發送 Socket/FCM 時附帶 `issuedAt`、`expiresAt`（初始 15s）。
2. `cancel-call` / `end-call` 強化「雙端同步終止」— 依 `call_registry` 廣播。
3. `cancel-call` 使用 `call_registry` 補齊目標集合。

#### B. 已完成更新（Flutter）

**檔案：** `Uban/mobile_app/lib/services/signaling.dart` — 新增 `_invalidCallIds`、`_isExpiredCallPayload`、`sendCallRequest` 帶 issuedAt/expiresAt/senderName。
**檔案：** `Uban/mobile_app/lib/main.dart` — FCM 過期檢查、CallKit 過期驗證。
**檔案：** `Uban/mobile_app/lib/screens/family_main_screen.dart` — 2.5s 輪詢 + debounce、pendingAcceptedCall 過期檢查。
**檔案：** `Uban/mobile_app/lib/screens/elder_home_screen.dart` — pendingAcceptedCall 過期檢查。
**檔案：** `Uban/mobile_app/lib/screens/elder_screen.dart` / `video_call_screen.dart` — 鏡頭預設開啟、忙線/拒接改對話框。

#### C. 2026-07-17 建置故障與處理（Windows）

錯誤：`flutter_inappwebview_android:compileDebugJavaWithJavac` 無法刪除 `build/.../javac/.../classes`（檔案鎖定）  
處理流程（已驗證可恢復）：

1. 終止鎖定行程（`java.exe` / `gradle.exe` / `flutter` / `dart`）。  
2. 刪除：
   - `Uban/mobile_app/build/flutter_inappwebview_android/intermediates/javac/.../classes`
   - `Uban/mobile_app/build`
3. 重跑：
   - `flutter clean`
   - `flutter pub get`
   - `flutter build apk --debug`

結果：`BUILD SUCCESSFUL`，APK 產於 `build/app/outputs/flutter-apk/app-debug.apk`。

---

### 2026-07-18 — 第四輪：被殺死狀態來電與雙端同步終止修復

> 目標：解決「雙端 APP 被系統殺死時收不到來電」與「一端拒接/掛斷/逾時，另一端未同步退出」兩大問題。

#### A. 來電有效期 15s → 45s 全鏈路對齊

- 根因：FCM 在 Doze/省電桶可能延遲數十秒送達，原本 `ttl=15s` 會讓被殺死的 APP 永遠收不到；且 CallKit 響鈴 45s 但第 16 秒後接聽被判過期。
- 後端 `socket_app.py`：`expires_at = issued_at + 45000`，call-request FCM `ttl=45s`。
- 前端統一常數 `globals.dart::kCallValidityMs = 45000`，套用於 `main.dart` / `signaling.dart` / `elder_home_screen.dart` / `family_main_screen.dart` 的過期判斷與 `sendCallRequest`、CallKit `duration`。

#### B. FCM 背景 handler 提前註冊（`main.dart`）

- 根因：`FirebaseMessaging.onBackgroundMessage(...)` 原註冊於 LineSDK/Analytics 之後、同一 try；任一項噴錯就導致 handler 未註冊。
- 修復：`Firebase.initializeApp()` 後「立即」以獨立 try/catch 註冊背景 handler；LineSDK/Analytics 改為各自 try/catch。

#### C. 拒接/掛斷/逾時 雙端同步終止

1. 無狀態 HTTP 拒接（`api_service.dart::declineCall`）— `_sendDeclineEvent` 改為「先 Singleton socket、後 HTTP 保底」。
2. 背景 isolate CallKit listener — 攔到拒接/逾時就走 HTTP `declineCall`。
3. `actionCallTimeout` 處理 — 響鈴逾時視同拒接，通知發起方停止等待。
4. `sendCallBusy` 加 HTTP 備援（`signaling.dart`）— Socket 未連線時改走 `ApiService.declineCall`。
5. 後端 `on_call_busy` 用 `call_registry` 補齊對端（`socket_app.py`）。
6. 發起方逾時主動取消 — `video_call_screen.dart` 20s 逾時 / `elder_screen.dart` 30s 逾時 → `sendCancelCall` + `hangUp`。

#### D. 前景 Socket 也附發 FCM（`socket_app.py`）

- 根因：`target_tokens` 只含「非前景」裝置，前景被殺→Socket 未逾時→不發 FCM→來電遺失。
- 修復：把前景在線 Socket 的 `fcmToken` 也併入 FCM 發送集合，由前端 3 秒去重。

#### E. 裝置級限制

- 小米/OPPO/華為等 force-stop 的 APP 收不到 FCM。已宣告 `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`，仍需引導使用者開「自啟動白名單 / 電池不最佳化」。

---

### 2026-07-19 — 第五輪：真機回報兩問題修復（commit `b95cc78` / `76b1b36`）

#### 問題1（長輩被殺死收不到來電）— `socket_app.py`

- 根因：長輩被殺死後 Socket 仍以 `appState=foreground` 殘留，其 `fcmToken` 為空/過期 → `target_fcm_tokens` 不含 → 完全不發 FCM。
- 修復：新增 `_get_all_known_fcm_tokens()`，回傳所有已知 FCM token（記憶體 + DB），不做 `is_socket_active` 過濾，併入 `fcm_send_map`。
- 測試：`test_call_request_killed_elder_lingering_foreground_socket_still_gets_fcm`。

#### 問題2（家屬冷啟動接聽後誤進主畫面）— `globals.dart` / `main.dart` / `splash_screen.dart`

- 根因：`SplashScreen` 家屬分支不消費 `pendingAcceptedCall`，Splash 動畫結束的 `pushReplacement(FamilyMainScreen)` 把最上層的 VideoCall 洗掉。
- 修復：(1) `globals.dart` 新增 `splashActive` 旗標；(2) main.dart 全域兜底加 `!splashActive` 條件；(3) splash_screen.dart 新增 `_navigateFamilyHome()` 確定性導航。

#### 第六輪（同日追加）— 冷啟動接聽事件遺失雙保險 + 兜底輪詢

- 根因：問題2仍在，真因是 `actionCallAccept` 在 `_setupCallKitListener` 註冊前發生 → 事件遺失。
- **背景 isolate 寫 prefs**：BG listener `actionCallAccept` 時把來電資料寫入 SharedPreferences `pendingAcceptedCall`。
- **`_checkInitialCall` 補救**：檢查 `activeCalls()` 中 `isAccepted=true` 且未過期的通話，補設 pending。
- **兜底輪詢**（`_scheduleAcceptedCallFallback`）：取代一次性 350ms；每 200ms 檢查、最多 8s——pending 被消費即停；`splashActive` 期間讓位。

#### 問題1 診斷指引

POCO/MIUI 特別檢查：設定→應用程式→Uban→**自啟動（Autostart）**；電池→**無限制**；其他權限→**顯示彈出式視窗**、**後台彈出介面**、**鎖屏顯示**。

---

### 2026-07-20 — 第七輪：pendingRingCallData 預寫 + 有效期 45s→120s + Doze 安全窗口

> 真機續報問題1/2仍在。問題2確認為「三重失敗場景」：BG isolate SharedPreferences 寫入失敗（小米嚴格背景 IO）+ `activeCalls()` isAccepted race + `onEvent` stream 錯過事件。

#### A. 背景 handler 預寫 pendingRingCallData（`main.dart`，Fix A）

長輩/家屬端 FCM `call-request` 路徑：在顯示 CallKit **之前**先寫入 `pendingRingCallData`（含 `isAccepted: false`），確保即使後續 Accept 事件遺失也有備援資料。`actionCallAccept` 時更新為 `isAccepted: true`。

#### B. `_checkInitialCall()` 重試機制（`main.dart`，Fix B）

單次查詢改為最多 3 次重試（間隔 300ms），等待 native CallKit plugin 狀態同步。

#### C. `main()` pendingRingCallData 備援讀取（`main.dart`，Fix C）

若 `pendingAcceptedCall` 為 null，檢查 `pendingRingCallData`：`isAccepted=true` 且未過期 → 重建 pending。

#### D. 有效期 45s → 120s 全鏈路（Fix D）

| 位置 | 舊值 | 新值 |
|------|------|------|
| `socket_app.py` `expires_at` | `issued_at + 45000` | `issued_at + 120000` |
| `socket_app.py` FCM `ttl` | `seconds=45` | `seconds=120` |
| `globals.dart` `kCallValidityMs` | `45000` | `120000` |

> **CallKit `duration` 保持 45s**：使用者接聽時間仍以 45s 為限，FCM 有充足時間（120s）穿透 Doze 延遲。

#### E. UnregisteredError DB 清除（`socket_app.py`，Fix E）

FCM 發送遇 `UnregisteredError` 時同步清除 DB `user_fcm_token`，避免下次 `_get_all_known_fcm_tokens` 查出同一支舊 token 重複失敗。

#### F. 驗證

- `flutter analyze lib/` — 無新增 error
- `python -m py_compile services/socket_app.py` — 通過
- `python -m pytest tests/test_call_signaling.py -v` — 6 passed
- 測試 `test_call_request_expires_at_is_45s` 更名為 `test_call_request_expires_at_is_120s`，assert 更新為 `120000`

---

## 6. 🚫 絕對不可改動區塊（給後續 AI）

> 下列區塊是本專案目前通話穩定性的「護欄」。除非明確知道連鎖影響並同步改完整條鏈路，**不要單點修改**。

1. **`Uban/mobile_app/lib/main.dart` → `_setupSignalingListener()` 的角色守門**
   - `if (appRole != 'elder') { s.onCallRequest = ... }`
   - **不可移除/放寬**：否則會覆蓋 `ElderHomeScreen` 的 callback，造成「長輩前景收不到來電」。

2. **`Uban/mobile_app/lib/main.dart` → `_setupCallKitListener()` 接聽路徑**
   - 先寫 `pendingAcceptedCall.value`，再短延遲 fallback `_navigateToVideoCall(...)`
   - **不可改回直接強推單一路徑**：否則會重現「接聽後回主頁、不進通話房」。

3. **`Uban/mobile_app/lib/main.dart` → `_navigateToVideoCall()`**
   - 只關閉 `_activeCallDialogContext`，**禁止** `popUntil(route.isFirst)` 清堆疊
   - **不可改回清堆疊**：會觸發 Splash/首頁重導，導致接聽失敗或黑屏。

4. **`Uban/mobile_app/lib/services/signaling.dart`**
   - `_invalidCallIds` + `_isExpiredCallPayload(...)` + 在 `call-request/cancel-call/call-busy/end-call` 的失效流程
   - **不可移除**：移除後會再出現「掛斷後延遲來電」「接起舊來電互打迴圈」。

5. **`uban-api/uban-api/services/socket_app.py`**
   - `call-request` 下發 `issuedAt/expiresAt`（**120 秒**，2026-07-20 修訂）與 FCM `ttl=120s`
   - `on_end_call()` 依 `call_registry` 對 Socket+FCM 廣播終止
   - `on_cancel_call()` / `on_call_busy()` 使用 `call_registry` 補齊目標並清理
   - 前景在線 Socket 的 `fcmToken` 也併入 FCM 發送集合（`fcm_send_map`）
   - `_get_all_known_fcm_tokens()` 回傳所有已知 token（記憶體+DB），不做 `is_socket_active` 過濾
   - **不可拆掉**：會回到「一端掛斷，另一端仍響/仍等待」或 killed 長輩收不到 FCM。

6. **`Uban/mobile_app/lib/screens/family_main_screen.dart`**
   - `2.5s` 輪詢 + `2.5s` debounce 套用 `isOnline`
   - **不要改回 1 秒瞬時切換**：會造成快速上下線抖動誤判。

7. **`Uban/mobile_app/lib/screens/elder_home_screen.dart` / `family_main_screen.dart`**
   - 消費 `pendingAcceptedCall` 前的過期判斷（**120 秒**，`kCallValidityMs`，2026-07-20 修訂）
   - **不可刪除**：會讓冷啟動延遲收到的舊來電再次被接起。

8. **`Uban/mobile_app/lib/screens/elder_screen.dart` + `video_call_screen.dart`**
   - `_isCameraOff = false`（進入視訊房預設開鏡頭）
   - **不可改回預設關閉**：與目前需求衝突，且會造成「接通黑畫面誤判」。

9. **`Uban/mobile_app/lib/main.dart` → `_firebaseMessagingBackgroundHandler`**
   - FCM `call-request` 路徑：在 `_showFullScreenCallkit` **之前**預寫 `pendingRingCallData`（含 `isAccepted: false`）
   - `actionCallAccept` 時更新 `pendingRingCallData` 的 `isAccepted` flag 為 `true`
   - **不可移除預寫**：否則 BG isolate 寫入失敗 + activeCalls() race + onEvent 遺失三重場景無備援。

10. **`Uban/mobile_app/lib/main.dart` → `_checkInitialCall()`**
    - 最多 3 次重試（間隔 300ms），等待 native CallKit plugin 狀態同步
    - `isAccepted=false`（僅響鈴中）**絕不**自動進房
    - **不可改回單次查詢**：冷啟動時 CallKit 狀態更新非同步，一次查詢常抓不到。

11. **`Uban/mobile_app/lib/main.dart` → `main()` pendingRingCallData 備援**
    - `pendingAcceptedCall` 為 null 時檢查 `pendingRingCallData`（`isAccepted=true` + 未過期 → 重建 pending）
    - **不可移除**：BG isolate 寫 `pendingAcceptedCall` 可能在小米/OPPO 嚴格背景 IO 下失敗。

12. **`Uban/mobile_app/lib/main.dart` → `_scheduleAcceptedCallFallback()`**
    - 兜底輪詢：每 200ms 檢查，最多 8s；`splashActive` 期間讓位；pending 被消費即停
    - **不可改回一次性 350ms 延遲**：無法覆蓋冷啟動時間變異。

13. **`Uban/mobile_app/lib/globals.dart` → `splashActive` 旗標**
    - 冷啟動接聽期間，main.dart 全域兜底導航必須讓位給 SplashScreen
    - **不可移除**：否則全域兜底把 VideoCallScreen push 到 Splash 上，又被 Splash 的 pushReplacement 洗掉。