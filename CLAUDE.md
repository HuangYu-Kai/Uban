# CLAUDE.md（`Uban/` — Flutter 前端）

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## 🚨 動手前必讀

> **在修改任何「視訊通話 / 來電通知 / 監控（CCTV）」相關的 Dart 程式碼之前，
> 必須先完整閱讀 [`CLAUDE_call-monitor.md`](CLAUDE_call-monitor.md)。**

該檔案是通話與監控子系統的**唯一權威參考**。本檔案不再記載通話／監控細節——
以前寫在這裡的 §2.2 Signaling/WebRTC 流程、§2.3 FCM→CallKit 喚醒鏈、§2.4 角色差異、
§5 修復記錄、§6 的 26 條護欄，**全部已遷移過去**（並已修正其中的路徑錯誤與自相矛盾條目）。

**觸發條件**（符合任一項就必須先讀）：

| 檔案 | 風險 |
|------|------|
| `lib/main.dart` | 🔴 極高（FCM BG handler、CallKit listener、冷啟動五層兜底） |
| `lib/services/signaling.dart` | 🔴 極高（Singleton、WebRTC、去重、失效清單） |
| `lib/globals.dart` | 🔴 極高（`pendingAcceptedCall`、`kCallValidityMs`、`splashActive`） |
| `lib/services/local_call_notification.dart` | 🔴 極高（CallKit 失敗時的唯一備援） |
| `lib/screens/elder_screen.dart` | 🔴 高（長輩端通話房 + CCTV） |
| `lib/screens/video_call_screen.dart` | 🔴 高（家屬端通話房） |
| `lib/screens/elder_home_screen.dart` / `family_main_screen.dart` | 🟠 中高（前景來電 dialog、裝置在線判定） |
| `lib/screens/splash_screen.dart` | 🟠 中高（冷啟動導航競態） |
| `lib/screens/camera_screen.dart` / `friends_screen.dart` | 🟠 中（監控入口、撥打入口） |

只改 UI 樣式（顏色、字體、間距）也**必須**先看 `CLAUDE_call-monitor.md` **§5 UI 按鈕與跳轉地圖**——
那一節就是為了讓只動 UI 的人不必讀完整條信令鏈也能安全改動而寫的。

⚠️ `lib/main.dart.bak` 是過期備份，會污染 grep 結果，**永遠不要編輯它**。

---
> 🚨 **CRITICAL RULE / 文件同步更新鐵律**: 
> 任何時候新增、修改或重構系統功能（包含 API 端點、資料庫 Schema、UI 介面、連線機制、TTS/AI 引擎、通話權限等），**必須同步更新相對應的 README.md 文檔**（`Uban/README.md` 及 `Uban-api/readme.md`），確保系統文檔 100% 保持最新且與實作無落差。

## 1. Common Commands

### Flutter Frontend (`Uban/mobile_app/`)

```bash
cd Uban/mobile_app

# Run the app (SERVER_IP injected via --dart-define; never hardcode)
flutter run --dart-define=SERVER_IP=localhost-0.tail5abf5e.ts.net \
  --dart-define=TURN_SERVER=152.69.196.5:3478 \
  --dart-define=TURN_USER=uban \
  --dart-define=TURN_PASS=115207

# Static analysis（改通話相關檔案後必跑，須 0 error）
flutter analyze lib

# Run all tests
flutter test

# Run a specific test file
flutter test test/services/api_service_test.dart
flutter test test/models/emotion_data_test.dart

# Install dependencies
flutter pub get

# 完整驗證（改通話相關檔案後必跑）
flutter build apk --debug
```

> Windows 上 `flutter build` 若出現 `compileDebugJavaWithJavac` 檔案鎖定錯誤，
> 復原步驟見 `CLAUDE_call-monitor.md` §9.6。

### FastAPI Backend (`uban-api/`)

> ⚠️ 後端根目錄是 **`uban-api/`**（不是舊文件寫的 `uban-api/uban-api/` 或 `Uban/uban-api/`）。

```bash
cd uban-api

pip install -r requirements.txt          # Python 3.12 only, NOT 3.13+
uvicorn main:app --host 0.0.0.0 --port 8000
pytest tests/
pytest tests/test_call_signaling.py -q   # 通話迴歸套件，須維持 15 passed
python -m py_compile services/socket_app.py
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
- uban-api (FastAPI 後端 + Socket.IO 信令): `https://localhost-0.tail5abf5e.ts.net`
- AI Server (Ollama AI 引擎): `https://boyo-desktop.tail531c8a.ts.net`
- TURN/STUN: `turn:152.69.196.5:3478`
- MySQL: `100.73.39.14:3306` (Tailscale)

### 2.2 通話與監控子系統 → 見 `CLAUDE_call-monitor.md`

| 想知道的事 | 節次 |
|-----------|------|
| 有哪些檔案、風險多高、`signaling.dart` 公開介面 | §2 檔案地圖 |
| Socket 事件 / FCM 欄位 / SharedPreferences 鍵位 | §3 資料契約 |
| 撥打 → 接聽 → 掛斷 完整流程（含冷啟動五層兜底） | §4 通話生命週期 |
| **按鈕在哪、按了跳去哪、可以安全改什麼** | §5 UI 按鈕與跳轉地圖 |
| 監控機／CCTV／裝置角色指派 | §6 監控子系統 |
| **72 條護欄（絕對不可單點修改）** | §7 |
| 這段程式碼為什麼長這樣（21 輪修復年表） | §8 |
| 出問題了怎麼查（三層 A/B/C 定位法、MIUI 檢查表） | §9 |
| 改完要做什麼 | §10 修改 SOP |

### 2.3 AI Dual-Engine & Pinecone Long-Term Memory

The backend runs two AI engines:
- **Primary**: Ollama (`gemma4:e4b-it-q4_K_M`), local via Tailscale, supports Tool Calling.
- **Fallback**: Google Gemini (`gemini_service.py`), activated when Ollama is unreachable.

**Pinecone Long-Term Memory**:
- Every chat is embedded (nomic-embed-text, 768-dim) and upserted to Pinecone index `uban` in a **background thread**.
- `daily_pond_leaf_job` (scheduled at 08:00 and 15:00 in `main.py`) queries Pinecone for semantic memory recall, generates a conversation topic, and pushes it via Socket.IO `'new-pond-leaf'` event to the Flutter `ZenPondScreen`.
- The AI agent personality is defined in `uban-api/server/agent/SOUL.md`, `IDENTITY.md`, etc.

### 2.4 Backend: Raw SQL + Scheduler

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

### 3.1 通用

1. **Do not hardcode IPs / server URLs** — always use `--dart-define=SERVER_IP=`
2. **No ORM in backend** — use `db_cursor()` with `%s` placeholders
3. **AI personality must be stable and serious** — no roleplay, pet speak, or impersonation
4. **Git commit messages must be in Traditional Chinese (繁體中文)**
5. **Do not hardcode MySQL host** — in production, use `uban-mysql`; avoid `localhost` or `127.0.0.1`
6. **Do not change the server port** — keep port 8000 for the FastAPI backend
7. **Use Python 3.12** — do not use Python 3.13 or higher
8. **計畫制定與成果檢驗用 Opus、執行用 Sonnet 子代理** — 所有實作計畫的制定，以及子代理產出的檢驗／驗收，一律由 Opus 模型負責；既定計畫的實際執行交由 Sonnet 子代理（`Agent` 工具傳 `model: "sonnet"`）。
9. **每次更動完成後必須清除不必要的空白檔案** — 收尾前掃一次工作目錄，刪除本次作業產生的零位元組檔、只剩空白字元的殘留檔、以及空的暫存目錄（例如中途建立後未使用的 stub、被清空但忘了刪的檔案）。**不要刪除**專案本來就需要的空檔案（如 `__init__.py`、`.gitkeep`、`py.typed`、空的 `__init__.dart`）。判斷準則：該檔是否被任何程式碼、設定或建置流程引用；有引用就留下。

### 3.2 通話與監控

**完整規則見 [`CLAUDE_call-monitor.md`](CLAUDE_call-monitor.md) §7（72 條護欄）。**
以下僅列最高頻的幾條，動手前仍必須讀完整版：

- **Never merge signaling and media tracks** — they are on separate hosts by design
- **Signaling is a Singleton** — never create a second `Signaling()` instance；斷線一律用 `forceDisconnect()`（用 `disconnect()` 會失去 FCM 接收能力）
- **Elder calls use `ElderScreen`** — do not route elders to `VideoCallScreen`
- **Do not broadcast SDP (Offer/Answer)** — must send to a specific `targetId` via `to=target_sid`
- **ICE candidates must be queued** — candidates arriving before `setRemoteDescription` must be queued and flushed after
- **Do not open user media after creating offer** — `localStream` must exist before `createOffer`
- **Always check socket connection before sending WebRTC signals** — poll with timeout (max 5s) to survive cold start
- **Use the `_isInCall` flag to prevent concurrent calls**
- **Convert SharedPreferences data properly** — `Map<String, dynamic>` → `Map<String, String?>` before assigning to `pendingAcceptedCall.value`
- **Navigate home with `pushAndRemoveUntil`, never `pop()`**
- **不要在 `Signaling` singleton 新增「顯示狀態」全域旗標** — 曾有一個 `isIncomingCallDialogVisible` 導致長輩端冷啟動失敗而被回退；需要跨路徑協調時，用**與 `callId` 綁定、讀不到就退回安全預設**的純資料欄位（比照 `lastProcessedCallId`）

---

## 4. Subproject Reference

| 主題 | 檔案 |
|------|------|
| **視訊通話 / 來電通知 / 監控**（最優先） | [`CLAUDE_call-monitor.md`](CLAUDE_call-monitor.md) |
| 專案總覽 | `../CLAUDE.md` |
| FastAPI 後端 | `../uban-api/CLAUDE.md` |
| Codex／其他代理 | `../AGENTS.md` |

Flutter 前端在 `Uban/mobile_app/` 下沒有更細的 CLAUDE.md，本檔即為前端的入口文件。

---

## 5. 變更歷史

通話與監控子系統的完整修復年表（2026-06-05 起共 21 輪，含每一輪的根因、檔案、行號）
已遷移至 [`CLAUDE_call-monitor.md`](CLAUDE_call-monitor.md) §8。

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

### 2026-07-22 — 第八輪：拒接三重訊息、角色反轉、拒接狀態清理、簡繁轉換

> 真機續報：(1) 長輩端未在前景時，家屬端撥打被拒後跳出**三個**拒絕訊息；(2) APP 外拒接後回到 APP 內仍看到來電通知，點擊後**角色反轉**（接收方變發起方）；(3) 長輩被殺死仍收不到來電（加診斷日誌待定位）；(4) 少數簡體中文需轉繁體。

#### Fix 1 — 拒接三重訊息（`main.dart::_sendDeclineEvent`）

- 根因：`_sendDeclineEvent` **同時**發 Socket `call-busy` 和 HTTP `declineCall`，後端 `on_call_busy` 與 `api_decline_call` 各自廣播 `call-busy`+`cancel-call`；再加上 BG isolate CallKit listener 也發一則 HTTP decline → 發起方收到多重拒絕 dialog。
- 修復：改為 **if-else 單通路**——Socket 在線只走 Socket，離線才走 HTTP；`catch` 區塊作 Socket 失敗時的 HTTP 備援。

#### Fix 2 — 拒接後陳舊狀態清理（`main.dart`）

- 根因：拒接路徑從不清除 `pendingRingCallData` / `pendingRingCall`（僅清 `pendingAcceptedCall`），下次冷啟動 `main()` 讀到 `pendingRingCallData` 誤重建 pending；FCM `call-request`（ttl 120s）延遲抵達又觸發假來電。
- 修復：(A) `_sendDeclineEvent` 三個 prefs key 全清；(B) BG isolate listener 拒接/逾時時同樣清三個 key；(C) FCM 前景 + BG `cancel-call` handler 清 prefs 並呼叫 `Signaling().invalidateCallId(callId)`（新增公開方法）標記失效。

#### Fix 3 — 防角色反轉（消費端 `senderRole` 驗證）

- 根因：所有 `pendingAcceptedCall` 消費端（`family_main_screen` / `elder_home_screen` / `splash_screen`）盲信自己是接聽方，對陳舊/反轉資料仍發 `sendCallAccept` → 對端反被叫。
- 修復：全鏈路帶上發起方角色 `senderRole`（`_showFullScreenCallkit` extra、CallKit accept、BG 寫入、`pendingRingCallData` 預寫皆補上），三個消費端消費前驗證 `senderRole != appRole`；相等即判為角色反轉 → 丟棄並清除。

#### Fix 4 — 簡體中文轉繁體

- `redesigned_ai_chat_screen.dart`（10 處 UI 可見字串：伴侶/互動/長者/狀態/活躍/回應/即時/風格/關閉）、`signaling.dart`（TURN 註解 7 處）、`ai_suggestion_service.dart`（1 處）、`family_main_screen.dart`（1 處 debugPrint）。掃描確認 `lib/` 已無殘留簡體字。

#### Fix 5 — 後端無設備診斷日誌（`socket_app.py::on_call_request`）

- FCM 發送迴圈後：若 `target_sids` 與 `fcm_send_map` 皆為空 → 打印 `🚨 目標完全無法觸達`；若僅有 Socket 無 token → 打印 `⚠️ 僅有在線 Socket、無 FCM token`。供真機測試定位問題1（killed 長輩收不到 FCM）之後端斷點。

#### 驗證

- `python -m py_compile services/socket_app.py` — 通過
- `python -m pytest tests/test_call_signaling.py -q` — **5 passed**（順手修正 round 7 遺漏的 stale test：`test_call_request_expires_at_is_45s`→`_120s`，assert `45000`→`120000`）
- `flutter analyze lib/` — 0 error（其餘為既有 withOpacity 等 info/warning）
- `flutter build apk --debug` — **BUILD SUCCESSFUL**

---

### 2026-07-22 — 第九輪：長輩被殺死收不到來電 **根因** 修復（monitor-wakeup 誤判）

> 真機關鍵線索：家屬撥長輩、**長輩被殺死收不到**；反向（長輩撥家屬、家屬被殺死）**正常**。兩機同型號 POCO/MIUI、權限全開。**對稱失效才是 MIUI 殺進程，但這是不對稱** → 必為 elder/family 結構性差異。第八輪的診斷日誌（Fix 5）指向此處。

## 環境要求
- Flutter SDK (latest stable)
- Python 3.12 (後端，不支援 3.13+)
- Android Studio (模擬器)
- 後端通過 Tailscale Funnel 對外開放

## 🚫 絕對不可改動區塊 (Critical Guardrails)

下列區塊是目前通話穩定性的重要護欄，不可單點修改：
#### 根因鏈（elder/family 唯一差異：FCM `type` 欄位）

- 後端依 `deviceMode` 決定 FCM `type`：`socket_app.py` `on_call_request`（call-request）與 `on_emergency_call`（emergency-call）皆為 `'monitor-wakeup' if info.get('deviceMode')=='monitor' else '...'`。
- 前端背景 handler `main.dart:76` 只放行 `call-request`/`emergency-call`/`cancel-call`，**`monitor-wakeup` 被靜默丟棄**（全 `lib/` 無任何 monitor-wakeup handler）。
- **family 永遠 `deviceMode='comm'`** → 永遠 `call-request` → 一定響；**elder 通訊機一旦被記成 `monitor`** → `monitor-wakeup` → 丟棄 → 被殺死不響。
- elder 通訊機為何被記成 monitor：`user_fcm_token` 主鍵 `(user_id, room_id, fcm_token)`，同一支 token 可在 `comm_elder_X` 與 `monitor_elder_X` 各留一列（曾當監控機、後改通訊機）。FCM token 去重（`_get_all_known_fcm_tokens` / `_get_target_sockets_and_tokens`）**無 ORDER BY + 記憶體無條件覆寫** → monitor 蓋掉 comm → 送 monitor-wakeup。
- 上游成因：`has_comm_elder_device` 信任 `on_disconnect` 從不清除的殘留離線 token → 主機重裝被誤判「已有通話機」→ 自我降級成 monitor。

#### 修復（分層）

| 層 | 檔案 | 修復 |
|----|------|------|
| **C1 前端止血** | `main.dart` BG + FG handler | 收到 `monitor-wakeup` 時，若本機權威旗標 `saved_is_cctv==false`（自認通訊機）→ 正規化為 `call-request`。裝新版即生效、免重新配對。 |
| **B2 後端根治** | `socket_app.py::on_join` / `on_update_fcm_token` | 新增 `_purge_stale_reverse_mode_token()`：elder join 時以 token 為鍵刪除「反向模式房間」的殘留列（記憶體+DB）。只清同一台實體裝置的錯誤列。 |
| **B1 後端防禦** | `_get_all_known_fcm_tokens` / `_get_target_sockets_and_tokens` | token 去重一律偏好 comm：記憶體迴圈加「comm 不被 monitor 覆蓋」，DB 查詢加 `ORDER BY (device_mode='comm') DESC`。 |
| **B3 防復發** | `has_comm_elder_device` | 只認在線 socket，移除「殘留離線 token 也算已有通話機」判斷。 |

#### 驗證

- `python -m pytest tests/test_call_signaling.py -q` — **7 passed**（新增 `test_all_known_tokens_prefers_comm_over_monitor`、`test_has_comm_elder_device_ignores_stale_offline_token`）
- `flutter analyze lib/main.dart` — 0 error
- `flutter build apk --debug` — **BUILD SUCCESSFUL**
- 端到端（真機）：長輩機裝新版 → 開一次 App（觸發 B2 清列）→ 殺死 → 家屬撥打 → 應跳 CallKit。`adb logcat -s flutter FLTFireMsgReceiver` 可見 `🔧 [BG] 本機為通訊機，將 monitor-wakeup 正規化為 call-request`。

---

### 2026-07-22 — 第十輪：長輩 token 查詢改用「家屬式 user_id 內容鍵」(位置鍵→內容鍵)

> 使用者洞察：家屬被殺死能收到、長輩不行，**何不讓長輩沿用家屬端邏輯**。這是第九輪的**互補第二條腿**：第九輪解「token 撈到了但 type 被標成 monitor-wakeup」；本輪解「token 因 room_id 字串漂移**根本沒撈到**」。

#### 根因：兩端 token 查詢的「鍵」不同

- **家屬端**（`target_role='family'`）用 **user_id 內容鍵**：`family_elder_relationship` → `family_id` → `WHERE role='family' AND user_id IN (...)`。跟裝置註冊在哪個房間無關 → 穩。
- **長輩端**（`target_role='elder'`）只用 **room_id 位置鍵**：`WHERE role='elder' AND room_id IN ('comm_elder_X','monitor_elder_X')`。房名字串一漂移（`elder_home_screen.dart:62` fallback 成 user_id、數字 elder_id 前導零/str↔int、舊格式殘列、重啟殘列）→ 查無 token → **完全不發 FCM** → 脆。
- 設計本意：`elder_profile.elder_id`（PK）作 room_id 保獨立性，`user_id`（FK）綁定通訊。room_id 是後端為 Socket.IO 造的「`comm_`/`monitor_` + elder_id」字串（`user_fcm_token`/`call_record` 兩表有此欄，非原始設計表格欄位），本輪把原本閒置的 `elder_id↔user_id` FK 綁定啟用為查詢鍵。

#### 修復（僅後端 `socket_app.py`，只改 FCM token 查詢，不動 room_id 的視訊信令/CCTV 用途）

- 新增 `_resolve_elder_user_id(elder_id)`：一律走 `elder_profile` 反解 user_id，**不做 int 短路**（避開 `_resolve_user_id_int` 對數字型 elder_id 如 '0064' 的誤判）。
- `_get_all_known_fcm_tokens` / `_get_target_sockets_and_tokens` elder 分支：DB 查詢 `WHERE role='elder' AND (room_id IN (%s,%s) OR user_id = %s)`（**疊加**，非取代——向後相容既有各種 room_id 殘列）；記憶體側新增「掃所有房間、`userId==elder_user_id`」的 user_id 補掃，對齊家屬式。
- **全程保留第九輪 comm-over-monitor 去重**（`ORDER BY (device_mode='comm') DESC` + `existing.deviceMode=='comm'` 防呆 + DB 迴圈 `token in` guard）。`elder_user_id` 為 None 時 `OR user_id=NULL` 恆假 → 安全退化回純 room_id。

#### 驗證

- `python -m pytest tests/test_call_signaling.py -q` — **8 passed**（新增 `test_all_known_tokens_found_by_user_id_when_room_id_drifts`；已用「移除 OR user_id 後測試變紅」反證其有效）
- `python -m py_compile services/socket_app.py` — 通過
- 前端本輪未改（第九輪 C1 已就位）。
- 端到端（真機）：後端日誌 `📡 [Routing] 目標查詢結果...離線 token N 個`，N 應 ≥1（先前 room_id mismatch 時為 0）。

---

### 2026-07-22 — 第十一輪：FCM 已送達但 CallKit 顯示不出來（原生層故障 + 通知備援）

> 真機 log 證實**問題性質變了**：FCM `call-request` **已送達**被殺死的長輩機（`type: call-request` 非 `monitor-wakeup` → 九/十輪送達修復成功），但收到後**零 CallKit 畫面**，11.5 秒後家屬掛斷的 `endAllCalls()` 崩潰 `PlatformException(content is null)`。從「收不到」變「**收到了但顯示不出來**」。

#### 根因（追進 flutter_callkit_incoming 3.0.0 原生 Kotlin 驗證）

- `showCallkitIncoming` 是**射後不理**：Kotlin `sendBroadcast()` 後立即 `result.success(true)`，真正建通知在 `CallkitIncomingBroadcastReceiver.onReceive` **非同步**執行 → Dart 端以為成功（無 error log），但原生 BroadcastReceiver 在 MIUI 被殺死背景進程**建立通知失敗**（無畫面）。
- `endAllCalls()` 是**同步** platform channel → 原生錯誤拋回 Dart，是同一故障唯一露出水面的部分。
- `targetSdk=36`（Android 16）+ Android 14+：全螢幕來電需 `USE_FULL_SCREEN_INTENT` 特殊權限，MIUI 常預設關閉。
- 來電**完全依賴 CallKit 一條路徑，無任何備援**。

#### 修復（三管齊下，全部跨版本安全）

| Fix | 檔案 | 修復 |
|-----|------|------|
| **1 修崩潰** | `main.dart` BG cancel-call + FG cancel-call + `showCallkitIncoming` | `endAllCalls()` / `showCallkitIncoming` 全包 try-catch + log，不再中斷後續清理、原生錯誤可見 |
| **2 全螢幕權限引導** | `elder_home_screen.dart::_requestPermissions` | 用套件 `canUseFullScreenIntent()`/`requestFullIntentPermission()`（**原生層自帶版本判斷**，Android 13- 恆 true/安全略過），false 時彈 dialog 導設定頁 |
| **3 原生通知備援** | 新增 `services/local_call_notification.dart` + `pubspec.yaml` | 新增 `flutter_local_notifications 18.0.1`，與 CallKit **平行發** heads-up 高優先級通知（標準 builder，非 CallKit RemoteViews，避開 content-is-null）；共用 callId，cancel-call/接聽/拒接一起關；點擊寫 `pendingAcceptedCall` → 冷啟動兜底 |

- 建置設定：`android/app/build.gradle.kts` 啟用 **core library desugaring**（`isCoreLibraryDesugaringEnabled=true` + `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")`），為 flutter_local_notifications 18.x 需求。

#### 驗證

- `flutter analyze lib/` — **0 error**
- `flutter build apk --debug` — **BUILD SUCCESSFUL**（先遇 desugaring 需求→已啟用）
- 端到端（真機 Android 14+）：啟動彈全螢幕權限引導→殺死→家屬撥打→CallKit 或備援通知至少一者顯示；掛斷 `endAllCalls` 不再崩潰。

---

### 2026-07-27 — 第十三輪：來電樣式回歸 CallKit、緊急通話瞬間掛斷、快速登入

> 真機回報四項：(1) **雙端**被殺死時來電通知是樸素 heads-up 樣式，不是要的 CallKit 來電 UI；(2) 緊急通話家屬端發起後**瞬間、無任何提示**跳回主畫面；(3) 長輩端登出後「快速登入同一長輩」永遠失敗；(4) 雙端被殺死時點通知進不了視訊房，走的是一般開 APP 流程。問題 1 與 4 為**同一條根因鏈**。

#### 問題1＋4：`call-request` 繞過 CallKit，且備援的 launch payload 無人消費

- `main.dart::_firebaseMessagingBackgroundHandler` 的長輩端／家屬端 `call-request` 分支（2026-07-25 改動）**只呼叫 `LocalCallNotification.show()` 就 return**，`_showFullScreenCallkit()` 從未執行。
- `_showFullScreenCallkit` 的備援條件掛在 `data['useLocalBackup'] == '1'`，而全專案（含後端）**從未設過該欄位** → 死碼。
- 問題4：APP 已終止時點擊備援通知，`onDidReceiveBackgroundNotificationResponse` 不保證觸發，payload 只在 `getNotificationAppLaunchDetails()` 裡，而全 `lib/` 從未呼叫它 → `pendingAcceptedCall` 從未寫入 → `_checkInitialCall` / `_scheduleExtendedActiveCallsPoll` / `_pollActiveCallsForAccepted` / Splash 最終防線四層兜底全部落空。

| Fix | 檔案 | 修復 |
|-----|------|------|
| A | `main.dart` BG handler | 兩條 `call-request` 分支改回 `_showFullScreenCallkit()`（保留 `pendingRingCallData` 預寫） |
| B | `main.dart::_showFullScreenCallkit` | 移除 `useLocalBackup` 死旗標；改為無條件探測 `activeCalls()`（350ms→600ms），CallKit 成功就完全不發備援（天然互斥），失敗才補發。**移到 `bgSub` listener 註冊之後**，避免 `await` 延後 listener |
| C | `local_call_notification.dart` | 樣式向 CallKit 靠攏（`largeIcon` ＋ 紅「拒接」/綠「視訊」`AndroidNotificationAction` ＋ 標題改為來電者名稱）；新增 `consumeLaunchPayload()`；decline action 走 HTTP `declineCall` ＋ 清三個 prefs key |
| D | `main.dart::main()` | 讀 `pendingAcceptedCall` prefs 前呼叫 `consumeLaunchPayload()` ＋ `prefs.reload()` |

> `flutter_local_notifications 18.0.1` 不支援原生 `Notification.CallStyle`，備援無法與 CallKit 像素一致；C 是純 Dart 的最接近版本。因 B 的互斥設計，備援僅在 CallKit 原生層失敗時出現。

#### 問題2：緊急通話全鏈路缺 `lastProcessedCallId` → 被自己的去重邏輯掛斷

- `signaling.dart` 的 `emergency-call` handler 與 `main.dart::s.onEmergencyCall` **都沒設 `lastProcessedCallId`**（`call-request` 有設）→ `elder_screen.dart` 的 `isSameOngoingCall` **恆為 false** → 任何第二次寫入 `pendingAcceptedCall` 都落入 `if (_isInCall) { hangUp() }` → emit `end-call` → 家屬端掛斷。
- **「沒有任何提示」**：`video_call_screen.dart` 的 `onCallEnded`/`onConnectionLost` 用 `SnackBar` 後立刻 `_goHomeAfterCall()`（`pushAndRemoveUntil`），route 當場移除、SnackBar 隨之消失。2026-07-15 第二輪 Issue 6 只修了 `onCallBusy`。

| Fix | 檔案 | 修復 |
|-----|------|------|
| 1 | `signaling.dart` `emergency-call` | 補 `_invalidCallIds` 檢查、2s 去重窗口、`lastProcessedCallId`/`Time`、`_currentCallId` |
| 2 | `main.dart::s.onEmergencyCall` ＋ BG emergency | 補設 `lastProcessedCallId`；pending 補 `senderRole`（緊急是全鏈路唯一漏帶的）＋ `issuedAt`/`expiresAt` |
| 3 | `elder_screen.dart` | 新增 `_activeCallId`，`isSameOngoingCall` 改為 `== lastProcessedCallId \|\| == _activeCallId`（第二道防線） |
| 4 | `video_call_screen.dart` | `onCallEnded`/`onConnectionLost` 改用 `_showCallRejectedThenGoHome()`，訊息「對方已掛斷通話」/「網路連線中斷」 |
| 5 | `signaling.dart::sendEmergencyCall` | 與 `sendCallRequest` 對齊：`callId`/`_currentCallId`/`role`/`callerUserId`/`senderName`/有效期 |
| 6 | `socket_app.py::on_emergency_call` | `call_id = data.get('callId') or uuid4()`；補上緊急通話一直缺的 **Layer B ＋ Layer C（`_get_all_known_fcm_tokens`）** → killed 長輩才收得到；補 `UnregisteredError` 清 DB ＋ 無設備診斷日誌 |

#### 問題3：登出清掉了快速登入所依賴的鍵

`_quickLoginSameElder` 讀 `caregiver_id`/`caregiver_name`/`user_role`，而 `elder_profile_tab::_handleLogout` 登出時正好 remove 掉前兩者。

修復：引入登出不清除的 `last_elder_id`/`last_elder_name`/`last_elder_room_id`/`last_elder_device_role`；`_quickLoginSameElder` 讀不到 session 鍵時回退並回寫，**同時還原 `device_role_$room` 與 `saved_is_cctv`**（否則重判角色可能誤判成 monitor → 觸發第九輪的 `monitor-wakeup` bug 鏈）。`force-logout`（遠端強制解綁）才一併清除。

#### 文件與程式碼不符（供後續 AI 注意）

- 後端 `socket_app.py` 實際路徑是 **`uban-api/services/socket_app.py`**（非 `uban-api/uban-api/...`）。
- 根目錄 `CLAUDE.md` 護欄 #5 所述「前景 active Socket 不發 FCM」**在現行程式碼中不存在**——`on_call_request` 是把前景在線 Socket 的 token 也併入 `fcm_send_map`（與本文件記載一致）。前景不雙重彈窗是靠**前端**擋（`isResumed` early return ＋ 3 秒 callId 去重）。本輪未更動此行為。

#### 驗證

- `python -m py_compile services/socket_app.py` — 通過
- `python -m pytest tests/test_call_signaling.py -q` — **8 passed**（不退步）
- `flutter analyze lib` — **0 error**（本輪改動的 6 個 Dart 檔案 0 issues）
- `flutter build apk --debug` — **BUILD SUCCESSFUL**

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
   - `call-request` 下發 `issuedAt/expiresAt`（15 秒）與 FCM `ttl=15s`
   - `on_end_call()` 依 `call_registry` 對 Socket+FCM 廣播終止
   - `on_cancel_call()` 使用 `call_registry` 補齊目標
   - **不可拆掉**：會回到「一端掛斷，另一端仍響/仍等待」。
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

14. **`Uban/mobile_app/lib/main.dart` → `_sendDeclineEvent()` 單通路（2026-07-22 第八輪）**
    - Socket 在線只走 `sendCallBusy`，離線才走 HTTP `declineCall`；`catch` 作 HTTP 備援
    - **不可改回「Socket + HTTP 兩路都發」**：會重現拒接三重訊息（後端兩個 handler 各廣播一次）。

15. **拒接/取消時清除三個 prefs key（2026-07-22 第八輪）**
    - `_sendDeclineEvent`、BG isolate CallKit decline/timeout listener、FCM 前景/BG `cancel-call` handler
      皆須清 `pendingAcceptedCall` + `pendingRingCallData` + `pendingRingCall`
    - **不可移除**：殘留 `pendingRingCallData` 會讓冷啟動 `main()` 誤重建 pending → 假來電/角色反轉。

16. **`senderRole` 防角色反轉（2026-07-22 第八輪）**
    - 全鏈路帶 `senderRole`（`_showFullScreenCallkit` extra、CallKit accept `pendingAcceptedCall`、BG 寫入、`pendingRingCallData` 預寫）
    - 三個消費端（`family_main_screen::_checkPendingAcceptedCall`、`elder_home_screen::_onPendingCallChanged`、`splash_screen::_isPendingRoleReversed`）消費前驗證 `senderRole != appRole`
    - **不可移除**：相等代表這通「來電」實為自身角色發出的 stale 資料，若照常 `sendCallAccept` 會讓對端反被叫（接收方變發起方）。

17. **`Uban/mobile_app/lib/services/signaling.dart` → `invalidateCallId()` / `isCallInvalidated()`（2026-07-22 第八輪）**
    - 供 main.dart FCM handler 於拒接/取消時標記 callId 失效
    - **不可移除**：與 `_invalidCallIds` 的失效流程一體，移除後延遲抵達的同一 call-request 會再彈窗。

18. **`monitor-wakeup` 正規化與 FCM token 模式一致性（2026-07-22 第九輪，長輩被殺死收不到來電根因）**
    - `main.dart` BG + FG handler：收到 `monitor-wakeup` 且 `saved_is_cctv==false` → 正規化為 `call-request`
    - `socket_app.py`：`_get_all_known_fcm_tokens` / `_get_target_sockets_and_tokens` 的 token 去重一律**偏好 comm**（記憶體不被 monitor 覆蓋 + DB `ORDER BY (device_mode='comm') DESC`）
    - `socket_app.py::on_join` / `on_update_fcm_token`：呼叫 `_purge_stale_reverse_mode_token()` 清同 token 反向模式殘留列
    - **不可移除任一環**：任何一環失守，通訊機的 elder 來電就會被送成 `monitor-wakeup` 而被 App 丟棄 → 長輩被殺死收不到來電（且是 elder 專屬、family 不受影響的不對稱失效）。

19. **`Uban/uban-api/services/socket_app.py` → `has_comm_elder_device()` 只認在線 socket（2026-07-22 第九輪）**
    - **禁止**改回信任 `room_fcm_tokens` 殘留離線 token
    - **原因**：`on_disconnect` 從不清除離線 token；若拿來當「已有通話機」依據，主通訊機重裝/清資料後會被自己的殘留 token 誤判 → 降級為監控機（monitor）→ 產生 monitor 列 → 觸發 #18 的整條 bug 鏈。

20. **`Uban/uban-api/services/socket_app.py` → 長輩 token 查詢的 `OR user_id` 疊加（2026-07-22 第十輪）**
    - `_get_all_known_fcm_tokens` / `_get_target_sockets_and_tokens` 的 elder 分支：DB `WHERE role='elder' AND (room_id IN (%s,%s) OR user_id = %s)` + 記憶體 user_id 補掃，`user_id` 由 `_resolve_elder_user_id()`（走 elder_profile、不 int 短路）反解。
    - **禁止**改回「只用 room_id」：家屬端用 user_id 內容鍵故穩，長輩端若只用 room_id 位置鍵，房名字串一漂移就查無 token → 完全不發 FCM → 長輩被殺死收不到（family 不受影響的不對稱失效）。
    - **禁止**用 `_resolve_user_id_int` 代替 `_resolve_elder_user_id`：前者對數字型 elder_id（如 '0064'）會 int 短路誤判成 user_id。
    - comm-over-monitor 去重（#18）必須與此並存，不可因加 user_id 查詢而讓 monitor 列覆蓋 comm。

21. **原生通知備援 + endAllCalls try-catch（2026-07-22 第十一輪，CallKit 在 MIUI 被殺死靜默失敗）**
    - `Uban/mobile_app/lib/services/local_call_notification.dart`（`flutter_local_notifications`）：MIUI 被殺死背景 isolate 下 CallKit 常靜默建立失敗，此備援是唯一的後備來電畫面。**禁止移除**。
      > ⚠️ **2026-07-27 第十三輪修訂**：不再與 CallKit「平行發」。改為 `_showFullScreenCallkit` 尾端探測 `activeCalls()`，**只在 CallKit 確實沒建立時才補發**——平行發會造成雙重推播，且讓使用者看到的是備援的樸素樣式而非 CallKit 來電 UI。詳見護欄 #22。
    - `main.dart`：所有 `FlutterCallkitIncoming.endAllCalls()` / `showCallkitIncoming()` **必須包 try-catch**——原生層在某些 MIUI 會拋 `PlatformException(content is null)`，未包會中斷 cancel-call 清理鏈。
    - `endAllCalls` / 拒接 / 接聽 / cancel-call 時**必須一併** `LocalCallNotification.cancel()`，否則備援通知殘留。
    - `elder_home_screen.dart::_requestPermissions`：Android 14+ 全螢幕權限引導用套件 API（自帶版本判斷），**禁止**改成寫死 SDK 版本判斷。
    - `android/app/build.gradle.kts`：**core library desugaring 不可移除**（flutter_local_notifications 18.x 需求，移除會 build 失敗）。

22. **CallKit 是唯一的主要來電 UI 路徑（2026-07-27 第十三輪）**
    - `main.dart::_firebaseMessagingBackgroundHandler` 的 `call-request` 分支（**長輩端與家屬端皆然**）必須呼叫 `_showFullScreenCallkit()`。
    - **禁止**改回「只發 `LocalCallNotification` 就 return」：那是「來電樣式不對」＋「被殺死時點通知進不了視訊房」的共同根因——備援通知的 launch payload 走的是另一條消費路徑（見 #23），CallKit 才有完整的冷啟動接聽鏈。
    - `_showFullScreenCallkit` 尾端的備援探測（延遲 600ms → `activeCalls()` → 沒建立才 `LocalCallNotification.show`）**必須放在 BG `bgSub` listener 註冊之後**：它會 `await`，擺在前面會延後拒接/接聽 listener 的註冊而漏接早期事件。
    - **禁止**恢復 `data['useLocalBackup']` 旗標判斷：全鏈路（含後端）從未設定該欄位，是死碼。

23. **`local_call_notification.dart::consumeLaunchPayload()`（2026-07-27 第十三輪）**
    - 必須在 `main()` 讀取 `pendingAcceptedCall` prefs **之前**呼叫，其後接 `prefs.reload()`。
    - **不可移除**：APP 已終止時點擊備援通知，payload 只存在於 `getNotificationAppLaunchDetails()`；`onDidReceiveBackgroundNotificationResponse` 對這個情境**不保證**被觸發。移除後備援路徑的接聽會退化成「開場動畫→主畫面」。

24. **緊急通話必須記錄 `lastProcessedCallId`（2026-07-27 第十三輪）**
    - `signaling.dart` 的 `emergency-call` handler 與 `main.dart::s.onEmergencyCall` 都要設 `lastProcessedCallId`/`lastProcessedCallTime`。
    - `elder_screen.dart::_checkPendingAcceptedCall` 的 `isSameOngoingCall` 必須同時比對 `_activeCallId`（第二道防線）。
    - **不可移除任一環**：少了就重現「第二次寫入 `pendingAcceptedCall` → 落入 `if (_isInCall) { hangUp() }` → emit `end-call` → 家屬端瞬間掛斷」。
    - 緊急路徑寫入 `pendingAcceptedCall` 時**必須帶 `senderRole`**（#16 的全鏈路要求，緊急通話原本是唯一漏帶的）。
    - 緊急通話的 FCM **刻意不帶** `issuedAt`/`expiresAt`（ttl 維持 3600s）：帶了會被前端 120s 過期判斷誤殺。

25. **`video_call_screen.dart` 的通話終止提示必須用 dialog（2026-07-27 第十三輪）**
    - `onCallEnded` / `onCallBusy` / `onConnectionLost` 一律走 `_showCallRejectedThenGoHome()`。
    - **禁止**改回 `SnackBar`：緊接的 `_goHomeAfterCall()` 是 `pushAndRemoveUntil((route)=>false)`，會當場移除 route 讓 SnackBar 消失 → 使用者看到「瞬間、無提示跳回主畫面」，故障也無從診斷。

26. **`last_elder_*` 快速登入記憶鍵（2026-07-27 第十三輪）**
    - `last_elder_id` / `last_elder_name` / `last_elder_room_id` / `last_elder_device_role`。
    - 使用者主動登出（`elder_tabs/elder_profile_tab.dart::_handleLogout`）**不可清除**這組鍵——它清 `caregiver_id`/`caregiver_name`，而 `_quickLoginSameElder` 正是讀那些鍵，這正是「快速登入抓不到上次 session」的根因。
    - `_quickLoginSameElder` 回退時**必須一併還原 `device_role_$room` 與 `saved_is_cctv`**：否則會重新 `hasCommDevice` 重判裝置角色，誤判成 monitor 就觸發 #18 的整條 bug 鏈。
    - 只有家屬端遠端 `force-logout`（強制解綁）才連同清除。

27. **全域音訊焦點共存 (Audio Focus Coexistence) 設定 (2026-08-04 第十四輪)**
    - `lib/main.dart` 啟動階段必須設定 `AudioPlayer.global.setAudioContext(AudioContext(android: const AudioContextAndroid(stayAwake: true, contentType: AndroidContentType.music, usageType: AndroidUsageType.media, audioFocus: AndroidAudioFocus.none)))`。
    - **禁止改回**預設獨佔焦點（`AndroidAudioFocus.GAIN` / `GAIN_TRANSIENT`）。
    - **原因**：長輩端全時語音喚醒 (`SpeechToText`) 運作時，若播放器強搶音訊焦點，系統會發送 `-2` (`AUDIOFOCUS_LOSS_TRANSIENT`) 導致音訊/新聞/TTS播音自動暫停。設定 `AndroidAudioFocus.none` 確保媒體播放與語音喚醒 100% 完全平行共存。

