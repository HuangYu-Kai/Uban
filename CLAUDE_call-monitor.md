> ⚠️ **本檔在兩個 repo 各有一份鏡像**：`Uban/CLAUDE_call-monitor.md` 與 `uban-api/CLAUDE_call-monitor.md`。
> 因為 `Uban/` 與 `uban-api/` 是兩個獨立的 git repo（專案根目錄的 `.git` 是空目錄、無法運作），
> 這份跨前後端的權威文件必須在兩邊各留一份才會被版控。
> **修改任一份時，必須同步更新另一份**，否則兩邊會分歧。

# CLAUDE_call-monitor.md — 視訊通話與監控子系統 唯一權威參考

> **最後更新：2026-08-11（第二十二輪後）**
> 本文件是 Uban 專案「視訊通話 + 監控（CCTV）」全部功能的**單一權威來源**。
> 相關內容已從 `CLAUDE.md` / `Uban/CLAUDE.md` / `uban-api/CLAUDE.md` 遷移至此，那些檔案只保留指向本檔的指標。

---

## 0. 給 AI 代理的使用說明（先讀這一節）

### 0.1 什麼時候必須讀本文件

**在動到下列任何一個檔案之前，你必須先完整讀過本文件的第 7 章（護欄）：**

```
Uban/mobile_app/lib/main.dart
Uban/mobile_app/lib/globals.dart
Uban/mobile_app/lib/services/signaling.dart
Uban/mobile_app/lib/services/local_call_notification.dart
Uban/mobile_app/lib/screens/video_call_screen.dart
Uban/mobile_app/lib/screens/elder_screen.dart
Uban/mobile_app/lib/screens/elder_home_screen.dart
Uban/mobile_app/lib/screens/family_main_screen.dart
Uban/mobile_app/lib/screens/splash_screen.dart
Uban/mobile_app/lib/screens/camera_screen.dart
Uban/mobile_app/lib/screens/friends_screen.dart
Uban/mobile_app/lib/screens/family/family_interaction_tab.dart
Uban/mobile_app/lib/services/cctv_alert_notification.dart
Uban/mobile_app/lib/services/api_service.dart（CCTV / alert 相關方法）
uban-api/services/socket_app.py
uban-api/services/call_security.py
uban-api/services/yolo_alert_dispatcher.py
uban-api/services/monitor_identity.py
uban-api/routers/alert.py
uban-api/routers/pairing.py
uban-api/routers/user.py（has-comm-device 端點）
```

### 0.2 三條最容易犯的錯

| # | 錯誤 | 後果 |
|---|------|------|
| 1 | 看到某段程式碼「多餘」「重複」「可以簡化」就刪掉 | 本子系統的多層兜底**是刻意設計的**，每一層都對應一個真機回報的故障。單點刪除必然回歸。 |
| 2 | 只改單邊（只改前端或只改後端） | 有效期、`isVideoCall`、`senderRole`、FCM `type` 都是**全鏈路契約**，改一端就對不上。 |
| 3 | 相信舊文件的敘述而不看程式碼 | 歷史文件有數處與程式碼不符，見 §7.3「已知的文件錯誤」。**以程式碼為準。** |

### 0.3 修改流程（強制）

1. 讀 §7 護欄，確認你要改的東西不在裡面。
2. 若在裡面 → 讀該護欄指向的完整鏈路，確認你能同步改完**整條**鏈路，否則不要動。
3. 改完跑 §9 的驗證指令。
4. 在 §8 補一筆修復記錄（日期、根因、檔案、修復）。
5. 若你發現本文件與程式碼不符 → **修本文件**，並在 §7.3 記一筆。
6. 若改到「連接／跳轉」語意（Socket 事件、REST 端點、FCM 欄位、跳轉路由、模組間呼叫關係）
   → **同步更新 `Uban/graphify-out/` 與 `uban-api/graphify-out/`**（2026-08-11 新增鐵律，見 §10.3）。

### 0.4 本文件不管轄的範圍

AI 對話、Pinecone 長期記憶、新聞爬蟲、遊戲、寵物、TTS/STT、`routers/ai.py` 的 `POST /webrtc/offer`（**那是 AI 語音橋接，與人對人通話完全不同路，別混淆**）。這些請看各自的 `CLAUDE.md`。

---

## 1. 系統概觀

### 1.1 雙軌制（最重要的架構前提）

信令與媒體走**實體上分離的兩台主機**，永遠不可合併：

| 軌 | 用途 | 主機 | 協定 |
|----|------|------|------|
| 1 — 信令 | SDP／ICE 文字交換 | Tailscale Funnel → 本地 Fedora FastAPI | TCP / WSS |
| 2 — 媒體 | 音視訊中繼 | Oracle Cloud Coturn（日本） | UDP |

**為什麼**：相機權限需要 HTTPS；Tailscale Funnel 提供免費 HTTPS 但**只支援 TCP**；即時視訊需要 UDP，而 UDP 需要專屬公網 IP（Oracle Cloud）。

服務位址：

| 服務 | 位址 |
|------|------|
| 信令 | `https://localhost-0.tail5abf5e.ts.net` |
| TURN/STUN | `turn:152.69.196.5:3478` |
| MySQL | `100.73.39.14:3306`（Tailscale） |

⚠️ 前端**禁止寫死**這些位址，一律 `--dart-define=SERVER_IP=` / `TURN_SERVER` / `TURN_USER` / `TURN_PASS` 注入。

### 1.2 雙通道來電傳遞

一通來電**同時**走兩條路，任一條到達即可：

```
                    ┌─── Socket.IO ────────────► 前景 APP：APP 內 dialog
後端 on_call_request │
                    └─── FCM (data-only) ──────► 背景／被殺死：CallKit 全螢幕來電
```

- **Socket.IO 是主要通路**（低延遲、雙向）。
- **FCM 是備援**（能穿透背景、被殺死狀態）。
- 兩條路都到達時靠**去重**避免雙重 UI，見 §3.7。

### 1.3 角色差異

| 面向 | 長輩端 `elder` | 家屬端 `family` |
|------|---------------|----------------|
| 通話畫面 | `ElderScreen` | `VideoCallScreen` |
| APP 內來電 UI | `ElderHomeScreen` 的綠色 dialog | `FamilyMainScreen` 的綠色 dialog |
| APP 外來電 UI | CallKit（備援：本地通知） | CallKit（備援：本地通知） |
| 撥出入口 | `FriendsScreen` 的視訊鍵／電話鍵 | 儀表板／互動頁的通話鍵 |
| 裝置模式 | `comm`（通訊機）或 `monitor`（監控機） | 永遠 `comm` |
| 緊急通話 | 接收方（CCTV 自動接聽、強制開鏡頭） | 發起方 |

**硬規則**：長輩端一律進 `ElderScreen`，**絕不可**讓長輩走 `VideoCallScreen`。

### 1.4 三個核心不變式

> 這三條是整個子系統的地基，任何修改都不得違反。

1. **只有真正顯示來電 UI 的通路，才可以宣告共用的去重 token**（`lastProcessedCallId`）。
   違反 → 一條通路「先佔位再什麼都不顯示」，把另一條通路的來電殺掉。（第十四輪問題 2 的根因）

2. **CallKit 是主要來電 UI，本地通知只是 CallKit 原生層失敗時的後備**，兩者必須互斥。
   違反 → 要嘛雙重通知、要嘛完全沒有來電畫面。（第十一／十三輪的根因）

3. **任何跨端欄位（有效期／`isVideoCall`／`senderRole`／FCM `type`）都是全鏈路契約**，
   Socket 通路、FCM 通路、prefs 通路、CallKit `extra` 通路四條路都要帶，且型別要正規化。
   違反 → 只有部分通路正確，故障呈現「有時好有時壞」。

---

## 2. 檔案地圖

### 2.1 前端（`Uban/mobile_app/`）

| 檔案 | 職責 | 關鍵函數／區塊 | 風險 |
|------|------|---------------|------|
| `lib/main.dart` | FCM 背景/前景 handler、CallKit 生命週期、全域導航兜底 | `_firebaseMessagingBackgroundHandler`、`_showFullScreenCallkit`、`_setupCallKitListener`、`_setupForegroundMessaging`、`_setupSignalingListener`、`_showIncomingCallDialog`、`_navigateToVideoCall`、`_checkInitialCall`、`_scheduleAcceptedCallFallback`、`_scheduleExtendedActiveCallsPoll`、`_pollActiveCallsForAccepted`、`_sendDeclineEvent`、`_claimCallDedupToken`、`_isExpiredCallPayload` | 🔴 **極高** |
| `lib/globals.dart` | 跨 isolate／跨畫面的全域狀態橋 | `pendingAcceptedCall`、`isAppReady`、`appRole`、`kCallValidityMs`、`splashActive`、`safeNavigateBack()`、`parseIsVideoCall()` | 🔴 極高 |
| `lib/services/signaling.dart` | Socket.IO 連線 + WebRTC（**Singleton**） | 見 §2.3 | 🔴 極高 |
| `lib/services/local_call_notification.dart` | CallKit 失敗時的本地通知備援 | `show()`、`cancel()`、`consumeLaunchPayload()`、`_handleDecline()`、`_persistTapAsAccepted()`、`notificationBackgroundTapHandler` | 🔴 極高 |
| `lib/services/api_service.dart` | HTTP 層；通話與監控相關 | `declineCall(roomId, senderId, callId)`、`pushCctvFrame()`、`triggerTestFall()`（回 `String?`）、`checkAudioBridge(alertId,{userId})`、`_deviceTokenHeader`（`X-Uban-Device-Token`） | 🟡 中 |
| `lib/services/cctv_alert_notification.dart` | YOLO／測試跌倒警報的高優先級通知（**獨立 channel**，與來電備援分開） | `show()` | 🟠 中高 |
| `lib/screens/video_call_screen.dart` | **家屬端**通話畫面 | `_initCall()`、`_toggleCamera`、`_toggleMic`、`_switchCamera`、`_toggleSpeaker`、`_safeHangUp`、`_goHomeAfterCall()`、`_showCallRejectedThenGoHome()` | 🔴 極高 |
| `lib/screens/elder_screen.dart` | **長輩端**通話畫面（含 CCTV 模式） | `_makeCall()`、`_checkPendingAcceptedCall()`、`_toggleCamera`、`_toggleMute`、`_switchCamera`、`_hangUp`、`_exitCCTVMode`、`_activeCallId` | 🔴 極高 |
| `lib/screens/elder_home_screen.dart` | 長輩主畫面；APP 內來電 dialog | `_onPendingCallChanged`、`_restoreSignalingCallbacks`、`_requestPermissions`（全螢幕權限引導） | 🔴 高 |
| `lib/screens/family_main_screen.dart` | 家屬主畫面；APP 內來電 dialog、裝置上下線、**CCTV 跌倒警報呈現** | `_checkPendingAcceptedCall`、`onElderDevicesUpdate`（2.5s 單向確認，見 G40）、`_isDeviceOnline`、`_knownAlertKeys`、`_cctvAlertDialogOpen`、`_alertTts`、`_offlineConfirmTimer` | 🔴 高 |
| `lib/screens/splash_screen.dart` | 冷啟動導航；接聽兜底最終防線 | `_navigateToNext()`、`_navigateFamilyHome()`、`_isPendingRoleReversed()` | 🔴 高 |
| `lib/screens/friends_screen.dart` | **長輩端撥出入口**（`isVideoCall` 的唯一來源） | `_startCall(friendName, {required bool isVideo})` | 🟡 中 |
| `lib/screens/camera_screen.dart` | 家屬端觀看監控畫面 | 建構子 `CameraScreen({required roomId})` | 🟡 中 |
| `lib/screens/device_selection_screen.dart` | 多裝置時選擇撥打對象 | `_initiateNormalCall()`（帶 `skipCallRequest`） | 🟡 中 |
| `lib/screens/monitor_pairing_screen.dart` | 監控機配對 | — | 🟡 中 |
| `lib/screens/elder_pairing_display_screen.dart` | 長輩配對碼顯示 + 快速登入 | `_quickLoginSameElder()` | 🟡 中 |
| `lib/screens/elder_tabs/elder_profile_tab.dart` | 長輩端登出 | `_handleLogout()`（**不可清 `last_elder_*`**） | 🟡 中 |
| `lib/screens/family_dashboard_view.dart` / `family_dashboard_screen.dart` | 家屬儀表板通話入口 | 多處 `VideoCallScreen(...)` | 🟢 低 |
| `lib/screens/family/family_interaction_tab.dart` | 家屬互動頁：通話入口、**監視機清單／「觀看 CCTV」／警報語音橋** | `_syncAudioBridgeForAlerts`、`_buildAudioBridgeButton`、`VideoCallScreen(..., returnByPop: true)` | 🟠 中高 |
| `lib/screens/family/ai_hub_screen.dart` | 家屬互動頁通話入口 | 多處 `VideoCallScreen(...)` | 🟢 低 |
| `lib/screens/role_selection_screen.dart` | 角色選擇 → 長輩畫面 | 三處 `ElderScreen(...)` | 🟢 低 |
| `lib/screens/socketio_test_screen.dart` | 測試畫面 | — | ⚪ 可忽略 |
| `android/app/build.gradle.kts` | **core library desugaring**（`flutter_local_notifications 18.x` 必需） | `isCoreLibraryDesugaringEnabled` | 🔴 高（移除會 build 失敗） |
| `android/app/src/main/AndroidManifest.xml` | 權限、`launchMode=singleTask` | `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`、`USE_FULL_SCREEN_INTENT` | 🔴 高 |

> ⚠️ `lib/main.dart.bak` 是備份檔，**不是**現行程式碼。搜尋結果出現它時請忽略。

### 2.2 後端（`uban-api/`）

| 檔案 | 職責 | 關鍵區塊 | 風險 |
|------|------|---------|------|
| `services/socket_app.py` | Socket.IO 信令 + FCM 推播 **（全部通話/監控後端邏輯都在這）** | 見 §2.4 | 🔴 **極高** |
| `main.py` | FastAPI 入口；`GET /api/call_history`(682)、`POST /api/call/decline`(698) | `api_decline_call` | 🟡 中 |
| `routers/pairing.py` | 配對；`POST /monitor_setup`、`POST /monitor_setup/resolve` 為監控機專用 | — | 🟡 中 |
| `routers/user.py` | `GET /elder/{elder_id}/has-comm-device`(251) — **裝置角色判定的唯一依據** | — | 🔴 高 |
| `routers/alert.py` | `/api/alerts` 與 `/api/cctv`：警報清單／確認、音訊橋接、影格推送、**跌倒測試** | `get_alerts`、`acknowledge_alert`、`open_audio_bridge`、`check_audio_bridge`、`push_cctv_frame`、`trigger_test_fall` | 🟠 中高 |
| `services/call_security.py` | **通話／監控的共用授權守衛**（REST 與 Socket 兩條路共用） | `test_fall_enabled()`、`ingest_token_ok()`、`elder_exists()`、`is_user_linked_to_elder()`、`get_alert_context()`、`is_device_of_elder()` | 🟠 中高 |
| `services/yolo_alert_dispatcher.py` | 跌倒警報派送（YOLO 與測試鈕共用） | `dispatch()`、`_insert_alert()`（**UPSERT，沿用 alert_id**）、`_build_push_payload()`、`_get_connected_family()`、`_get_family_fcm_tokens()` | 🟠 中高 |
| `services/monitor_identity.py` | 監視機 `device_id` 計算 | `monitor_device_id(elder_id, device_name)` = `crc32("elder_id|name") & 0x7FFFFFFF` | 🟡 中 |
| `tests/test_call_signaling.py` | 通話信令回歸測試（目前 15 passed） | — | 🟡 中 |
| `.env` / `.env.example` | `CCTV_TEST_FALL_ENABLED`、`CCTV_INGEST_TOKEN`（見 §6.10） | — | 🟠 中高 |

> ⚠️ **路徑更正**：後端 socket 檔的實際路徑是 **`uban-api/services/socket_app.py`**。
> 歷史文件寫成 `uban-api/uban-api/services/socket_app.py` 或 `Uban/uban-api/services/socket_app.py` 都是**錯的**。

### 2.3 `signaling.dart` 公開介面

**Singleton — 永遠不可 `Signaling()` 建第二個實例。**
`--dart-define` 常數：`SERVER_IP` / `TURN_SERVER` / `TURN_USER` / `TURN_PASS`（禁止寫死）。

| 類別 | 成員 |
|------|------|
| typedef | `StreamStateCallback`、`IncomingCallCallback`、`ErrorCallback`、`CallRequestCallback(roomId, senderId, callId, [senderName])`、`CallAcceptedCallback` |
| 去重／失效 | `lastProcessedCallId`、`lastProcessedCallTime`、`_invalidCallIds`、`isCallInvalidated(callId)`、`invalidateCallId(callId)`、`_isExpiredCallPayload(data)` |
| 視訊/語音旗標 | `incomingCallIsVideoCallId`、`incomingCallIsVideo`、`isVideoCallFor(callId)` |
| 連線 | `connect()`、`reconnect()`、`_asyncJoin()`、`_registerSocketListeners()`、`_emitJoin()`、`joinRoom()`、**`forceDisconnect()`**、`updateAppForeground()`、`_setupTokenMonitor()` |
| 信令送出 | `sendCallRequest(room,{role,callId,targetId,isVideoCall})`、`sendCallAccept(targetSocketId,{callId})`、`sendCallBusy(targetSocketId,{callId,room})`、`sendCancelCall(room,{role})`、`sendEmergencyCall(room,{targetId,callId,role})`、`sendDeleteDevice(room,targetId)`、`sendGetElderDevices(roomId)` |
| WebRTC | `_createPeerConnection()`、`createOffer()`、`startMonitoring(targetId)`、`_acceptCall()`、`_processCandidateQueue()`、`_generateDynamicTURNConfig()`、`openUserMedia(renderer,{videoEnabled})`、`hangUp()`、`stopMedia()`、`clearSession()`、`_closePeerConnection()` |
| 連線品質（第十七輪） | **`onPeerConnected`**（ICE 真正連通，取 `onConnectionState` ∪ `onIceConnectionState`，見 G37）、**`onPeerConnectionFailed(String reason)`**、**`_startMediaWatchdog()`** / `_mediaWatchdogTimer`（12s 檢查 `inbound-rtp.bytesReceived`，見 G38） |
| 其他 | `enableSpeakerphone()`、`sendHeartbeat()`、`pushContent()`、`listenToElderChat()`、`listenToMedicationConfirmation()` |

> **`forceDisconnect()` vs `disconnect()`**：一律用 `forceDisconnect()`。`disconnect()` 會讓 socket 徹底斷開並失去 FCM 接收能力。

### 2.4 `socket_app.py` 結構

**事件 handler**（`@sio.on`）：

| 行 | handler | 事件 |
|----|---------|------|
| 859 | `connect` | 連線 |
| 978 | `on_join` | `join` |
| 1152 | `on_update_fcm_token` | `update-fcm-token` |
| 1195 | `on_client_state` | `client-state` |
| 1257 | `on_get_elder_devices` | `get-elder-devices` |
| 1268 | `on_disconnect` | `disconnect` |
| **1372** | **`on_call_request`** | `call-request` |
| 1603 | `on_cancel_call` | `cancel-call` |
| 1666 | `on_emergency_call` | `emergency-call` |
| 1833 | `on_call_accept` | `call-accept` |
| 1866 | `on_call_busy` | `call-busy` |
| 1931 / 1945 / 1956 | `on_offer` / `on_answer` / `on_candidate` | WebRTC 信令 |
| 1966 | `on_end_call` | `end-call` |
| 2025 | `on_delete_device` | `delete-device` |
| 2083 | `on_cctv_alert_ack` | `cctv-alert-ack` |
| 2109 | `on_audio_bridge_request` | `audio-bridge-request` |

**內部輔助函數**：

| 行 | 函數 | 用途 |
|----|------|------|
| 38 | `init_db_tables` | 建立 `user_fcm_token` 等表 |
| 149 / 152 | `_is_foreground` / `_is_socket_active_and_foreground` | 判斷 socket 前景狀態 |
| 164 | `_utc_ms_now` | 產生 `issuedAt` 用的毫秒時戳 |
| 167 | `_matches_target` | 比對 `targetId`（可為 sid 或 token） |
| **177** | **`_resolve_elder_user_id`** | 由 `elder_id` 走 `elder_profile` 反解 `user_id`；**不做 int 短路**（護欄 #20） |
| 200 | `_get_family_ids_for_elder` | 由 `family_elder_relationship` 取家屬清單 |
| **254** | **`_get_target_sockets_and_tokens`** | 主要目標查詢：在線 socket + 離線 token |
| **429** | **`_get_all_known_fcm_tokens`** | Layer C：所有已知 token（記憶體+DB），**不做在線過濾** |
| 537 | `_parse_room_id` | 解析 `comm_elder_X` / `monitor_elder_X` |
| 570 | `_verify_room_access` | 房間存取授權 |
| 629 / 739 / 811 | `_get_elder_devices_list` / `_broadcast_elder_devices_update` / `_push_elder_devices_update` | 裝置清單 |
| 761 | `has_comm_elder_device` | 是否已有通訊機（**只認在線 socket**，護欄 #19） |
| 819 | `_purge_stale_reverse_mode_token` | 清除反向模式殘留 token（護欄 #18） |
| 875 / 878 | `_ip_hash` / `_fcm_token_hash_short` | 日誌用雜湊 |
| 881 / 918 / 934 / 957 | `_get_monitor_device_limit` / `_count_active_monitor_devices_for_elder` / `_count_monitor_devices_for_ip` / `_cleanup_monitor_ip_on_disconnect` | 監控機數量與 IP 限制 |
| 1324 | `_resolve_user_id_int` | 一般 user_id 解析（**不可**拿來解 elder_id） |
| 1340 | `_get_caller_name` | 解析來電者顯示名稱 |
| 784 | `push_pond_leaf` | 記憶落葉推播（**不屬本文件管轄**） |

---

## 3. 資料契約

### 3.1 Socket.IO 事件

#### 通話核心事件

| 事件 | 方向 | payload | 後端 handler | 前端處理 |
|------|------|---------|-------------|---------|
| `join` | C→S | `room`、`role`、`deviceName`、`deviceMode`（`comm`/`monitor`/`listener`）、`userId`、`fcmToken`、`appState`(`foreground`/`background`) | `on_join`:978 | `signaling.dart::_emitJoin`:607 |
| `join-failed` | S→C | `message` | — | `signaling.dart` `on('join-failed')` |
| `update-fcm-token` | C→S | `room`、`token` | `on_update_fcm_token`:1152 | `signaling.dart`:625 |
| `client-state` | C→S | `appState` | `on_client_state`:1195 | `signaling.dart::updateAppForeground`:646 |
| **`call-request`** | C→S | `room`、`role`、`callId`、`issuedAt`、`expiresAt`、`targetId`(選)、`callerUserId`、`senderName`(選)、**`isVideoCall`（字串）** | `on_call_request`:1372 | `signaling.dart::sendCallRequest`:661 |
| **`call-request`** | S→C | `senderId`、`room`、`role`、`callId`、`issuedAt`(str)、`expiresAt`(str)、`senderName`、`callerName`(相容)、**`isVideoCall`（原值透傳）** | 送出於 :1496 | `signaling.dart` `on('call-request')`:240 |
| `call-accept` | C→S→C | C→S: `targetId`、`callId`；S→C: `accepterId`、`callId` | `on_call_accept`:1833（emit :1863） | `sendCallAccept`:693 |
| `call-busy` | C→S→C | C→S: `targetId`、`callId`；S→C: `targetId`、`callId`、`message`(選) | `on_call_busy`:1866（emit :1902） | `sendCallBusy`:707 |
| `cancel-call` | C→S→C | C→S: `room`、`role`、`callId`；S→C: `senderId`、`room`、`callId` | `on_cancel_call`:1603（emit :1630/:1904/:2000） | `sendCancelCall`:723 |
| `end-call` | C→S→C | C→S: `room`、`targetId`、`callId`；S→C: `room`、`callId`、`senderId` | `on_end_call`:1966（emit :1999） | `hangUp`:1040 |
| **`emergency-call`** | C→S | `room`、`role`、`callId`、`issuedAt`、`expiresAt`、`targetId`(選)、`callerUserId`、`senderName`(選) | `on_emergency_call`:1666 | `sendEmergencyCall`:739 |
| **`emergency-call`** | S→C | `senderId`、`room`、`callId`、`role`、`senderName`、`callerName`、**`issuedAt`／`expiresAt`（2026-08-11 第二十二輪新增）** | emit :1738 | `signaling.dart` `on('emergency-call')` |
| `offer` | C→S→C | 整包透傳（含 `room`、`targetId`、SDP） | `on_offer`:1931 | `signaling.dart`:952/987 |
| `answer` | C→S→C | 同上 | `on_answer`:1945 | `signaling.dart`:785 |
| `candidate` | C→S→C | 同上 | `on_candidate`:1956 | `signaling.dart`:883/886 |

> ⚠️ `offer`/`answer`/`candidate` **必須** `to=target_sid` 精準轉發，**禁止廣播**。
> `on_offer`:1941 有一條 `room=room, skip_sid=sid` 的廣播退路，僅在無 `targetId` 時觸發——**新程式碼絕不可依賴它**。

> **`Signaling.lastEmergencyMeta`（2026-08-12 第二十三輪新增）** — `Map<String, String>`，
> 鍵為 `role` / `issuedAt` / `expiresAt`。`emergency-call` 的 S→C payload 帶得比
> `CallRequestCallback(roomId, senderId, callId, [senderName])` 的簽章塞得下的多，
> 而改簽章會牽動全部註冊點。`signaling.dart` 因此在**呼叫 `onEmergencyCall` 之前**先寫入這個欄位，
> `main.dart::s.onEmergencyCall`（:1807）緊接著讀取。
> ⚠️ 這是**與 `callId` 同步寫入的純資料欄位，不是狀態旗標**——`Uban/CLAUDE.md` §3.2 的
> 「不要在 `Signaling` singleton 新增顯示狀態全域旗標」（`isIncomingCallDialogVisible` 事件）
> 約束的是後者。讀不到時退回空 Map，消費端視同「無有效期資訊」，行為與舊版相同。

#### 監控／裝置事件

| 事件 | 方向 | payload | 後端 | 說明 |
|------|------|---------|------|------|
| `get-elder-devices` | C→S | `room`（字串直傳，非 dict） | `on_get_elder_devices`:1257 | 請求裝置清單 |
| `elder-devices-update` | S→C | 裝置陣列 | `_broadcast_elder_devices_update`:922（emit :940）／`on_get_elder_devices` 直回 :999 | join(:1333)、delete-device(:1464)、force-logout(:1548)、**disconnect(:1628)**、改名(:2467) 都會廣播。~~只在 join 時廣播~~ 是舊文件的錯誤記載，見 §6.6 |
| `monitor-renamed` | S→該監視機 | `{elderId, oldDeviceName, newDeviceName, deviceId}` | `routers/pairing.py`:398 | 家屬端改名後推送；監視機收到後更新畫面標籤與 `saved_device_name`。與 `elder-devices-update` 同時發出。見護欄 **G57** |
| `monitor-removed` | S→該監視機 | `{elderId, deviceName, deviceId}` | `routers/pairing.py`:359 | **第二十輪新增**（需求 4）。家屬端刪除監視器後推送；監視機收到即 `SessionManager.releaseSession()` → 導回身分選擇畫面。🚫 **必須在 `sio.disconnect(kick_sid)` 之前 emit**，見護欄 **G65**。前端 `signaling.dart::onMonitorRemoved`:96（listener :501），註冊點只有 `elder_screen.dart`:697（`isCCTVMode` 分支內） |
| `delete-device` | C→S | `room`、`targetId` | `on_delete_device`:2025 | 家屬端移除長輩裝置；會對被踢裝置發 `force-logout` |
| `force-logout` | S→C | `{}` | emit :2053（另有 FCM :2064） | 遠端強制解綁 |
| `user-joined` / `user-left` / `user-state-changed` | S→C | `id`、`role` 等 | :1139/:1275/:1241 | 房內成員變動 |
| `cctv-alert-ack` | C→S | `alert_id`、`user_id` | `on_cctv_alert_ack`:2083 | 回應 YOLO 告警；回 `cctv-alert-ack-success/failed` |
| `audio-bridge-request` | C→S | — | `on_audio_bridge_request`:2109 | 回 `audio-bridge-response` |

#### 不屬本文件管轄

`heartbeat-message`、`new-pond-leaf`、`send-heartbeat`、`push-content`、`request-elder-chat`、`elder-chat-update-$elderId`、`medication-confirmed-$elderId` — 屬 AI／關懷推播子系統。

### 3.2 FCM 推播 payload

> ⚠️ **通話類 FCM 一律是 data-only**（**不可**含 `notification` 區塊）。
> 含 `notification` 的訊息在 Android 背景／被殺死時會被系統匣直接接管，
> Flutter 的 `_firebaseMessagingBackgroundHandler` **不會被觸發** → CallKit 不會響鈴。

#### `call-request`（`socket_app.py`:1532-1563）

| 欄位 | 值 | 說明 |
|------|-----|------|
| `type` | `'monitor-wakeup' if deviceMode=='monitor' else 'call-request'` | ⚠️ 見 §6.4，這一行是「長輩被殺死收不到來電」的根因所在 |
| `senderId` | 發起端 sid | |
| `roomId` | `comm_elder_X` / `monitor_elder_X` | 注意 Socket 通路叫 `room`，FCM 通路叫 `roomId` |
| `role` | `str(sender_role)` | 發起方角色，前端存成 `senderRole` |
| `callId` | UUID | |
| `issuedAt` / `expiresAt` | `str(ms)`，`expiresAt = issuedAt + 60000` | **2026-08-11 第二十二輪：120000 → 60000**，見 G73 |
| `callerName` / `senderName` | 來電者顯示名稱（兩個欄位同值，向後相容） | |
| **`isVideoCall`** | `str(data.get('isVideoCall', True))` | ⚠️ Python `str()` → `"True"`/`"False"`，見 §3.6 |
| `callerUserId` | `str(caller_user_id)` 或 `''` | 供接收端過濾「自己發起的來電」 |
| **ttl** | `datetime.timedelta(seconds=60)` | 與 `expiresAt` 對齊。**2026-08-11 第二十二輪：120 → 60**，讓 FCM 自己在 60 秒後丟棄未送達的來電，見 G73 |
| APNS | `apns-priority: 10`、`apns-push-type: background`、`content_available: True` | |

#### `emergency-call`（`socket_app.py`:1772-1799）

| 欄位 | 值 | 說明 |
|------|-----|------|
| `type` | `'monitor-wakeup' if deviceMode=='monitor' else 'emergency-call'` | |
| `senderId` / `roomId` / `callId` | 同上 | |
| `callerName` / `senderName` | 同上 | |
| `isEmergency` | `'true'` | |
| `callerUserId` | 同上 | |
| **ttl** | `datetime.timedelta(seconds=60)` | ⚠️ **2026-08-11 第二十二輪：3600 → 60**。舊值代表一通緊急通話最久可以在 1 小時後才彈出來電，正是使用者回報的「延遲來電通知」最極端案例。見 **G22（已改寫）** 與 **G73** |
| **`issuedAt` / `expiresAt`** | `str(ms)`，`expiresAt = issuedAt + 60000` | ⚠️ **2026-08-11 第二十二輪新增**。這推翻了 G22 原本「緊急刻意不帶」的設計，改帶之後前端 60s 過期判斷會生效——**這正是要的**，見 G73 的取捨說明 |
| **無 `role`** | — | ⚠️ 見 §7.3 已知缺口 |
| **無 `isVideoCall`** | — | 緊急通話一律視訊 |

#### `cctv-alert`（`services/yolo_alert_dispatcher.py`:68-95）— 跌倒／異常警報

> 這條**不是通話**，是監控子系統的警報推播（YOLO 偵測與「跌倒測試」鈕共用同一條派送路徑）。
> Socket 通路事件名同為 `cctv-alert`，payload 由同檔的 `_build_push_payload()` 產生。

| 欄位 | 值 | 說明 |
|------|-----|------|
| `type` | `'cctv-alert'` | 前端在 `main.dart`:122（BG）與 :1439（FG）分流；**必須排在通話型別白名單之前** |
| `elderId` | `str(elder_id)` | 原始（未加前綴）長輩 ID |
| `deviceId` | `str(device_id)` | 監視機的 `monitor_device_id`（見 §6.9） |
| `alertType` | `'fall'` / `'prolonged_inactivity'` / `'lying_down'` / `'crawl'` | |
| `alertId` | `str(alert_id)` | ⚠️ **會被重複沿用**，見下 |
| `confidence` | `str(round(confidence, 3))` | |
| **`timestamp`** | `str(int(utcnow().timestamp()))` | ⚠️ **去重的關鍵欄位** |
| priority | `android=AndroidConfig(priority='high')`、APNS `content_available` | 無 `notification` 區塊（同 G33） |

> 🚫 **`alertId` 單獨不可作為去重鍵**：`_insert_alert()` 對「同 elder + 同 device + 同 alert_type
> 且 `status='active'`」的既有列是 **UPDATE `detected_at` 並沿用原本的 `alert_id`**。
> 只用 `alertId` 去重，第二次以後的同類警報會**完全靜默**
> （「跌倒測試」鈕按第二次沒反應，YOLO 連續偵測也一樣）。
> 家屬端因此用 **`"a$alertId@$timestamp"` 複合鍵**（`family_main_screen.dart::_knownAlertKeys`）。
> 後端若要改掉 UPSERT 語意，必須同步改前端這個鍵。

#### `cancel-call`（:1634 / :1908 / :2004）

`type='cancel-call'` + `roomId` + `callId` 等；**ttl = 10 秒**（取消訊息過期就沒意義）。
分別由 `on_cancel_call`、`on_call_busy`、`on_end_call` 三處發出。

#### `force-logout`（:2064）

`type='force-logout'`、`roomId`；`priority='high'`。

### 3.3 SharedPreferences 鍵位

#### 通話狀態鍵（**這三個必須同進同退**）

| 鍵 | 寫入 | 讀取 | 清除 | 生命週期 |
|----|------|------|------|---------|
| `pendingAcceptedCall` | `main.dart`:185（BG emergency）、:416（BG CallKit accept）、:1588（FG CallKit accept）、`local_call_notification.dart::_persistTapAsAccepted` | `main.dart`:525（冷啟動）、:1137（resume） | :124、:400、:1141、:1832 | 「使用者已接聽」→ 待導航 |
| `pendingRingCallData` | `main.dart`:216（BG 長輩 call-request）、:248（BG 家屬 call-request）、:428（accept 時更新 `isAccepted:true`） | :555 | :125、:401、:1833 | 「正在響鈴」預寫，防 accept 事件遺失 |
| `pendingRingCall` | ⚠️ **`main.dart` 中無任何寫入點** | — | :126、:402、:1834 | **遺留鍵**，只被清除。歷史文件說它是預寫鍵是**過時的**（現行是 `pendingRingCallData`） |

> **拒接／取消時三個鍵必須一起清**（護欄 #15）。殘留 `pendingRingCallData` 會讓下次冷啟動 `main()` 誤重建 pending → 假來電／角色反轉。

#### 緊急通話鍵

| 鍵 | 說明 |
|----|------|
| `pending_emergency_room` / `pending_emergency_sender` | `elder_screen.dart`:130-139 讀取後立即 remove |

#### 裝置角色鍵（**監控子系統的權威來源**）

| 鍵 | 說明 |
|----|------|
| `saved_is_cctv` | **本機權威旗標**：`false` = 通訊機、`true` = 監控機。`monitor-wakeup` 正規化靠它（護欄 #18） |
| `device_role_$room` | 每個房間各自的裝置角色 |
| `saved_role` / `saved_id` / `saved_device_name` | 登入 session |
| `elder_room_id` | 長輩房間 ID |

#### 快速登入記憶鍵（**登出不清除**，護欄 #26）

`last_elder_id` / `last_elder_name` / `last_elder_room_id` / `last_elder_device_role`

> 只有家屬端遠端 `force-logout`（強制解綁）才連同清除。
> `_quickLoginSameElder` 回退時**必須一併還原 `device_role_$room` 與 `saved_is_cctv`**，
> 否則會重新 `hasCommDevice` 重判角色，誤判成 monitor 就觸發 §6.4 的整條 bug 鏈。

#### session 鍵

`caregiver_id`、`caregiver_name`、`user_id`、`user_role`、`user_name`、`selected_elder_id`、`selected_elder_name`、`selected_elder_room_id`、`access_token`

> ⚠️ `elder_profile_tab::_handleLogout` 會 remove `caregiver_id`/`caregiver_name`——這正是引入 `last_elder_*` 的原因。

**權威清單在 `lib/services/session_manager.dart`:18 的 `_sessionKeys`（2026-08-11 第二十輪，需求 1／5）**

該常數是「登出／換身分時必須清掉什麼」的唯一定義，涵蓋上列 session 鍵
再加 `user_role`／`saved_role`／`saved_id`／`saved_device_name`／`saved_is_cctv`／
`elder_room_id`／`last_elder_*`／三個 pending 通話鍵，另外掃掉所有 `device_role_*`。

- `releaseSession()`（:38）：通知後端 → `Signaling().clearSession()` + `forceDisconnect()`
  → 逐鍵 remove → `appRole = null`。
- `releaseIfBound()`（:96）：只在真的殘留 session 鍵時才做，回傳有無釋放；
  `identification_screen.dart`:26 於 `addPostFrameCallback` 呼叫。
- 🚫 **禁止改用 `prefs.clear()`**：那會一併清掉 `wake_word_enabled` 等裝置偏好，
  以及 FCM／通知相關的非 session 鍵。見護欄 **G58**。

#### 裝置偏好鍵（**與帳號無關，登出不清除**）

| 鍵 | 說明 |
|----|------|
| `wake_word_enabled` | `globals.dart`:32 的 `kWakeWordEnabledKey`，**預設 `false`**。長輩端「🎙️ 語音喚醒（免持呼叫 AI）」開關，記憶體鏡像是 `wakeWordEnabledNotifier`（:29）。**刻意不列入 `_sessionKeys`**——它是這台機器的偏好，不是誰登入的狀態。見護欄 **G59** |

### 3.4 `pendingAcceptedCall` 欄位契約

型別 `Map<String, String?>`（**注意**：從 prefs 讀出的 `Map<String, dynamic>` 必須轉型，否則執行期爆型別錯誤）。

| 欄位 | 意義 | 寫入者 | 消費者用途 | 缺漏後果 |
|------|------|--------|-----------|---------|
| `roomId` | 房間 ID | 全部路徑 | 建構通話畫面 | **必壞**，無法進房 |
| `senderId` | 發起端 socket id | 全部路徑 | `sendCallAccept(targetId)` | 接聽送不出去，發起方一直等 |
| `callId` | 通話 UUID | 全部路徑 | 去重、失效標記、`isSameOngoingCall` | 去重全失效 → 重複 dialog／緊急通話被自己掛斷 |
| **`senderRole`** | 發起方角色 | BG:180/223/255、CallKit:422/435、FG:1585、:1757 | **三個消費端驗證 `senderRole != appRole`** | **角色反轉**：接收方變發起方（護欄 #16） |
| `callerName` | 來電者顯示名 | BG:222/254、:434、:1756 | dialog 標題 | 顯示「未知來電」 |
| `issuedAt` / `expiresAt` | 有效期 | **全部路徑，緊急也要**（2026-08-11 第二十二輪起） | 消費前 **60s** 過期判斷 | 冷啟動時舊來電被再次接起 |
| **`timestamp`** | **本機**寫入時刻（ms） | **全部路徑，緊急也要**（BG:236、備援:218、CallKit accept:477、`s.onEmergencyCall` ~:1682） | `main()`:599 與 `_checkPendingCallFromSharedPreferences`:1249 的新鮮度判斷（60s／`pendingRingCallData` 120s） | **這筆 prefs 永生**：缺 `timestamp` 時舊寫法的 `ts != null && age > 窗口` 恆 false → 每次冷啟動都載入同一通死掉的通話 → **APP 永久白屏**（第二十一輪需求 4）。見 **G67** |
| **`isVideoCall`** | 視訊/語音 | :225/257、:349、:423/436、:1256、:1337、:1758 | `VideoCallScreen(isVideoCall:)` 決定鏡頭初始狀態 | 語音通話會開鏡頭（退化為預設 true） |
| `isEmergency` | 緊急通話標記 | :177、:1584、:1883、:1932 | 走緊急分支（強制視訊、自動接聽） | 緊急通話當一般通話處理 |
| `isAccepted` | 僅 `pendingRingCallData` 使用 | :226/258（false）、:437（true） | `false` 時**絕不**自動進房 | 響鈴中就自動進房（護欄 #10） |

> ⚠️ **`timestamp` 與 `issuedAt`/`expiresAt` 是兩件不同的事，不要混用**：
> 後者是**後端下發**的通話有效期（**60 秒**，第二十二輪起緊急通話**也帶**，見改寫後的 G24）；
> 前者是**純本機**的「這筆 prefs 是什麼時候寫的」，所有路徑（含緊急）都必須帶。
>
> 讀取端的判斷式必須是 **`if (ts == null || ageMs > 窗口)` → 視為過期並 `prefs.remove(...)`**。
> 「缺 `timestamp` 就當新鮮」是第二十一輪需求 4 的根因；
> 而「讀到過期就移除」這一半是**已中毒裝置的自癒路徑**，比寫入端補欄位更不可省。

### 3.5 房間 ID 規則

```
comm_elder_{elder_id}      ← 雙向通訊房（通訊機）
monitor_elder_{elder_id}   ← 單向監控房（監控機／CCTV）
```

後端 `_parse_room_id`（:537）回傳 `(elder_id, mode)`；若傳入的是純數字字串，會查 `elder_profile WHERE user_id = %s OR elder_id = %s` 反解，回傳 `(elder_id, 'comm')`。

**前端雙重 prefix 防呆**：`elder_screen.dart` 約 66-70 行做房名格式化。
早期 bug 是房名被加了兩次 prefix（`comm_elder_comm_elder_X`）導致後端回 `join-failed: 您無權加入此通訊房間`。**格式化前務必先檢查是否已有 prefix。**

**ID 語意**：
- `elder_id` 是 `elder_profile` 的主鍵。
- `user_id` 是外鍵。
- `room_id` 是**後端為 Socket.IO 造的字串**（`user_fcm_token` / `call_record` 兩表有此欄），不是原始設計的表格欄位。
  → 因此它會「漂移」，這正是第十輪要改用 `user_id` 內容鍵的原因（§6.4）。

### 3.6 ⚠️ `isVideoCall` 型別陷阱

**同一個值經四條通路會變成四種型別：**

| 通路 | 型別 | 實際值 |
|------|------|--------|
| Socket（前端送出） | String | `"true"` / `"false"`（`signaling.dart`:670 用 `.toString()`） |
| Socket（後端透傳） | 原值 | 後端 :1505 `data.get('isVideoCall', True)` 直接透傳 |
| **FCM** | **String** | **`"True"` / `"False"`** ← Python `str(bool)` **首字大寫**（:1543） |
| prefs / CallKit `extra` | String | `"true"` / `"True"` / `"false"` / `"False"` 都可能 |

**因此前端一律用 `globals.dart::parseIsVideoCall()` 正規化：**

```dart
bool parseIsVideoCall(dynamic raw) {
  if (raw == null) return true;
  if (raw is bool) return raw;
  return raw.toString().trim().toLowerCase() != 'false';
}
```

語意：**只有明確為 false 才判定為語音通話**，其餘（含 null、無法解析）一律 `true`（安全預設 = 視訊）。

> 🚫 **嚴禁**寫 `raw != 'false'`、`raw == 'true'` 之類的字面比較——FCM 通路送的是大寫 `"False"`，字面比較會靜默失敗，症狀是「Socket 路徑正常、FCM 路徑失效」的間歇性 bug。

### 3.7 去重機制全表

| 機制 | 位置 | 窗口 | 作用 |
|------|------|------|------|
| `lastProcessedCallId` + `lastProcessedCallTime` | `signaling.dart`:265-273 | **2 秒** | 跨通路共用 token；**只有真正顯示 UI 的通路可以宣告**（核心不變式 1） |
| `_fcmCallIdCache` | `main.dart` | **3 秒** | FCM 通道自己的去重，不影響 Socket |
| **Socket 寬限期** | `main.dart::_setupForegroundMessaging` | **1500ms** | 前景收到 FCM 時先等 Socket；逾時未處理才由 FCM 補 dialog |
| `_invalidCallIds` | `signaling.dart` | 永久 | 收到 `cancel-call`/`call-busy`/`end-call` 後標記失效，延遲抵達的同 callId 直接丟棄 |
| `_isExpiredCallPayload` | `signaling.dart` / `main.dart` | **60s** | 超過 `expiresAt`（或 `issuedAt + kCallValidityMs`）一律忽略。**2026-08-11 第二十二輪：120s → 60s**，見 G73 |
| 自我過濾 | `signaling.dart`:241-249 | — | `senderId == socket.id` 或 `senderRole == _role` 直接丟棄 |
| **`_cancelled_call_ids`（後端）** | `socket_app.py` | **300s**（`_CANCELLED_CALL_TTL_SEC`，上限 500 筆） | **2026-08-11 第二十二輪新增**。`on_cancel_call` 把 callId 記進去；`on_call_request` / `on_emergency_call` 開頭先 `_is_call_cancelled()`，命中就整通不發（Socket 與 FCM 皆不送）。這是**伺服器端**的最後一道「遏止另一端來電通知」防線——前端的 `_invalidCallIds` 只擋得住已經送到的封包，擋不住還沒送出的 |

### 3.8 監控裝置的 REST 端點（2026-08-10 第十九輪）

> 這幾支都在 `routers/pairing.py`，前綴 `/api/pairing`。
> **授權一律走 `services/call_security.py::is_user_linked_to_elder`，無權回 404（G45）。**

| 方法 | 路徑 | 實作 | 說明 |
|------|------|------|------|
| `POST` | `/monitor_setup/resolve` | :88 | 兌換 6 位數配對碼。**必須同步 UPSERT `monitor_device_binding`**（G53）。寫入失敗只記 log、不阻斷配對 |
| `GET` | `/monitor_devices?elder_id=&user_id=` | :138 | 回傳與 `elder-devices-update` **完全相同形狀**的清單（直接呼叫 `_get_elder_devices_list`）。家屬端 `_refreshMonitorDevicesViaHttp()` 每 10 秒打一次，見 §6.6 |
| `DELETE` | `/monitor_device?elder_id=&device_name=&user_id=` | :161 | 刪除監視機。**第十九輪才補上授權**——原本零檢查，任何人知道 `elder_id` + `device_name` 就能刪別人的監視機。同時刪 `monitor_device_binding` 對應列 |
| `PATCH` | `/monitor_device` | :290 | body `{elder_id, user_id, old_device_name, new_device_name}`。**五處儲存必須一起改**，見 **G57** |
| `POST` | `/session/release` | :1218 | **第二十輪新增**（需求 1／5）。body `{user_id?, elder_id?, device_name?, role?}`，全部欄位皆可省略。前端 `SessionManager.releaseSession()` 在清 prefs **之前**呼叫，讓後端一併釋放殘留的 socket／FCM token 綁定。**刻意不做關係驗證**——它只會「解除」不會「取得」任何東西，而且身分選擇頁呼叫它時本來就還沒有身分。失敗一律吞掉、不阻斷前端清理 |

🚫 **`user_id` 缺漏（`None`）也必須回 404**，不可退化成「不帶參數就跳過驗證」。
迴歸鎖：`test_delete_and_rename_monitor_device_reject_unlinked_caller`。

---

## 4. 通話生命週期

> 圖例：`[F]` 家屬端　`[E]` 長輩端　`[S]` 後端　→ Socket　⇢ FCM

### 4.1 家屬撥打長輩 — 長輩在 APP 前景

```
[F] 使用者按通話鍵
     └─ Navigator.push(VideoCallScreen(autoStart: true, ...))
[F] VideoCallScreen._initCall()
     ├─ 輪詢 socket.connected（100 × 100ms，最多 10s）
     ├─ openUserMedia(localRenderer)        ← 必須先取得 localStream
     └─ signaling.sendCallRequest(room, role:'family', isVideoCall: ...)
          │
          →  [S] on_call_request:1372
              ├─ _parse_room_id → (elder_id, mode)
              ├─ _get_target_sockets_and_tokens  ← Layer A：在線 socket + 離線 token
              ├─ Layer B：把在線 socket 自帶的 fcmToken 也併入 fcm_send_map
              ├─ Layer C：_get_all_known_fcm_tokens（記憶體 + DB，不做在線過濾）
              ├─ **_is_call_cancelled(call_id)? → 命中就整通不發**（第二十二輪，G73）
              ├─ 生成 call_id / issued_at / expires_at(+60000)
              ├─ → emit 'call-request' to=每個 target_sid
              └─ ⇢ FCM data-only 給 fcm_send_map 全部 token（ttl=60s）
                    │
[E] Socket 通路（主要，約 200-800ms 先到或後到）
     └─ signaling.dart on('call-request'):240
         ├─ 五道關卡：自我過濾 → 同角色過濾 → _invalidCallIds → 過期 → 2s 去重
         ├─ 寫 lastProcessedCallId / lastProcessedCallTime   ← 宣告去重 token
         ├─ 寫 incomingCallIsVideoCallId / incomingCallIsVideo
         └─ onCallRequest(roomId, senderId, callId, senderName)
              └─ ElderHomeScreen 顯示綠色 dialog

[E] FCM 通路（備援）
     └─ main.dart::_setupForegroundMessaging
         ├─ isResumed == true → 排 1500ms 寬限計時器
         └─ 1500ms 後依序檢查：
              mounted？ / callId == lastProcessedCallId？ / 過期？ / 已失效？
              全部通過才 _claimCallDedupToken + _showIncomingCallDialog
              （= Socket 當次斷線時的補救；Socket 正常時這裡什麼都不做）
```

**為什麼 FCM 常常比 Socket 先到**：後端 `await sio.emit(...)` 只是把 websocket frame 排進佇列，
其後的 `messaging.send()` 是**同步阻塞**呼叫，會卡住 asyncio event loop 使 frame 延後 flush。
→ 這就是第十四輪問題 2 的物理根因，也是 1500ms 寬限期的存在理由。

### 4.2 家屬撥打長輩 — 長輩在背景 / 被殺死

```
[S] 同 4.1，FCM 一定會發（Layer C 保證涵蓋被殺死裝置的 DB token）
     ⇢
[E] main.dart::_firebaseMessagingBackgroundHandler:60
     ├─ WidgetsFlutterBinding.ensureInitialized() + Firebase.initializeApp()
     ├─ type == 'monitor-wakeup' → 讀 saved_is_cctv 正規化（§6.4）
     ├─ 過期檢查 _isExpiredCallPayload
     ├─ 預寫 prefs['pendingRingCallData'] = {... isAccepted:false ...}
     └─ await _showFullScreenCallkit(message.data)          ← 護欄 #22：必須走這裡
          ├─ 組 CallKitParams（含 extra: roomId/senderId/callId/senderRole/isVideoCall/...）
          ├─ FlutterCallkitIncoming.showCallkitIncoming(params)   ← 射後不理，無回傳值
          ├─ 註冊背景 isolate 的 bgSub listener（拒接／逾時 → HTTP declineCall）
          └─ ★ 互斥探測（必須在 bgSub 之後）
               ├─ 第一段：每 250ms × 8 次（2.0s）探 activeCalls()
               │    └─ 任一次非空 → CallKit 存活 → LocalCallNotification.cancel() → 結束
               ├─ 全空 → LocalCallNotification.show(data)      ← 備援
               └─ 第二段：每 250ms × 6 次（1.5s）→ CallKit 事後出現則 cancel 備援
```

**兩條接聽路徑（互斥）**：

| 路徑 | 接聽事件 | 寫 pending 的位置 |
|------|---------|------------------|
| CallKit | `actionCallAccept` | 背景 isolate `main.dart`:416 / 主 isolate `_setupCallKitListener`:1588 |
| 本地通知備援 | 通知本體 tap（`showsUserInterface: true`） | `local_call_notification.dart::_persistTapAsAccepted` → 由 `consumeLaunchPayload()` 於 `main()` 讀出 |

### 4.3 長輩撥打家屬（含視訊／語音分流）

```
[E] FriendsScreen 按「視訊」或「電話」
     └─ _startCall(name, isVideo: true/false)
         └─ Navigator.push(ElderScreen(roomId, deviceName, autoCall:true, isVideoCall: isVideo))
[E] ElderScreen.initState
     ├─ 依 widget.isVideoCall 設 _isCameraOff
     └─ autoCall → _makeCall()
         └─ sendCallRequest(_formattedRoomId, role:'elder', isVideoCall: widget.isVideoCall)
              → [S] → ⇢
[F] 收到後：
     APP 內   → FamilyMainScreen dialog → 接聽 → VideoCallScreen(isVideoCall: _signaling.isVideoCallFor(callId))
     APP 外   → CallKit → 接聽 → pending['isVideoCall'] → VideoCallScreen(isVideoCall: parseIsVideoCall(...))
[F] VideoCallScreen._initCall()
     └─ if (!widget.isVideoCall) { _isCameraOff = true; videoTrack.enabled = false; }
        ★ 仍然取得 video track — 使用者可隨時按鏡頭鍵升級為視訊（「預設關閉、可手動開啟」）
```

**語音通話的行為契約**：雙端進房時鏡頭關閉，但**鏡頭鍵必須保持可用**，
`_toggleCamera` 不得被 `if (!widget.isVideoCall)` 之類的條件擋住、按鈕不得隱藏或 disable。
（`Icons.cameraswitch` 前後鏡頭切換鍵則正常地被 `_isCameraOff` 擋住——鏡頭關著時切換無意義。）

### 4.4 接聽後的 WebRTC 建立

**唯一正確的 offer 建立時機：接聽方回 `call-accept`，發起方收到後才 `createOffer`。**

```
[接聽方] sendCallAccept(targetSocketId: senderId, callId: ...)
          ├─ 輪詢 socket.connected（100 × 100ms，最多 10s）  ← 冷啟動必需
          → [S] on_call_accept:1833 → emit 'call-accept' {accepterId, callId} to=發起方
[發起方] on('call-accept')
          ├─ _isInCall 防並發檢查
          └─ createOffer(targetId: accepterId)      ← ★ 建立 offer 的唯一入口
              ├─ 前提：localStream 必須已存在（護欄：不可先 createOffer 再開 media）
              ├─ _createPeerConnection() + _generateDynamicTURNConfig()
              └─ emit 'offer' {to: targetId, sdp}
[接聽方] on('offer') → setRemoteDescription → _processCandidateQueue() → createAnswer
          └─ emit 'answer' {to: senderId, sdp}
[雙方]   on('candidate') → 若尚未 setRemoteDescription 則進佇列，之後 flush
          └─ P2P 建立（媒體走 TURN 152.69.196.5:3478/UDP）
```

**兩個不可違反的規則**：
1. **ICE candidate 必須佇列化** — 早於 `setRemoteDescription` 抵達的 candidate 若直接 `addCandidate` 會被丟棄，造成「接通但無畫面」。
2. **SDP 禁止廣播** — `offer`/`answer` 必須帶 `targetId`，後端以 `to=target_sid` 精準轉發。

### 4.5 拒接

拒接必須讓**發起方立刻停止等待**，共有三條路徑：

| 情境 | 路徑 | 實作 |
|------|------|------|
| APP 內 dialog 按拒接 | Socket | `signaling.sendCallBusy(targetSocketId, callId, room)` |
| CallKit 拒接（主 isolate 活著） | Socket → HTTP 保底 | `_setupCallKitListener` `actionCallDecline` → `_sendDeclineEvent` |
| CallKit 拒接／逾時（背景 isolate） | **HTTP** | `_showFullScreenCallkit` 內的 `bgSub` listener → `ApiService.declineCall` |
| 本地通知備援按「✕ 拒絕」 | **HTTP** | `local_call_notification.dart::_handleDecline` → `ApiService.declineCall` |

**為什麼備援拒接一定要走 HTTP**：背景 isolate 沒有 Socket 連線，也沒有 plugin registrant。
`_handleDecline` 必須：
1. 開頭 `WidgetsFlutterBinding.ensureInitialized()` + `DartPluginRegistrant.ensureInitialized()`
2. **先**呼叫 `ApiService.declineCall`（純 HTTP，最不依賴環境）
3. **後**清 prefs 三個鍵
4. 每段各自 try/catch，任一段失敗不得阻斷其餘

> 歷史 bug：`_handleDecline` 第一件事是 `SharedPreferences.getInstance()`，在裸 isolate 拋 `MissingPluginException` 被整包 catch 吞掉 → `declineCall` 永遠執行不到 → 使用者看到「只能接聽、無法拒絕」。

**拒接後前端必做三件事**（護欄 #15）：
```dart
prefs.remove('pendingAcceptedCall');
prefs.remove('pendingRingCallData');
prefs.remove('pendingRingCall');
```
少清任何一個，下次冷啟動 `main()` 會重建 pending → 假來電或角色反轉。

**後端** `on_call_busy`:1866 依 `call_registry` 對「發起端所有 socket + 其他被叫裝置」廣播
`call-busy` + `cancel-call`，離線裝置補發 FCM（ttl=10s），並清理 registry。

### 4.6 掛斷／取消／逾時 — 雙端同步終止

| 觸發 | 前端 | 後端 |
|------|------|------|
| 通話中按掛斷 | `hangUp()` → emit `end-call` | `on_end_call`:1966 依 registry 對所有相關 socket+FCM 廣播 |
| 撥出中主動取消 | `sendCancelCall(room, role)` | `on_cancel_call`:1603 對所有已登記目標廣播 |
| 家屬撥出逾時 | `video_call_screen.dart` **20 秒** → `sendCancelCall` + `hangUp` | 同上 |
| 長輩撥出逾時 | `elder_screen.dart::_makeCall` **30 秒** → `sendCancelCall` + `hangUp` | 同上 |
| CallKit 響鈴逾時 | `actionCallTimeout` 視同拒接 → `declineCall` | `api_decline_call` |

**接收 `cancel-call` / `call-busy` 時前端必做**：
1. `_invalidCallIds.add(callId)` — 之後同 callId 的延遲 `call-request` 全部丟棄
2. `FlutterCallkitIncoming.endAllCalls()`（**包 try/catch**，MIUI 會拋 `PlatformException(content is null)`）
3. `LocalCallNotification.cancel()`

**終止提示必須用 dialog，不可用 SnackBar**（護欄 #25）：
`onCallEnded` / `onCallBusy` / `onConnectionLost` 一律走 `_showCallRejectedThenGoHome()`——
顯示 dialog 2 秒後才 `_goHomeAfterCall()`。因為 `_goHomeAfterCall()` 是
`pushAndRemoveUntil((route) => false)`，會當場移除 route 讓 SnackBar 消失，
使用者看到的是「瞬間、無提示跳回主畫面」，故障也無從診斷。

### 4.7 緊急通話

家屬端發起 → 長輩端**無條件**自動接聽、強制開鏡頭（第二十二輪起不再限於 CCTV 模式）。與一般通話的差異：

| 面向 | 一般通話 | 緊急通話 |
|------|---------|---------|
| 事件 | `call-request` | `emergency-call` |
| FCM ttl | 60s | **60s**（~~3600s~~，第二十二輪改齊） |
| `issuedAt`/`expiresAt` | Socket+FCM 都帶 | **Socket+FCM 也都帶**（~~刻意不帶~~，第二十二輪推翻，見改寫後的 G22） |
| 長輩端 UI | 響鈴等待接聽 | **無條件自動接聽**、無響鈴；改播 7 秒提示音（~~TTS 語音播報~~，第二十二輪需求 9） |
| 鏡頭 | 依 `isVideoCall` | **強制開啟** |
| `isVideoCall` | 帶 | 不帶（一律視訊） |

**必須設 `lastProcessedCallId`**（護欄 #24）：
`signaling.dart` 的 `emergency-call` handler 與 `main.dart::s.onEmergencyCall` **都要**設
`lastProcessedCallId` / `lastProcessedCallTime` / `_currentCallId`。
少了任一個，`elder_screen.dart::_checkPendingAcceptedCall` 的
```dart
isSameOngoingCall = callId == _signaling.lastProcessedCallId || callId == _activeCallId;
```
會恆為 false → 第二次寫入 `pendingAcceptedCall` 時落入 `if (_isInCall) { hangUp(); }`
→ emit `end-call` → 家屬端 `onCallEnded` → **家屬端瞬間無提示掛斷**。
`_activeCallId` 是**第二道防線**，不依賴各路徑是否正確設定 `lastProcessedCallId`，不可移除。

`main.dart` 緊急路徑寫入 `pendingAcceptedCall` 時**必須帶 `senderRole`**（護欄 #16）。

### 4.8 冷啟動接聽的四層兜底鏈

APP 被殺死時接聽，`actionCallAccept` 事件可能發生在 `_setupCallKitListener` 註冊**之前**而遺失。
四層兜底缺一不可：

| 層 | 位置 | 機制 |
|----|------|------|
| **L0** | 背景 isolate `main.dart`:416 | `bgSub` 收到 `actionCallAccept` 時**直接寫 prefs** `pendingAcceptedCall`（不依賴主 isolate） |
| **L0'** | `local_call_notification.dart::consumeLaunchPayload()` | 備援通知路徑；讀 `getNotificationAppLaunchDetails()`。**必須在 `main()` 讀 prefs 之前呼叫，之後要 `prefs.reload()`**（護欄 #23） |
| **L1** | `main.dart::main()`:525 | 冷啟動讀 prefs → 設 `pendingAcceptedCall.value` |
| **L2** | `_checkInitialCall()`:1251 | 檢查 `activeCalls()` 中 `isAccepted == true` 且未過期的通話 → 補設 pending。**`isAccepted == false`（僅響鈴）絕不自動進房**（護欄 #10） |
| **L3** | `_scheduleAcceptedCallFallback` / `_scheduleExtendedActiveCallsPoll` | 每 200ms 檢查、最多 8s；pending 被消費即停；`splashActive` 期間讓位 |
| **L4** | `SplashScreen._navigateToNext()` / `_navigateFamilyHome()` | 動畫結束後最終防線：先確定性 `pushReplacement(主畫面)`，有 pending 再 `push(通話畫面)` 疊上 |

**`splashActive` 旗標的作用**：冷啟動期間 `main.dart` 的全域兜底導航必須讓位給 Splash，
否則 `main.dart` 把通話畫面 push 到 Splash 之上，Splash 動畫結束的 `pushReplacement(主畫面)`
又會把最上層的通話畫面洗掉 → 使用者看到「開場動畫 → 主畫面」。

#### 這條兜底鏈本身的兜底（2026-08-11 第二十一輪新增）

這五層全部建立在「APP 有跑起來、Splash 有做出決定」的前提上。第二十一輪的
「APP 永久白屏」證明這個前提**會失守**，所以另外加了三道與通話無關的保命機制：

| 機制 | 位置 | 作用 |
|------|------|------|
| **`runApp()` 無條件執行** | `main.dart::main()` | 開機初始化整段搬進 `_bootstrap()` 並 `.timeout(10s)` 包 try/catch，`runApp` 在 try **之外**。任何 platform channel 卡住都不再擋住 UI。→ **G68** |
| **每個 `await` 各自逾時** | `_bootstrap()` 內、`splash_screen.dart` 內 | `Firebase.initializeApp()` 6s、`requestPermission()` 4s、`SharedPreferences` 5s、`getPairedElders` 6s、`activeCalls()` 2s…。**Dart 的 try/catch 攔不到「卡住」，只有 `.timeout()` 能把它變成可攔截的例外。** |
| **Splash 導航看門狗** | `splash_screen.dart` | `_navigated` 一次性互斥 ＋ 15s 看門狗強制決定去向 ＋ 5s 後顯示載入指示（畫在動畫下層）。→ **G69** |

> 另外：L1（`main()`:599）與 resume 路徑（:1249）的新鮮度判斷已改為
> **「缺 `timestamp` 一律視為過期並移除」**——那筆永生的毒 prefs 正是白屏的根因。見 **G67** 與 §3.4。

---

## 5. UI 按鈕與跳轉地圖

> **這一章是給「只改 UI、不懂信令」的人看的。**
> 想改按鈕外觀、換版面、加動畫 → 讀 §5.1 ~ §5.4 就夠。
> 想改按鈕**做什麼事**（onPressed 內容）→ 必須先讀 §5.5 的紅線。

### 5.1 通話相關畫面總覽

| 畫面 class | 檔案 | 角色 | 何時出現 |
|-----------|------|------|---------|
| `VideoCallScreen` | `screens/video_call_screen.dart` | **家屬** | 家屬撥出 或 家屬接聽 |
| `ElderScreen` | `screens/elder_screen.dart` | **長輩** | 長輩撥出 或 長輩接聽 或 CCTV 模式 |
| `CameraScreen` | `screens/camera_screen.dart` | 家屬 | 家屬觀看監控畫面 |
| `DeviceSelectionScreen` | `screens/device_selection_screen.dart` | 家屬 | 長輩有多台裝置時選擇撥打對象 |
| `FriendsScreen` | `screens/friends_screen.dart` | 長輩 | **長輩端唯一的撥出入口** |

> **`MonitorViewScreen` 不存在。** 歷史文件（2026-06-07 記錄）宣稱建立過此畫面，
> 但現行程式碼中沒有這個 class。監控畫面就是 `CameraScreen`。

### 5.2 全部畫面建構點（33 處 / 17 檔）

> 行號為 **2026-08-10 第十九輪**實測值（家屬端 UI 大改版後全數重新校準）。

**`VideoCallScreen(` — 20 處**

| 檔案:行 | 情境 | 是否來電路徑 | `isVideoCall` | `monitorViewOnly` |
|---------|------|-------------|--------------|------------------|
| `main.dart`:2023 | `_navigateToVideoCall` 全域兜底 | ✅ 是 | 由 pending 取得 | `false` |
| `family_main_screen.dart`:380 | `_startNormalVideoCall`（一般視訊的**單一**發起點） | ❌ 撥出 | 預設 `true` | `false` |
| `family_main_screen.dart`:634 | `_presentCctvAlert` 跌倒警報彈窗「查看監視畫面」 | ❌ 監控 | — | **`true`**（G55） |
| `family_main_screen.dart`:1001 | `_checkPendingAcceptedCall`（背景/被殺死接聽） | ✅ 是 | `parseIsVideoCall(args['isVideoCall'])` | `false` |
| `family_main_screen.dart`:1083 | APP 內 dialog 接聽 | ✅ 是 | `_signaling.isVideoCallFor(callId)` | `false` |
| `splash_screen.dart`:483 | 冷啟動最終防線 | ✅ 是 | 由 pending 取得 | `false` |
| `family/family_interaction_tab.dart`:719 / :743 | 互動頁撥出（一般 / 緊急）**已補傳 `targetSocketId`** | ❌ 撥出 | 預設 `true` | `false` |
| `family/family_interaction_tab.dart`:1676 | 監控卡片「觀看 CCTV」 | ❌ 監控 | — | **`true`**（G55） |
| `device_selection_screen.dart`:226 / :270 | 選定裝置後撥出 | ❌ 撥出 | 預設 `true` | `false` |
| `family_dashboard_screen.dart`:47 / :115 / :398 | 儀表板撥出 | ❌ 撥出 | 預設 `true` | `false` |
| `family_dashboard_view.dart`:344 / :1137 / :1494 | 儀表板撥出 | ❌ 撥出 | 預設 `true` | `false` |
| `family/ai_hub_screen.dart`:557 / :579 | AI Hub 撥出 | ❌ 撥出 | 預設 `true` | `false` |
| `socketio_test_screen.dart`:120 | 測試畫面 | ❌ | 預設 `true` | `false` |

> 🚫 **`monitorViewOnly` 只有上表標星的兩列可以是 `true`**，見 **G55**。
> ⚠️ `family_dashboard_view.dart`、`family/ai_hub_screen.dart`、`camera_screen.dart`
> 目前**沒有任何建構點**（家屬端改版後成為孤兒畫面），列在這裡只是因為它們自己會建構
> `VideoCallScreen`。清理屬另一次獨立作業，第十九輪刻意不動。

**`ElderScreen(` — 12 處**

| 檔案:行 | 情境 |
|---------|------|
| `elder_home_screen.dart`:443 / :549 | APP 內 dialog 接聽 |
| `friends_screen.dart`:59 | **長輩撥出（唯一帶 `isVideoCall` 的建構點）** |
| `elder_chat_screen.dart`:533 | 聊天畫面撥出 |
| `elder_pairing_display_screen.dart`:170 | 配對完成後進入 |
| `monitor_pairing_screen.dart`:73 | 監控機配對完成 |
| `role_selection_screen.dart`:109 / :159 / :241 | 角色選擇後進入 |
| `splash_screen.dart`:586 / :617 / :625 | 冷啟動導航 |

**`CameraScreen(` — 宣告於 `camera_screen.dart`:9**

### 5.3 通話畫面內按鈕對照

#### `VideoCallScreen` 控制列（`video_call_screen.dart`:813-843）

| 位置 | 圖示 | onPressed | 監控檢視 | 可否改外觀 | 可否改行為 |
|------|------|-----------|---------|-----------|-----------|
> 行號為 **2026-08-11 第二十輪**實測值。

| 位置 | 圖示 | onPressed | 監控檢視 | 可否改外觀 | 可否改行為 |
|------|------|-----------|---------|-----------|-----------|
| 848-853 | **音量來源**：`_isSpeakerOn ? volume_up : phone_in_talk` | `_toggleSpeaker`（:420） | ✅ 保留 | ⚠️ 見下方「音量來源」 | ⚠️ 需測藍牙/聽筒切換 |
| 856-861 | 麥克風 | `_toggleMic`（:332） | ✅ 保留 | ✅ | ⚠️ |
| 868-873 | `Icons.call_end` | **`_safeHangUp`**（:467） | 🚫 **`monitorViewOnly` 時整顆隱藏**（第二十輪，需求 3） | ✅ | 🚫 **禁止**改為直接 `Navigator.pop()` |
| 877-883 | 鏡頭 | **`_toggleCamera`（:346）— 無條件可按** | 🚫 `monitorViewOnly` 時整顆隱藏 | ✅ | 🚫 除了 `monitorViewOnly`，**禁止**再加任何條件或隱藏 |
| 885-891 | `Icons.cameraswitch` | `_switchCamera`（:410），gated `(_mediaInitialized && !_isCameraOff)` | 🚫 `monitorViewOnly` 時整顆隱藏 | ✅ | ✅ 這個 gate 是合理的 |

> **音量來源（2026-08-11 第二十輪，需求 9）** — 見護欄 **G61**
> - `_isSpeakerOn` 改為 `late`，於 `initState`（`video_call_screen.dart`:72/:76 宣告）
>   依通話類型決定初值：**視訊／緊急／監控 → 擴音；一般語音通話 → 聽筒**。
>   長輩端同款邏輯在 `elder_screen.dart`:52/:53/:173。
> - 語音通話中途**開啟鏡頭**時自動切擴音：`_autoSwitchToSpeakerOnCameraOn()`（:368），
>   由 `_toggleCamera`（:362）與 `_initializeAndToggleCamera`（:396）呼叫。
> - **只自動切一次**（`_speakerAutoSwitched`，:76）。使用者手動按過喇叭鍵之後
>   （`_toggleSpeaker`:422 會把旗標設起來），自動邏輯不得再覆寫他的選擇。
> - 🚫 圖示**不可**改回 `volume_up` / `volume_off`：`volume_off` 的語意是「靜音」，
>   使用者會誤以為按下去會沒聲音。聽筒不是「停用狀態」，所以兩態都不做灰階。

> **監控檢視為什麼沒有掛斷鍵**（需求 3）：監控是單向觀看、不是一通「電話」，
> 掛斷的隱喻本身就是錯的；而左上角的「← 返回」走 `returnByPop: true` 的既有離開路徑。
> 兩個出口並存只會讓使用者選到錯的那個。見護欄 **G60**。

> **`monitorViewOnly`（:38，預設 `false`）的完整影響面**（2026-08-10 第十九輪，需求 2）：
> `:192` `getUserMedia(videoEnabled: !monitorViewOnly)`（**根本不取視訊軌**）、
> `:198/:204` 視為鏡頭關閉、`:718` 隱藏前後鏡頭切換、`:777` 隱藏本地預覽 PiP、
> `:832`/`:840` 隱藏兩顆鏡頭按鈕。
> 家屬觀看監控時只剩**麥克風 / 擴音 / 掛斷 / 返回**四顆。
> 🚫 這是護欄 **G8** 的登記例外，只有兩個 CCTV 檢視建構點可傳 `true`——見 **G55**。
>
> **2026-08-11 第二十二輪（需求 4）追加一項**：頂端資訊列（通話類型膠囊 ＋ 紅色通話時長膠囊）
> 整段包在 `if (!widget.monitorViewOnly)` 內。
> 監控是「持續觀看」不是「一通電話」，顯示「緊急通話 00:37」只會讓家屬誤以為正在通話中。
> 🚫 **這是純顯示層的隱藏**：`_inCall` / `_callTimer` / `_formattedDuration` 的**計時邏輯完全沒動**
> （通話記錄與掛斷判斷仍靠它們）。想「順手把計時器也停掉」的人請住手——見 **G74**。

> **等待畫面／逾時 UI（2026-08-12 第二十三輪，需求 3）**
> `_callConnecting` 期間的遮罩現在**只有一種樣態**：`CircularProgressIndicator` ＋「正在連線中...」。
> 原本併在同一個 `Stack` 裡的**失敗畫面已整段刪除**（紅色 `Icons.wifi_off` ＋
> 「連線逾時，請檢查網路連接或稍後再試」＋ 藍色「重試連線」按鈕），
> 連同只被它讀取的 `_callErrorMessage` 欄位一起移除（原始例外訊息仍在 `debugPrint`）。
> 取而代之的是 `showCallRetryDialog`（`widgets/call_retry_dialog.dart`），
> **家屬端與長輩端共用**，兩顆按鈕分別是「離開通話」與「重新撥打」——見 **G84**。
> `_callFailed`（:82）**保留**：`initState` 的 5 秒 `Timer.periodic` 仍讀它。

#### `ElderScreen` 控制列（`elder_screen.dart`）

| 行 | 功能 | onPressed | 備註 |
|----|------|-----------|------|
| 896 | 鏡頭 | `_toggleCamera`（:534） | 同上，禁止加條件 |
| 919 | 前後鏡頭 | `_switchCamera`，gated `_isCameraOff ? null :` | 合理 |
| 942 | 靜音 | `_toggleMute`（:570） | |
| 955 | 掛斷 | `_hangUp` | 禁止改為直接 pop |
| 979 | 撥出 | `_makeCall()`（:594） | **`sendCallRequest` 唯一呼叫點（長輩端）** |

#### `FriendsScreen` 撥出鍵（`friends_screen.dart`:66-95，2026-08-11 第二十一輪改寫）

```dart
Future<void> _startCall(String friendName, {required bool isVideo}) async {
  String? roomId = widget.roomId?.trim();
  if (roomId == null || roomId.isEmpty) {
    // 上游沒帶就回頭讀 prefs 的權威值（登入／配對時寫入）
    final prefs = await SharedPreferences.getInstance();
    roomId = prefs.getString('elder_room_id')?.trim();
  }
  if (!mounted) return;
  if (roomId == null || roomId.isEmpty) {
    // 🚫 絕不拿 caregiver_id 硬湊一個不存在的房間
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('找不到您的通話帳號資料，請重新登入後再試')));
    return;
  }
  Navigator.push(context, MaterialPageRoute(
    builder: (context) => ElderScreen(
      roomId: roomId!,
      deviceName: widget.userName,
      autoCall: true,
      isVideoCall: isVideo,          // ← 整條 isVideoCall 鏈路的源頭
    ),
  ));
}
```

> 「視訊」鍵傳 `isVideo: true`、「電話」鍵傳 `isVideo: false`。
> **這是全專案唯一決定通話類型的地方。** 加新的撥出入口時記得也要傳。
>
> 🚫 **舊寫法 `widget.roomId ?? widget.userId.toString()` 已廢除**（護欄 **G70**）：
> `FriendsScreen.userId` 是 **`caregiver_id`**（帳號整數 PK）**不是 `elder_id`**。
> 用它拼出來的 `comm_elder_<caregiver_id>` 是不存在的房間，
> 後端查不到任何家屬、log 印「無任何轉發目標」、兩端零錯誤 →
> 「長輩端按了撥打完全沒反應」（第二十一輪需求 1）。
>
> **上游責任**：每個建構 `ElderHomeScreen` 的地方都要把 `roomId` 傳下去，
> 特別是 `video_call_screen.dart::_buildFallbackHome()`（:476）——
> 它原本沒帶，正是上面那個 null 的來源。

#### 監控（CCTV）相關按鈕 — 2026-08-05 第十七輪新增、2026-08-10 第十九輪擴充

> 行號為 **2026-08-10** 實測值。第十七輪記的那組（`:1084-1105` / `:515-533` / `:623-631` / `:949-985`）
> 已因家屬端 UI 大改版全數失效，不要沿用。

| 端 | 位置 | 按鈕 | 行為 | 備註 |
|----|------|------|------|------|
| 家屬 | `family_interaction_tab.dart`:1694 | **「觀看 CCTV」** `ElevatedButton.icon` | `Navigator.push` → `VideoCallScreen(roomId: monitorRoomId, targetSocketId: socketId, isEmergency: true, autoStart: true, returnByPop: true, **monitorViewOnly: true**)` | `onPressed` 由 `isOnline` gate（離線時 disabled）。卡片本體 `_buildMonitorDeviceCard`（:1549），資料來自 `_monitorDevices`。**第二十二輪起整張卡片改為家屬端暗色系，按鈕主色取自 `_tierAccentColor()`**（見下方色票） |
| 家屬 | `family_interaction_tab.dart`:1709 | **卡片 overflow menu**（`PopupMenuButton<String>`） | `rename` → `_showRenameMonitorDeviceDialog`（:1801）→ `PATCH /api/pairing/monitor_device`；`delete` → `_showDeleteMonitorDeviceDialog`（:1752）→ `DELETE /api/pairing/monitor_device` | **第十九輪新增**（需求 3）。兩者結尾都呼叫 `widget.onDevicesChanged?.call()` 讓家屬端立即刷新，不等下一次輪詢 |
| 家屬 | `family_main_screen.dart`:634（`_presentCctvAlert`，:522） | 跌倒警報彈窗的**「查看監視畫面」** | 同「觀看 CCTV」，先 `pop()` 掉彈窗再 push；**同樣傳 `monitorViewOnly: true`** | 只有 `canView`（有在線監視機）時才顯示。**這是 G55 的第二個合法建構點** |
| 家屬 | `video_call_screen.dart`:683-702 | **「← 返回」** | `Navigator.pop()` | **只在 `widget.returnByPop == true` 時渲染**（即 CCTV 檢視） |
| 長輩 | `elder_screen.dart`:1131-1155 | **「🚨 跌倒測試」** | `_sendTestFallAlert()`（:1216）→ `ApiService.triggerTestFall` → `POST /api/cctv/test-fall` | 位於「退出監視機」正下方，**只在 CCTV 模式畫面出現**；`_testFallSending` 防連點。**第二十二輪起，後端回「測試端點未啟用」時改顯示可操作的長文案**（見下方註記） |
| 長輩 | `elder_screen.dart`:1098-1112 | **「退出監視機」** | `_exitCCTVMode()`（:910） | **第十九輪起會先 `deleteMonitorDevice`（:957）再斷線**，家屬端清單即時移除、不留離線殘影（見 §6.8） |

> **`returnByPop` 的語意**（`video_call_screen.dart`:24-38，預設 `false`）：
> `true` → `_goHomeAfterCall()` 走 `Navigator.pop()` 返回上一頁；
> `false` → 維持既有的 `pushAndRemoveUntil` 重建主畫面。
> 🚫 **不可把預設值改成 `true`**：`false` 是給「冷啟動時疊在 `SplashScreen` 上的來電路徑」用的，
> 那條路徑底下沒有可 pop 的頁面，pop 會黑屏（這正是 §5.5 導航規則的由來）。
> 程式碼中另有 `canPop()` 二次保險（:444）。

> **「跌倒測試」是暫時性測試入口**：走的是與 YOLO 真實偵測**完全相同**的派送路徑
> （寫 `emergency_alerts` → Socket `cctv-alert` + 高優先級 FCM → 家屬端亮螢幕 + 通知 + 朗讀）。
> 後端該端點**預設關閉**，見 §6.10。`triggerTestFall` 回傳 `String?`：
> `null` = 成功，非 null = 可直接顯示給使用者的失敗原因。
> 🚫 **不要改回 `Future<bool>`**——關閉／密鑰錯誤／查無監視機三種失敗長得一樣，
> 使用者會完全不知道為什麼按了沒反應。
>
> **2026-08-11 第二十二輪（需求 2）**：使用者回報按下去只看到冷冰冰的
> 「測試端點未啟用」，無從判斷是 App 壞了還是設定沒開。
> `_sendTestFallAlert()`（`elder_screen.dart`:1216）現在會比對回傳字串是否含
> 「測試端點未啟用」（`disabledByServer`，:1224），命中就改顯示一段**說明這不是 App 故障、
> 並指出要在後端 `.env` 設 `CCTV_TEST_FALL_ENABLED=true` 再重啟**的長文案，
> 用 `SnackBar(duration: 8s)` 讓人看得完。
> 🚨 **這是純文案改動，不是修復**：這個開關在**遠端實體伺服器**的 `.env` 上，
> 本機改不到。要真的能測，必須有人上遠端主機改 `.env` 並重啟後端（測完改回 `false`）。
> 🚫 **絕對不要**為了「讓按鈕能用」而把後端預設值改成 `true` 或拿掉這道開關——那是 **G43**。

#### 監控相關 UI — 2026-08-11 第二十二輪新增

以下五項都是**同一輪**針對「家屬端監控體驗」的修正，改任何一項前先看完整組，
因為它們共用 `_tierAccentColor()` 與 `fetchMonitorDevicesOrNull()` 兩個新的單一來源。

| # | 需求 | 位置 | 行為 |
|---|------|------|------|
| 1 | 綁定完成後**自動關掉配對碼彈窗** | `family_interaction_tab.dart::_showAddMonitorDialog` 成功分支（`_monitorBindPollTimer`，欄位在 :74） | 顯示配對碼的同時起一支 **2 秒** `Timer.periodic`，偵測到「清單裡出現新裝置」就 `Navigator.pop()` 關窗、toast「監控設備「X」已完成綁定」、`onDevicesChanged?.call()`。硬上限 **150 次（5 分鐘）**，逾時只停輪詢、**不關窗**（後端配對碼壽命 15 分鐘，使用者仍可手動按「完成」） |
| 4 | 監控畫面**不顯示計時與「緊急通話」字樣** | `video_call_screen.dart` 頂部資訊列 | 整段包進 `if (!widget.monitorViewOnly)`。純顯示層，計時邏輯未動——見上方 `monitorViewOnly` 影響面 |
| 5 | 監控 UI 改**家屬端暗色系**、ICON 依**會員等級**變色 | `family_interaction_tab.dart::_tierAccentColor()`（:2106）＋監控卡片（:1487/:1662/:1711） | 底色 `0xFF1E293B`、邊框 `0xFF334155`、主文字 `0xFFE2E8F0`、次文字 `0xFF94A3B8`（與 `family_main_screen` 一致）。主色：一般 `0xFF10B981` 綠／黃金 `0xFFF5C451` 金黃／鑽石 `0xFF38BDF8` 亮藍 |
| 6 | 運行中被刪除時顯示「**該監控機已被刪除**」 | `elder_screen.dart::_verifyMonitorStillExists()`（:999）、`_status` 於 :806/:970/:1027 | 斷線時**不再直接**寫「連線中斷」，先打 `fetchMonitorDevicesOrNull` 交叉驗證：`null`（查詢失敗／無權 404）→「連線中斷」；清單裡沒有自己 →「該監控機已被刪除」；找得到 →「連線中斷」 |
| 9 | 緊急通話改播 **7 秒提示音** | `elder_screen.dart::_playEmergencyTone()`（:518）／`_stopEmergencyTone()`（:530） | `AssetSource('sounds/emergency_alert.wav')`（`assets/sounds/`，已註冊於 `pubspec.yaml`:136）。取代舊的「緊急通話，自動接聽中」TTS。`onPeerConnected`（:569）與 `dispose`（:1474）都會停並釋放 |

> **色票是刻意比 `family_dashboard_view.dart` 的那組更亮一階**（`_tierAccentColor()` 的註解 :2100）：
> 舊那組是為**白底卡片**挑的，搬到 `0xFF1E293B` 深底上對比度不足，黃金的暗金會整個糊掉。
> `_buildTierBadge()`（:2117）已改為共用同一個函式——**同一畫面不可以出現兩種「黃金色」**。
> ⚠️ 這代表**徽章的顏色也連帶變了**，那是預期內的，不是回歸。
> 🚫 `_tierAccentColor()` 對未知 `tierLevel` **必須**退回綠色、**不可拋例外**：
> 該值來自後端訂閱查詢，查詢失敗時會是 `'free'` 以外的任意字串，拋出去就整個分頁白畫面。

> 🚫 **`fetchMonitorDevicesOrNull` 不得把失敗吞成空清單**（這正是它與 `fetchMonitorDevices` 並存的唯一理由）。
> 需求 1 的「綁好了 → 關窗」與需求 6 的「查無自己 → 已被刪除」**都是拿「清單裡沒有」當判斷依據**；
> 若網路抖動時回傳 `const []`，前者會在還沒綁定時就關窗（其實沒關係）、
> 後者會**在監控機正常運行時謊報「該監控機已被刪除」**（很有關係）。
> 兩個呼叫點都必須維持「`null` → 什麼都不做」的寫法。

> 🚫 **綁定輪詢不可以改用 Signaling 回呼實作**。
> 看起來註冊一個 `onElderDevicesUpdate` 比起 2 秒輪詢優雅得多，但 `Signaling` 是 **Singleton**，
> 那個欄位同時被 `family_main_screen` 佔用（§7 G-系列多次強調的覆寫問題），
> 在對話框裡搶註冊會把主畫面的裝置狀態更新整條打斷，關窗時又極容易忘了還原。
> 現行做法只讀 `widget.monitorDevices`（由父層推下來）＋ 自己打 HTTP，**不碰任何全域回呼**。

#### APP 內來電 dialog

| 端 | 位置 | 樣式基準 |
|----|------|---------|
| 家屬 | `family_main_screen.dart`:398 附近 | 綠色接聽／紅色拒接 `ElevatedButton.icon` + `AlertDialog` |
| 長輩 | `elder_home_screen.dart` | 同上 |
| FCM 備援 | `main.dart::_showIncomingCallDialog`:1557-1638 | 必須與上兩者一致 |

> ⚠️ `_showIncomingCallDialog` 的 `showDialog(...)` **必須**接
> `.then((_) { _activeCallDialogContext = null; })`。
> 少了它，對話框若以其他方式關閉，`_activeCallDialogContext` 會**永久卡住**，
> 之後所有來電 dialog 全被擋。對照組是 `family_main_screen.dart`:398-400 的
> `.then((_) => _isIncomingCallDialogOpen = false)`。

#### APP 外來電 UI

| 層 | 實作 | 樣式來源 |
|----|------|---------|
| 主要 | CallKit（`_showFullScreenCallkit` 的 `CallKitParams`） | `backgroundColor: '#1a472a'`、`textAccept`、`textDecline`、`duration: 45000`、`isShowFullLockedScreen: true` |
| 備援 | `LocalCallNotification.show()` | 向 CallKit 對齊：`✓ 接聽` / `✕ 拒絕`、`color: Color(0xFF1A472A)` + `colorized: true`、`largeIcon` 頭像、`fullScreenIntent`、`category: call`、`Importance.max`、**系統來電鈴聲 ＋ `FLAG_INSISTENT`**（第二十三輪，見 **G83**） |

> **2026-08-12 第二十三輪（需求 2）**：使用者回報「長輩端在 APP 外的來電音效是系統**提醒**音效、
> 而非系統**來電**音效」。這句話本身就是一個診斷結論——CallKit 宣告的是
> `ringtonePath: 'system_ringtone_default'`，會發出提醒音的**只可能是備援通知**。
> 換言之，**那台裝置的 CallKit 原生層是失敗的**，看到的一直是第十三輪的互斥備援。
> 修法是把備援本身的鈴聲修對（新 channel `uban_incoming_call_ringtone` ＋
> `content://settings/system/ringtone` ＋ `notificationRingtone` 音軌 ＋ `FLAG_INSISTENT`），
> **不是**去動 CallKit——見 **G83**。

> **能力上限**：`flutter_local_notifications 18.0.1` **不支援** Android 原生 `Notification.CallStyle`，
> 備援無法與 CallKit 像素一致。`colorized` 在部分 Android 版本只對 foreground-service 通知生效。
> **正確做法是讓 CallKit 本來就成功**（§4.2 的輪詢探測），備援只覆蓋原生層真的失敗的殘餘情況。
> 🚫 **絕不能為了樣式一致而改成「只發 CallKit、失敗就沒畫面」**——那會讓長輩端在 MIUI 下完全收不到來電。

### 5.4 「我只想改 UI」— 安全清單

**✅ 隨便改（純外觀，不影響邏輯）**

- 任何 `Color` / `TextStyle` / `EdgeInsets` / `BorderRadius` / 圓角陰影
- `Icon` 圖示換成別的（但 `Icons.call_end` 換掉時請確認語意仍是掛斷）
- `Text` 文案（除了 §5.5 列的幾個特殊字串）
- Widget 樹的排版重構：`Row`↔`Column`、加 `Padding`、換 `Container`→`Card`
- 動畫、轉場效果
- 新增純展示性 widget（頭像、通話計時器、網路品質指示）

**⚠️ 改之前先讀本章對應段落**

- 按鈕的 `onPressed` 指向哪個函數
- `Navigator.push` / `pushReplacement` / `pushAndRemoveUntil` 的選擇
- 建構 `VideoCallScreen` / `ElderScreen` 時傳的參數
- 任何 `if (widget.isVideoCall)` / `if (_isCameraOff)` 條件

**🚫 絕對不要碰（改了必壞）**

| 東西 | 為什麼 |
|------|--------|
| `initState()` / `dispose()` 內的順序 | 通話是時序敏感的；`_initCall()` 有 socket 輪詢、media 開啟順序的硬性依賴 |
| 任何 `_signaling.onXxx = ...` 的 callback 註冊/清空 | 有 8 個註冊點互相依賴；`main.dart` 的角色守門就在其中 |
| `_isInCall` / `_activeCallId` / `_mediaInitialized` 旗標 | 防並發與去重的核心狀態 |
| `_goHomeAfterCall()` 的 `pushAndRemoveUntil` | 改回 `pop()` 會黑屏 |
| `_showCallRejectedThenGoHome()` | 改回 SnackBar 會讓提示瞬間消失 |
| `SharedPreferences` 的任何讀寫 | 見 §3.3，三個通話鍵必須同進同退 |

### 5.5 導航規則（改 UI 最容易踩雷的地方）

| 情境 | 必須用 | 絕不可用 | 原因 |
|------|--------|---------|------|
| 進入通話畫面 | `Navigator.push` | `pushReplacement` | 通話結束要能回到原畫面 |
| 通話結束回首頁 | `pushAndRemoveUntil((route) => false)`（即 `_goHomeAfterCall()`） | `pop()` | 冷啟動時堆疊裡可能沒有首頁 → 黑屏 |
| 關閉來電 dialog | `Navigator.of(ctx).pop()` + `canPop()` guard | **`popUntil(route.isFirst)`** | 會清空堆疊觸發 Splash/首頁重導，接聽失敗或黑屏（護欄 #3） |
| 冷啟動導航 | 讓 `SplashScreen` 主導（`splashActive` 旗標） | 在 `main.dart` 直接 push | 兩邊搶導航會互相洗掉（§4.8） |
| 喚起被背景化的長輩 APP | `com.example.app/bring_to_front` MethodChannel | `action.MAIN` / LAUNCHER intent | LAUNCHER intent 會冷重啟走 SplashScreen，丟掉 `onCallRequest` |

**新增撥出入口的正確做法（配方）**

```dart
// 家屬端 → 長輩
Navigator.push(context, MaterialPageRoute(
  builder: (_) => VideoCallScreen(
    roomId: roomId,          // comm_elder_{elder_id}
    userName: myName,
    autoStart: true,         // 進畫面自動撥出
    // isVideoCall 不傳 → 預設 true（視訊）
  ),
));

// 長輩端 → 家屬
Navigator.push(context, MaterialPageRoute(
  builder: (_) => ElderScreen(
    roomId: roomId,
    deviceName: myName,
    autoCall: true,
    isVideoCall: isVideo,    // ← 有「電話/視訊」之分時務必傳
  ),
));
```

🚫 **不要**在新的 UI 裡自己呼叫 `Signaling().sendCallRequest(...)`。
撥出一律透過建構通話畫面 + `autoStart` / `autoCall` 旗標，
因為 `_initCall()` / `_makeCall()` 內含 socket 輪詢、media 前置開啟、`_isInCall` 防並發，
繞過它們會出現「offer 建立時沒有 localStream」「並發通話」等問題。


---

## 6. 監控（CCTV）子系統

### 6.1 兩種裝置模式

| 模式 | 房間 | `saved_is_cctv` | FCM `type` | 用途 |
|------|------|----------------|-----------|------|
| **通訊機** `comm` | `comm_elder_{id}` | `false` | `call-request` | 雙向視訊通話 |
| **監控機** `monitor` | `monitor_elder_{id}` | `true` | `monitor-wakeup` | 單向監控，家屬觀看 |

一位長輩可同時擁有一台通訊機與多台監控機。

### 6.2 裝置角色如何決定

**登入順序決定，無 DB 欄位**：

```
長輩裝置登入
  → 呼叫 GET /elder/{elder_id}/has-comm-device（routers/user.py:251）
      → 後端 has_comm_elder_device()（socket_app.py:761）
          → 只檢查「在線 socket」中是否已有 deviceMode == 'comm' 的長輩裝置
  → false → 本機成為通訊機（saved_is_cctv = false）
  → true  → 本機成為監控機（saved_is_cctv = true）
```

> ⚠️ `has_comm_elder_device` **只認在線 socket**（護欄 #19）。
> **禁止**改回信任 `room_fcm_tokens` 的殘留離線 token——`on_disconnect` 從不清除離線 token，
> 拿來當「已有通話機」依據會讓主通訊機重裝後被自己的殘留 token 誤判 → 自我降級為監控機
> → 產生 monitor 列 → 觸發 §6.4 的整條 bug 鏈。

歷史上曾嘗試「用按鈕手動轉換模式」，已回退。**不要重新引入。**

#### 6.2.1 監視機綁定的持久化與家屬端清單的四個階段（2026-08-10 第十九輪）

**綁定成立的時刻＝配對碼被兌換的那一刻**，不是 Socket join 成功的時候。
`routers/pairing.py::resolve_monitor_setup`（:88）會 UPSERT 一列 `monitor_device_binding`
（`elder_id` / `family_id` / `device_name` / `device_id`，唯一鍵 `(elder_id, device_name)`）。
理由與絕對不可回退的原因見護欄 **G53**。

家屬端清單來源 `socket_app.py::_get_elder_devices_list`（:752）現在有**四個**階段：

| 階段 | 資料源 | 產出 |
|------|--------|------|
| **0（新）** | `monitor_device_binding`（查成 `bound_by_name` 字典） | 只在最後**補漏**，見下 |
| 1 | `rooms_manager` 的 `comm_elder_<id>` + `monitor_elder_<id>` | 在線裝置；同名取 `joinedAt` 較新者（**G51**） |
| 2 | `room_fcm_tokens` | 有 token 但 socket 已斷的裝置 |
| 3 | DB `user_fcm_token` | 跨重啟的已知裝置 |

階段 0 的字典在函式開頭就建好，但**只在 `return` 前使用**：把「階段 1–3 都沒產出、
但存在於綁定表」的名稱補成一列離線紀錄
（`id='bound_<device_id>'`、`deviceMode='monitor'`、`isOnline=False`、`appState='offline'`），
去重 key 沿用階段 1–3 的 `online_device_names`。
🚫 **不可改成「先塞再覆蓋」**——理由見護欄 **G54**。

> **為什麼需要階段 0**：`on_join` 有六條 `join-failed` 分支，命中任一條就 `sio.disconnect(sid)`
> 且不留任何持久狀態。修復前，「配對碼兌換成功」與「家屬端看得到裝置」之間隔著一個
> **可能失敗且雙端都沒有可見錯誤**的 Socket join。這正是第十九輪遠端真機測試回報的
> 「6 位數配對碼配對成功、家屬端卻始終看不到裝置」。

### 6.3 監控機數量與 IP 限制

| 函數 | 行 | 作用 |
|------|----|----|
| `_get_monitor_device_limit` | 881 | 讀取每位長輩的監控機上限 |
| `_count_active_monitor_devices_for_elder` | 918 | 計算目前在線監控機數 |
| `_count_monitor_devices_for_ip` | 934 | 同一 IP 的監控機數（防濫用） |
| `_cleanup_monitor_ip_on_disconnect` | 957 | 斷線時釋放 IP 計數 |
| `_ip_hash` | 875 | 日誌只記雜湊，不記明文 IP |
| `_extract_client_ip` | 1066 | **取得真實客戶端 IP**（2026-08-10 第十九輪新增） |

> ⚠️ **「同 IP 上限 5 台」在反向代理後方原本是「全球上限 5 台」**（第十九輪查出）。
> `_client_ips`（:205）記的是 **TCP 對端位址**；走 Tailscale Funnel 時**所有裝置共用同一個
> `ip_hash`**，第 6 台監視機起會被全球性拒絕（`join-failed` reason `ip_limit_exceeded`），
> 而且這條分支不留任何持久狀態、兩端都沒有可見錯誤。
> 之所以還沒爆掉，只是因為 `purge_monitor_device_ip_on_startup()`（:157-177）每次重啟都清空。
>
> 修復：`on_connect`（:1111）改呼叫 `_extract_client_ip(environ)`，
> 優先序 **`X-Forwarded-For` 第一段 → `X-Real-IP` → TCP 對端位址**。
> 🚫 仍是**未完全解決**——若 Funnel 不轉送這兩個標頭就會退化回單一 `ip_hash`。
> 真機驗證前**不要**再放寬上限（見 §7.4 #4）。

### 6.4 ⚠️ `monitor-wakeup` 誤判 — 「長輩被殺死收不到來電」的歷史根因

**這是本專案追了 4 輪才找到的 bug，務必理解後再動任何 token 查詢邏輯。**

```
後端 socket_app.py:1534 / :1774
    type = 'monitor-wakeup' if info.get('deviceMode') == 'monitor' else 'call-request'
前端 main.dart:76
    只放行 call-request / emergency-call / cancel-call
    → monitor-wakeup 被靜默丟棄（全 lib/ 無任何 monitor-wakeup handler）
```

**不對稱失效是關鍵診斷線索**：家屬端 `deviceMode` 永遠是 `comm` → 永遠收得到；
長輩端通訊機一旦被記成 `monitor` → 收不到。
**對稱失效才是 MIUI 殺進程；不對稱一定是結構性差異。**

**通訊機為何會被記成 monitor**：
`user_fcm_token` 主鍵是 `(user_id, room_id, fcm_token)`，同一支 token 可以在
`comm_elder_X` 與 `monitor_elder_X` 各留一列（曾當監控機、後改通訊機）。
token 去重時**無 `ORDER BY` + 記憶體無條件覆寫** → monitor 列蓋掉 comm 列。

**四層修復，任一環失守即回歸**（護欄 #18）：

| 層 | 位置 | 修復 |
|----|------|------|
| C1 前端止血 | `main.dart` BG + FG handler | 收到 `monitor-wakeup` 且本機權威旗標 `saved_is_cctv == false` → 正規化為 `call-request` |
| B1 後端防禦 | `_get_all_known_fcm_tokens` / `_get_target_sockets_and_tokens` | token 去重一律**偏好 comm**：記憶體迴圈「comm 不被 monitor 覆蓋」+ DB `ORDER BY (device_mode='comm') DESC` |
| B2 後端根治 | `on_join` / `on_update_fcm_token` | `_purge_stale_reverse_mode_token()`：elder join 時以 token 為鍵刪除「反向模式房間」的殘留列（記憶體+DB） |
| B3 防復發 | `has_comm_elder_device` | 只認在線 socket（見 §6.2） |

### 6.5 ⚠️ 長輩 token 查詢的「內容鍵 vs 位置鍵」

**這是與 §6.4 互補的第二條腿**：§6.4 解「token 撈到了但 type 被標成 monitor-wakeup」；
本節解「token 因 room_id 字串漂移**根本沒撈到**」。

| 端 | 查詢鍵 | 穩定性 |
|----|--------|--------|
| 家屬 | **user_id 內容鍵**：`family_elder_relationship → family_id → WHERE role='family' AND user_id IN (...)` | ✅ 與裝置註冊在哪個房間無關 |
| 長輩（修復前） | **room_id 位置鍵**：`WHERE role='elder' AND room_id IN ('comm_elder_X','monitor_elder_X')` | ❌ 房名字串一漂移就查無 token → 完全不發 FCM |

room_id 漂移的來源：`elder_home_screen.dart` 的 fallback 成 user_id、數字 elder_id 的前導零 / str↔int、舊格式殘列、重啟殘列。

**修復（護欄 #20）**：elder 分支的 DB 查詢改為**疊加**（非取代，向後相容既有殘列）：
```sql
WHERE role='elder' AND (room_id IN (%s, %s) OR user_id = %s)
```
`user_id` 由 **`_resolve_elder_user_id()`**（走 `elder_profile` 反解、**不做 int 短路**）取得。

> 🚫 **禁止**用 `_resolve_user_id_int` 代替 `_resolve_elder_user_id`：
> 前者對數字型 elder_id（如 `'0064'`）會 int 短路誤判成 user_id。
> 🚫 **禁止**改回「只用 room_id」。
> `elder_user_id` 為 `None` 時 `OR user_id = NULL` 恆假 → 安全退化回純 room_id 查詢。

### 6.6 裝置上下線偵測

> ⚠️ **2026-08-10 第十九輪據實更正**：舊版這裡寫「後端只在 `join` 時廣播
> `elder-devices-update`，`disconnect` 時不廣播」，以及「有 15 秒 staleness watchdog」。
> 兩者都與程式碼不符——`on_disconnect` **確實會廣播**（`socket_app.py`:1628），
> 而 15 秒 watchdog **從來不存在**。以下是實際行為。

後端在 join(:1333)、`delete-device`(:1464)、`force-logout`(:1548)、
**disconnect**(:1628)、改名(:2467) 都會呼叫 `_broadcast_elder_devices_update`。
即使如此，前端仍不能只靠 Socket 事件——socket 一斷（切網路、進背景被凍結、後端重啟）
就再也收不到任何更新，清單會永遠停在舊值。因此前端有三條並行路徑：

1. **Socket 輪詢 2.5 秒**：`_startDeviceRefreshTimer()` → `sendGetElderDevices('comm_elder_<id>')`
2. **HTTP 交叉驗證 10 秒**：`_refreshMonitorDevicesViaHttp()` →
   `GET /api/pairing/monitor_devices`（後端呼叫的是**同一支** `_get_elder_devices_list()`）。
   啟動時**先立即打一次**，避免剛配對完要等滿 10 秒才看到裝置。
   兩條路徑都收斂到同一個 `_applyDeviceList()`，**後到者覆蓋先到者**（不是聯集）——
   因為兩邊資料源同一支函式，內容本就一致，取聯集反而會讓已刪除的裝置復活。
   🚫 HTTP 路徑**回空陣列時直接 return、不套用**：這是補強路徑，
   後端暫時不可用不該把清單清空。真正的「裝置消失」由 Socket 路徑負責。
3. `onElderDevicesUpdate` 收到事件後：
   - 裝置**清單**與「離線→上線」→ **立即套用**
   - 「上線→離線」→ 做一次性 **2.5 秒**確認（計時器 `??=` 建立，**永不因新事件重啟**）

> 🚫 **不要改回 1 秒瞬時切換**：會造成快速上下線抖動誤判。
> 🚫 **更不要改回「每收到事件就 cancel + 重排」的雙向 debounce**——那與輪詢週期同為 2500ms，
> 會互相取消到永遠不 fire，家屬端因此**看不到監視機、在線燈不亮**（第十七輪需求 1+3 的根因）。
> 完整規則見 **G40**。
> `isOnline` 的型別檢查要容忍 bool / int / String 多型別
>（曾有只判 `== true` 導致字串 `"true"` 被當離線的回歸）。

### 6.7 監控相關事件

| 事件 | 說明 |
|------|------|
| `get-elder-devices` / `elder-devices-update` | 裝置清單查詢與推播。join／`delete-device`／`force-logout`／**disconnect**／改名都會廣播（見 §6.6，舊文件「只在 join 時廣播」是錯的） |
| `monitor-renamed` | 家屬端改名後推送給**該監視機**：`{elderId, oldDeviceName, newDeviceName, deviceId}`，監視機更新標籤與 `saved_device_name`（G57） |
| `delete-device` → `force-logout` | 家屬端移除長輩裝置；被踢裝置收到 `force-logout`（Socket + FCM 雙路）。**發送者必須是該長輩 comm/monitor 房間成員**（G46） |
| `cctv-alert` | 後端 → 家屬：YOLO／測試跌倒警報（見 §3.2、§6.9） |
| `cctv-alert-ack` | 回應影像告警；後端回 `cctv-alert-ack-success` / `cctv-alert-ack-failed`。**需通過關係驗證**，無權回 `{'reason': 'not_found'}`（G44/G45） |
| `audio-bridge-request` → `audio-bridge-response` | 30 分鐘單向音訊橋接（家屬 → 監視機）。**需關係驗證 + `to_device_id` 歸屬驗證**（G44） |
| `emergency-call` | CCTV 模式下自動接聽、強制開鏡頭（§4.7） |

### 6.8 CCTV 模式進出

- 進入：`ElderScreen` 依 `saved_is_cctv` 判定
- 退出：`elder_screen.dart::_exitCCTVMode`（**:910**，入口鈕在 :1098；舊文件記 `:795` 是錯的）
- 緊急通話待處理鍵：`pending_emergency_room` / `pending_emergency_sender`（`elder_screen.dart`:130-139 讀取後立即 remove）

**退出時必須先解綁再斷線（2026-08-10 第十九輪，需求 3c）**
`_exitCCTVMode()` 舊版只清 7 個 prefs 鍵 + `clearSession()` + `forceDisconnect()`，
**既不呼叫刪除 API 也不發任何事件** → 家屬端清單留下一個永遠離線的殘影，
而且第十九輪之後綁定已持久化到 `monitor_device_binding`，殘影會**跨重啟存在**。
現在在 `forceDisconnect()` **之前**呼叫 `ApiService.deleteMonitorDevice(...)`（:957）：
- 走 **HTTP**、不依賴 socket 是否還活著（此時正要斷線）。
- 成功與否都繼續往下走完既有清理流程，**不可**因為 API 失敗就中止退出。
- 後端該端點連同 `monitor_device_binding` 一起刪，隨即 `_broadcast_elder_devices_update`
  把它從家屬端清單移除。

**家屬端刪除監視器 → 監視機必須立刻退回主畫面（2026-08-11 第二十輪，需求 4／5）**

第十九輪只做了「監視機主動退出 → 家屬端清單移除」這一個方向；
**反方向**（家屬端刪除 → 監視機仍停在 CCTV 畫面）當時沒做，造成兩個連鎖故障：

1. 監視機畫面還停在「CCTV 監視中」，使用者只能自己去按「退出並重置」。
2. 更糟的是，那台機器接著**再也綁不上任何配對碼**——不論輸入幾次正確的 6 位數
   都回「綁定碼過期或錯誤」（見下方兩段修法）。

修法（兩端）：
- **後端** `routers/pairing.py::delete_monitor_device`：在 `sio.disconnect(kick_sid)`
  **之前**先 emit `monitor-removed`（:359）。順序反了事件就送不出去 → **見 G65**。
- **前端** `elder_screen.dart`:697（只在 `isCCTVMode` 分支註冊，且以 `elderId`／
  `deviceName` 過濾非本機事件）→ `await SessionManager.releaseSession()`（:706）
  → `pushAndRemoveUntil(IdentificationScreen)`。`dispose()`（:1102）必須清掉這個 callback。

`_exitCCTVMode()`（:992）也改走同一條路：
**`deleteMonitorDevice(...)` → `SessionManager.releaseSession()`（:1051）→ 導回身分選擇畫面**。
刪除 API 必須排在 `releaseSession()` **之前**——後者會清掉呼叫該 API 所需的 `caregiver_id`
與裝置名稱（:1026 有就地註記）。

**為什麼「曾當過監控機的裝置就再也綁不上」**：舊版 `resolve_monitor_setup` 把配對碼
從行程內 dict **`pop` 掉**，而該裝置本機殘留的 session 又讓它跳過重新配對；
一旦後端重啟或第一次兌換沒走完，那組碼就永久消失 → 使用者看到的就是「綁定碼過期或錯誤」。
第二十輪改成持久化到 `monitor_setup_code` 表且**不 pop**（15 分鐘 TTL 內可重入），
並把「不存在」與「已過期」分成 **404 / 410** 兩種可辨識的錯誤 → **見 G64**。

### 6.9 跌倒警報派送鏈（YOLO 與「跌倒測試」共用）

```
影格來源
 ├─ 監視機推流：ApiService.pushCctvFrame → POST /api/cctv/frame（multipart PNG）
 │     └─ 後端每 2 秒取一個窗口送 YOLO 推論
 └─ 「跌倒測試」鈕：ApiService.triggerTestFall → POST /api/cctv/test-fall
       └─ 跳過 YOLO，直接以 alert_type='fall' 進入下一步

           ↓ 兩條路在此匯流（services/yolo_alert_dispatcher.py::dispatch）

  _insert_alert()  ← ⚠️ UPSERT 語意：同 elder+device+type 且 status='active' 只更新
                       detected_at 並沿用原 alert_id（見 §3.2 的去重警告）
           ↓
  Layer 1  Socket.IO 'cctv-alert' → 在線家屬 sid
  Layer 2  FCM data-only（priority=high）→ 離線／背景家屬 token
           ↓
  家屬端 family_main_screen.dart
    ├─ 複合鍵 "a$alertId@$timestamp" 去重（_knownAlertKeys）
    ├─ WakelockPlus 強制點亮螢幕
    ├─ CctvAlertNotification（獨立 channel，與來電備援分開）
    ├─ FlutterTts 朗讀
    └─ AlertDialog（_cctvAlertDialogOpen 防疊加）+「查看監視畫面」鍵
```

**`device_id` 的計算**（`services/monitor_identity.py`）：
```python
monitor_device_id(elder_id, device_name) = zlib.crc32(f"{elder_id}|{device_name.strip()}") & 0x7FFFFFFF
```
> ⚠️ 兩端必須都用**原始（未加 `elder_`／`comm_`／`monitor_` 前綴）的 elder_id**，
> 否則算出來的 id 不同 → 後端「查無此監視機」。

### 6.10 監控安全開關（2026-08-05 第十七輪新增）

兩個環境變數，都在 `uban-api/.env`（範本見 `.env.example`），
實作在 `uban-api/services/call_security.py`（**在呼叫時讀取，不在 import 時讀**）：

| 變數 | 預設 | 作用 |
|------|------|------|
| `CCTV_TEST_FALL_ENABLED` | `false` | `POST /api/cctv/test-fall` 的總開關。關閉時回 **404** 並附中文原因，前端會直接顯示在 SnackBar |
| `CCTV_INGEST_TOKEN` | 空 | 推流與測試端點的共用密鑰。**留空 = 不驗證（向後相容既有行為）**；有值則兩個端點都要求 `X-Uban-Device-Token` 標頭，不符回 403 |

前端以 `--dart-define=CCTV_INGEST_TOKEN=<同一字串>` 注入
（`api_service.dart`:31 的 `_cctvIngestToken` / `_deviceTokenHeader`，空字串時**不送**該標頭）。

**要測「跌倒測試」鈕時**：`.env` 設 `CCTV_TEST_FALL_ENABLED=true` → 重啟後端 → 測完**立刻改回 `false`**。
理由：`elder_id` 只有 4 位數字（10 000 組，可完整列舉），長期開放等同開放對任意長輩家庭發動騷擾。

### 6.11 怎麼測 YOLO 的跌倒偵測

> 對應使用者的提問「我要趴在地上幾分鐘之類的」。**先看這裡再去躺地板。**

**先決條件**
1. 監視機端已進入 CCTV 模式且正在推流（後端 log 每 2 秒一個窗口）。
2. 家屬端 APP 已登入同一位長輩，且**至少開過一次**（FCM token 才會寫進 `user_fcm_token`）。
3. 想跳過 YOLO 直接驗證「派送 + 家屬端呈現」→ 用 §6.10 的測試鈕，**不需要躺地板**。

**分兩階段測，不要混在一起測**

| 階段 | 目的 | 方法 | 判準 |
|------|------|------|------|
| **A. 派送鏈** | 驗證 DB 寫入 → Socket/FCM → 亮螢幕 + 通知 + 朗讀 + 彈窗 | 開 `CCTV_TEST_FALL_ENABLED=true`，按「🚨 跌倒測試」 | 家屬端**熄屏**狀態下也要亮起並朗讀。連按兩次要**兩次都有反應**（驗證複合鍵去重沒退化） |
| **B. YOLO 推論** | 驗證模型真的判得出跌倒 | 見下方姿勢清單 | 後端 log 出現 `🚨 [YoloAlert] fall ...` 且 `confidence` 合理 |

**階段 B 的實際做法**

- **姿勢比時間重要**：`fall` 的判準是**人體 bounding box 的長寬比翻轉**（站姿是高>寬，倒地是寬>高）＋持續數個窗口。
  所以要**整個人平躺／側躺、身體長軸與畫面水平方向大致平行**。蹲下、彎腰、坐地板通常**不會**觸發。
- **時間**：後端每 2 秒一個推論窗口。維持姿勢 **10–15 秒**足夠讓連續窗口都判到；
  不需要趴好幾分鐘。若 15 秒沒觸發，代表是角度／距離／光線問題，趴更久也沒用。
- **鏡頭位置**：監視機要能**看到全身**。太近（只拍到上半身）會讓長寬比失效，這是最常見的失敗原因。
  建議 2–3 公尺、離地 1.2–1.8 公尺、稍微俯角。
- **光線**：偏暗會讓信心度掉到門檻以下。先在明亮環境測通，再測夜間。
- **安全**：請在**床墊或瑜珈墊**上做，不要真的往硬地板倒。模型看的是最終姿勢，不是倒下的過程。
- **其他型別**：`prolonged_inactivity`（久臥不動）需要的時間長很多，
  測它請直接改後端門檻參數，不要用肉身等——那才是真的要躺好幾分鐘。

**測不出來時的排查順序**
1. 後端 log 有沒有收到影格？沒有 → 推流斷了，看 §9 的 A/B/C 定位法。
2. 有影格但沒 `[YoloAlert]` → 推論沒過門檻，調整鏡頭距離／光線／姿勢。
3. 有 `[YoloAlert]` 但家屬端沒反應 → 是派送鏈問題，回頭跑階段 A 隔離。

---

## 7. 護欄（合併後的唯一權威清單）

> 目前共 **85 條**（G1–G85）：G1–G36 合併自 `CLAUDE.md`（13 條）與 `Uban/CLAUDE.md`（26 條）並去重、
> 修正矛盾；G37–G46 為 2026-08-05 第十七輪新增（連線可靠性 4 條、監控警報 2 條、安全 4 條）；
> G47–G52 為 2026-08-05 第十八輪新增（前端 4 條：監控機連線、冷啟動衝刺、鎖屏覆蓋、掛斷提示；
> 後端 2 條：裝置清單同名去重、CCTV 端點部署）；
> G53–G57 為 2026-08-10 第十九輪新增（後端 3 條：綁定持久化、階段 0 只補洞、改名五處同步；
> 前端 2 條：`monitorViewOnly` 是 G8 的例外、監控自動接聽必須靜音但不得省略接聽動作）；
> G58–G66 為 2026-08-11 第二十輪新增（前端 6 條：session 統一釋放、語音喚醒預設關閉、
> 監控檢視無掛斷鍵、音量來源、撥出前等連線、家屬端動態文字寬度約束；
> 後端 3 條：配對碼持久化、`monitor-removed` 的 emit 順序、`on_end_call` 容忍 `room=None`）；
> **G67–G72 為 2026-08-11 第二十一輪新增**（前端 5 條：`pendingAcceptedCall` 的 `timestamp` 契約、
> `runApp()` 不得被開機初始化擋住、Splash 導航看門狗與互斥、長輩房名不得退回 `caregiver_id`、
> `_initElderMode` 的逾時與 `onError`；後端 1 條：`session/release` 只能以 `fcm_token` 為鍵）；
> **G73–G80 為 2026-08-11 第二十二輪新增**（前端 6 條：來電有效期收斂為 60s 且單一來源、
> `monitorViewOnly` 只隱藏顯示不停用計時、CCTV 推幀三層自癒、離開監控的釋放順序與 socket `dispose()`、
> 緊急通話無條件接聽＋7 秒提示音、「查詢失敗 ≠ 查無裝置」與層級主色單一來源；
> 後端 2 條：已取消 `call_id` 整通不發、兌換配對碼後必須廣播裝置清單）。
> **G81–G85 為 2026-08-12 第二十三輪新增**（全部前端：緊急通話自動接聽的四通路單一收斂點、
> FCM 背景 handler 保活到使用者決定（否則拒接鍵永遠無效）、來電備援通知的鈴聲與 channel
> 不可就地改音、無人接聽／連線逾時一律用 `showCallRetryDialog` 且重撥不得重跑媒體初始化、
> 不可取消的 `Future.delayed` 看門狗必須用世代編號守衛）。
> **G23 已於第十八輪修訂**（改為只約束「要顯示提示時用什麼元件」，是否顯示交由 G50）。
> **G8 已於第十九輪加註例外**（`monitorViewOnly`，見 G55）。
> **G22 已於第二十二輪改寫**（緊急通話由「刻意不帶有效期、ttl 3600s」**反轉**為「兩條路都帶、ttl 60s」，見 G73）。
> **G67 已於第二十二輪修訂**（`pendingRingCallData` 窗口 120000 → 60000；並更正其中誤植的 G24 條號）。
> **G77 已於第二十三輪擴充**（自動接聽的範圍由「`ElderScreen` 內」擴大到**四條抵達通路**，見 G81；
> 提示音改為救護車雙音並搬進全域單例 `EmergencyTone`）。
> **除非明確知道連鎖影響並能同步改完整條鏈路，不要單點修改。**

### 7.1 前端護欄

**G1 — `main.dart::_setupSignalingListener()` 的角色守門**
`if (appRole != 'elder') { s.onCallRequest = ... }`
**不可移除／放寬**：否則會覆蓋 `ElderHomeScreen` 的 callback → 長輩前景收不到來電。

**G2 — `main.dart::_setupCallKitListener()` 接聽路徑**
先寫 `pendingAcceptedCall.value`，再短延遲 fallback `_navigateToVideoCall(...)`。
**不可改回直接強推單一路徑**：會重現「接聽後回主頁、不進通話房」。

**G3 — `main.dart::_navigateToVideoCall()`**
只關閉 `_activeCallDialogContext`，**禁止** `popUntil(route.isFirst)` 清堆疊。
清堆疊會觸發 Splash／首頁重導 → 接聽失敗或黑屏。

**G4 — `signaling.dart` 的失效流程**
`_invalidCallIds` + `_isExpiredCallPayload(...)` + 在 `call-request`/`cancel-call`/`call-busy`/`end-call` 的失效標記。
**不可移除**：會再出現「掛斷後延遲來電」「接起舊來電互打迴圈」。

**G5 — `signaling.dart::invalidateCallId()` / `isCallInvalidated()`**
供 `main.dart` FCM handler 於拒接／取消時標記失效。與 G4 一體，不可移除。

**G6 — `family_main_screen.dart` 的 2.5s 節流**
`2.5s` 輪詢 + `2.5s` debounce 套用 `isOnline`。**不要改回 1 秒瞬時切換**。

**G7 — 消費 `pendingAcceptedCall` 前的過期判斷**
`elder_home_screen.dart` / `family_main_screen.dart` / `splash_screen.dart`，
**60 秒**（`kCallValidityMs`，`globals.dart`:47；**2026-08-11 第二十二輪：120 → 60**，見 G73）。
**不可刪除**：會讓冷啟動延遲收到的舊來電再次被接起。
🚫 **不可再寫死 `120000` / `60000` 字面值**——第二十二輪已把 `main.dart`:672、
`splash_screen.dart`:272/:288 三處寫死的 `120000` 全部換成 `kCallValidityMs`。
有效期只能有**一個**來源，否則調一次值就會漏掉幾處、產生「某些路徑仍用舊窗口」的鬼故事。

**G8 — `_isCameraOff = false`（進入視訊房預設開鏡頭）**
`elder_screen.dart` + `video_call_screen.dart` 的**宣告式初值不可改動**。
> ⚠️ **例外（2026-08-02 第十四輪，使用者明確要求）**：長輩端發起的若是「電話」而非「視訊」，
> 雙端進房時鏡頭預設關閉。實作是新增 `isVideoCall` 參數（**預設 `true`**），
> 只在明確收到 `isVideoCall == false` 時才把 `_isCameraOff` 設為 `true` 並停用 video track。
> 本條禁止的是「把預設改回關閉」，不是禁止語音通話旗標。
> **鏡頭鍵必須保持可按**（「預設關閉、可手動開啟」），不得鎖死或隱藏。

**G9 — BG handler 預寫 `pendingRingCallData`**
`main.dart::_firebaseMessagingBackgroundHandler` 的 `call-request` 路徑：
在 `_showFullScreenCallkit` **之前**預寫（含 `isAccepted: false`）；`actionCallAccept` 時更新為 `true`。
**不可移除**：否則「BG isolate 寫入失敗 + `activeCalls()` race + `onEvent` 遺失」三重場景無備援。

**G10 — `_checkInitialCall()` 重試 + 不自動進房**
最多 3 次重試（間隔 300ms）等待 native CallKit 狀態同步；
`isAccepted == false`（僅響鈴中）**絕不**自動進房。
**不可改回單次查詢**。

**G11 — `main()` 的 `pendingRingCallData` 備援讀取**
`pendingAcceptedCall` 為 null 時檢查 `pendingRingCallData`（`isAccepted=true` + 未過期 → 重建 pending）。
**不可移除**：BG isolate 寫 `pendingAcceptedCall` 在小米／OPPO 嚴格背景 IO 下可能失敗。

**G12 — `_scheduleAcceptedCallFallback()` 兜底輪詢**
每 200ms 檢查、最多 8s；`splashActive` 期間讓位；pending 被消費即停。
**不可改回一次性 350ms 延遲**：無法覆蓋冷啟動時間變異。

**G13 — `globals.dart::splashActive` 旗標**
冷啟動接聽期間，`main.dart` 全域兜底導航必須讓位給 `SplashScreen`。
**不可移除**：否則全域兜底把通話畫面 push 到 Splash 上，又被 Splash 的 `pushReplacement` 洗掉。

**G14 — `_sendDeclineEvent()` 單通路**
Socket 在線只走 `sendCallBusy`，離線才走 HTTP `declineCall`；`catch` 區塊作 HTTP 備援。
**不可改回「Socket + HTTP 兩路都發」**：後端兩個 handler 各廣播一次 → 拒接三重訊息。

**G15 — 拒接／取消時清三個 prefs key**
`pendingAcceptedCall` + `pendingRingCallData` + `pendingRingCall`，
在 `_sendDeclineEvent`、BG isolate CallKit decline/timeout listener、FCM 前景/BG `cancel-call` handler、
`local_call_notification.dart::_handleDecline` 全部要清。
**不可移除**：殘留會讓冷啟動 `main()` 誤重建 pending → 假來電／角色反轉。

**G16 — `senderRole` 防角色反轉**
全鏈路帶 `senderRole`（`_showFullScreenCallkit` extra、CallKit accept、BG 寫入、`pendingRingCallData` 預寫、**緊急路徑**）；
三個消費端（`family_main_screen::_checkPendingAcceptedCall`、`elder_home_screen::_onPendingCallChanged`、`splash_screen::_isPendingRoleReversed`）消費前驗證 `senderRole != appRole`。
**不可移除**：相等代表這通「來電」實為自身角色發出的 stale 資料，照常 `sendCallAccept` 會讓對端反被叫。

**G17 — `monitor-wakeup` 正規化（前端側）**
`main.dart` BG + FG handler：收到 `monitor-wakeup` 且 `saved_is_cctv == false` → 正規化為 `call-request`。
完整鏈路見 §6.4。

**G18 — 原生通知備援 + `endAllCalls` try-catch**
- `local_call_notification.dart` 是 MIUI 下 CallKit 靜默失敗時**唯一**的後備來電畫面，**禁止移除**。
- 所有 `FlutterCallkitIncoming.endAllCalls()` / `showCallkitIncoming()` **必須包 try-catch**（MIUI 會拋 `PlatformException(content is null)`）。
- `endAllCalls` / 拒接 / 接聽 / `cancel-call` 時**必須一併** `LocalCallNotification.cancel()`。
- `elder_home_screen.dart::_requestPermissions` 的 Android 14+ 全螢幕權限引導用套件 API（自帶版本判斷），**禁止**寫死 SDK 版本判斷。
- `android/app/build.gradle.kts` 的 **core library desugaring 不可移除**（`flutter_local_notifications 18.x` 需求，移除會 build 失敗）。

**G19 — CallKit 是唯一的主要來電 UI 路徑**
- BG handler 的 `call-request` 分支（**長輩端與家屬端皆然**）必須呼叫 `_showFullScreenCallkit()`。
  **禁止**改回「只發 `LocalCallNotification` 就 return」。
- `_showFullScreenCallkit` 尾端的**備援互斥探測**（輪詢 `activeCalls()` → 沒建立才 `LocalCallNotification.show`）
  **必須放在 BG `bgSub` listener 註冊之後**——它會 `await`，擺在前面會延後拒接／接聽 listener 的註冊而漏接早期事件。
- **禁止**恢復 `data['useLocalBackup']` 旗標判斷：全鏈路（含後端）從未設定該欄位，是死碼。

**G20 — `local_call_notification.dart::consumeLaunchPayload()`**
必須在 `main()` 讀取 `pendingAcceptedCall` prefs **之前**呼叫，其後接 `prefs.reload()`。
**不可移除**：APP 已終止時點擊備援通知，payload 只存在於 `getNotificationAppLaunchDetails()`；
`onDidReceiveBackgroundNotificationResponse` 對這個情境**不保證**觸發。

**G21 — 備援通知的拒接必須能在裸 isolate 存活**
`notificationBackgroundTapHandler` 開頭必須有
`WidgetsFlutterBinding.ensureInitialized()` + `DartPluginRegistrant.ensureInitialized()`；
`_handleDecline` 必須**先** `ApiService.declineCall`、**後**清 prefs，每段各自 try/catch。
**不可改回「prefs 先、整包一個 try/catch」**：`SharedPreferences.getInstance()` 在裸 isolate 拋
`MissingPluginException` 會被整包吞掉 → `declineCall` 永遠執行不到 → 使用者看到「只能接聽、無法拒絕」。

**G22 — 緊急通話必須記錄 `lastProcessedCallId`**
`signaling.dart` 的 `emergency-call` handler 與 `main.dart::s.onEmergencyCall` 都要設
`lastProcessedCallId`/`lastProcessedCallTime`；
`elder_screen.dart::_checkPendingAcceptedCall` 的 `isSameOngoingCall` 必須同時比對 `_activeCallId`（第二道防線）。
緊急路徑寫入 `pendingAcceptedCall` 時**必須帶 `senderRole`**。
> ⚠️ **2026-08-11 第二十二輪改寫（需求 10）**：本條原文是
> 「緊急通話的 FCM ~~刻意不帶~~ `issuedAt`/`expiresAt`（ttl 維持 ~~3600s~~）——帶了會被前端 120s 過期判斷誤殺」。
> **這條已經作廢，現在完全相反**：緊急通話的 Socket 與 FCM **兩條路都必須帶** `issuedAt`/`expiresAt`
> （`expiresAt = issuedAt + 60000`），FCM `ttl` 也一律 **60s**。
> **推翻的理由**：舊設計是為了「不要誤殺緊急通話」，代價卻是**緊急通話永遠不會過期**——
> ttl 3600s 意味著一通兩三分鐘前就該結束的緊急通話，可以在**一小時後**才被 FCM 送達並彈出來電畫面，
> 這正是使用者回報的「延遲來電通知」最極端的一種。緊急與否不改變「這通電話早就沒人在等了」的事實。
> 「怕誤殺」在有效期是 120s 時是合理顧慮，收斂到 **60s** 且發起端本來就只等 1 分鐘之後，
> 過期即代表「發起端已經放棄」，此時彈出來電才是錯的。見 **G73**。
完整鏈路見 §4.7。

**G23 — 通話終止提示若要顯示，必須用 dialog（不可用 `SnackBar`）**
緊接的 `_goHomeAfterCall()` 是 `pushAndRemoveUntil((route)=>false)`，
會當場移除 route 讓 SnackBar 消失 → 「瞬間、無提示跳回主畫面」。
> ⚠️ **2026-08-05 第十八輪修訂**：原條文要求 `onCallEnded` / `onCallBusy` / `onConnectionLost`
> **一律**走 `_showCallRejectedThenGoHome()`。使用者已明確要求刪除「通話已結束」視窗，
> 故 `onCallEnded`（正常掛斷）改為**靜默**直接返回主介面。
> 本條現在只約束「**決定要顯示提示時**該用什麼元件」，見 **G50**。

**G24 — `last_elder_*` 快速登入記憶鍵**
`last_elder_id` / `last_elder_name` / `last_elder_room_id` / `last_elder_device_role`。
使用者主動登出（`elder_tabs/elder_profile_tab.dart::_handleLogout`）**不可清除**這組鍵。
`_quickLoginSameElder` 回退時**必須一併還原 `device_role_$room` 與 `saved_is_cctv`**
（否則重判裝置角色，誤判成 monitor 就觸發 §6.4 的整條 bug 鏈）。
只有家屬端遠端 `force-logout` 才連同清除。
> ⚠️ 另有第二處登出：`elder_screen.dart`:674-680 也會 remove `saved_is_cctv`/`saved_role`/`saved_id`/
> `saved_device_name`/`user_role`/`caregiver_id`/`caregiver_name`。改登出行為時**兩處都要看**。

**G25 — 去重 token 只能由「真正顯示 UI 的通路」宣告（第十四輪核心不變式）**
`_claimCallDedupToken(callId)` 只能在**確定要顯示來電 UI 的當下**呼叫。
FCM 前景路徑必須先排 **1500ms** 寬限期，屆時依序檢查
`mounted` → `callId == lastProcessedCallId` → `_isExpiredCallPayload` → `isCallInvalidated`
全部通過才 claim 並顯示。
**禁止**改回「先寫 token 再判斷要不要顯示」：那會讓 FCM 通路「先佔位、再什麼都不顯示」，
把 Socket 通路的來電殺掉 → 家屬端在 APP 內約 90% 收不到來電。

**G26 — `_showIncomingCallDialog` 的 guard 必須釋放**
`showDialog(...)` 尾端必須接 `.then((_) { _activeCallDialogContext = null; });`
**不可移除**：對話框若以其他方式關閉，guard 會**永久卡住**，之後所有來電 dialog 全被擋。
對照組：`family_main_screen.dart`:398-400 的 `.then((_) => _isIncomingCallDialogOpen = false)`。

**G27 — 不可在 `Signaling` 單例上新增「影響顯示流程」的全域旗標**
歷史事故：曾加入 `isIncomingCallDialogVisible` 全域 guard，導致長輩端冷啟動失敗、已回退。
可以加的是**與 callId 綁定、讀不到就退回安全預設的純資料欄位**
（如 `incomingCallIsVideoCallId` / `incomingCallIsVideo`，與 `lastProcessedCallId` 同一模式）。

**G28 — 不可更動 `typedef CallRequestCallback` 簽章**
有 8 個註冊／清空點：`main.dart`:1481（**G1 的角色守門就在這行**）、
`elder_home_screen.dart`:114/266、`family_main_screen.dart`:124、
`family_dashboard_screen.dart`:155、`family_dashboard_view.dart`:127、`socketio_test_screen.dart`:35/194。
需要傳新資訊時，用 G27 的「callId 綁定資料欄位」模式，不要改簽章。

**G37 — 「已連線」UI 與通話計時不可綁在 `onTrack` / `onAddRemoteStream` 上**
`onTrack` 只代表 **SDP 談成**，不代表 ICE 已連通、更不代表有位元組在流動。
計時器必須由 `onPeerConnected` 觸發，而 `onPeerConnected` 取
`onConnectionState == Connected` **與** `onIceConnectionState == Connected/Completed` 的**聯集**
（`signaling.dart`:887-925）。
- 取聯集是**刻意**的：`flutter_webrtc` 在部分 Android 原生層 `onConnectionState` 回報不完整，
  單押它會讓正常通話**完全不計時**——比修復前更糟。兩端的 `_startCallTimer()` 都以
  `_callTimer?.cancel()` 開頭，冪等，重複觸發無副作用。
- 🚫 **絕對不要**把 `RTCIceConnectionStateFailed` 接到 `onPeerConnectionFailed`：
  ICE 層的 Failed 有機會自行恢復，接上去等於製造「通話中途無故被掛斷」的新回歸。
  失敗判定只由 `onConnectionState` 的 `Failed` 分支與 G38 的媒體看門狗負責。

**G38 — 媒體看門狗只能掛在 `onTrack`，不可掛在 Connected**
`_startMediaWatchdog()`（`signaling.dart`:985）在收到 remote track 後 **12 秒**檢查
`inbound-rtp` 的 `bytesReceived` 總和，仍為 0 就呼叫 `onPeerConnectionFailed` 據實回報。
🚫 **不可改掛在 `onConnectionState == Connected`**：`startMonitoring()` 建立的是 **recvonly**
監控連線，那一端本來就不會收到 remote track、永遠不會有 `inbound-rtp`，
掛在 Connected 上會**誤殺所有 CCTV 監控連線**。
清理點有三處（`hangUp` / `_cleanup` / PeerConnection close 前），少一處就會在連線關閉後才觸發。

**G39 — TURN 的靜態帳號必須排在第一組**
Coturn 實際只有 `lt-cred-mech` 靜態帳號 `uban`（`README.md`:338-343）。
`_turnUser`／`_turnPass` 那組必須是 `iceServers` 的**第一組 TURN**；
`uban_elder_<id>` 那組是為「日後真的開了 per-elder 帳號」預留的，只能**附加在後面**。
🚫 **不可改回只送 `uban_elder_<id>`**：會被 Coturn 回 401 → 拿不到任何 relay 候選 →
同網域靠 srflx 還能通、**跨網域對稱 NAT 就必然「SDP 談成、ICE 配不出 pair」**
→ 有通話計時卻零影音（第十七輪問題 2 的根因）。

**G40 — 裝置在線判定的 debounce 不可重啟、且不可與輪詢週期相等**
`family_main_screen.dart::onElderDevicesUpdate`：
- 裝置**清單**（`_monitorDevices`）與「離線→上線」一律**立即套用**，不 debounce。
- 只有「上線→離線」方向做 **2.5 秒**確認，且計時器用 `??=` 建立，**永遠不因新事件重啟**。

🚫 **不可改回「每收到事件就 cancel + 重排」的雙向 debounce**：
輪詢週期也是 2500ms、後端還會廣播給房內所有家屬 socket，於是 debounce 幾乎永遠在 fire
之前就被下一個事件取消 → `_isElderOnline` 與 `_monitorDevices` **長期停在初始值**
（家屬端看不到監視機、在線燈不亮）。
`isOnline` 的型別檢查要容忍 bool / int / String 多型別（`_isDeviceOnline`，:340）。

**G41 — 跌倒警報去重必須用 `alertId + timestamp` 複合鍵**
後端 `_insert_alert()` 對同 elder+device+type 的 active 列是 UPDATE 並**沿用原 alert_id**。
只用 `alertId` 去重 → 第二次以後的同類警報**完全靜默**。見 §3.2 與 §6.9。

**G42 — 跌倒警報彈窗的防疊加旗標必須是畫面內的區域變數**
`_cctvAlertDialogOpen` 宣告在 `_FamilyMainScreenState` 內。
🚫 **不可搬進 `Signaling` 單例**——這正是 G27 禁止的那類「影響顯示流程的全域旗標」。

**G47 — `ElderScreen` 進場時必須「無條件」呼叫 `_signaling.connect()`**
🚫 **不可再包一層 `if (socket?.connected != true)`**。
`Signaling.connect()` 內部（`signaling.dart`:169-173）**本來就有**「已連線則只重新 `_asyncJoin`」
的重用分支，不會重新註冊 listener、不會覆寫 callback，一律呼叫是安全的。
包上外層 guard 的後果：監控機在配對後若 socket 已連著，就**永遠不會**以
`deviceMode:'monitor'` 加入 `monitor_elder_<id>`，停留在 `comm_elder_<id>`，
家屬端遠端視訊清單因此**永遠是空的、重開 App 也不會好**（第十八輪需求 5 前端根因）。

**G48 — 冷啟動衝刺通道不得繞過既有的來電有效性檢查**
`splash_screen.dart::_sprintToPendingCall()` 只在 `pendingAcceptedCall.value != null` 時啟用，
且**只讀本機 prefs、不呼叫任何 API**；角色校正改由 `_refreshRoleInBackground()` 背景執行
（仍必須 `user_role` + `saved_role` **兩個鍵一起寫回**，見第十六輪 / G16 系列）。
🚫 衝刺通道**不可自己決定要不要進房**——導航一律交給既有的
`_resolveElderDestination()`（內含角色反轉檢查）與 `_navigateFamilyHome()`
（內含角色反轉 + 有效期檢查）。本機資料不完整就回傳 `false` 退回標準流程，
**不可自行兜底**：標準流程有多層防線，衝刺通道只是抄捷徑、不是取代它。
`ApiService.getStatus` 在標準流程必須帶 `.timeout(6s)`，逾時落入既有 catch 由 prefs 決定去向。

**G49 — 鎖屏覆蓋只做「蓋上去」，不主動解安全鎖；離開通話必須還原**
`MainActivity.kt::showOverLockScreen()`：
- 靠 `setShowWhenLocked(true)` + `FLAG_SHOW_WHEN_LOCKED` 讓通話畫面**蓋在**鎖定畫面之上。
- `requestDismissKeyguard` **只在 `!keyguardManager.isKeyguardSecure` 時**呼叫。
  🚫 **不可無條件呼叫、也不可加回 `FLAG_DISMISS_KEYGUARD`**：有 PIN／圖形／指紋的裝置
  會被強制彈出解鎖畫面，使用者必須先解鎖才能接聽（第十八輪需求 4 的成因）。
- 通話畫面離開時**必須**呼叫 `restoreLockScreen`（清掉 `setShowWhenLocked`／
  `setTurnScreenOn`／三個 window flag），否則 App 會**永久蓋在鎖定畫面之上**、螢幕永不休眠。
  呼叫點：`video_call_screen.dart::_goHomeAfterCall()` 開頭、
  `elder_screen.dart::dispose()`（**`isCCTVMode` 除外**——監控機必須維持恆亮才能持續推幀）。
- Dart 端一律用 `.catchError()` 而非同步 `try/catch`：`invokeMethod` 的
  `PlatformException` 是**非同步**丟出的，同步 `try/catch` 接不到（會變成 dead code）。

**G50 — 「正常掛斷」靜默返回，「異常結束」仍必須有提示**
`video_call_screen.dart`：
- `onCallEnded`（正常掛斷）→ `_endCallAndGoHome()`，**不顯示任何視窗**
  （使用者第十八輪需求 3 明確要求刪除「通話已結束」對話框）。
- `onCallBusy`（拒接／忙線）／`onConnectionLost`／`onPeerConnectionFailed`
  → `_showCallProblemThenGoHome(title, message)`，**保留提示**。
🚫 **不可把這三條也一起消音**：家屬撥出後若毫無提示就跳回主畫面，會分不清是被拒接
還是自己誤觸；第八輪的拒接回饋與第十七輪的媒體看門狗失敗回報都依賴它。
🚫 提示元件仍受 **G23** 約束（必須 dialog，不可 `SnackBar`）。
🚫 標題**不可**再叫「通話已結束」——那正是需求 3 要刪掉的視窗。

**G55 — `monitorViewOnly` 是 G8「鏡頭預設開啟」的明文例外，只有 CCTV 檢視可傳 `true`**
`VideoCallScreen.monitorViewOnly` 預設 **`false`**。為 `true` 時才允許：
不取視訊軌（`getUserMedia` 只要 `audio`）、隱藏本地預覽 PiP、隱藏鏡頭開關與前後鏡頭切換，
控制列只剩**麥克風／擴音／掛斷／返回**。
全專案**只有兩個** CCTV 檢視建構點可以傳 `true`，且**兩處都必須傳**：

| 入口 | 建構點 |
|------|--------|
| 互動分頁監控卡片「觀看 CCTV」 | `family_interaction_tab.dart::_buildMonitorDeviceCard` |
| 跌倒警報彈窗「查看監視畫面」 | `family_main_screen.dart::_presentCctvAlert` |

🚫 其餘所有 `VideoCallScreen(` 建構點（來電接聽 ×2、`_startNormalVideoCall`）**一律維持預設 `false`**——
一般通話與緊急通話的鏡頭仍必須預設開啟。
🚫 **不可只改其中一個 CCTV 入口**：同一個監控功能從兩個入口進去行為不一致，
使用者只會回報成「有時候會開自己的鏡頭」，極難定位。
> 記在這裡的理由：**G8 曾被後續 AI「修」回去過一次。**
> 看到 `monitorViewOnly` 不要以為它違反 G8 而刪掉——它是 G8 唯一的登記在案例外。

**G56 — 監視機自動接聽必須「靜音」，但不得「不接」**
`elder_screen.dart::_handleEmergencyAccept()` 在 `isCCTVMode == true` 時**必須**跳過 `FlutterTts` 播報。
🚫 但 `endAllCalls()` 與 `sendCallAccept(...)` **不可**一併略過——
監視機仍要自動接聽，只是全程無聲。拿掉 `sendCallAccept` 會讓監控完全建立不起來。
**原因**：家屬開啟監控不應驚動被監控端（第十九輪需求 1）。
> 附帶事實（勿誤判）：後端 FCM **本來就已經是 data-only**
> （`socket_app.py` 全檔的 `messaging.Message(` 建構點都沒有 `notification` 區塊），
> 監控的聲音來源**只有**上述 `FlutterTts` 一處。不要為了「消音」去動後端送信迴圈。
> 同理，本輪**沒有**在被監控端新增任何「有人正在觀看」的提示——
> `elder_screen.dart` 的「CCTV 監視中…」是靜態模式標籤，不是觀看者指示器，維持原樣。

**G58 — 換身分／登出一律走 `SessionManager`，禁止各自 remove 或 `prefs.clear()`**
`lib/services/session_manager.dart`:18 的 `_sessionKeys` 是「session 由哪些鍵構成」的唯一定義。
- 四個登出入口（`family/family_settings_view.dart`、`family/family_data_tab.dart` ×2、
  `family_dashboard_screen.dart`、`elder_tabs/elder_profile_tab.dart`）一律
  `await SessionManager.releaseSession()`。
- `identification_screen.dart`:26 進入身分選擇頁時 `SessionManager.releaseIfBound()`。
🚫 **禁止**在別處手寫 `prefs.remove('user_role')` 這類片段清理，也**禁止** `prefs.clear()`。
**原因**：第二十輪的需求 1／5 就是這麼壞掉的——身分選擇頁沒釋放 session，
於是（a）停在身分選擇頁也會收到上一個帳號的來電；（b）重新開 App 直接登入被綁死的帳號；
（c）曾當過監控機的裝置永遠綁不上新配對碼。片段清理必然漏鍵，鍵一漏 session 就活著。
`wake_word_enabled` 等裝置偏好**刻意不在** `_sessionKeys` 內（見 G59），所以 `prefs.clear()`
會多殺；反過來手寫 remove 又會少殺。兩邊都錯，只能走同一份清單。

**G59 — 語音喚醒預設關閉，五條自動重啟路徑都必須先過旗標**
`globals.dart`:29/:32 的 `wakeWordEnabledNotifier` / `kWakeWordEnabledKey`（預設 **`false`**）。
`elder_home_screen.dart` 的五個入口都必須在**申請麥克風權限之前**早退：
`_initWakeWordListener`（:132）、`_loadAssistantSettings`（:161-172）、
`_startWakeWordWatchdog`（:197）、`_safeRestartWakeWordListening`（:263）、
`didChangeAppLifecycleState`（:278）。開關在 `elder_tabs/elder_profile_tab.dart`。
🚫 **禁止**把預設值改成 `true`，也**禁止**只擋其中幾條。
**原因**：這五條會互相把對方拉起來（watchdog 每 5 秒檢查、lifecycle resume 重啟、
STT 的 `onStatus` 收到 `done` 再排一次），只要漏掉一條，麥克風就會恢復成
「開 App 後無限開開關關」。而這個 App 全程環繞長輩語音操作，
麥克風被雜訊觸發就會誤啟動 AI 對話。

**G60 — 監控檢視不得出現「掛斷」鍵**
`video_call_screen.dart`:868 的 `Icons.call_end` 必須包在 `if (!widget.monitorViewOnly)` 內。
離開監控只有左上角「← 返回」一個出口（`returnByPop: true`，:715-721）。
🚫 **禁止**恢復掛斷鍵「當作備援」。
**原因**：監控是單向觀看不是通話，掛斷會發 `end-call` 到一個沒有對端通話的房間；
兩個出口並存也讓使用者無從判斷該按哪個。

**G61 — 音量來源：一般通話走聽筒、視訊走擴音，自動切換只能發生一次**
`_isSpeakerOn` 的初值（`video_call_screen.dart`:72 宣告、`elder_screen.dart`:173）
= `isVideoCall || isEmergency || monitorViewOnly`。
語音通話中途開鏡頭時由 `_autoSwitchToSpeakerOnCameraOn()`（:368）切成擴音，
並立刻把 `_speakerAutoSwitched`（:76）設起來。
🚫 使用者手動按過喇叭鍵（`_toggleSpeaker`:422 也會設該旗標）之後，
**禁止**任何自動邏輯再覆寫他的選擇。
🚫 圖示**禁止**改回 `volume_up`/`volume_off`——`volume_off` 讀起來是「靜音」。

**G62 — 撥出前必須確認 socket 已連上，`issuedAt` 要在連上之後才取**
`signaling.dart::sendCallRequest`（:781）是 `Future<bool>`：socket 為 null 直接回 `false`，
未連線則輪詢 50×100ms（最多 5 秒），**連上之後**才 `DateTime.now()` 取 `issuedAt`。
🚫 **禁止**改回 `void` 或「不管連沒連上就 emit」。
**原因**：長輩端「APP 內撥不出去」（第二十輪需求 7）就是這樣——
`emit` 在未連線的 socket 上是**靜默丟棄**，畫面會停在「撥號中」直到逾時，
兩端都沒有任何錯誤。另外若在輪詢**之前**就取 `issuedAt`，等到真的連上時
已經燒掉數秒有效期，接聽端可能當場判定過期。

**G63 — 家屬端 Row 裡的動態文字必須有寬度約束**
凡是長度不可控的文字——長輩名字、AI 產生的 `mood_title`、後端下發的
`alert.typeLabel`、方案特色文案——放進 `Row` 時必須包 `Expanded`／`Flexible`，
或（當它是非 flex 子元素時）用 `ConstrainedBox(maxWidth:)` 設上限。
🚫 只加 `overflow: TextOverflow.ellipsis` **沒有用**：`Text` 仍會索取完整的固有寬度，
RenderFlex 照樣溢位（黃黑斜紋警示）。
🚫 也**不要**無腦全包 `Flexible`：`Row` 本身若收到**無界**寬度約束，
內含 flex 子元素會直接丟 assertion。每個點都要個別看。
**原因**：`Row` 會**先用無限寬量測非 flex 子元素**，量出來多寬就佔多寬——
一個 AI 產生的長徽章可以把空間吃光，讓旁邊的 `Expanded` 只剩 0 寬，然後整條溢出。
第二十輪需求 2 的 12 處修正都是這個形狀。
⚠️ **第二十一輪補充**：第二十輪漏掉了 `family_interaction_tab.dart::_buildCallSection()`
（:938 起，深藍漸層 `#1E1B4B → #1E40AF → #0284C7` 那張「視訊通話」卡片）——
它的內層 `Row`（:990）在外層 `Expanded` 裡放了 **兩個非 flex 子元素**
（`Text('視訊通話')` ＋ 徽章 `Container`），必定溢出 13px。
已改為 `Wrap(spacing: 8, runSpacing: 4)`：**`Wrap` 永遠不會溢位**，
遇到「標題＋徽章」這種寬度都不可控的組合，它比 `Expanded`／`ConstrainedBox` 更省事也更安全。

**G67 — `pendingAcceptedCall` 的每個寫入點都必須帶 `timestamp`；讀取端「缺 `timestamp` 一律視為過期並移除」**
寫入點目前有四處：`main.dart` BG 緊急路徑（:236）、備援通知路徑（:218）、
CallKit accept（:477）、`s.onEmergencyCall` 的長輩分支（~:1682）。
讀取點（`main()` :599、`_checkPendingCallFromSharedPreferences` :1249）的判斷必須是
`if (ts == null || ageMs > 60000) { await prefs.remove('pendingAcceptedCall'); }`。
`pendingRingCallData` 同理（窗口 60000ms，**2026-08-11 第二十二輪：120000 → 60000**）。
🚫 **禁止**把「缺 `timestamp`」當成 `age = 0`（新鮮）。
> ⚠️ **2026-08-11 第二十二輪修訂**：原文此處有一條
> 「~~🚫 **禁止**在緊急路徑補 `issuedAt`／`expiresAt` —— 那是 G24 明訂的刻意省略~~」，
> 有**兩個錯**：一是條號寫錯（該規則屬 **G22**，G24 是 `last_elder_*` 快速登入記憶鍵）；
> 二是規則本身已被第二十二輪推翻——緊急路徑**現在必須**補上這兩個欄位。
> 但下面這句仍然成立、且**更需要強調**：
> `timestamp` 是**另一個、純本機**的新鮮度鍵，與後端下發的 `issuedAt`/`expiresAt` **不可混為一談**。
> 兩者現在窗口值剛好都是 60s，這是巧合不是同一件事：
> 前者量的是「這筆 prefs 在本機躺了多久」，後者量的是「發起端還願意等多久」。
> 🚫 **不可**因為數字一樣就把其中一個刪掉、或用其中一個推導另一個。
**原因**：第二十一輪需求 4「APP 永久白屏」的根因就在這裡。
`s.onEmergencyCall` 是全專案唯一漏帶 `timestamp` 的寫入點，而缺 `timestamp` 時
`ts != null && ageMs > 60000` 恆為 false → 這筆資料**永遠不會過期**；
緊急通話結束時又沒有任何路徑移除該 prefs 鍵 →
之後**每一次**冷啟動都重新載入同一通早已結束的通話 →
Splash 立刻 `_fadedOut = true`（沒有開場動畫）並被導去一通死掉的通話 →
使用者看到的就是「怎麼重開都是不會動的白畫面」。
「讀取端移除」這一半是**已中毒裝置的自癒路徑**，比「寫入端補欄位」更不可省。

**G68 — `runApp()` 必須無條件執行；開機路徑上的每一個 `await` 都要有 `.timeout()`**
`main()` 的結構固定為：`_bootstrap().timeout(10s)` 包在 try/catch 裡，
`runApp(const MyApp())` 在 try/catch **之外、無條件**執行。
`_bootstrap()` 內部每個 platform channel 呼叫各自帶逾時：
`dotenv.load` 3s／`initializeDateFormatting` 3s／`SharedPreferences.getInstance()` 5s／
`prefs.reload()` 3s／`consumeLaunchPayload()` 3s／`Firebase.initializeApp()` 6s／
`LineSDK.setup()` 4s／`FirebaseMessaging.requestPermission()` 4s。
🚫 **禁止**把 `runApp()` 移進 try 區塊或任何 `await` 之後而不設逾時。
🚫 `requestPermission()` **必須**排在 `onBackgroundMessage` 註冊**之後**（它會等系統對話框）。
**原因**：Dart 的 `try/catch` 攔得到**丟例外**，攔不到**卡住**。
只要有一個 platform channel 不回來，`runApp()` 就永遠不會被呼叫 →
畫面停在系統的原生啟動底色（純白、無動畫、無法操作、也不可能跳轉），
而且每次重開都一樣。`.timeout()` 把「卡住」轉成可攔截的例外
（它不會取消底層工作，那個 future 仍會繼續跑完，這正是我們要的）。
`configureHttpOverrides()` 是同步函式，刻意不包。

**G69 — `SplashScreen` 必須有導航看門狗與 `_navigated` 互斥旗標**
`_navigated`（一次性）＋ `_navWatchdog`（15s）＋ `_slowBootTimer`（5s 後顯示載入指示）。
所有 `Navigator.pushReplacement` 一律走 `_replaceWith()`；
`_navigateFamilyHome` 因為要「先 replace 再 push」不能用它，但**必須自己補**
`if (!mounted || _navigated) return; _navigated = true; _navWatchdog?.cancel();`。
`dispose()` 要在 `splashActive = false` **之前**取消兩個 timer。
Splash 內每個 `await`（prefs 3~5s、`ApiService.getPairedElders` 6s、
`FlutterCallkitIncoming.activeCalls()` 2s）都要有逾時。
🚫 **禁止**移除 `_navigated` 互斥後只留看門狗：看門狗會與正常路徑競態導致雙重導航。
**原因**：Splash 是冷啟動唯一的導航決策點，只要它的任何一條 `await` 卡住，
使用者就永遠停在開場畫面上（動畫跑完淡出後是一片純色，看起來完全等同白屏）。
`_slowBoot` 指示器刻意畫在動畫**下層**：動畫還不透明時看不到，
只有在 `_fadedOut` 之後、導航卻還沒發生的那段空窗才露出來。

**G70 — 長輩端的房名不得退回 `caregiver_id`**
`friends_screen.dart::_startCall`（:66）解析順序固定為
`widget.roomId` → prefs `elder_room_id` → **明確報錯**（`SnackBar`「找不到您的通話帳號資料」）。
上游每個建構 `ElderHomeScreen` 的地方都必須把 `roomId` 傳下去，
包含 `video_call_screen.dart::_buildFallbackHome()`（:476）。
🚫 **禁止**寫成 `widget.roomId ?? widget.userId.toString()`。
**原因**：`FriendsScreen.userId` 是 `caregiver_id`（帳號整數 PK），**不是** `elder_id`。
拿它拼出來的 `comm_elder_<caregiver_id>` 是個不存在的房間，
後端 `_get_family_ids_for_elder()` 查不到任何家屬 → log 印「無任何轉發目標」→
長輩按下撥打後**完全沒有反應、兩端零錯誤**（第二十一輪需求 1）。
房名前綴由 `ElderScreen::_getFormattedRoomId()` 統一補，且是冪等的，
所以帶著 `comm_elder_` 前綴的值傳下去也安全。

**G71 — `_initElderMode()` 的 `getToken()` 必須有逾時，`.then()` 必須帶 `onError`**
`elder_screen.dart`：`FirebaseMessaging.instance.getToken()` 包 try/catch ＋ `.timeout(5s)`，
失敗就以「無 token」繼續進房；`_initElderMode().then(...)` 的第二參數必須是
`onError:`，且錯誤分支**照樣**呼叫 `tryAutoCall()`。
🚫 **禁止**讓任何未加逾時的 `await` 擋在 `_signaling.connect()` 之前。
**原因**：`getToken()` 在網路異常／Google Play 服務異常時可以掛很久。
它卡住會同時封死兩件事——後面的 `connect()`（:475，於是根本沒進房），
以及 `.then()` 的 autoCall 鏈（於是 `autoCall: true` 靜默失效）。
沒有 `onError` 時，`_initElderMode()` 一丟例外就整條 `.then()` 不執行，
使用者看到的同樣是「按了撥打沒反應」。

**G73 — 來電有效期是 **60 秒**，且只能有 `kCallValidityMs` 一個來源（前後端一致）**
`globals.dart`:47 `const int kCallValidityMs = 60000;`。
前端所有過期判斷（`_isExpiredCallPayload`、消費 `pendingAcceptedCall`/`pendingRingCallData` 前的檢查、
`splash_screen.dart` 兩道最後防線）**一律引用這個常數**；
後端 `call-request` / `emergency-call` 的 `expiresAt = issuedAt + 60000`、FCM `ttl` 同為 **60s**。
🚫 **禁止**在任何地方再寫死 `120000` / `60000` 字面值（第二十二輪已清掉 `main.dart`:672、
`splash_screen.dart`:272/:288 三處）。
🚫 **禁止**為緊急通話開特例（那正是被推翻的舊 G22，見該條的修訂說明）。
> ⚠️ CallKit 的 `duration: 45000`（`signaling.dart`:662）**是另一回事**——那是「響鈴幾秒」，
> 不是「這通電話還有效嗎」。兩者不可互相推導、不可合併。
**原因**（第二十二輪需求 10）：使用者回報「明明兩三分鐘前撥的電話，怎麼突然跳出來電通知」。
網路不佳時 FCM 會延遲送達，而舊值 120s（緊急路徑甚至 **3600s**）讓一通早就沒人在等的通話
仍被判定有效並彈出來電畫面。使用者要的是「發起端最多只等 1 分鐘」，
60s 就是這條規則在資料契約上的投影。

**G74 — `monitorViewOnly` 只能隱藏 UI，不得停用計時邏輯**
`video_call_screen.dart` 頂部資訊列（通話類型膠囊 + 紅色時長膠囊）包在
`if (!widget.monitorViewOnly)` 內即可。
🚫 **禁止**順手把 `_callTimer` 停掉、把 `_inCall` 改成 false、或跳過 `_formattedDuration` 的更新。
**原因**：使用者只要求「監控畫面不要出現計時與『緊急通話』字樣」（第二十二輪需求 4），
但 `_inCall` / `_callTimer` 同時是掛斷判斷與通話記錄的依據，
停掉它們會讓 CCTV 檢視的離開流程走進「從未接通」分支。
**顯示與狀態要分開改**——這是本專案反覆踩到的同一類錯。

**G75 — CCTV 推幀迴圈的三層自癒不可拆（逾時 / 連續失敗 / 看門狗）**
`elder_screen.dart::_startCctvFrameLoop`（:181）必須同時具備：
1. `captureFrame().timeout(6s)` 與 `pushCctvFrame(...).timeout(10s)`；
2. `_cctvFrameFailStreak >= 3` → `_recoverCctvCapture()`；
3. `_cctvLastFrameOkAt` **30 秒**無成功影格看門狗（且必須放在 `localStream` 檢查**之前**）；
4. `finally { _cctvFrameSending = false; }`。
🚫 **絕對不可移除第 4 點**，它是「畫面停住」的解鎖點。
🚫 **不可**把 `_recoverCctvCapture()` 換成直接呼叫 `_initializeMedia()`——後者開頭有
`if (_mediaInitialized) return;`，直接叫等於什麼都沒做。
**原因**（第二十二輪需求 3，使用者回報「奇數次進入監控會讓監控機停機、偶數次才恢復」）：
家屬端進入監控時，監控機的 `_closePeerConnection()` 會 `removeTrack` 把視訊軌從編碼器拆下來；
若此刻剛好有一輪 `captureFrame()` 在等原生層回傳，那個 Future **永遠不會完成**——
不是丟例外，是卡住，`try/catch` 攔不到 → `finally` 不執行 → `_cctvFrameSending` 永遠停在 `true`
→ 之後每一輪都被開頭的 `if (_cctvFrameSending) return;` 擋掉。
家屬端再進一次時 peer connection 重建、軌道重掛，卡住的 Future 才被原生層以錯誤收掉，
`finally` 終於跑到 → 旗標歸位。**這就是奇偶數規律的完整機制**，不是玄學。
> 🪤 這是本專案第二次被「Dart 的 `await` 可以永遠不返回」咬到（第一次是第二十一輪的開機路徑，見 G68）。
> **只要是等原生層／網路的 `await`，就該有 `.timeout()`。**

**G76 — 離開監控時：先停推幀、先還相機，`forceDisconnect()` 必須真的 `dispose()` socket**
`elder_screen.dart::_exitCCTVMode()` / `dispose()` 的順序固定為
**停 `_cctvFrameTimer` → `stopMedia()` 還相機 → 解除掛在 socket 上的原生監聽（`force-logout` 等）
→ `SessionManager.releaseSession()` → `forceDisconnect()`**。
`signaling.dart::forceDisconnect()` 一律走 `_disposeSocket()`（:1429），
其內部順序固定為 **`clearListeners()` → `dispose()`**，兩步各自 try/catch，
並把 `_currentRoomId` / `_peerSocketId` 清成 `null`。
🚫 **禁止**改回 `if (socket != null && socket!.connected) { socket?.disconnect(); socket = null; }`。
**原因**（第二十二輪需求 8：「從監視機跳回長輩端後通話全滅、>50% 機率 ANR」）：舊寫法有兩個致命點——
(a) socket **已經斷線**時整段是 no-op，`socket` 欄位仍指著舊物件，它的 handler 與**重連排程都還活著**
（監控機退出時正是這個狀態）；(b) 就算進得去，也只 `disconnect()` 不 `dispose()`，listener 全留著。
於是長輩端會同時存在**新舊兩個 socket**：新的負責來電通知（所以「通知收得到」），
舊的搶走 join／SDP 回應（所以「進了房卻永遠連不上」、「按接聽沒反應」），
而未釋放的相機再疊上來就是 ANR。
> `clearListeners()` 必須在 `dispose()` **之前**：`dispose()` 內部的 `disconnect()` 會觸發
> `onclose('io client disconnect')`，沒先拔掉 handler 就會回打到 `onConnectionLost`，
> 退出監控時誤跳「連線中斷」。

**G77 — 緊急通話：無條件自動接聽 + 7 秒提示音，且提示音必須停得掉**
`elder_screen.dart`：緊急通話一律自動接聽（**不再限於 CCTV 模式**，:502）。
> **2026-08-12 第二十三輪擴充**：自動接聽的責任已由 `ElderScreen` **上移**到
> `main.dart::_autoAcceptEmergencyCall`，四條抵達通路全部收斂在那裡——見 **G81**。
> `ElderScreen` 這一段是進房**之後**的提示音責任，兩者並存不衝突。

提示音以 `_playEmergencyTone()`（:517）取代舊的「緊急通話，自動接聽中」TTS 播報。
播放器本身在全域單例 `services/emergency_tone.dart::EmergencyTone.instance`，
音檔為 `assets/sounds/emergency_siren.wav`（7.00 s、44100 Hz 16-bit mono，
960/770 Hz **救護車雙音**每 0.5 秒交替；舊的 `emergency_alert.wav` 已刪除）。
`_stopEmergencyTone()`（:521）**必須**在 `onPeerConnected`（:550）與 `dispose()`（:1496）**兩處**都呼叫；
`main.dart` 的 FCM `cancel-call`（:1727）與 Socket `onCancelCall`（:1841）也各有一個停止點
——對端在長輩接起前就取消時，只有這兩處攔得到。
> **為什麼是單例**：提示音由 `main.dart`（進房前）播、由 `ElderScreen`（進房後）停，
> 跨兩個 widget。舊寫法把 `AudioPlayer` 放在 `_ElderScreenState` 欄位裡，
> `main.dart` 拿不到它 → 停不掉 → 響滿 7 秒蓋在通話音訊上。
> `EmergencyTone` 內部用**遞增世代編號**（`_generation`）作為停止判斷，
> 因為 `Future.delayed` 無法取消（同 **G85**）。
> ⚠️ 背景 isolate **不可**呼叫它：plugin 實例不共用，那裡播出去的聲音主 isolate 停不掉。
> 被殺死狀態的提示音因此是在冷啟動進入 `ElderScreen` 後才開始響——**刻意如此**。
🚫 **禁止**恢復 TTS 播報（第二十二輪需求 9 使用者明確要求刪除）。
🚫 **禁止**給這個 `AudioPlayer` 指定會搶音訊焦點的 `AudioContext`——見 **G27**，
全域已設 `AndroidAudioFocus.none`，單獨覆寫會讓提示音把通話音訊壓掉。
🚫 **禁止**讓提示音播放失敗中斷接聽流程：`_playEmergencyTone()` 整段 try/catch，失敗只記 log。
> **CCTV 模式仍然必須完全靜音**（G56 不變）。兩者不衝突：G56 管的是「家屬觀看監控」，
> G77 管的是「家屬撥打緊急通話」。判斷點是 `widget.isCCTVMode`。

**G78 — 「查詢失敗」與「查無此裝置」必須分得開；會員層級主色只能有一個來源**
`ApiService.fetchMonitorDevicesOrNull`（:1208）**失敗回 `null`、成功回清單**，
`fetchMonitorDevices` 只是它的 `?? const []` 包裝。
🚫 **禁止**讓 `fetchMonitorDevicesOrNull` 把失敗吞成 `const []`。
兩個消費點都必須是「`null` → 什麼都不做」：
`elder_screen.dart::_verifyMonitorStillExists()`（:999，決定顯示「連線中斷」還是「該監控機已被刪除」）、
`family_interaction_tab.dart` 的配對碼輪詢（決定要不要自動關窗）。
**原因**：網路抖一下就在監控機正常運行時謊報「該監控機已被刪除」，比不顯示還糟。
同條並管 `_tierAccentColor()`（`family_interaction_tab.dart`:2106）：
一般 `0xFF10B981`／黃金 `0xFFF5C451`／鑽石 `0xFF38BDF8`，
`_buildTierBadge()` 與監控卡片**共用同一個函式**，未知層級退回綠色、**不可拋例外**
（`tierLevel` 來自後端訂閱查詢，失敗時是任意字串，拋出去整個分頁白畫面）。
🚫 **不要**從 `family_dashboard_view.dart` 複製那組舊色票——那是為白底卡片挑的，
放到 `0xFF1E293B` 深底上黃金會整個糊掉。

**G81 — 緊急通話的自動接聽只能有一個收斂點，且長輩端永遠不得出現接聽／拒絕 UI**
使用者需求原文：「緊急通話不需要經過長輩同意，無論長輩端在 APP 內或 APP 外還是任何情況，
就由不得長輩端設備接受或拒絕接聽，而是直接打開視訊通話房間」。
緊急通話有**四條互不相干的抵達通路**，第二十二輪只修好其中兩條：

| 通路 | 第二十二輪 | 第二十三輪 |
|------|-----------|-----------|
| Socket `emergency-call`（APP 存活，`main.dart`:1804） | 自動接聽 ✅ | 改走 `_autoAcceptEmergencyCall` |
| FCM 背景 isolate（APP 被殺死，`main.dart`:225） | 寫 prefs ＋ `AndroidIntent` 喚醒 ✅ | **不變** |
| FCM 前景備援（Socket 掉線／慢，`main.dart`:1642） | **彈接聽／拒絕 dialog ❌** | 改走 `_autoAcceptEmergencyCall` |
| `_showIncomingCallDialog` 最終防線（`main.dart`:1990） | **彈接聽／拒絕 dialog ❌** | 改走 `_autoAcceptEmergencyCall` |

`_autoAcceptEmergencyCall`（`main.dart`:1892）內含：`_lastHandledEmergencyCallId` 去重、
`_claimCallDedupToken`、關閉既有來電 dialog、`endAllCalls()`、`LocalCallNotification.cancel()`、
提示音（**`saved_is_cctv==true` 時靜音**，G56）、寫 `pendingAcceptedCall`（prefs ＋ notifier）。
- 🚫 **禁止**本函式自己導航：導航統一由 `elder_home_screen` / `splash_screen` /
  `main.dart` 全域兜底三處消費 `pendingAcceptedCall` 完成。多插一條會與那三層打架（第五／六輪黑屏）。
- 🚫 **禁止**背景 isolate 呼叫它：plugin 實例不共用、提示音停不掉（見 G77）。
- 🚫 **禁止**把 FCM 前景分支移回 `isResumed` 的 1.5 秒寬限期**之後**：寬限期存在的理由是
  「讓 Socket 先彈窗、避免兩個來電 UI」，而緊急通話根本不彈窗，等 1.5 秒只是延後長輩進房。
- 角色判定必須用 `_deriveMyRoleFromCall(senderRole, appRole)`（**payload 優先、`appRole` 只作退路**），
  不可退回裸 `appRole == 'elder'`——第十六輪的角色雙鍵殘留會讓它恆不成立。

**G82 — FCM 背景 handler 必須保活到使用者做出決定，否則拒接鍵 100% 無效**
`main.dart::_showFullScreenCallkit`（:458-465、:586-598）：用一個 `Completer` 把背景
handler 的 Future 壓住，直到**拒接／響鈴逾時／接聽／通話結束**任一發生（或 **50 秒**上限）才放行。
> **根因**：`bgSub` listener 從第四輪就存在，但它的壽命等於背景 `FlutterEngine` 的壽命。
> `_showFullScreenCallkit` 一 return → Android `FlutterFirebaseMessagingBackgroundService`
> 的 `latch` 放行 → `JobIntentService` 收工 → isolate 連同 listener 一起消失。
> 使用者是**幾秒後**才按按鈕的。「接受有效、拒絕無效」正是這個 bug 的指紋：
> 接受由 CallKit **原生層**直接拉起 `MainActivity`（完全不需要 Dart），
> 拒絕卻只有 Dart 這一條路（要送 `declineCall`、要清三個 prefs 鍵）。
- 🚫 **保活必須放在整個函式的最後**，在備援互斥探測（最多 3.5 秒 `await`）**之後**。
  擺前面會讓「CallKit 沒建立就補發備援通知」整整晚 50 秒，等於廢掉 G22-era 的互斥機制。
- ⚠️ **已知取捨，刻意接受，不要「修掉」**：FCM 背景 handler 在 Android 是**序列**執行的，
  保活期間後續 FCM（例如發起方按取消的 `cancel-call`）會排隊。最壞情況是發起方取消後、
  被叫端仍響到 CallKit 自己的 45 秒 `duration` 逾時。這在 G73「來電最多等 1 分鐘」的預算內，
  換來的是「拒接從全滅變成可用」，且逾時事件終於送得到發起方（G84 的雙端對話框靠它）。
- `actionCallEnded` 分支**只放行保活、不送 `declineCall`**：結束方已經知道了，
  重複送只會製造多重拒絕訊息（G14 的單通路原則）。

**G83 — 來電備援通知的鈴聲：channel 不可就地改音，`FLAG_INSISTENT` 與 `timeoutAfter` 必須成對**
`local_call_notification.dart`：channel id 為 `uban_incoming_call_ringtone`（:50），
建立時 `deleteNotificationChannel('uban_incoming_call_backup')` 刪掉舊 channel（:49/:86）。
- 🚫 **禁止**改音卻沿用舊 channel id：Android 的 `NotificationChannel` **建立後 sound／importance
  即不可變**，就地改只會靜默無效——使用者回報「來電音效是系統提醒音效而非來電鈴聲」正是這個。
  換鈴聲**一定**要換新 id ＋ 刪舊 id（否則舊 channel 留在系統設定裡變成孤兒）。
- `UriAndroidNotificationSound('content://settings/system/ringtone')`（:58）＝
  `Settings.System.DEFAULT_RINGTONE_URI`，**必須**與 `AudioAttributesUsage.notificationRingtone`
  （:98 channel／:139 通知，**兩處都要**）成對出現，音量才走「鈴聲」音量軌而不是「通知」軌。
- `additionalFlags: _insistentFlag`（:64/:140，`Int32List.fromList(<int>[4])` ＝ `FLAG_INSISTENT`）
  讓鈴聲**重複播放直到通知被取消**。因此它**必須**與 `timeoutAfter: 60000`（:144）
  及既有的所有 `LocalCallNotification.cancel()` 呼叫點成對存在，否則會響到天荒地老。
- ⚠️ `Int32List` 由 `package:flutter/foundation.dart` 轉出，**不要**再 `import 'dart:typed_data'`
  （會觸發 `unnecessary_import`，analyze 基線就從 141 變 142）。

**G84 — 無人接聽／連線逾時：雙端一律用 `showCallRetryDialog`，且「重新撥打」不得重跑媒體初始化**
`widgets/call_retry_dialog.dart`（新增）是兩端共用的唯一實作，回傳
`CallRetryChoice.leave`（離開通話房間 → 回主畫面）或 `.retry`（重送通話封包 → 留在原畫面）。
| 端 | 觸發點 | 逾時 | 重撥動作 |
|----|--------|------|---------|
| 家屬 `video_call_screen.dart` | `_armConnectTimeout`（:298）→ `_handleConnectTimeout`（:313） | 一般 **20s**／緊急 **60s** | `_retryCall`（:385）→ `_sendCallInvite()` ＋ 重新武裝看門狗 |
| 長輩 `elder_screen.dart` | `_armCallTimeout`（:1256）→ `_handleCallTimeout`（:1268） | **30s** | `_makeCall()`（自行重設狀態與看門狗） |

- 🚫 **禁止**讓「重新撥打」呼叫 `_initCall()`：那是被刪掉的舊「重試連線」按鈕的做法，
  會整個重跑媒體初始化，重複 `openUserMedia` 在真機上常造成鏡頭被佔用而黑畫面。
  重撥前的 `hangUp(disconnectSocket: false, disposeLocalStream: false)` 是刻意的——
  關 peer connection、作廢 `_currentCallId`，但**保住 `localStream`**，所以不必再開一次相機。
- 🚫 **禁止**改用 `SnackBar`：接「離開」的 `pushAndRemoveUntil` 會當場吞掉它（**G23**）。
- 對話框 `barrierDismissible: false` ＋ `PopScope(canPop: false)`，且**回傳 `null` 視同離開**——
  使用者不該被留在一個已經斷線的通話畫面上。
- **CCTV 監控機（`widget.isCCTVMode`）不彈這個對話框**，直接返回：監視機旁邊沒有人可以按
  （G56 同一精神），彈了只會變成一個永遠卡在畫面上的 modal。
- 媒體初始化失敗**不適用**本對話框（重撥變不出相機），走既有的 `_showCallProblemThenGoHome`。
- 🚫 已刪除的舊 UI（紅色 `Icons.wifi_off` ＋「連線逾時，請檢查網路連接或稍後再試」＋
  藍色「重試連線」）**不要復活**：它只存在於家屬端、且那顆按鈕做的是錯的事。

**G85 — 不可取消的 `Future.delayed` 看門狗必須用「世代編號」守衛**
`video_call_screen.dart::_connectAttempt`（:113）、`elder_screen.dart::_callAttempt`（:1247）、
`emergency_tone.dart::_generation`：武裝時 `final attempt = ++_x;`，回呼裡第一件事是
`if (attempt != _x) return;`。
> **原因**：Dart 的 `Future.delayed` **沒有 cancel**。重新撥打後舊的那一輪仍會照時觸發，
> 沒有守衛就會彈出第二個對話框（或把新撥出的通話當成逾時掛掉）。
> 🚫 **不要**改用「一個 bool 旗標」代替：連續重撥兩次時第一輪的回呼會把旗標清掉，
> 第二輪的看門狗跟著失效。編號單調遞增才不會有 ABA 問題。

### 7.2 後端護欄

**G29 — `socket_app.py` 的終止廣播**
- `call-request` 下發 `issuedAt`/`expiresAt`（**60 秒**）與 FCM `ttl=60s`
  （**2026-08-11 第二十二輪：120 → 60**；`emergency-call` 亦同，其 `ttl` 由 3600s 一併收斂，見 G73）
- `on_end_call()` 依 `call_registry` 對 Socket + FCM 廣播終止
- `on_cancel_call()` / `on_call_busy()` 使用 `call_registry` 補齊目標並清理
- 前景在線 Socket 的 `fcmToken` **也**併入 FCM 發送集合（`fcm_send_map`）
- `_get_all_known_fcm_tokens()` 回傳所有已知 token（記憶體 + DB），**不做** `is_socket_active` 過濾
**不可拆掉任一環**：會回到「一端掛斷，另一端仍響／仍等待」或 killed 長輩收不到 FCM。

**G30 — `has_comm_elder_device()` 只認在線 socket**
**禁止**改回信任 `room_fcm_tokens` 殘留離線 token。完整原因見 §6.2。

**G31 — token 去重一律偏好 comm**
`_get_all_known_fcm_tokens` / `_get_target_sockets_and_tokens`：
記憶體迴圈「comm 不被 monitor 覆蓋」+ DB `ORDER BY (device_mode='comm') DESC`；
`on_join` / `on_update_fcm_token` 呼叫 `_purge_stale_reverse_mode_token()`。
完整鏈路見 §6.4。

**G32 — 長輩 token 查詢的 `OR user_id` 疊加**
elder 分支 DB 查詢 `WHERE role='elder' AND (room_id IN (%s,%s) OR user_id = %s)` + 記憶體 user_id 補掃，
`user_id` 由 `_resolve_elder_user_id()` 反解。
**禁止**改回「只用 room_id」；**禁止**用 `_resolve_user_id_int` 代替。完整原因見 §6.5。

**G33 — 通話類 FCM 必須是 data-only**
**禁止**加 `notification` 區塊：含 `notification` 的訊息在 Android 背景／被殺死時會被系統匣接管，
Flutter BG handler 不會被觸發 → CallKit 不會響鈴。

**G34 — SDP 精準轉發**
`offer`/`answer`/`candidate` 必須 `to=target_sid`。**禁止廣播**。

**G35 — 資料庫存取**
無 ORM，一律 `db_cursor()` + `%s` 參數化查詢。**禁止** f-string 拼 SQL。

**G36 — 環境固定值**
Python **3.12**（不可 3.13+）；FastAPI **port 8000** 不可更改；
production MySQL host 用 `uban-mysql`（**不可** `localhost` / `127.0.0.1`）。
> ℹ️ 後端跑在**遠端實體機**上。本機開發機只有 Python 3.13/3.14 是**正常的**，不是環境問題。

**G43 — `/api/cctv/test-fall` 必須預設關閉**
`CCTV_TEST_FALL_ENABLED` 的預設值是 `false`，關閉時回 **404**。
🚫 **不可改為預設開啟、不可移除開關**：該端點會走與真實 YOLO **完全相同**的派送路徑
（寫 DB + 對所有家屬送高優先級 FCM → 強制亮螢幕 + 通知 + 朗讀），
而 `elder_id` 只有 4 位數字可被完整列舉。

**G44 — 授權檢查一律走 `services/call_security.py`，REST 與 Socket 兩條路徑強度必須一致**
每個既有洞都有**兩個入口**（REST + Socket），只補一邊等於沒補：

| 動作 | REST | Socket |
|------|------|--------|
| 確認警報 | `POST /api/alerts/{id}/acknowledge` | `cctv-alert-ack` |
| 開音訊橋接 | `POST /api/alerts/{id}/audio-bridge` | `audio-bridge-request` |

`is_user_linked_to_elder()` 的判定邏輯**刻意與 `socket_app.py::_verify_room_access()` 一致**
（長輩本人 via `elder_profile`，或已配對家屬 via `family_elder_relationship`）。
改其中一邊必須同步改另一邊。
- 查詢失敗時的預設：`is_user_linked_to_elder` / `is_device_of_elder` 回 **False**（守寫入，安全優先）；
  `elder_exists` 回 **True**（可用性優先，DB 抖動不該打斷監視機推流）。
- 音訊橋接的 SQL 必須帶 `AND to_device_id = %s`，否則會**延長到別台裝置的權限**。

**G45 — 「無權」一律回 404，不要回 403**
`elder_id` 是 4 位數字、`alert_id` 是自增整數，兩者都可完整列舉；
403 等於確認該 ID 存在。與 `routers/institution_common.py` 的既有慣例一致。
（例外：`X-Uban-Device-Token` 不符回 **403**——那是密鑰錯誤，不洩漏任何 ID 是否存在。）

**G46 — `delete-device` 必須驗證發送者身分**
`on_delete_device` 先 `_parse_room_id(room)` 取出 elder，再確認 `sid` 是
`comm_elder_<id>` 或 `monitor_elder_<id>` **其中之一的成員**，否則直接 return。
🚫 **不可移除**：這個 handler 會踢掉裝置（`force-logout`）並清掉它的 FCM token，
等於讓任意連線者把任意長輩的通訊機變成收不到來電。

**G51 — `_get_elder_devices_list` 的同名去重必須取「最新加入者」，不可先到先贏**
階段 1 掃描 `comm_elder_<id>` 與 `monitor_elder_<id>` 兩個房間，
同一台裝置（同 `deviceName`）在兩房都可能留有列。
必須依 `joinedAt`（`on_join` 寫入 `rooms_manager[room][sid]['joinedAt'] = time.time()`）
取**較新**的那一列，較舊的丟棄。
🚫 **不可靠房間迭代順序決定勝者**：`comm_room` 先被掃到，所以一台剛切成監控機的裝置
會被殘留在 `comm_elder_<id>` 的舊列蓋掉 → 回給家屬端的 `deviceMode` 永遠是 `'comm'`
→ `family_main_screen.dart`:246 的 `where(d['deviceMode'] == 'monitor')` 濾不到任何東西
→ **遠端視訊清單永遠是空的**（第十八輪需求 5 後端根因）。
配套的兩處殘列清理**不可省略**：
- `on_join`：長輩加入時，把**兄弟房**（comm ↔ monitor 的另一邊）中同 `deviceName` 的舊列刪掉。
  🚫 **此處不可呼叫 `sio.disconnect`**——那個 sid 有可能就是本次 join 自己的連線。
- `_purge_stale_reverse_mode_token`：清 DB 的同時，也要清掉 `rooms_manager[reverse_room]` 中
  同 `fcmToken` 的長輩列（房間清空就刪掉 key），整段包 `except (KeyError, RuntimeError)`。

**G52 — CCTV 端點上線後，遠端必須確實部署，否則整條鏈路靜默失效**
`/api/cctv/*` 是 2026-08-04／08-05 才加入的 router。遠端若沒 `git pull` + 重啟，
FastAPI 會對這些路徑回傳它的預設未匹配回應 —— 字面上的 `{"detail":"Not Found"}`。
症狀具有欺騙性：前端顯示「Not Found」看起來像授權或參數錯誤，實際上是**路由根本不存在**。
連帶後果：監控機的推幀全數 404 → `cctv_feed_status` 永遠是空的 → YOLO 跌倒偵測從未在遠端跑過。
排查一律先打 `GET /openapi.json` 數一下 `/api/cctv` 開頭的路徑有幾條，**不要**先去讀授權碼。
`/api/cctv/test-fall` 另需遠端 `.env` 設 `CCTV_TEST_FALL_ENABLED=true`（見 G43，預設關閉）。

**G53 — 監視機綁定必須在「配對碼被兌換」當下持久化**
`routers/pairing.py::resolve_monitor_setup`（:88）兌換 6 位數配對碼時，
**必須**同步 UPSERT 一列 `monitor_device_binding`。
🚫 **禁止**退回「靠 Socket `join` 成功的副作用（`rooms_manager` / `room_fcm_tokens` /
`user_fcm_token`）才算綁定」的舊設計。
**原因**：`monitor_setup_codes`（:20）是**行程內 dict**，`/resolve` 一 `pop` 就什麼都不剩；
而 `on_join` 有六條 `join-failed` 分支（缺 room、房名格式錯、缺 userId、
`_verify_room_access` 未授權、訂閱裝置數上限 `monitor-limit`、同 IP 上限 `ip_limit_exceeded`），
每條結尾都 `sio.disconnect(sid)` 且不留任何持久狀態。
命中任一條時 **REST 配對回報成功、家屬端清單卻永遠空白，且兩端都沒有可見錯誤**——
這正是第十九輪的阻斷性故障（遠端真機實測：配對碼成功、裝置永不出現）。
迴歸鎖：`tests/test_call_signaling.py::test_resolve_monitor_setup_makes_device_visible_before_any_join`。

**G54 — `_get_elder_devices_list` 的階段 0 只做「補漏」，不得改寫階段 1–3**
階段 0（查 `monitor_device_binding` 建 `bound_by_name`）只能在 `return` 前，
把「階段 1–3 都沒產出、但存在於綁定表」的名稱補成
`{'id': f'bound_{device_id}', 'deviceMode': 'monitor', 'isOnline': False, 'appState': 'offline'}`，
且去重 key **必須沿用**階段 1–3 既有的 `online_device_names`。
🚫 **禁止**改成「先用綁定表塞滿、再讓階段 1–3 覆蓋」。
**原因**：階段 1–3 是線上路徑，任何改寫都可能動到 `isOnline` / `appState` /
同名去重取較新 `joinedAt`（**G51**）的既有行為。補漏式寫法保證線上路徑輸出與修改前
逐位元組相同，零回歸風險；「先塞再覆蓋」則會讓同一台實體裝置出現兩張卡片（一在線一離線）。
迴歸鎖：`test_bound_device_not_duplicated_after_successful_join`。

**G57 — 改名＝改身分，五處儲存必須一次更新**
`services/monitor_identity.py::monitor_device_id()` 是
`zlib.crc32(f"{elder_id}|{name.strip()}") & 0x7FFFFFFF`——**名稱一改，`deviceId` 必然改變**。
`PATCH /api/pairing/monitor_device`（`pairing.py`:290）必須在同一次操作內更新全部五處：

1. `monitor_device_binding`（`device_name` **和** `device_id`）
2. `user_fcm_token.device_name`（`room_id='monitor_elder_<id>'` 的列）
3. `cctv_feed_status.device_id`
4. 記憶體 `rooms_manager['monitor_elder_<id>']`
5. 記憶體 `room_fcm_tokens['monitor_elder_<id>']`

🚫 缺任一處都會造成**裝置分身**：同一台實體機在清單出現兩列，
或推幀的 `device_id` 與清單對不上導致警報找不到來源。
完成後必須 `await _broadcast_elder_devices_update(elder_id)`（:2467），
並對該裝置 emit `monitor-renamed`（:398）讓它更新畫面標籤與 `saved_device_name`。
迴歸鎖：`test_rename_monitor_device_syncs_all_stores_and_changes_device_id`。

**G64 — 配對碼必須持久化，`/resolve` 不得 `pop`；不存在與已過期要分成 404／410**
`monitor_setup_code` 表由 `socket_app.py`:149 的 `_DB_TABLE_DEFINITIONS` 開機冪等建立
（SQLite 分支在 `database.py`:411，衝突鍵 `(code)`）。
`routers/pairing.py::resolve_monitor_setup`（:141）：記憶體優先、查不到再查 DB，
**只標記 `used_at`（:222）不刪列** → 15 分鐘 TTL 內重複兌換是冪等的。
- 查無此碼 → **404**「綁定碼不存在，請確認家屬端產生的 6 位數字」
- 逾時 → **410**「綁定碼已過期（有效 15 分鐘），請家屬重新產生」
`_cleanup_monitor_setup_codes()`（:43）留 1 天緩衝再清；`_generate_monitor_code()`（:64）
產碼時要查 DB 避免撞號。
🚫 **禁止**改回「行程內 dict + `pop`」。
**原因**：舊版一 `pop` 就什麼都不剩，後端重啟／自動 pull 也一起清空 →
使用者輸入正確的碼卻拿到「綁定碼過期或錯誤」，而且兩種失敗長得一模一樣、無從自救。
迴歸鎖：`tests/test_call_signaling.py` 第二十輪新增的 3 條。

**G65 — `monitor-removed` 必須在 `sio.disconnect()` 之前 emit**
`routers/pairing.py::delete_monitor_device`（:359）。
🚫 **禁止**調換順序，也**禁止**「反正對方會斷線自己發現」。
**原因**：先 disconnect 的話事件根本送不出去，監視機會停在 CCTV 畫面
（第二十輪需求 4），使用者只能自己按「退出並重置」——而那條路徑又會撞上 G64 的綁定碼問題。

**G66 — `on_end_call` 必須容忍 `room=None`，並用 `accepter_sid` ＋ 房內廣播補齊對端**
`socket_app.py::on_call_accept`（:2215）在 :2257 把接聽方 sid 併進 `call_registry`；
`on_end_call`（:2367）的通知集合 = `call_registry` 既有目標 ∪ `accepter_sid`（:2402）
∪ **該房間內所有其他 sid**。
🚫 **禁止**把「`room` 必須非空」加回發送條件。
**原因**：第二十輪需求 8「一端掛斷、另一端仍留在通話房」的根因是前端
`hangUp()` 要求 `_currentRoomId != null` 才發 `end-call`，
而接聽方在某些路徑下 `_currentRoomId` 是空的（只有 `_peerSocketId`／`_currentCallId`）。
前端已放寬成「三者其一非空就發」（`signaling.dart`:1300），
後端就必須能處理 `room=None` 的 `end-call`，否則放寬等於沒放寬。

**G72 — `POST /api/pairing/session/release` 的 `user_fcm_token` 刪除只能以 `fcm_token` 為鍵**
`pairing.py::release_session` 的 SQL 固定為
`DELETE FROM user_fcm_token WHERE fcm_token = %s`。
`room_id` / `user_id` 只能寫進診斷 log，**不得**進入 `WHERE`。
🚫 **禁止**再加 `AND room_id = %s` 或 `AND user_id = %s` 收窄條件。
**原因**（第二十輪引入、第二十一輪需求 2 修正）：
用戶端送的是 prefs 的 `elder_room_id`，那是**裸的 elder id**（例如 `'0001'`）；
而 `user_fcm_token.room_id` 存的是**帶前綴的 socket 房名**
（`comm_elder_0001` / `monitor_elder_0001`，寫入點 `socket_app.py`:1456-1463、:1506-1514）。
兩者永遠對不上 → `rowcount = 0` → FCM token 從未被釋放 →
長輩重新登入後舊 session 殘留 → 家屬端撥打顯示「無法連線」。
`user_id` 同樣不可靠：殘留列帶的是**舊帳號**的 user_id。
`fcm_token` 是這支實體裝置的唯一穩定識別，一律以它為鍵；
「刪掉這支裝置的所有殘留列」正是 session 釋放要的語意。
記憶體清理（步驟 2）與 `_broadcast_elder_devices_update`（步驟 3）維持原樣。

**G79 — 取消／逾時過的 `call_id`，伺服器端必須整通不發（Socket 與 FCM 皆不送）**
`socket_app.py`:225-259：`_cancelled_call_ids`（`call_id → time.time()`）、
`_CANCELLED_CALL_TTL_SEC = 300`、`_CANCELLED_CALL_MAX` 上限，
配 `_mark_call_cancelled()` / `_is_call_cancelled()` / `_prune_cancelled_call_ids()`。
- `on_cancel_call` 結尾**必須** `_mark_call_cancelled(call_id)`（:2078）。
- `on_call_request`（:1767）與 `on_emergency_call`（:2120）**開頭第一件事**就是
  `if _is_call_cancelled(call_id): return`——要擺在任何 emit / FCM 之前。
- 取消推播的 `ttl` 必須 **≥ 來電推播的 ttl**（現為 60s，:2067 由 10s 提高）：
  取消訊息若比來電訊息早過期，使用者就會收到「來電來了、取消卻沒到」。
🚫 **禁止**只在前端擋。前端的 `_invalidCallIds` 只擋得住**已經送到**的封包，
擋不住還沒送出的——而「延遲來電通知」的本質正是封包卡在 FCM 佇列裡還沒送出。
🚫 **TTL 300s 不可調到小於來電有效期（60s）**，否則記錄比通話先過期，等於沒擋。
**原因**：第二十二輪需求 10。使用者要「發起端最多等 1 分鐘，逾時就關閉這次連線，
**同時遏制另一端的來電通知發送**」——後半句只能在伺服器端做到。

**G80 — 兌換配對碼成功後必須廣播 `elder-devices-update`**
`pairing.py::resolve_monitor_setup`（:218-239）在寫入 `monitor_device_binding` 之後，
以**獨立 daemon 執行緒 + `asyncio.run(...)`** 呼叫 `_broadcast_elder_devices_update(elder_id)`。
🚫 **不可把 `resolve_monitor_setup` 改成 `async def`**：它是 sync endpoint（FastAPI 丟 threadpool，
該執行緒沒有 running loop），且 `tests/test_call_signaling.py` 有三支測試**直接以同步方式呼叫它**。
🚫 廣播失敗**不可**讓配對回應失敗——整段 try/except，失敗只記 log。
**原因**：刪除與改名都會廣播，唯獨「新增綁定」不會，家屬端得等下一次輪詢才看得到新裝置，
配對碼彈窗也就無從得知何時該自動關閉（第二十二輪需求 1）。

### 7.3 已知的文件錯誤（以程式碼為準）

> 這些是歷史文件與現行程式碼不符之處。已在本文件中修正，此處保留記錄以免後續 AI 又被舊敘述誤導。

| # | 舊文件說法 | 實際 | 佐證 |
|---|-----------|------|------|
| 1 | 後端路徑 `uban-api/uban-api/services/socket_app.py` 或 `Uban/uban-api/services/socket_app.py` | **`uban-api/services/socket_app.py`** | 檔案系統 |
| 2 | 根目錄護欄 #5：「前景 active Socket **不發** FCM（Layer B `continue` + Layer C 雙重過濾）」 | **會發**。前景在線 Socket 的 token 也併入 `fcm_send_map` | `socket_app.py`:1520-1523 |
| 3 | 前景不雙重彈窗是後端擋的 | **是前端擋的**：1500ms Socket 寬限期 + 3s callId 去重 | `main.dart::_setupForegroundMessaging` |
| 4 | 有效期 15 秒 / 45 秒；FCM `ttl=15s`/`45s`（更早的版本）；**120 秒**（第七～二十一輪） | **60 秒**（**2026-08-11 第二十二輪定案**；CallKit `duration` 仍為 45s，兩者無關） | `socket_app.py`、`globals.dart`:47 |
| 5 | 2026-06-07 記錄宣稱建立了 `MonitorViewScreen` | **不存在**。監控畫面是 `CameraScreen` | 全 `lib/` grep |
| 6 | 冷啟動預寫鍵是 `pendingRingCall` | **`pendingRingCallData`**。`pendingRingCall` 在 `main.dart` 中**只被清除、從無寫入**，是遺留鍵 | `main.dart` grep |
| 7 | 冷啟動兜底是「三層防線」 | **五層**（L0/L0'/L1/L2/L3/L4，見 §4.8） | `main.dart` |
| 8 | 緊急通話「FCM 不帶有效期」；第十七～二十一輪的正確答案是「**Socket 與 FCM 兩條路都不帶**」 | ⚠️ **2026-08-11 第二十二輪起兩條路都帶**（`expiresAt = issuedAt + 60000`），FCM `ttl` 由 3600s → 60s。舊敘述現在是錯的 | `socket_app.py` `on_emergency_call`；G22（已改寫）、G73 |
| 9 | `_parse_room_id` 只解析 `comm_`/`monitor_` 前綴 | 另有第三分支：純數字 room id 會查 `elder_profile` 反解，回傳 `(elder_id, 'comm')` | `socket_app.py`:537-568 |
| 10 | 長輩端登出只有 `elder_profile_tab::_handleLogout` 一處 | **另有 `elder_screen.dart`:674-680** | grep |
| 11 | `Uban/CLAUDE.md` 護欄 #5 同時寫「15 秒」與「120 秒」兩組矛盾條目 | 兩組**都已作廢**，以 **60 秒**為準 | 同 #4 |
| 12 | `Uban/CLAUDE.md` 第九輪記錄中段插入了 `## 環境要求` + `## 🚫 絕對不可改動區塊` 片段 | 結構損毀，非有意內容 | `Uban/CLAUDE.md`:452-458 |
| 13 | `signaling.dart` 的 **`_configuration`** 看起來是 ICE / TURN 設定 | **死碼，完全沒有被使用**（`flutter analyze` 有 `unused_field` 警告）。真正生效的是 **`_generateDynamicTURNConfig()`**，由 `_createPeerConnection` 呼叫 | **2026-08-10 實測 :157**（第十七輪記的 :116 已漂移）；`_showCallkitIncoming` 死碼在 **:610**（原記 :542） |
| 14 | §3.1 / §6.6 / §6.7 稱「`elder-devices-update` **只在 join 時廣播**，disconnect 不廣播」 | **會廣播**。join(:1333)、`delete-device`(:1464)、`force-logout`(:1548)、**disconnect(:1628)**、改名(:2467) 都呼叫 `_broadcast_elder_devices_update` | `socket_app.py`:1628 |
| 15 | §6.6 宣稱有「**15 秒 staleness watchdog**」 | **從來不存在**（全 `lib/` grep 無此物）。前端只有 2.5 秒 Socket 輪詢 + 10 秒 HTTP 交叉驗證 | `family_main_screen.dart` grep |
| 16 | §6.6 宣稱有「每 10 秒 HTTP API 交叉驗證」 | 第十七／十八輪**確實不存在**（憑空記載）；**2026-08-10 第十九輪 A4 才真正實作出來** | `family_main_screen.dart`:338 `_refreshMonitorDevicesViaHttp` |
| 17 | §6.8 記 `_exitCCTVMode` 在 `elder_screen.dart`:795 | 實際在 **:910**（入口鈕 :1098） | grep |

> 🪤 **#13 是一個很容易踩的陷阱**：要改 TURN 憑證或 ICE 參數的人，第一眼會看到 `_configuration`
> 並改在那裡——**改了不會有任何效果**，而且它裡面的 `iceServers` 內容看起來還很合理。
> 一律改 `_generateDynamicTURNConfig()`。
> （`signaling.dart`:542 的 `_showCallkitIncoming` 同樣是未被引用的死碼，見 §7.3 的既有記錄脈絡。）

> ⚠️ `Uban/mobile_app/lib/main.dart.bak` 是**備份檔**，grep 會撈到它。永遠不要編輯它。

### 7.4 已知且**刻意保留**的安全缺口（2026-08-05 第十七輪稽核結論）

> 這些是稽核時看到、評估後**決定不改**的項目。寫在這裡是為了：
> (a) 後續 AI 不要以為是漏看的；(b) 真的要補時，知道代價在哪。

| # | 缺口 | 為什麼不補 | 真要補的話 |
|---|------|-----------|-----------|
| 1 | **整個 App API 實質上未認證**：後端**會發** JWT（`auth.py::create_access_token`，在 `routers/auth.py`:79 與 `routers/pairing.py`:91/339/486/883 呼叫），但 `get_current_user` **只在 `auth.py` / `auth_staff.py` 出現，沒有任何 router 把它當 dependency**；`api_service.dart` 也從不送 `Authorization` 標頭 | 硬上 `Depends(get_current_user)` 會讓**每一幀 CCTV 推流當場 401**，監控與通話全滅 | 前後端同時上線：`api_service.dart` 統一注入標頭 → 後端逐 router 加 dependency → 最後才移除本文件的關係驗證兜底 |
| 2 | `offer` / `answer` / `candidate` 依 `targetId` 轉發，**不檢查房間成員資格** | 要利用得先拿到受害者的**隨機 UUID sid**，而 sid 只在已受 `_verify_room_access` 保護的房間內揭露；反之在 SDP 路徑加嚴格成員檢查，極可能打斷冷啟動 join 競態——正是本子系統「單點修改幾乎必然造成回歸」的典型 | 要做就連同 §4 的 join 時序一起重測，並補進 `tests/test_call_signaling.py` |
| 3 | Socket 連線的 `userId` 是**自稱**的（socket 層同樣沒有 JWT） | 同 #1，是同一個根問題的不同切面 | 隨 #1 一起解 |
| 4 | **「同 IP 上限 5 台監視機」在反向代理後方實為「全球上限 5 台」**（2026-08-10 第十九輪查出） | 第十九輪已讓 `on_connect` 優先讀 `X-Forwarded-For` → `X-Real-IP` → TCP 對端位址（`_extract_client_ip`:1066）。但**若 Tailscale Funnel 不轉送這兩個標頭，仍會退化回單一 `ip_hash`**，第 6 台監視機起全球被拒 | 真機實測 Funnel 是否轉送 XFF。**在確認之前不要放寬上限**——放寬只會把「配不上」換成「濫用沒防線」。確認不轉送的話，改用 `elder_id` 而非 IP 作為配額鍵 |

**第十七輪實際補起來的洞**（都已上線，見 §8）：
`test-fall` 未授權觸發、`frame` 可偽造推流、音訊橋接可開進**任意裝置**（最嚴重）、
`acknowledge` 可偽造／消音、警報清單可列舉任意長輩、音訊橋接查詢洩漏 `from_id`/`to_device_id`、
`delete-device` 可遠端踢任意裝置。

---

## 8. 修復年表

> 只記通話／監控相關。每輪格式：日期 — 標題 → 症狀 / 根因 / 修復。

### 2026-06-05 / 06 — 第一輪：早期通話信令
雙重 room ID prefix（`comm_elder_comm_elder_X` → `join-failed: 您無權加入此通訊房間`）、
`join-failed` 誤斷線、緊急模式 camera 強制開啟、unbind id / import 型別修正、
CallKit 不自動喚醒、cold-start `call-accept` 輪詢。

### 2026-06-07 — 通話／監控十項修復
`singleTask` launchMode、Splash 跳過動畫、`pushAndRemoveUntil` 黑屏修復、`_isInCall` 防並發、
socket 連線輪詢、降級 UI 移除、全域 watchdog 錯誤復原。
> ⚠️ 原記錄宣稱「MonitorViewScreen 建立」，該 class **不存在**（§7.3 #5）。

### 2026-07-10 — Socket 通話信令回歸直接轉發（`dbdaa55` / `9c5e430`）
後端移除 `call_registry` 回歸確定性直接轉發，`on_join` 新增通話護欄；
前端 `_checkInitialCall` 移除未接聽自動導航；`_goHomeAfterCall()` 杜絕冷啟動黑屏。
（`call_registry` 後續在第三輪被重新引入用於終止廣播。）

### 2026-07-14 — 第一輪來電通知六項修復（分支 `call-fix`）

| # | 症狀 | 根因 | 修復 |
|---|------|------|------|
| 1 | 家屬端來電 dialog 樣式不一致 | FCM 前景備援用樸素 `AlertDialog` | 重寫 `_showIncomingCallDialog` 與 `FamilyMainScreen` 一致 |
| 2 | 背景家屬端接聽後攝像頭無法開啟 | `_isCameraOff = true` 預設關閉 | `isIncomingCall` 時設 false；`openUserMedia` 失敗延遲 500ms 重試 |
| 3 | 背景長輩端接聽後只進主畫面 | 冷啟動時 `_setupCallKitListener` 錯過 `actionCallAccept` | 三層防線（BG 預寫 → `_checkInitialCall` → Splash） |
| 4 | 前景家屬端接聽後無法進房 | `_navigateToVideoCall` 的 `popUntil(route.isFirst)` 清空堆疊 | 只關 dialog context，直接 `Navigator.push` |
| 5 | 前景長輩端無法接收來電 | FCM 前景備援對長輩端 early return | 改用去重檢查取代 early return |
| 6 | 發起方持續等待 | 連鎖效應 + 30s 逾時過長 | 逾時 30s → 20s |

### 2026-07-15 — 第二輪殘留 Bug（6 項，3 項致命）

| # | 症狀 | 根因 | 修復 |
|---|------|------|------|
| 1 | 進房鏡頭應預設開啟 | `_isCameraOff = false` 僅限 `isIncomingCall` | 移除條件，無條件 false |
| 2 | 背景長輩端接聽後無法進房 | `_navigateToVideoCall` 的 dedup guard 誤殺 CallKit accept | 移除 elder 端 dedup guard |
| 3 | 前景家屬端接聽後無法進房 | incomingCall 路徑無 socket 輪詢 | 補 50×100ms 輪詢 |
| 4 | 前景長輩端無法接收來電 | dialog 建 `ElderScreen` 時缺 `initialCallData` | 補傳；`_restoreSignalingCallbacks` 傳 `senderName` |
| 5 | 拒絕來電後黑屏 | decline 路徑仍用 `popUntil(route.isFirst)` | 改 `pop()` + `canPop()` guard |
| 6 | 拒絕／結束訊息立即消失 | `SnackBar` 隨 route 移除而消失 | 改 `showDialog` 2 秒後導航 |

### 2026-07-17 — 第三輪：延遲來電、過期來電、同步終止
- 後端：`call-request` 新增 `issuedAt`/`expiresAt`（初始 15s）+ FCM `ttl=15s`；
  `cancel-call`/`end-call` 依 `call_registry` 廣播至所有相關 Socket/FCM。
- 前端：新增 `_invalidCallIds`、`_isExpiredCallPayload`；`sendCallRequest` 自動產生 UUID 並帶有效期；
  收到 `cancel-call`/`call-busy` 時 `endAllCalls()`；`family_main_screen` 改 2.5s 輪詢 + debounce。
- 建置故障（Windows 檔案鎖定 `flutter_inappwebview_android:compileDebugJavaWithJavac`）：
  終止 `java.exe`/`gradle.exe`/`flutter`/`dart` → 刪 `build/` → `flutter clean` + `pub get` + `build apk --debug`。

### 2026-07-18 — 第四輪：被殺死狀態來電與雙端同步終止
- **有效期 15s → 45s 全鏈路對齊**（FCM 在 Doze 可能延遲數十秒；CallKit 響鈴 45s 但第 16 秒後接聽被判過期）。
- **FCM 背景 handler 提前註冊**：`Firebase.initializeApp()` 後立即以獨立 try/catch 註冊，
  LineSDK/Analytics 改各自 try/catch（原本同一 try，任一噴錯就導致 handler 未註冊）。
- 拒接／掛斷／逾時雙端同步終止：無狀態 HTTP `declineCall`、BG isolate CallKit listener、
  `actionCallTimeout` 視同拒接、`sendCallBusy` HTTP 備援、`on_call_busy` 用 registry 補齊、
  發起方逾時主動取消（家屬 20s / 長輩 30s）。
- 前景 Socket 也附發 FCM（涵蓋「前景時被殺、Socket 尚未逾時斷線」的窗口）。
- 裝置級限制：小米／OPPO／華為 force-stop 的 APP 收不到任何 FCM，需引導使用者開自啟動白名單／電池不最佳化。

### 2026-07-19 — 第五輪：真機回報兩問題（`b95cc78` / `76b1b36`）
- **問題1（長輩被殺死收不到）**：長輩被殺死後 Socket 仍以 `appState=foreground` 殘留，
  其 `fcmToken` 為空／過期 → 完全不發 FCM。
  → 新增 `_get_all_known_fcm_tokens()`（記憶體 + DB，不做在線過濾）併入 `fcm_send_map`。
- **問題2（家屬冷啟動接聽誤進主畫面）**：`SplashScreen` 家屬分支不消費 `pendingAcceptedCall`，
  Splash 的 `pushReplacement(FamilyMainScreen)` 把最上層的 VideoCall 洗掉。
  → 新增 `splashActive` 旗標 + `_navigateFamilyHome()` 確定性導航。

### 2026-07-19 — 第六輪：冷啟動接聽事件遺失雙保險
真因是 `actionCallAccept` 在 `_setupCallKitListener` 註冊**之前**發生 → 事件遺失。
→ BG isolate 直接寫 prefs、`_checkInitialCall` 檢查 `activeCalls()` 的 `isAccepted`、
兜底輪詢（每 200ms、最多 8s，`splashActive` 期間讓位）取代一次性 350ms。

### 2026-07-20 — 第七輪：預寫 + 有效期 45s → 120s
問題2確認為**三重失敗場景**：BG isolate SharedPreferences 寫入失敗（小米嚴格背景 IO）
+ `activeCalls()` `isAccepted` race + `onEvent` stream 錯過事件。
- BG handler 在顯示 CallKit **之前**預寫 `pendingRingCallData`（`isAccepted: false`）
- `_checkInitialCall()` 改為最多 3 次重試（間隔 300ms）
- `main()` 新增 `pendingRingCallData` 備援讀取
- **有效期 45s → 120s**（CallKit `duration` 維持 45s）
- FCM `UnregisteredError` 時同步清除 DB `user_fcm_token`

### 2026-07-22 — 第八輪：拒接三重訊息、角色反轉、狀態清理、簡繁轉換
- **拒接三重訊息**：`_sendDeclineEvent` 同時發 Socket + HTTP，後端兩個 handler 各廣播一次，
  加上 BG isolate listener 也發 → 改為 **if-else 單通路**。
- **拒接後陳舊狀態**：拒接路徑從不清 `pendingRingCallData`/`pendingRingCall` → 三個 key 全清 + `invalidateCallId()`。
- **角色反轉**：消費端盲信自己是接聽方 → 全鏈路帶 `senderRole`，三個消費端驗證 `senderRole != appRole`。
- 簡體轉繁體（`redesigned_ai_chat_screen.dart` 10 處等）。
- 後端無設備診斷日誌（`🚨 目標完全無法觸達` / `⚠️ 僅有在線 Socket、無 FCM token`）。

### 2026-07-22 — 第九輪：`monitor-wakeup` 誤判（長輩被殺死收不到來電**根因**）
關鍵線索：**不對稱失效**（長輩收不到、家屬正常，同型號同權限）→ 必為結構性差異，非 MIUI 殺進程。
根因鏈與四層修復（C1/B1/B2/B3）詳見 §6.4。
測試新增 `test_all_known_tokens_prefers_comm_over_monitor`、`test_has_comm_elder_device_ignores_stale_offline_token`（7 passed）。

### 2026-07-22 — 第十輪：長輩 token 查詢改用 user_id 內容鍵
使用者洞察：「家屬被殺死能收到、長輩不行，何不讓長輩沿用家屬端邏輯」。
第九輪解「撈到了但 type 錯」，本輪解「room_id 漂移根本沒撈到」。詳見 §6.5。
測試新增 `test_all_known_tokens_found_by_user_id_when_room_id_drifts`（8 passed，已用「移除 `OR user_id` 後測試變紅」反證有效）。

### 2026-07-22 — 第十一輪：FCM 已送達但 CallKit 顯示不出來
問題性質變了：FCM 確認送達（`type: call-request` 非 `monitor-wakeup`），但**零 CallKit 畫面**，
11.5 秒後家屬掛斷的 `endAllCalls()` 崩潰 `PlatformException(content is null)`。
- 根因：`showCallkitIncoming` 是**射後不理**（Kotlin `sendBroadcast()` 後立即 `result.success(true)`），
  真正建通知在 `CallkitIncomingBroadcastReceiver.onReceive` 非同步執行 →
  Dart 端以為成功，但原生 BroadcastReceiver 在 MIUI 被殺死背景進程建立通知失敗。
  `endAllCalls()` 是同步 channel，是同一故障唯一露出水面的部分。
- 修復三管齊下：崩潰包 try-catch、Android 14+ 全螢幕權限引導（用套件自帶版本判斷 API）、
  新增 `local_call_notification.dart` 通知備援（+ core library desugaring）。

### 2026-07-25 — 第十二輪：雙重推送修復（部分已被後續推翻）
把「前景 active Socket 也發 FCM」改為不發。
> ⚠️ **此改動在現行程式碼中不存在**——`on_call_request` 仍會把前景 Socket token 併入 `fcm_send_map`。
> 前景不雙重彈窗改由前端擋（見第十四輪 Fix A）。§7.3 #2/#3 記錄此矛盾。

### 2026-07-27 — 第十三輪：來電樣式回歸 CallKit、緊急通話瞬間掛斷、快速登入
- **問題1+4（同一根因鏈）**：BG handler 的 `call-request` 分支只呼叫 `LocalCallNotification.show()` 就 return，
  `_showFullScreenCallkit()` 從未執行；備援條件掛在**從未被設定過的** `data['useLocalBackup']` 死旗標上；
  且備援通知的 launch payload 無人消費（全 `lib/` 從未呼叫 `getNotificationAppLaunchDetails()`）
  → 四層冷啟動兜底全部落空。
  → Fix A（改回 `_showFullScreenCallkit`）、Fix B（無條件探測 `activeCalls()`，放在 `bgSub` 之後）、
  Fix C（備援樣式向 CallKit 靠攏 + `consumeLaunchPayload()`）、Fix D（`main()` 前置呼叫 + `prefs.reload()`）。
- **問題2（緊急通話瞬間無提示掛斷）**：緊急全鏈路缺 `lastProcessedCallId` → `isSameOngoingCall` 恆 false
  → 第二次寫入 pending 落入 `if (_isInCall) { hangUp(); }` → 家屬端掛斷；
  且 `onCallEnded`/`onConnectionLost` 用 `SnackBar` 被 `pushAndRemoveUntil` 當場移除 → 「無任何提示」。
  → 六處修復，含 `elder_screen.dart` 新增 `_activeCallId` 第二道防線。
- **問題3（快速登入失敗）**：`_handleLogout` 清掉了 `_quickLoginSameElder` 依賴的 `caregiver_id`/`caregiver_name`
  → 引入登出不清除的 `last_elder_*` 記憶鍵。

### 2026-08-02 — 第十四輪：新版長輩端 UI 融合後的四項缺陷
> 專案融合了新版長輩端前端 UI（家屬端 UI 不變），按鈕與跳轉邏輯與舊版分歧。

| # | 症狀 | 根因 | 修復 |
|---|------|------|------|
| **1** | 長輩端被殺死時，彈出來電通知**只能接聽、無法拒絕** | 備援通知的 `notificationBackgroundTapHandler` 缺 `WidgetsFlutterBinding` / `DartPluginRegistrant` 初始化；`_handleDecline` 第一件事就是 `SharedPreferences.getInstance()` → 裸 isolate 拋 `MissingPluginException` → 被整包 catch 吞掉 → `ApiService.declineCall` 永遠執行不到。接聽正常是因為 accept action 的 `showsUserInterface: true` 會啟動 APP 由主 isolate 接手 | **Fix C**：補 binding 初始化；`_handleDecline` 重排為「先 `declineCall`、後清 prefs」，每段獨立 try/catch |
| **2** | 家屬端**在 APP 內**約 90% 收不到長輩端來電（APP 外完全正常） | `_setupForegroundMessaging` 先在 1376-1380 行**寫入** `lastProcessedCallId`，再在 1384-1388 行因 `isResumed == true` 而**無條件 return 不顯示任何 UI** → 隨後抵達的 Socket `call-request` 被 `signaling.dart` 的 2s 去重窗口丟棄。FCM 系統性領先是因為後端 `await sio.emit()` 只排入佇列，其後的 `messaging.send()` 同步阻塞卡住 event loop 延後 flush | **Fix A**：去重 token 改為「真正顯示 UI 時才宣告」（`_claimCallDedupToken`）；前景改排 **1500ms** 寬限期，逾時未被 Socket 處理才由 FCM 補 dialog。附帶修 `_showIncomingCallDialog` 的 `_activeCallDialogContext` 洩漏 |
| **3** | 長輩端發起「電話」時，家屬端仍開鏡頭 | `elder_screen.dart` 的 `sendCallRequest` 沒傳呼叫類型，`signaling.dart::sendCallRequest` 根本沒這個參數 → 後端 `data.get('isVideoCall', True)` 永遠取到 `True`；`VideoCallScreen` 也沒有 `isVideoCall` 參數 | **Fix E**：全鏈路貫通（`sendCallRequest` 新增參數並 `.toString()` 避免 Python `str(bool)` 大寫問題、`signaling.dart` 新增 callId 綁定的 `incomingCallIsVideo` / `isVideoCallFor()`、CallKit `extra` 與所有 pending 寫入點補欄位、`VideoCallScreen` 新增 `isVideoCall` 參數）。行為採「**預設關閉、可手動開啟**」（使用者決定）——仍取得 video track，鏡頭鍵保持可按 |
| **4** | 長輩端 APP 外的來電通知樣式與家屬端不一致 | 與問題 1 同一根因鏈：長輩機在 `_showFullScreenCallkit` 的**單次** 900ms `activeCalls()` 取樣回空 → 落到備援的樸素樣式（BG handler 兩條分支結構其實完全對稱，`_showFullScreenCallkit` 內也無 role 分支） | **Fix B**：單次取樣改**兩段輪詢**（每 250ms × 8 = 2.0s 探測；全空才發備援，再每 250ms × 6 = 1.5s 二次探測，CallKit 事後出現則撤掉備援）。**Fix D**：備援樣式向 CallKit 對齊（`✓ 接聽`/`✕ 拒絕`、`color: 0xFF1A472A` + `colorized`、緊急/一般內文區分） |

**新增護欄**：G25（去重 token 只能由真正顯示 UI 的通路宣告）、G26（dialog guard 必須釋放）、G21（備援拒接必須在裸 isolate 存活）。
**新增專案鐵律**：計畫制定與子代理成果檢驗用 Opus，既定計畫執行交由 Sonnet 子代理。
**驗證**：`flutter analyze lib` 0 error（137 項既有 info/warning）、`pytest tests/test_call_signaling.py -q` 8 passed、`flutter build apk --debug` BUILD SUCCESSFUL（Gradle 267.9s）。

### 2026-08-03 — 文件重整
把散落在 `CLAUDE.md` / `Uban/CLAUDE.md` / `uban-api/CLAUDE.md` 的通話／監控內容
全部遷移至本檔（`CLAUDE_call-monitor.md`），並在各 AI 記憶檔加上強制先讀本檔的指示。
順帶修正 §7.3 列出的 12 項文件與程式碼不符處。

### 2026-08-04 — 第十五輪：九項稽核（CCTV / YOLO / 訂閱）
> ⚠️ **補記**（2026-08-05 第十七輪時才回填）。當時未即時記錄，內容依程式碼中的
> `★ 2026-08-04 第 N 項` 註解與記憶檔 `project_round15_cctv_yolo_subscription.md` 重建。
> 程式碼註解是權威。

| 項 | 內容 | 落點 |
|----|------|------|
| 3 | ICE 協商加速：`iceCandidatePoolSize` 預蒐候選、`bundlePolicy: max-bundle`、`rtcpMuxPolicy: require`、`sdpSemantics: unified-plan` | `signaling.dart::_generateDynamicTURNConfig()`（:826）⚠️ **不是** `_configuration`，見 §7.3 #13 |
| 4 | 訂閱到期／設備超量彈窗改為**每次進入畫面只提示一次**，不再每次重新整理都彈 | `family_main_screen.dart`:79、:588、:614 |
| 6 | 訂閱層級（free / gold / diamond）在家屬端要一眼分辨得出來 | `family_interaction_tab.dart`:20、:1193 |
| 7 | **CCTV → YOLO 影格推送**與**警報語音橋接**：`_pushCctvFrame` 每 2 秒推一張、`audio-bridge` 30 分鐘單向語音（家屬 → 監視機） | `elder_screen.dart`:57/90/106/387、`family_interaction_tab.dart`:46/82/111/154 |
| B1/B2/B3 | `elder-unbound` 監聽器改為冪等註冊（原本直接掛 `socket?.on` 會在重連後失效）、連線失敗補重試、join 參數診斷 log | `family_main_screen.dart`:135/183/187/223/277/326 |

**幾個容易記錯的事實**（都被實測推翻過一次）：
- 「每 2 秒推一幀」是**由後端推論窗口反推**得到的節奏，不是任意選的。
- `device_id` 用的 `elder_id` 必須**去掉前綴**（見 §6.9）。
- 設備數量限制是「**同一 IP 合計 5 台**」的硬上限，且**只排除自己那一列**。
- `captureFrame` 產出的是 **PNG**（不是 JPEG）。

### 2026-08-05 — 第十六輪：家屬→長輩三態全滅（角色鍵分歧）
> ⚠️ **補記**，同上。依 `main.dart`:60-76/205-212/1464-1470 與記憶檔
> `project_videocall_round16_role_key_split.md` 重建。

**症狀**：家屬 → 長輩的來電，在長輩端 **APP 內／APP 外／被殺死三種狀態全部收不到**；
反方向（長輩 → 家屬）完全正常。

**根因**：角色有**兩個鍵**（`user_role` / `saved_role`），不同寫入者各寫各的；
`splash_screen` 校正時**只改記憶體裡的 `appRole`，沒有寫回 prefs**
→ FCM 背景 isolate 每次都讀到殘留的 `'family'`
→ BG handler 的長輩 CallKit 分支**恆不成立**。
**撥出**方向不讀這個鍵，所以失效是**不對稱**的——這就是關鍵線索。

**修復**：
- 前端 `_deriveMyRoleFromCall(senderRoleRaw, localRole)`（`main.dart`:76）：
  由**來電 payload 的發起方角色反推本機角色**，不再直接採信本機 prefs。
  兩處採用：BG handler（:212）與角色反轉判定（:1470，原本用 `appRole == senderRole`）。
- 後端補上 elder 在線 socket 的**內容鍵**查詢與對稱診斷 log。

### 2026-08-05 — 第十七輪：連線可靠性、監控可用性、跌倒測試、**全面安全稽核**

> 本輪分兩段：**A. 使用者提出的 5 項功能需求**（1-5），**B. 使用者追加的安全稽核**。

#### A. 功能需求

| # | 需求／症狀 | 根因 | 修復 |
|---|-----------|------|------|
| **1** | 家屬端判別長輩 `isOnline` 太慢，要求收斂到 **2.5 秒** | `onElderDevicesUpdate` 的 debounce 是「每收到事件就 cancel + 重排 2500ms」的**雙向** debounce，而輪詢週期也正好 2500ms、後端還會廣播給房內每個家屬 socket → debounce 幾乎永遠在 fire 之前就被下一個事件取消 → `_isElderOnline` 與 `_monitorDevices` **長期停在初始值** | 清單與「離線→上線」**立即套用**；只有「上線→離線」做一次性 2.5s 確認，計時器用 `??=` 建立**永不重啟**。→ **G40**。這同時是需求 3「家屬端看不到監視機」的根因之一 |
| **2** | 跨網域／網路不穩時，會出現「**WebRTC 連線成功、通話計時已跳動，但雙端完全沒有影音**」 | **三個獨立缺陷疊加**：(a) TURN 只送 `uban_elder_<id>` 帳號，但 Coturn 實際只有靜態帳號 `uban` → 被回 **401** → 拿不到任何 relay 候選 → 同網域靠 srflx 還能通、跨網域對稱 NAT 必然配不出 pair；(b) 通話計時與「已連線」UI 綁在 `onTrack`／`onAddRemoteStream` 上，而它只代表 **SDP 談成**；(c) 連線失敗時沒有任何回報，UI 停在假裝已連線的畫面 | (a) 靜態帳號**放第一組**，per-elder 帳號降為附加 → **G39**；(b) 改由 `onPeerConnected` 觸發，取 `onConnectionState` 與 `onIceConnectionState` 的**聯集** → **G37**；(c) 新增**媒體看門狗**：收到 remote track 後 12s 檢查 `inbound-rtp.bytesReceived`，仍為 0 就據實回報並安全返回主畫面 → **G38** |
| **3** | 監控機已連線，家屬端列表**不顯示監視器名稱**、無法點開、也退不回來 | 顯示不出來 = 問題 1 的 debounce 死結（`_monitorDevices` 停在初始值）。退不回來 = `VideoCallScreen` 結束一律走 `pushAndRemoveUntil` 重建主畫面 | 修 debounce（同 #1）；`VideoCallScreen` 新增 **`returnByPop`**（預設 `false`），CCTV 檢視傳 `true` 改走 `pop()`，並在 `true` 時渲染「← 返回」鍵。**預設值不可改**，見 §5.3 |
| **4** | YOLO 尚無法實測，需要一個**「跌倒測試」**鈕，走與真實偵測完全相同的通知路徑 | — | 長輩端 CCTV 畫面新增「🚨 跌倒測試」→ `POST /api/cctv/test-fall` → 與 YOLO 共用 `yolo_alert_dispatcher.dispatch`。家屬端補齊**亮螢幕（WakelockPlus）+ 獨立 channel 通知 + TTS 朗讀 + 彈窗**。**附帶抓到的既有 bug**：`_insert_alert` 是 UPSERT 且沿用原 `alert_id`，只用 `alertId` 去重會讓第二次以後的警報完全靜默 → 改用 `alertId + timestamp` 複合鍵 → **G41** |
| **5** | 「怎麼測 YOLO 跌倒偵測比較合適」 | — | 已答覆並寫入 **§6.11**（分派送鏈／推論兩階段測；姿勢比時間重要，10-15 秒足夠，不需要趴好幾分鐘；鏡頭要拍得到全身） |

#### B. 安全稽核（使用者追加：「為所有與雙向通話與單向監控的功能都做安全檢查」）

**稽核時發現的根本問題**：後端**會發** JWT，但**沒有任何 router 把 `get_current_user` 當 dependency**，
前端也從不送 `Authorization` 標頭 —— **整個 App API 實質上未認證**。
硬上 JWT 會讓每一幀 CCTV 推流當場 401、監控與通話全滅，
因此採取 **(a) 一律開啟的關係驗證 + (b) 選用的共用密鑰** 雙軌策略：
**所有檢查都是現行合法客戶端本來就會通過的**，不改變任何既有行為；
要更硬的保護則透過預設維持現狀的環境變數開啟。

新增 `uban-api/services/call_security.py`（環境變數**在呼叫時讀取**，不與 `load_dotenv()` 順序耦合）。

| # | 位置 | 洞 | 修補 |
|---|------|----|------|
| 1 | `POST /api/cctv/test-fall` | 無驗證、無開關，任何人可對任意長輩觸發真實緊急警報 + 高優先級 FCM | 開關（**預設關**）+ 密鑰 + 長輩存在 + 裝置歸屬，四道 |
| 2 | `POST /api/cctv/frame` | 無驗證，可冒充任意長輩推影格讓 YOLO 判出跌倒 | 密鑰 + 長輩存在（DB 抖動時放行，可用性優先） |
| 3 | `POST /api/alerts/{id}/audio-bridge` | **最嚴重**——可把 30 分鐘單向語音開進**任意裝置** | `from_id` 關係驗證 + `to_device_id` 歸屬驗證 |
| 4 | Socket `audio-bridge-request` | 同 #3；另有既有缺陷：延長權限的 SQL **沒帶 `to_device_id`**，會延長到別台裝置 | 同上 + SQL 補 `AND to_device_id = %s`（兩處） |
| 5 | `POST /api/alerts/{id}/acknowledge` | 可偽造確認者、可消音真實警報 | 關係驗證 |
| 6 | Socket `cctv-alert-ack` | 同 #5 | 關係驗證 |
| 7 | `GET /api/alerts/{elder_id}` | 可列舉任意長輩的跌倒史與快照 URL | `user_id` 改為**必填** + 關係驗證（安全前提：全專案**零呼叫端**） |
| 8 | `GET /api/alerts/audio/{id}` | 洩漏 `from_id` / `to_device_id` | 新增選填 `user_id`；未驗證時**不回傳**這兩個欄位 |
| 9 | Socket `delete-device` | 任何連線者可遠端踢掉任意裝置並清掉其 FCM token | 發送者必須是該長輩 comm/monitor 房間的成員 → **G46** |

**刻意不改的三項**（連同理由）記在 **§7.4**：整體未認證的架構問題、
SDP `targetId` 轉發不檢查房間成員、socket `userId` 自稱。

**新增護欄**：G37（連線判定取聯集）、G38（媒體看門狗掛 `onTrack`）、G39（TURN 靜態帳號優先）、
G40（在線判定 debounce 不可重啟）、G41（警報複合去重鍵）、G42（警報彈窗旗標不進單例）、
G43（test-fall 預設關）、G44（REST/Socket 授權強度一致）、G45（無權回 404）、G46（delete-device 驗身分）。

**新增檔案**：`uban-api/services/call_security.py`、`lib/services/cctv_alert_notification.dart`。
**新增環境變數**：`CCTV_TEST_FALL_ENABLED`（預設 `false`）、`CCTV_INGEST_TOKEN`（預設空＝不驗證），見 §6.10。

**API 契約變更**（呼叫端請對照）：
- `ApiService.triggerTestFall` 回傳 **`Future<String?>`**（原 `Future<bool>`）：`null` = 成功，非 null = 可直接顯示的原因。
- `ApiService.checkAudioBridge(alertId, {int? userId})` 新增選填 `userId`。
- `GET /api/alerts/{elder_id}` 的 `user_id` 由無 → **必填**。

**驗證**：`flutter analyze lib` **0 error**（135 項既有 info/warning）、
改動的 3 個 Dart 檔 `flutter analyze` **No issues found**、
`python -m py_compile`（`alert.py` / `call_security.py` / `socket_app.py`）OK、
`pytest tests/test_call_signaling.py -q` **8 passed**、`flutter build apk --debug` BUILD SUCCESSFUL。

> ℹ️ **一項刻意保留的不對稱**：`elder_screen.dart` 仍在 SDP 談成當下就把 `_status` 設為「通話中」，
> 而計時器只在真正連通時才啟動。因為 `_isInCall` 同時是 `onJoinFailed` 讀取的**並發守衛**，
> 把它延後到 ICE 連通會打開一個並發窗口。顯示文字與計時器不同步是**已知且可接受**的。

---

### 2026-08-05 — 第十八輪：音訊輸出、冷啟動速度、通話結束提示、鎖屏接聽、監控清單

使用者回報 5 項體驗／功能缺陷 + 1 項專案規範。新增護欄 **G47–G52**，並**修訂 G23**。

**① 通話中切換擴音／聽筒（與攝像頭開關無關）**
家屬端（`video_call_screen.dart`）本來就有這顆鍵，**只有長輩端缺**。
`elder_screen.dart`：新增 `_isSpeakerOn`（`:51`，預設 `true` = 擴音）、`_toggleSpeaker()`（`:724`）、
控制列的小型 FAB（`:1209`，`heroTag: 'speaker'`）。
`_initializeMedia()` 取得 `localStream` 之後（`:661`）先
`Helper.setAndroidAudioConfiguration(AndroidAudioConfiguration.communication)`
再 `enableSpeakerphone(_isSpeakerOn)` —— 順序不可顛倒，否則 Android 會把音訊路由回媒體串流。
`signaling.dart::enableSpeakerphone`（`:672`）是**既有**方法，本輪未改動。

**② APP 被殺死時，從 APP 外跳回視訊房間過久 → 冷啟動衝刺通道**
根因：`splash_screen.dart` 的標準流程在導航前會先 `await ApiService.getStatus`（**無逾時**）
再跑 `_pollActiveCallsForAccepted` 的延遲輪詢，兩者相加就是使用者感受到的等待。
修法：`_navigateToNext()` 開頭加一條衝刺通道（`:77`）——
`pendingAcceptedCall.value != null` 時呼叫 `_sprintToPendingCall()`（`:309`），
**只讀本機 prefs、不打任何 API**，直接交給既有的 `_resolveElderDestination()` / `_navigateFamilyHome()`。
角色校正改由 `_refreshRoleInBackground()`（`:365`）背景執行，仍**兩個鍵一起寫回**
（`user_role` + `saved_role`，第十六輪的教訓）。標準流程的 `getStatus` 補上 `.timeout(6s)`（`:136`）。
本機資料不完整就回傳 `false` 退回標準流程 → **見 G48**。

**③ 長輩端「無法接聽」提示放大配色 + 家屬端刪除「通話已結束」視窗**
- `elder_screen.dart::onCallBusy`（`:478`）：SnackBar 改為深綠 `#1A472A`、floating、圓角 18、
  `Icon(phone_missed, 32)` + 24sp/w700 白字「家人目前無法接聽通話」、4 秒。
- `video_call_screen.dart`：`_showCallRejectedThenGoHome` 拆成兩支——
  `_endCallAndGoHome()`（`onCallEnded` 專用，**靜默**）與
  `_showCallProblemThenGoHome(title, message)`（`onCallBusy` / `onConnectionLost` /
  `onPeerConnectionFailed`，**保留提示**、標題改為「未能接通」「連線中斷」「連線失敗」）。
  ⚠️ 沒有把四條全部消音，因為那會一併毀掉第八輪的拒接回饋與第十七輪的媒體看門狗回報 → **見 G50**。

**④ 有螢幕鎖的裝置接聽時跳過鎖定畫面，結束後還原**
`MainActivity.kt`（`mobile_app/android/app/src/main/kotlin/com/example/flutter_application_1/`）：
- `addFlags` 組合中**移除 `FLAG_DISMISS_KEYGUARD`**；`requestDismissKeyguard` 改為只在
  `SDK ≥ O && !keyguardManager.isKeyguardSecure` 時呼叫。原本無條件呼叫會讓有 PIN／圖形／指紋的
  裝置被強制彈出解鎖畫面——**這正是「無法直接接聽」的成因**。
- 新增 `restoreLockScreen()`（`:56`）：`setShowWhenLocked(false)` / `setTurnScreenOn(false)` +
  `clearFlags(SHOW_WHEN_LOCKED or TURN_SCREEN_ON or KEEP_SCREEN_ON)`；channel `when` 補 `"restoreLockScreen"`（`:111`）。
- Dart 呼叫點：`video_call_screen.dart::_goHomeAfterCall()` 開頭、
  `elder_screen.dart::dispose()`（`:895`，**`isCCTVMode` 除外**，監控機要維持恆亮推幀）。
  兩處都用 `.catchError()` —— `invokeMethod` 的 `PlatformException` 是非同步丟出的 → **見 G49**。

**⑤ 綁定監控機後，家屬端遠端視訊清單不刷新（重開 APP 也不會好）**
這一項有**三個各自獨立的根因**，全部修掉才會好：
1. **前端**：`elder_screen.dart:410-427` 原本包著 `if (socket?.connected != true)` 才 `connect()`。
   監控機配對後 socket 常常已經連著 → 永遠不會用 `deviceMode:'monitor'` 加入 `monitor_elder_<id>`。
   改為**無條件** `connect(..., deviceMode: widget.isCCTVMode ? 'monitor' : 'comm')`（`:427`）→ **見 G47**。
2. **後端**：`_get_elder_devices_list` 階段 1 用房間迭代順序先到先贏，
   `comm_elder_<id>` 的舊列會蓋掉 `monitor_elder_<id>` 的新列 → 回給家屬端的 `deviceMode` 恆為 `'comm'`
   → `family_main_screen.dart:246` 的 `where(d['deviceMode'] == 'monitor')` 濾不到東西。
   改為 `stage1_by_name` 依 `joinedAt` 取新（`socket_app.py:758-788`），
   `on_join` 寫入 `'joinedAt': time.time()`（`:1316`），並補兩處殘列清理：
   `on_join` 的兄弟房清理（`:1237-1250`，**刻意不呼叫 `sio.disconnect`**，那個 sid 可能是本次連線自己）
   與 `_purge_stale_reverse_mode_token` 的 `rooms_manager` 清理（`:974-984`）→ **見 G51**。
3. **部署**（不是程式問題）：遠端實測 `GET /openapi.json` 共 133 條路由、
   **`/api/cctv/*` 一條都沒有**；`POST /api/cctv/test-fall` 回的 `{"detail":"Not Found"}`
   正是 FastAPI 對未匹配路由的預設回應。`/cctv/frame`（`5accbdb`, 08-04）與
   `/cctv/test-fall`（`901d894`, 08-05）都還沒部署上去。
   連帶後果：**監控機的推幀一直在 404**，`cctv_feed_status` 從未被寫入，YOLO 跌倒偵測在遠端從未跑過。
   → 遠端需 `git pull` + 重啟，並在 `.env` 加 `CCTV_TEST_FALL_ENABLED=true`（G43 預設關閉）→ **見 G52**。

**⑥ 新增專案鐵律：每次更動完成後清除不必要的空白檔案**
寫入三份 `CLAUDE.md`（根目錄 §3.1 #9、`Uban/` §3.1 #9、`uban-api/` #10）。
判斷準則是「有沒有被程式碼／設定／建置流程引用」，不是檔案大小——
`__init__.py`、`.gitkeep`、`py.typed`、空的 `__init__.dart` **必須保留**。

**改動檔案**：`elder_screen.dart`、`video_call_screen.dart`、`splash_screen.dart`、
`MainActivity.kt`、`services/socket_app.py`、三份 `CLAUDE.md`。
`signaling.dart`、`main.dart`、`globals.dart`、`local_call_notification.dart` **本輪未動**。

**驗證**：`flutter analyze lib` **0 error**（135 項既有 info/warning，與第十七輪基線相同）、
`pytest tests/test_call_signaling.py -q` **8 passed**、
`flutter build apk --debug` **BUILD SUCCESSFUL**、
空白檔掃描（145 個 Dart + 166 個後端檔）**0 個零位元組／純空白殘留檔**。

---

### 2026-08-10 — 第十九輪：監視機綁定持久化、單向監控體驗、家屬端 UI 融合回補

使用者回報 4 項需求；測試中另發現 1 項**阻斷性**缺陷（下列第 ⓪ 項，優先級最高，
因為需求 ①②③ 全部操作在「監視機清單」上，而那個清單當時永遠是空的）。
新增護欄 **G53–G57**。

**⓪（阻斷性）6 位數配對碼配對成功，家屬端卻永遠看不到裝置**

根因：整個「綁定」在後端**沒有任何持久化**。
`routers/pairing.py:20` 的 `monitor_setup_codes` 是**行程內 dict**，`resolve_monitor_setup`
把配對碼 `pop` 掉之後就回傳，**不寫任何 DB**；「這台是 elder X 的監視機」唯一的紀錄，
是 Socket `join` **成功後**的副作用（`rooms_manager` / `room_fcm_tokens` / `user_fcm_token`），
而家屬端清單來源 `_get_elder_devices_list` 的三個階段**只讀這三處**。
`on_join`（`socket_app.py:1264`）有**六條** `join-failed` 分支，每條結尾都是 `sio.disconnect(sid)`
且**不留下任何持久狀態**：缺 room、房名格式錯、缺 userId、`_verify_room_access` 未授權、
訂閱裝置數上限（reason `monitor-limit`）、同 IP 上限 5 台（reason `ip_limit_exceeded`）。
→ 命中任一條，REST 配對回報成功、清單永遠空白，而**兩端都沒有可見的錯誤**
（家屬端完全無感；監視機端雖有 `onJoinFailed` 對話框，但當時不顯示 reason，測試者未辨識出）。

修法分三段：
- **持久化**：新表 `monitor_device_binding`（`socket_app.py:86` 的 `_DB_TABLE_DEFINITIONS`
  開機冪等建立、`database.py:391` SQLite 分支同步）。`resolve_monitor_setup`（`pairing.py:88`）
  在 `pop` 配對碼之後、回傳之前 **UPSERT 一列**（`:114`）→ 綁定在「配對碼被兌換」那一刻
  就成立，不再依賴 join 是否成功 → **見 G53**。
- **補洞**：`_get_elder_devices_list` 新增**階段 0**（`socket_app.py:777-787` 先查出
  `bound_by_name`，`:904` 在 `return` 前把「階段 1–3 都沒產出、但存在於綁定表」的名稱
  補成離線列 `bound_<device_id>`）。刻意採「補漏」而非「先塞再覆蓋」——
  階段 1–3 的輸出與修改前逐位元組相同，線上路徑零回歸 → **見 G54**。
- **讓失敗看得見**：`signaling.dart:82` 的 `onJoinFailed` 簽章改為
  `Function(String message, {String? reason})`，`:296-299` 把伺服器的 `reason` 一併傳出；
  `elder_screen.dart:361` 的失敗對話框顯示伺服器原文 + reason code，
  不再靜默留在 CCTV 模式假裝正常。

順帶查出並修掉的必爆隱患：`_client_ips` 原本只取 TCP 對端位址，全專案**沒有任何地方**讀
`X-Forwarded-For`。走 Tailscale Funnel 時所有裝置共用同一個 `ip_hash`，
「同 IP 上限 5 台」的實際語意其實是**全球 5 台**（目前靠 `purge_monitor_device_ip_on_startup()`
重啟清空才沒有立刻爆掉）。新增 `_extract_client_ip()`（`socket_app.py:1057`，
`X-Forwarded-For` 第一段 → `X-Real-IP` → TCP 對端），`on_connect` 改用它（`:1111`）。
⚠️ **仍待真機確認 Funnel 是否轉送該標頭** → 見 §7.4 第 4 項。

**① 家屬端開啟監控不應觸發長輩端的緊急通話聲音**

`elder_screen.dart::_handleEmergencyAccept`（`:301`）裡唯一會發出聲音的是那段 `FlutterTts`，
改用 `if (!widget.isCCTVMode)` 包住（`:319-320`）。
`endAllCalls()` 與 `sendCallAccept(...)` **完全不動**——監視機仍然自動接聽，只是**靜音** → **見 G56**。

後端不需要改：`on_emergency_call`（`socket_app.py:2024`）送的 FCM 本來就是**純 data**
（全檔 grep `messaging.Notification` / `notification=` 零使用，已在 `:2122` 就地註記），
系統層不會替它跳出有聲的 heads-up。

「不讓被監控端知道有人在看」：本輪**未新增**任何觀看者指示器；
`elder_screen.dart:1093` 起的「CCTV 監視中」只是靜態模式標籤，維持原樣。

**② 家屬端觀看監控時不顯示自己的鏡頭、也不要鏡頭類按鈕**

`VideoCallScreen` 新增 `final bool monitorViewOnly`（`:38`，預設 `false`、`:51`）。為 `true` 時：
`openUserMedia(videoEnabled: false)`（`:192`）→ **根本不取視訊軌**；
`:198` / `:204` 一併把 `_isCameraOff` 視為關閉（沒有視訊軌卻顯示「鏡頭開啟」會誤導）；
隱藏切換前後鏡頭鍵（`:718`）、本地預覽 PiP（`:777`）、控制列的鏡頭開關與切換鍵（`:832` / `:840`）。
**保留**麥克風開關、擴音、掛斷。

⚠️ 這是護欄 **G8**（進視訊房鏡頭預設開啟）的明文例外 → **見 G55**。
建構點有**兩處**（不是原計畫寫的「唯一設定點」）：
`family_interaction_tab.dart:1676`（互動分頁「觀看 CCTV」）與
`family_main_screen.dart:634`（跌倒警報彈窗「查看監視畫面」進入的監控檢視）。
兩者是同一個功能的不同入口，只改一處會造成「同功能從不同入口進去行為不一樣」。

**③ 家屬端要能刪除／改名監控；監視機主動退出也要從清單移除**

- **卡片選單**：`family_interaction_tab.dart::_buildMonitorDeviceCard` 加
  `PopupMenuButton<String>`（`:1709`）→ 重新命名（`:1714` → `:1801`）／刪除（`:1716` → `:1752`）。
  在此之前 `_showDeleteMonitorDeviceDialog` 唯一入口是「超過上限」對話框。
- **補上刪除端點的授權**：`DELETE /api/pairing/monitor_device`（`pairing.py:161`）
  **原本完全沒有任何授權檢查**——任何人知道 `elder_id` + `device_name` 就能刪掉別人的監視機。
  改走 `services/call_security.py::is_user_linked_to_elder`（`:187`），
  **未帶 `user_id` 或無關係一律回 404 不是 403**；同時刪掉 `monitor_device_binding` 對應列（`:219`）。
- **改名端點**：新增 `PATCH /api/pairing/monitor_device`（`pairing.py:290`，授權同上 `:315`）。
  `device_id = crc32(f"{elder_id}|{device_name}")` → **改名即改身分**，必須在同一次請求內
  更新**五個**存放點：`monitor_device_binding`（`:346`）、`user_fcm_token.device_name`、
  `cctv_feed_status.device_id`、記憶體的 `rooms_manager` 與 `room_fcm_tokens`；
  完成後 `_broadcast_elder_devices_update()`，並對該裝置 emit `monitor-renamed`（`:398`）
  讓它自己更新標籤與 `saved_device_name` → **見 G57**。
- **監視機主動退出**：`elder_screen.dart::_exitCCTVMode`（`:910`）原本只清 prefs +
  `clearSession()` + `forceDisconnect()`，**既不呼叫刪除 API 也不發任何事件**，
  家屬端因此留著一張永遠離線的殘影卡片。改為在 `forceDisconnect()` **之前**先呼叫
  `ApiService.deleteMonitorDevice(...)`（`:957`，走 HTTP、不依賴 socket 是否還活著），
  成功與否都繼續走完既有流程。
- **交叉驗證端點**：新增 `GET /api/pairing/monitor_devices`（`pairing.py:138`），
  直接呼叫 `_get_elder_devices_list`，回傳形狀與 `elder-devices-update` **完全相同**；
  家屬端 `family_main_screen.dart:163` 每 **10 秒**打一次（`:344`），與既有 2.5 秒 Socket
  輪詢併行。這正是 §6.6 原本宣稱存在、但程式碼裡根本沒有的機制（本輪一併把文件改成描述實作）。

**④ 與其他分支整合後的家屬端 UI 融合回補**

- `family_home_tab.dart` 的「開始撥號」原本**只跳 SnackBar、什麼都不呼叫** →
  新增 `onStartVideoCall` 回呼（`:19` / `:26` / `:947`），由 `family_main_screen.dart:1396`
  接到 `_startNormalVideoCall`，與舊版走同一條路徑。
- `family_interaction_tab.dart` 的一般視訊（`:723`）與緊急（`:746`）在建構 `VideoCallScreen`
  時**沒有傳 `targetSocketId`** → 補上 `family_main_screen` 已維護的 `_elderSocketId`，
  SDP 才能定點送達而不是靠房間廣播找對象（G9）。
- `family_main_screen.dart::dispose()` **只清了 `onElderDevicesUpdate`**，
  `onCallRequest` / `onEmergencyCall` / `onCancelCall` 三個覆寫留在 Signaling singleton 上 →
  一併清除（`:1248-1256`），並取消 `_monitorHttpTimer`（`:1237`）。

> ⚠️ **本輪還修了合併帶來的編譯損壞**（與上述五項需求無關，但不修連建置都過不了）：
> `api_service.dart`（2 處方法被截斷）、`family_main_screen.dart`（缺欄位 + 缺 import）、
> `elder_pairing_display_screen.dart`（缺區域變數）、
> `family_interaction_tab.dart`（重複的生命週期方法 + 3 個缺欄位 + 一段 102 行被誤插入的方法本體）。
> 分支在 HEAD 狀態下 `flutter analyze` 是紅的，這批損壞**不是本輪改動造成的**。

**改動檔案**
後端：`routers/pairing.py`、`services/socket_app.py`、`database.py`、`tests/test_call_signaling.py`。
前端：`signaling.dart`、`elder_screen.dart`、`video_call_screen.dart`、`family_main_screen.dart`、
`family/family_interaction_tab.dart`、`family/family_home_tab.dart`、`services/api_service.dart`、
`elder_pairing_display_screen.dart`。
`main.dart`、`globals.dart`、`local_call_notification.dart`、`splash_screen.dart` **本輪未動**。

**驗證**
- `flutter analyze lib` — **0 error**（142 項既有 info/warning）
- `flutter build apk --debug` — **BUILD SUCCESSFUL**
- `python -m py_compile services/socket_app.py routers/pairing.py database.py services/call_security.py` — 通過
- `pytest tests/test_call_signaling.py -q` — **12 passed**（8 → 12）
- `DB_HOST=100.73.39.14 pytest tests/test_institution.py -q` — **34 passed**（本輪未動該檔）

新增的 4 條迴歸鎖（全在 `tests/test_call_signaling.py`，共用一個以 dict 模擬 MySQL 的
`_FakeMonitorDB`，同時掛在 `routers.pairing.db_cursor` 與 `services.socket_app.db_cursor` 上——
本輪的核心正是這條跨模組資料流，兩邊各接各的假 DB 就測不到它們對不對得上）：

| 測試 | 鎖住什麼 |
|------|---------|
| `test_resolve_monitor_setup_makes_device_visible_before_any_join` | G53＋G54：**完全沒有任何 join** 也必須看得到一台離線裝置 |
| `test_bound_device_not_duplicated_after_successful_join` | G54：階段 0 只補洞，join 成功後同名裝置不得出現兩張卡片 |
| `test_delete_and_rename_monitor_device_reject_unlinked_caller` | D2：無關係與**未帶 `user_id`** 都必須回 **404**，且不得留下半套副作用 |
| `test_rename_monitor_device_syncs_all_stores_and_changes_device_id` | G57：五個存放點同步、`deviceId` 確實改變、清單不出現裝置分身 |

**尚未收斂的兩件事**
1. `X-Forwarded-For` 修法**尚未經真機確認** Tailscale Funnel 是否轉送該標頭。
   確認之前**不要放寬 5 台上限**——放寬只是把「配不上」換成「濫用沒防線」。見 §7.4 第 4 項。
2. 遠端的 `scripts/migrations/001_institution.sql` **從未執行過**（先前 `main.py` 的
   `db_cursor` NameError 讓自動 pull 之後的啟動失敗），下一次成功部署才會建出那批表。
   `monitor_device_binding` **不受影響**——它走 `_DB_TABLE_DEFINITIONS` 的開機冪等建立，
   不靠 migration 腳本。

---

### 2026-08-11 — 第二十輪：session 綁死、監控刪除雙向同步、麥克風常駐、撥出失敗、音量來源

使用者回報 **9 項**。其中 ①⑤ 是同一個根因（session 從不釋放）、③④ 是監控刪除的兩個方向、
⑥ 拆成「麥克風」與「攝像頭」兩半。新增護欄 **G58–G66**。

**①⑤ session 被綁死（未選身分也綁上次的 session、監控機退出後再也綁不上配對碼）**

根因有兩層：

- **前端**：全專案**沒有任何統一的 session 釋放**。四個登出入口各自 `prefs.remove(...)`
  片段清理，漏鍵是常態；身分選擇頁 `IdentificationScreen` 是 `StatelessWidget`，
  **進頁時什麼都不做**。於是殘留的 `user_role`／`saved_role`／`elder_room_id` 讓
  Signaling 仍在舊房間裡 → 停在身分選擇頁也照樣收到來電（APP 內／外／被殺死皆然），
  下次開 App 又被 `splash_screen` 的自動恢復導回被綁死的帳號。
- **後端**：`monitor_setup_codes` 是**行程內 dict**，`resolve_monitor_setup` 把碼 `pop` 掉。
  後端一重啟（遠端是自動 pull 後重啟）那組碼就永久消失；而「不存在」與「已過期」
  回的是同一句話 → 使用者輸入正確的 6 位數，永遠只看到「綁定碼過期或錯誤」。

修法：
- 新增 `lib/services/session_manager.dart`（`_sessionKeys`:18／`releaseSession`:38／
  `releaseIfBound`:96）。四個登出入口 + `identification_screen.dart`:26 全部改走它 → **G58**。
  🚫 **不用 `prefs.clear()`**——會連 `wake_word_enabled` 這種裝置偏好一起殺掉。
- 新增 `POST /api/pairing/session/release`（`pairing.py`:1218），前端清 prefs 前先通知後端
  釋放殘留的 socket／FCM 綁定。刻意不做關係驗證（它只解除、不取得任何東西，
  而且身分選擇頁呼叫時本來就還沒有身分）。
- 配對碼改持久化到新表 `monitor_setup_code`（`socket_app.py`:149、`database.py`:411），
  `/resolve` **不再 `pop`**，改標記 `used_at`（15 分鐘 TTL 內冪等），
  「不存在 404 / 已過期 410」分開回 → **G64**。前端
  `monitor_pairing_screen.dart`:42 優先顯示 `ApiService.lastResolveError` 的伺服器原文。
- `splash_screen.dart` 補一條家屬 session 守門：`role=='family' && uid!=null` 時直接
  `_navigateFamilyHome`，不讓它掉進長輩恢復流程。

**② 刪除家屬端所有的 RenderFlex 溢位警示（黃黑斜紋）**

先用 import 可達性把範圍從「34 個名目上的家屬畫面」收斂到**實際掛在 `main.dart` 上的 9 個**
（`family_dashboard_view.dart`、`family_agent_view.dart`、`ai_hub_screen.dart` 等
全是零建構點的孤兒，改了使用者也看不到）。掃出 28 個候選、逐一判讀後**實修 13 處 / 7 檔**。

反覆出現的形狀是：
`Row(spaceBetween, [Row(icon + 動態 Text), Container(badge)])` 而左側 `Row` 沒有 `Expanded`。
關鍵是 **`Row` 會先用無限寬量測非 flex 子元素**——一個 AI 產生的
`mood_title` 徽章可以把寬度吃光，讓左邊的 `Expanded` 只剩 0 → 整條溢出。
所以 `family_home_tab.dart` 的心情徽章用的是 `ConstrainedBox(maxWidth: 180)` 而不是 `Flexible`
（它是非 flex 子元素，包 `Flexible` 會破壞 1:1 的 flex 分配）。

實修清單：`family_main_screen.dart`（AppBar 標題——它出現在家屬端**每一頁**最上方、
長輩名字長度不可控，是螢幕截圖最可能的來源；來電 dialog 標題）、
`family_home_tab.dart`（情緒氣象台 header、心情徽章、對話紀錄 dialog 標題、
長輩名、SnackBar）、`family_data_tab.dart`（人生故事膠囊 header、故事卡標題）、
`family_interaction_tab.dart`（「遠端視訊監控」header——原本是 `Text + Spacer`，
標題不可壓縮，一旦出現「N 警報」徽章總寬就超過卡片內寬）、
`alert_center_screen.dart`（`typeLabel` 由後端下發）、
`family_subscription_screen.dart`、`subscription_test_screen.dart`。→ **G63**

**③ 家屬端監控介面刪掉「掛電話」鍵**

`video_call_screen.dart`:868 包進 `if (!widget.monitorViewOnly)`。
監控是單向觀看不是通話，掛斷的隱喻本身就錯；離開走左上「← 返回」
（`returnByPop: true`，第十九輪就已存在）。→ **G60**

**④ 家屬端刪除監視器後，監控機要立刻退回主畫面**

第十九輪只做了「監視機主動退出 → 家屬端清單移除」，**反方向沒做**。
新增 Socket 事件 `monitor-removed`：後端 `pairing.py`:359 在 `sio.disconnect(kick_sid)`
**之前** emit（順序反了就送不出去 → **G65**）；前端 `signaling.dart`:96/:501，
註冊點只有 `elder_screen.dart`:697（`isCCTVMode` 分支內、以 `elderId`/`deviceName` 過濾），
收到即 `SessionManager.releaseSession()` → 導回身分選擇畫面。
`_exitCCTVMode()`（:992）也改走 `deleteMonitorDevice` → `releaseSession()`（:1051）→ 導頁，
刪除 API **必須排在 `releaseSession()` 之前**（後者會清掉呼叫它所需的 `caregiver_id`）。

**⑥ 麥克風／攝像頭不該在開 App 後自動不斷開開關關**

麥克風：根因是長輩端的**全時語音喚醒**。`elder_home_screen.dart` 有**五條**會互相把對方
拉起來的自動重啟路徑（`_initWakeWordListener`、`_loadAssistantSettings`、
每 5 秒的 watchdog、`_safeRestartWakeWordListening`、lifecycle `resume`），
只擋其中幾條沒有用。新增 `wakeWordEnabledNotifier`／`kWakeWordEnabledKey`
（`globals.dart`:29/:32，**預設關閉**），五條全部在**申請麥克風權限之前**早退，
開關放在長輩端個人設定。→ **G59**

順帶稽核確認**不需要**再加閘：`elder_chat_tab.dart` 的 `_voiceLoopEnabled` 預設 `false`
且監聽是長按對講；`google_assistant_overlay.dart` 的 `initState` 只 `initialize()`
不 `listen()`；`zen_pond` 系列都是按鈕觸發。
（`elder_chat_tab.dart` 在 `lib/` 內**零建構點**，是孤兒檔。）

攝像頭：全專案只有 3 個 `openUserMedia` 呼叫點，全在通話／CCTV 畫面內，
沒有任何 `CameraController`／`availableCameras` —— 也就是**平時不會開鏡頭**，
需求的「限制攝像頭僅在視訊通話時才可開啟」在架構上已經成立。
⚠️ **但語音通話仍會取得視訊軌再 `enabled = false`**，所以系統的鏡頭指示燈還是會亮一下。
要真正釋放硬體得走 `replaceTrack` / renegotiation，而
`signaling.dart`:964-970 明文禁止 ICE restart 與重新協商（那是本專案風險最高的改動）。
**本輪刻意不動**，留待獨立一輪處理。

**⑦ 長輩端在 APP 內撥不出電話給家屬端**

`sendCallRequest` 原本是 `void`，且**不檢查 socket 連線狀態**就 `emit`。
socket.io 對未連線的 socket 是**靜默丟棄**——畫面停在「撥號中」直到逾時，兩端零錯誤。
改成 `Future<bool>`（`signaling.dart`:781）：socket 為 null 直接回 `false`，
未連線則輪詢 50×100ms（最多 5 秒），**連上之後才取 `issuedAt`**
（在輪詢前取會先燒掉數秒有效期，接聽端可能當場判過期）。→ **G62**

**⑧ 一端掛斷、另一端仍留在通話房**

前端 `hangUp()` 要求 `_currentRoomId != null` 才發 `end-call`，
但接聽方在某些路徑下只有 `_peerSocketId`／`_currentCallId`、`_currentRoomId` 是空的
→ 掛斷根本沒送出去。前端放寬成「三者其一非空就發」（`signaling.dart`:1300）；
後端對應補強：`on_call_accept`（`socket_app.py`:2215）在 :2257 把接聽方 sid
併進 `call_registry`，`on_end_call`（:2367）的通知集合 =
既有目標 ∪ `accepter_sid`（:2402）∪ 該房間內所有其他 sid，且**容忍 `room=None`**。→ **G66**

**⑨ 通話音量來源（電話／擴音）切換鍵**

`_isSpeakerOn` 改為 `late`，初值 = `isVideoCall || isEmergency || monitorViewOnly`
（`video_call_screen.dart`:72、`elder_screen.dart`:173）→
**一般通話預設聽筒、視訊／緊急／監控預設擴音**。
語音通話中途開鏡頭時 `_autoSwitchToSpeakerOnCameraOn()`（:368）自動切擴音，
但只切一次（`_speakerAutoSwitched`:76）——使用者手動按過喇叭鍵後不再自動覆寫。
圖示改為 `volume_up`（擴音）／`phone_in_talk`（聽筒）；
原本的 `volume_off` 語意是「靜音」，會讓使用者以為按下去會沒聲音。→ **G61**

**驗證**

- `flutter analyze lib` — **0 error**（142 issues，與本輪動工前基線一致）
- `flutter build apk --debug` — **BUILD SUCCESSFUL**
- `pytest tests/test_call_signaling.py -q` — **15 passed**（新增 3 條，見下表）
- `DB_HOST=100.73.39.14 pytest tests/test_institution.py -q` — **34 passed**（本輪未動該檔）

| 測試 | 鎖住什麼 |
|------|---------|
| 配對碼持久化 | G64：後端「重啟」後同一組碼仍可兌換，且 TTL 內重複兌換冪等 |
| 配對碼錯誤分流 | G64：不存在回 **404**、逾時回 **410**，兩者訊息不同 |
| 掛斷路由 | G66：`room=None` 的 `end-call` 仍能通知到 `accepter_sid` 與房內其他成員 |

**本輪的兩個例外聲明**

1. **鐵律「Opus 制定／檢驗、Sonnet 執行」本輪無法遵守**：三個 Sonnet 子代理
   （`round20-call`／`round20-session`／`round20-backend`）全部以
   `You've hit your session limit` 失敗（第十九輪亦然），實作由 Opus 直接完成。
2. **需求 ⑥ 的「攝像頭硬體釋放」刻意未做**，理由見上方 ⑥。

---

### 2026-08-11 — 第二十一輪：APP 永久白屏、長輩撥不出、session 殘留、13px 溢位漏網

使用者回報 **4 項**。需求 2 是第二十輪自己引入的缺陷，需求 4 由需求 2 誘發但根因獨立。
新增護欄 **G67–G72**。

**④ 無論重開幾次 APP 都是「無動畫、不跳轉、無法操作的白屏」（最嚴重，全鏈路四層修）**

根因是一筆**永生的毒資料**：

- `main.dart::s.onEmergencyCall` 的長輩分支（~:1682）寫 `pendingAcceptedCall` 到 prefs 時
  **沒有帶 `timestamp`** —— 這是全專案唯一漏帶的寫入點
  （BG 緊急路徑 :236、CallKit accept :477、備援通知 :218 都有）。
- `main()`（:599）的過期判斷寫成 `ts != null && ageMs > 60000`，缺 `timestamp` 時**恆為 false**
  → 這筆資料**永遠不會過期**；而緊急通話結束時也沒有任何路徑移除這個 prefs 鍵。
- 於是**每一次**冷啟動都重新載入同一通早已結束的通話 →
  Splash 立刻 `_fadedOut = true`（對應「既無動畫」）並被導去一通死掉的通話（對應「也不跳轉」）→
  永遠如此（對應「無論重新打開 APP 幾次」）。

四層修法（缺一都不夠）：

1. **寫入端**補 `'timestamp': DateTime.now().millisecondsSinceEpoch`。
   ⚠️ 只補 `timestamp`，**不補** `issuedAt`/`expiresAt`——**G22**（原文誤寫成 G24）明訂緊急通話刻意省略那兩個欄位。
   ⚠️ **這條在第二十二輪已被推翻**：緊急路徑現在兩個欄位都必須帶（`+60000`），見改寫後的 G22 與 G73。
   當時的判斷在「有效期 120s」的前提下是合理的；此處保留原文以記錄推理脈絡。
2. **讀取端**（`main()` :599、`pendingRingCallData`、`_checkPendingCallFromSharedPreferences` :1249）
   一律改成 `ts == null || ageMs > 窗口` → 視為過期並 `prefs.remove(...)`。
   這一半是**已中毒裝置的自癒路徑**，比第 1 點更重要。
3. **Splash** 在 `pendingAcceptedCall.value != null` 時 `unawaited(_clearPendingCallPrefs())`，
   記憶體接手後就清掉 prefs 副本；同時**移除**原本在這裡就 `setState(() => _fadedOut = true)` 的兩處。
4. **兜底**：`runApp()` 改為無條件執行（`_bootstrap().timeout(10s)` 包 try/catch，
   `runApp` 在 try **之外**），開機路徑每個 `await` 各自帶逾時；
   Splash 加 `_navigated` 互斥 ＋ 15s 導航看門狗 ＋ 5s 後才顯示的載入指示。→ **G67 / G68 / G69**

> 關鍵認知：**Dart 的 `try/catch` 攔得到「丟例外」，攔不到「卡住」。**
> 原本 `runApp()` 雖然在 try/catch 之外，但只要 `Firebase.initializeApp()`、
> `requestPermission()`（會等系統權限對話框）、`LineSDK.setup()` 任一個不回來，
> 它就永遠不會被呼叫 → 畫面停在系統原生啟動底色（純白、無動畫、無法操作）。
> `.timeout()` 把「卡住」轉成可攔截的例外（不取消底層工作，future 仍會跑完，這正是要的）。
> `requestPermission()` 另外移到 `onBackgroundMessage` 註冊**之後**，
> 避免使用者不點權限對話框就把整個開機擋死。

**① 長輩端在 APP 內仍打不通家屬端（第二十輪 ⑦ 只修掉一半）**

第二十輪修的是 `sendCallRequest` 不等 socket 連線（G62）。本輪找出**另外四個**獨立缺陷：

- `friends_screen.dart::_startCall` 寫成 `widget.roomId ?? widget.userId.toString()`，
  而 `userId` 是 **`caregiver_id`**（帳號整數 PK）**不是 elder_id** →
  roomId 缺漏時撥出的房名變成 `comm_elder_<caregiver_id>`，
  後端查不到任何家屬、log 印「無任何轉發目標」、兩端零錯誤。
  改為 `widget.roomId` → prefs `elder_room_id` → **明確報錯**。→ **G70**
- `video_call_screen.dart::_buildFallbackHome()`（:476）建構 `ElderHomeScreen` 時
  **沒傳 `roomId`** —— 這就是上面那個 null 的上游來源。已補上 `widget.roomId`
  （前綴由 `ElderScreen::_getFormattedRoomId()` 冪等處理）。
- `elder_screen.dart::_initElderMode()`（:470）的 `FirebaseMessaging.instance.getToken()`
  **沒有逾時**，卡住會同時封死 `_signaling.connect()`（:475）與 `.then()` 的 autoCall 鏈。
  已加 try/catch ＋ `.timeout(5s)`，失敗就以「無 token」繼續進房。→ **G71**
- `initState()`（:181）的 `_initElderMode().then((_) => tryAutoCall())` **沒有 `onError`**，
  一丟例外整條鏈不執行。已改為帶 `onError:` 且錯誤分支**照樣**呼叫 `tryAutoCall()`。

**② 重新登入長輩端後仍有 session 不釋放，家屬端撥打顯示「無法連線」**

這是第二十輪 `POST /api/pairing/session/release` 自己引入的缺陷：
DELETE 條件寫成 `WHERE fcm_token = %s AND room_id = %s`，
但用戶端（`session_manager.dart`:38-59）送的是 prefs 的 `elder_room_id` = **裸 elder id**（`'0001'`），
而 `user_fcm_token.room_id` 存的是**帶前綴的 socket 房名**（`comm_elder_0001`／`monitor_elder_0001`，
寫入點 `socket_app.py`:1456-1463、:1506-1514）→ 永遠 0 rows → token 從未釋放。
改為**只以 `fcm_token` 為鍵**；`room_id`／`user_id` 只寫進診斷 log。
（`user_id` 同樣不可靠——殘留列帶的是**舊帳號**的 user_id。）→ **G72**
記憶體清理與 `_broadcast_elder_devices_update` 兩個步驟未動。

**③ 家屬端「互動」分頁仍有 13px RenderFlex 溢位徽章壓到視訊通話鍵**

第二十輪的 13 處修正全部沒打到真正溢出的那個 `Row`。
實際位置是 `family_interaction_tab.dart::_buildCallSection()`（:938 起，
深藍漸層 `#1E1B4B → #1E40AF → #0284C7`，與截圖底色一致）的內層 `Row`（:990）——
它在外層 `Expanded` 裡放了**兩個非 flex 子元素**（`Text('視訊通話')` ＋ 徽章 `Container`），
必定溢出。改用 `Wrap(spacing: 8, runSpacing: 4)`（`Wrap` 永遠不會溢位），順手移除多餘的 `SizedBox`。
該檔其餘 17 個 `Row` 已逐一稽核，都已有 `Expanded`／`Flexible`。→ **G63 補充**

**驗證**

- `flutter analyze lib` — **0 error**（141 issues；比第二十輪基線 142 少 1，因 `Wrap` 改寫移除一個 `const SizedBox`）
- `flutter build apk --debug` — **BUILD SUCCESSFUL**
- `python -m pytest tests/test_call_signaling.py -q` — **15 passed**（不退步）
- `python -m py_compile routers/pairing.py` — 通過

**本輪的鐵律遵守情形**

「Opus 制定／檢驗、Sonnet 執行」**本輪部分遵守**：需求 ② 的後端修改由 Sonnet 子代理
`r21-backend` 執行並自驗（15 passed），由 Opus 覆核；
其餘三項為前端多檔連動、且與需求 ④ 的根因鏈交纏，由 Opus 直接完成。
（第十九、二十輪的 Sonnet 子代理全數以 `session limit` 失敗，本輪已恢復正常。）

---

### 2026-08-11 — 第二十二輪：監控停機的奇偶數之謎、跳回長輩端後通話全滅、來電有效期收斂

使用者一次提出 11 項。以下依「根因」而非「需求編號」分組，因為多項共用同一條因果鏈。

**① 監控機「奇數次進入會停機、偶數次才恢復」（需求 3）— 卡住的 `await`，不是玄學**

使用者特別註明「此問題已確認確實與進入次數有關，不必質疑」。查下去確實有嚴格的機制：

1. 家屬端進入監控 → 監控機的 `startMonitoring`/`_acceptCall` 先走 `_closePeerConnection()`，
   其中 `for (sender in await pc.getSenders()) { await pc.removeTrack(sender); }`
   會把本機視訊軌從編碼器上拆下來。
2. 若此刻剛好有一輪 `videoTracks.first.captureFrame()` 正在等原生層回傳，
   那個 Future **永遠不會完成**——不是丟例外，是卡住，`try/catch` 完全攔不到。
3. `finally` 因此不執行，`_cctvFrameSending` 永遠停在 `true`，
   之後每一輪都被迴圈開頭的 `if (_cctvFrameSending) return;` 擋掉 → **推幀徹底停止**，畫面凍住。
4. 家屬端**再進一次**時 peer connection 重建、軌道重新掛回編碼器，
   卡住的 Future 才被原生層以錯誤收掉 → `finally` 終於跑到 → 旗標歸位 → 恢復正常。

奇偶數規律正是「拆軌／掛軌」交替造成的。修法三層（`elder_screen.dart`:181-234）：
`captureFrame().timeout(6s)` + `pushCctvFrame().timeout(10s)`、連續 3 輪失敗重建、
30 秒無成功影格看門狗（看門狗刻意放在 `localStream` 檢查**之前**，
因為「localStream 變 null」本身就是要重建的故障態，擺後面會被 `return` 掉而永不觸發）。
新增 `_recoverCctvCapture()`（:243）：停迴圈 → `stopMedia()` → 等 400ms → `_initializeMedia()` → 重掛預覽 → 重啟迴圈。
（不能直接叫 `_initializeMedia()`，它開頭有 `if (_mediaInitialized) return;`。）→ **G75**

**② 從監視機跳回長輩端後通話全滅、>50% 機率 ANR（需求 8）— 孤兒 socket ＋ 未釋放的相機**

使用者推測「可能依舊仍是 session 未清理乾淨」，方向正確，但漏的不是 prefs 而是**物件**。兩個獨立根因疊加：

- **孤兒 socket**：`forceDisconnect()` 舊寫法是
  `if (socket != null && socket!.connected) { socket?.disconnect(); socket = null; }`。
  監控機退出時 socket **已經斷線**，於是整段是 no-op——`socket` 欄位仍指著舊物件，
  它的 handler 與**重連排程都還活著**。接著 `connect()` 又用新的 `io.io(...)` 直接覆蓋欄位。
  結果長輩端同時有新舊兩個 socket：新的收 FCM／來電通知（所以「通知收得到」），
  舊的一旦自己重連成功就用**舊 sid** 搶走 join 與 offer/answer（所以「進了房永遠連不上」）。
  每進出一次監控就多一個孤兒，背景重連風暴最終拖成 ANR。
  修法：新增 `_disposeSocket()`（`signaling.dart`:1429），順序固定 `clearListeners()` → `dispose()`，
  兩步各自 try/catch；`forceDisconnect()` 與 `connect()` 建新連線前都走它。→ **G76**
  > `clearListeners()` 必須在前：`dispose()` 內部的 `disconnect()` 會觸發 `onclose`，
  > 沒先拔 handler 就會回打到 `onConnectionLost`，退出監控時誤跳「連線中斷」。
- **未釋放的相機**：`openUserMedia()` 取新媒體前沒有釋放舊的 `localStream`（既沒 `stop()` 也沒 `dispose()`）。
  Android 相機是獨占資源，累積幾個孤兒 stream 後 `getUserMedia` 會**卡住不返回**
  （同樣不是丟例外）→ 接聽流程停在那一行 → 「按了接聽沒反應、不跳轉」。
  `openUserMedia()`（:1314）改為先釋放再取；`elder_screen.dart::dispose()`（:1355）改成
  **先停推幀、先還相機**，再解除 socket 原生監聽（:1418）、`releaseSession()`、`forceDisconnect()`。
  `disposeLocalStream` 改為**視模式而定**（:1431）。
- 順帶把 `SessionManager` 漏清的 camelCase 待處理來電鍵補上（`session_manager.dart`:30/:94/:111），
  並在清 prefs 後一併清掉記憶體裡的 `pendingAcceptedCall` notifier。

**③ 「延遲來電通知」：發起端最多等 1 分鐘（需求 10）**

使用者回報「明明是 2、3 分鐘前撥的電話，怎麼又突然跳出來電通知」。三處都要改，缺一無效：

- **有效期 120s → 60s**：`globals.dart`:47 `kCallValidityMs = 60000`；
  後端 `expiresAt = issuedAt + 60000`、FCM `ttl=60s`。
  同時把三處寫死的 `120000`（`main.dart`:672、`splash_screen.dart`:272/:288）換成常數。→ **G73**
- **緊急通話不再是特例**：舊設計「刻意不帶 `issuedAt`/`expiresAt`、`ttl` 維持 **3600s**」
  意味著一通早該結束的緊急通話可以在**一小時後**才彈出來電畫面——正是本需求最極端的個案。
  現在兩條路都帶有效期、`ttl` 一律 60s。**這推翻了舊 G22**，該條已就地改寫並標註推翻理由。
- **伺服器端遏止**：新增 `_cancelled_call_ids`（`socket_app.py`:225-259，TTL 300s、上限 500 筆）。
  `on_cancel_call` 記下 callId；`on_call_request`(:1767) / `on_emergency_call`(:2120)
  **開頭第一件事**就是 `_is_call_cancelled()`，命中整通不發（Socket 與 FCM 皆不送）。
  取消推播的 `ttl` 由 10s 提高到 60s（否則取消訊息比來電訊息先過期）。→ **G79**
  > 前端的 `_invalidCallIds` 只擋得住**已經送到**的封包，擋不住**還沒送出**的——
  > 而「延遲來電通知」的本質正是封包卡在 FCM 佇列裡還沒送出。只能在伺服器端做。

**④ 緊急通話無條件接聽 + 7 秒提示音（需求 9）**

自動接聽不再限於 CCTV 模式（`elder_screen.dart`:448）；
刪除「緊急通話，自動接聽中」TTS，改播 `assets/sounds/emergency_alert.wav`（約 7 秒，
`_playEmergencyTone()`:518），`onPeerConnected`(:569) 與 `dispose()`(:1474) 兩處都會停並釋放。
`pubspec.yaml`:136 新增 `assets/sounds/`。→ **G77**
（CCTV 模式仍必須完全靜音，**G56 不變**——判斷點是 `widget.isCCTVMode`。）

**⑤ 監控 UI 五項（需求 1／4／5／6）**

- 配對碼彈窗在監視機兌換成功後**自動關閉**：2 秒輪詢「清單裡出現新裝置」，
  來源是父層推下來的 `widget.monitorDevices` ＋ HTTP `fetchMonitorDevicesOrNull`，
  硬上限 150 次（5 分鐘）逾時只停輪詢不關窗。後端 `resolve_monitor_setup` 補上
  `_broadcast_elder_devices_update`（`pairing.py`:218，daemon 執行緒 + `asyncio.run`，
  **不可改成 `async def`**——三支測試同步呼叫它）。→ **G80**
- 監控畫面隱藏計時與「緊急通話」膠囊：`video_call_screen.dart`:653 包 `if (!widget.monitorViewOnly)`，
  **純顯示層，計時邏輯一行未動**。→ **G74**
- 監控 UI 改家屬端暗色系、ICON 依會員層級變色：`_tierAccentColor()`（:2106，全分頁唯一來源，
  `_buildTierBadge()` 一併共用）。一般 `0xFF10B981`／黃金 `0xFFF5C451`／鑽石 `0xFF38BDF8`，
  刻意比 `family_dashboard_view.dart` 那組亮一階（舊那組是為白底挑的，深底上黃金會糊掉）。
- 運行中被刪除顯示「該監控機已被刪除」：新增 `fetchMonitorDevicesOrNull`（**失敗回 `null`**）
  供 `_verifyMonitorStillExists()`（:999）區分「查詢失敗」與「查無此裝置」。→ **G78**
- 跌倒測試（需求 2）：後端回「測試端點未啟用」時改顯示 8 秒長文案，說明這是後端安全預設值、
  不是 App 故障。🚨 **這不是修復**——`CCTV_TEST_FALL_ENABLED` 在**遠端實體伺服器**的 `.env` 上，
  本機改不到，要真的能測必須有人上遠端改設定並重啟（測完改回 `false`）。**不可**動後端預設值（G43）。

**⑥ 連線加速與畫質提升（需求 7）— 保守、可逐項還原**

使用者明確要求「若無法做到就還原，**不要動到目前通話的完整性**」，故只做四項零風險改動：

| 項目 | 前 → 後 | 位置 | 還原方式 |
|------|--------|------|---------|
| `iceCandidatePoolSize` | 2 → **4** | `signaling.dart`:1024 | 改回 `2` |
| 編碼參數套用時機 | `setLocalDescription` → `setParameters` → `emit`　⇒　**`emit` → `setParameters`** | `createOffer`:1252、`_handleAnswer`:949 | 把 `await _applyVideoEncodingParams()` 移回 `emit` 之前 |
| 視訊上限 | 2.5 Mbps / 30fps → **4 Mbps / 60fps** | `signaling.dart`:1194-1195 | 改回 `2500000` / `30` |
| `getUserMedia` ideal | 1280×720@30 → **1920×1080@60** | `openUserMedia`:1301-1305 | 改回 `1280`/`720`/`30` |

關鍵是**沒有動任何流程與時序語意**：
編碼參數只影響「送出去的畫質」、與 SDP 內容無關（改的是 sender encoding 不是 local description），
所以移到 `emit` 之後語意完全等價，卻讓對端早幾百毫秒開始協商（那幾個 `setParameters`
是跨 platform channel 的原生呼叫，中低階 Android 實測數百毫秒）。
`getUserMedia` 的 **`min` 值刻意維持 640×480@24 不變**——`mandatory` 的 min 在 Android 是硬性條件，
跟著拉高會讓不支援 1080p60 的機型直接 `getUserMedia` 失敗（等於無法通話）；
`ideal` 拿不到只會退到最接近的解析度。位元率上限提高也不會塞爆網路，
WebRTC 的擁塞控制（GCC）仍會依實測頻寬自動下修。
`iceServers` **一個字都沒動**（靜態帳號 `uban` 必須排第一組，G39）。
> ⚠️ **1~2 秒接通是目標不是承諾**。真正的下限由 Tailscale Funnel（TCP-only 信令）
> 與日本 Oracle Coturn 的 RTT 決定，那是 §2 雙軌架構的固有成本，不是程式碼能消除的。
> 本輪只砍掉了「可以不等的等待」。若實測仍不理想，**照上表逐項還原即可，彼此獨立**。

**⑦ 新增鐵律（需求 11）**

三份 `CLAUDE.md`（根目錄 §3.1 #10、`Uban/` §3.1 #10、`uban-api/` Hard Rules #11）同步加入：
改動「連接／跳轉」語意（Socket 事件、REST 端點、FCM 欄位、畫面跳轉路由、模組間呼叫關係）時，
除了回寫 `.md`，還要同步更新 `Uban/graphify-out/` 與 `uban-api/graphify-out/`。
純樣式改動（顏色、字體、間距、文案）不觸發本條。

**驗證**

- `flutter analyze lib` — **0 error**（141 issues，與第二十一輪基線完全相同）
- `python -m pytest tests/test_call_signaling.py -q` — **17 passed**（基線 15，本輪新增 2 支：
  緊急通話帶有效期且差值 60000、已取消 callId 再送必須被擋）
- `DB_HOST=100.73.39.14 python -m pytest tests/test_institution.py -q` — **34 passed**
- `flutter build apk --debug` — 見本輪報告

**本輪的鐵律遵守情形**

「Opus 制定／檢驗、Sonnet 執行」**本輪未遵守**：所有 Sonnet 子代理在本次工作階段開始時
即因 `session limit` 全數失敗（與第十九、二十輪同一情況），改由 Opus 直接執行全部實作。
這是被迫偏離，已在交付報告中揭露。
「每輪回寫 `CLAUDE_call-monitor.md`」**已遵守**（本節）。
「收尾刪除空白殘留檔」**已遵守**。
新增的「同步 graphify」鐵律**本輪自己適用**：需求 8 動到 socket 生命週期、需求 10 動到 FCM 欄位
與 Socket 事件的擋下條件，屬「連接」語意變更，須執行 `/graphify . --update` 後複製到雙端。

---

### 2026-08-12 — 第二十三輪：緊急通話真正的「無條件」、APP 外拒接全滅、來電鈴聲引錯、雙端重撥對話框

使用者分兩次提出，共四項。本輪**全部是前端**，後端一行未動。

**① 緊急通話：自動接聽只做了一半（延續第二十二輪需求 9）**

使用者原話：「緊急通話不需要經過長輩同意，**無論長輩端在 APP 內或 APP 外還是任何情況**，
就由不得長輩端設備接受或拒絕接聽」。第二十二輪只改了 `elder_screen.dart` 的**進房之後**，
但「要不要進房」的決定發生在更前面，而**緊急通話有四條互不相干的抵達通路**：

| 通路 | 第二十二輪後 |
|------|-------------|
| Socket `emergency-call`（APP 存活） | 自動接聽 ✅ |
| FCM 背景 isolate（APP 被殺死） | 寫 prefs ＋ Intent 喚醒 ✅ |
| **FCM 前景備援**（Socket 掉線／慢） | **彈接聽／拒絕 dialog ❌** |
| **`_showIncomingCallDialog` 最終防線** | **彈接聽／拒絕 dialog ❌** |

後兩條就是「長輩端還看得到拒絕按鈕」的實際來源。修法是把三條 Dart 通路收斂到單一函式
`main.dart::_autoAcceptEmergencyCall`（:1892），背景 isolate 那條**維持原樣**
（plugin 實例不共用，那裡播的音停不掉）。FCM 前景分支刻意放在 `isResumed` 1.5 秒寬限期
**之前**——寬限期是為了「避免兩個來電 UI」，而緊急通話根本不彈窗，等它只是延後進房。→ **G81**

音效同時換掉：`assets/sounds/emergency_siren.wav`（7.00 s、44100 Hz 16-bit mono，
960/770 Hz 救護車雙音每 0.5 秒交替，程式生成；舊的 `emergency_alert.wav` 已刪除），
播放器搬進全域單例 `services/emergency_tone.dart`。
> **為什麼一定要搬單例**：現在是 `main.dart`（進房前）播、`ElderScreen`（進房後）停，
> 跨兩個 widget。放在 `_ElderScreenState` 欄位裡 `main.dart` 根本拿不到 → 停不掉。
> 停止點共四處：`onPeerConnected`、`ElderScreen.dispose`、FCM `cancel-call`、Socket `onCancelCall`。→ **G77 擴充**

順帶補上 `Signaling.lastEmergencyMeta`：`emergency-call` 的 payload 帶了 `role`/`issuedAt`/`expiresAt`，
但 `CallRequestCallback` 的簽章塞不下，改簽章又要牽動全部註冊點。改用「呼叫回呼前先寫欄位」傳遞。

**② APP 外「拒絕」按鈕 100% 無效，只有「接受」能用（需求 1）— 背景 isolate 早就死了**

`bgSub` listener 從第四輪就存在，看起來一直是對的。真正的問題是**它的壽命**：
`_showFullScreenCallkit` 一 return → FCM 背景 handler 的 Future 完成 →
Android `FlutterFirebaseMessagingBackgroundService` 的 `latch.await()` 放行 →
`JobIntentService` 收工 → 背景 `FlutterEngine` 連同 listener 一起銷毀。
而使用者是**幾秒後**才按下按鈕的。

> **「接受有效、拒絕無效」就是這個 bug 的指紋**：接受由 CallKit **原生層**直接拉起
> `MainActivity`，完全不需要 Dart；拒絕卻只有 Dart 一條路（送 `declineCall`、清三個 prefs 鍵）。
> 只要看到「兩顆按鈕一顆有效一顆無效」，第一個該懷疑的就是「無效的那顆是不是需要 Dart」。

修法：`Completer` 把 handler 的 Future 壓住，直到拒接／逾時／接聽／通話結束任一發生
或 50 秒上限。**保活必須放在整個函式最後**，在備援互斥探測（最多 3.5 秒 `await`）之後，
否則「CallKit 沒建立就補發備援通知」會晚 50 秒執行，等於廢掉第十三輪的互斥機制。
`actionCallEnded` 分支只放行、不送 `declineCall`（G14 單通路）。→ **G82**
> ⚠️ **刻意接受的取捨**：FCM 背景 handler 在 Android 是**序列**執行，保活期間後續 FCM
> （含發起方的 `cancel-call`）會排隊。最壞情況是取消後被叫端仍響到 CallKit 45 秒逾時，
> 仍在 G73「最多等 1 分鐘」的預算內。

**③ APP 外來電音效引用錯誤（需求 2）— 這句回報本身就是診斷結論**

使用者說「是系統**提醒**音效而非系統**來電**音效」。CallKit 宣告的是
`ringtonePath: 'system_ringtone_default'`，會發出提醒音的**只可能是備援通知**——
反推可知**那台裝置的 CallKit 原生層一直是失敗的**，看到的自始至終是第十三輪的互斥備援。
所以要修的是備援，不是 CallKit。

改動集中在 `local_call_notification.dart`：`content://settings/system/ringtone`
（＝`Settings.System.DEFAULT_RINGTONE_URI`）＋ `AudioAttributesUsage.notificationRingtone`
（channel 與通知**兩處都要**，音量才走鈴聲軌）＋ `FLAG_INSISTENT`（`4`，鈴聲重複到通知被取消）
＋ `timeoutAfter: 60000`。
> **關鍵陷阱**：Android 的 `NotificationChannel` **建立後 sound／importance 即不可變**，
> 就地改音會**靜默無效**。因此 channel id 必須換新（`uban_incoming_call_ringtone`）
> 並 `deleteNotificationChannel` 掉舊的 `uban_incoming_call_backup`，否則舊 channel
> 會留在系統設定裡變成孤兒。副作用：曾手動調整過舊 channel 設定的使用者會回到預設值。→ **G83**

**④ 雙端「無人接聽／連線逾時」對話框，並刪掉舊失敗畫面（需求 3）**

新增 `widgets/call_retry_dialog.dart`（`showCallRetryDialog`），兩端共用，
選項為「離開通話」／「重新撥打」。`video_call_screen.dart` 的
紅色 `Icons.wifi_off` ＋「連線逾時，請檢查網路連接或稍後再試」＋「重試連線」整段刪除，
`_callErrorMessage` 欄位一併移除（唯一讀取點就是那個畫面；原始例外訊息仍在 `debugPrint`）。

| 端 | 看門狗 | 逾時 | 重撥動作 |
|----|--------|------|---------|
| 家屬 `video_call_screen.dart` | `_armConnectTimeout`:298 → `_handleConnectTimeout`:313 | 一般 20s／緊急 60s | `_retryCall`:385 → `_sendCallInvite()` |
| 長輩 `elder_screen.dart` | `_armCallTimeout`:1256 → `_handleCallTimeout`:1268 | 30s | `_makeCall()` |

- **重撥只重送通話封包，不重跑 `_initCall()`**。舊的「重試連線」按鈕正是呼叫 `_initCall()`，
  會重跑媒體初始化，重複 `openUserMedia` 在真機上常造成鏡頭被佔用而黑畫面。
  `hangUp(disconnectSocket: false, disposeLocalStream: false)` 保住 `localStream`，
  所以重撥不必再開一次相機。→ **G84**
- **世代編號守衛**：`Future.delayed` 無法取消，重撥後舊那一輪仍會照時觸發。
  `_connectAttempt` / `_callAttempt` 單調遞增，回呼開頭比對不符就作廢。
  用 bool 旗標會有 ABA 問題（連撥兩次時第一輪回呼把旗標清掉）。→ **G85**
- CCTV 監控機（`widget.isCCTVMode`）**不彈**這個對話框——旁邊沒有人可以按（G56 精神）。
- 媒體初始化失敗不走這條（重撥變不出相機），維持既有的 `_showCallProblemThenGoHome`。
- 對話框 `barrierDismissible: false` ＋ `PopScope(canPop: false)`，回傳 `null` 視同離開。

**驗證**

- `flutter analyze lib` — **0 error**（141 issues，與第二十一／二十二輪基線完全相同）
  > 中途曾升到 142：`Int32List` 由 `package:flutter/foundation.dart` 轉出，
  > 多寫的 `import 'dart:typed_data'` 觸發 `unnecessary_import`。已移除。
- `flutter build apk --debug` — **BUILD SUCCESSFUL**（`build/app/outputs/flutter-apk/app-debug.apk`）
- `python -m pytest tests/test_call_signaling.py -q` — **17 passed**（後端未改動，確認不退步）

**本輪的鐵律遵守情形**

「Opus 制定／檢驗、Sonnet 執行」**本輪未遵守**：所有 Sonnet 子代理在本工作階段開始時
即因 `session limit` 全數失敗（與第十九、二十、二十二輪同一情況），改由 Opus 直接執行全部實作。
被迫偏離，已在交付報告中揭露。
「每輪回寫 `CLAUDE_call-monitor.md`」**已遵守**（本節）。
「收尾刪除空白殘留檔」**已遵守**。
「同步 graphify」**適用**：需求 1 動到緊急通話的通路收斂（跳轉語意）、需求 3 新增畫面間的
對話框與重撥路徑，屬「連接與跳轉」變更。

---

## 9. 驗證與除錯

### 9.1 靜態驗證（改完必跑）

```bash
# 前端
cd D:\114project\Uban\mobile_app
flutter analyze lib          # 須 0 error；改動的檔案須 0 issue
flutter build apk --debug    # 須 BUILD SUCCESSFUL

# 後端
cd D:\114project\uban-api
python -m py_compile services/socket_app.py main.py
python -m pytest tests/test_call_signaling.py -q   # 目前基準：17 passed，不可退步
```

> 既有 **135** 項 `withOpacity` 等 info/warning 是歷史遺留，**不算退步**，但你改動的檔案必須 0 issue。
> `flutter analyze` 只要有任何 issue 就 **exit code 1**，這**不代表失敗**——看的是 `error` 的數量。
> `flutter analyze lib` 冷跑要 300 秒以上；只想確認自己改的檔案時，直接把檔案路徑列在後面（約 45 秒）。

### 9.2 真機驗收矩陣

| # | 情境 | 預期 |
|---|------|------|
| 1 | 長輩端殺死 → 家屬撥打 → 按通知的**拒絕**鍵 | 家屬端**立即**收到拒絕提示並停止等待 |
| 2 | 家屬端**開著 APP 停在主畫面** → 長輩撥打 × 10 次 | **10/10** 都跳出來電 dialog，且**不可同時出現兩個** |
| 3 | 長輩端 `FriendsScreen` 按**電話**鍵 | 雙端進房鏡頭皆關、顯示「語音通話」；任一端按鏡頭鍵可開啟。再測**視訊**鍵，雙端鏡頭皆開 |
| 4 | 雙端各自殺死後互撥 | 兩端看到的來電畫面樣式一致（皆為 CallKit）；**同一支手機同時只出現一則通知** |
| 5 | 長輩端被殺死 → CallKit 接聽 | 進入 `ElderScreen` 視訊房，**不得**走「開場動畫 → 主畫面」 |
| 6 | 家屬端被殺死 → CallKit 接聽 | 進入 `VideoCallScreen` |
| 7 | 緊急通話（家屬端發起） | 不得瞬間無提示掛斷；長輩端自動接聽、鏡頭強制開啟 |
| 8 | 長輩端登出 → 快速登入同一長輩 | 成功，且裝置角色維持原本的通訊機／監控機 |
| 9 | 通話中一端掛斷 | 另一端顯示 dialog 提示 2 秒後才回首頁（不可瞬間跳走） |
| 10 | **雙端接不同網域**（一端 Wi-Fi、一端行動網路）互撥 | 進房後**看得到對方影像、聽得到聲音**。若失敗，必須在 12 秒內跳出「無法建立影音連線」並安全返回主畫面，**不可**停在有計時卻沒畫面的假連線 |
| 11 | 長輩監控機上線／下線 | 家屬端列表**最遲 2.5 秒**出現／移除監視器名稱；點「觀看 CCTV」可進入，按「← 返回」回到原本的分頁（**不是**重建主畫面） |
| 12 | `.env` 開 `CCTV_TEST_FALL_ENABLED=true` → 按「🚨 跌倒測試」**連按兩次** | 家屬端（含**熄屏**狀態）**兩次都**亮螢幕 + 通知 + 朗讀 + 彈窗。改回 `false` 後再按 → SnackBar 顯示 8 秒長文案（說明是後端設定未開、非 App 故障），而非靜默無反應 |

#### 2026-08-11 第二十二輪新增（13–19）

| # | 情境 | 預期 |
|---|------|------|
| 13 | 家屬端進出監控 **6 次**，每次都停留 30 秒以上 | 監控機畫面**每一次**都持續更新，**不再有「奇數次停住、偶數次恢復」**。監控機 log 不應出現連續的 `影格推送失敗`；若出現，看門狗須在 30 秒內印出 `🚑 重建擷取管線` 並自行復原 |
| 14 | 監控機「退出監視機」→ 回長輩端 → 家屬端撥打**一般通話** | **APP 內**按「接聽」須**立即**跳轉並雙端連通；**APP 外**點來電通知同樣可進房並連通。連做 5 次不得出現 ANR（「Uban 沒有回應」）。監控機 log 須看到 `🧨 拆除舊 socket` |
| 15 | 家屬撥打 → **不接**，等待 **超過 60 秒** | 發起端自行關閉本次連線；此後**不論**長輩端何時恢復網路，**都不得**再彈出這通的來電畫面（Socket 與 FCM 皆已被伺服器端擋下）。後端 log 須有 `🚫 已被取消／逾時，拒絕重送` |
| 16 | 家屬撥打**緊急通話**，長輩端 (a) APP 內 (b) APP 外 (c) 被殺死 (d) 螢幕關閉 | 四種狀態**都**無條件進入緊急視訊房；播放約 7 秒提示音（**不是** TTS 語音），接通瞬間停止。CCTV 監控檢視仍須**完全無聲**（G56） |
| 17 | 家屬端產生配對碼 → 監視機輸入完成 | 家屬端配對碼彈窗**自動關閉**（最遲約 2 秒），toast 顯示「監控設備「X」已完成綁定」，清單即時出現該裝置。中途把家屬端網路關掉再開，彈窗**不可**誤關 |
| 18 | 監控機運行中，家屬端於卡片選單刪除它 | 監控機畫面顯示「**該監控機已被刪除**」（不是「連線中斷」）。另測：拔掉監控機網路（裝置未被刪除）→ 須顯示「**連線中斷**」 |
| 19 | 家屬端「互動」分頁的監控卡片 | 底色為暗色系（`0xFF1E293B`）、與其他分頁一致；ICON 與按鈕主色**依會員層級**變色（一般綠／黃金金黃／鑽石亮藍），層級徽章與監控 ICON **同一種顏色**。CCTV 檢視畫面**不得**出現計時與「緊急通話」字樣 |

### 9.3 三層數據定位法（「收不到來電」的標準診斷）

| 層 | 檢查方式 | 判讀 |
|----|---------|------|
| **A. 後端有沒有發** | Fedora 上看 uvicorn stdout / journalctl，撥打當下找 `📡 [Routing] 目標查詢結果`、`[Call Request] FCM 推播已發送` | 沒有「已發送」行 → 後端 routing 問題。看是否印出 `🚨 目標完全無法觸達` 或 `⚠️ 僅有在線 Socket、無 FCM token` |
| **B. 裝置有沒有收** | 目標機接 USB：`adb logcat -s FLTFireMsgReceiver FirebaseMessaging flutter`，殺掉 APP 再撥打 | 無任何輸出 → FCM 沒進裝置（MIUI 層級殺進程／force-stop） |
| **C. 收到但沒響** | 同上 logcat 找 `Background message received` | 有此行但無 CallKit → Flutter 端處理問題。找 `🔧 [BG] 本機為通訊機，將 monitor-wakeup 正規化為 call-request` 確認 §6.4 是否觸發 |

### 9.4 診斷心法

**不對稱失效 = 結構性差異，不是系統殺進程。**
「長輩收不到、家屬收得到」「同型號同權限」這種線索一定指向 elder/family 的程式碼路徑差異
（`deviceMode` / token 查詢鍵 / FCM `type`），不要浪費時間在 MIUI 電池設定上。
反之，**對稱失效**（雙端都收不到）才考慮裝置級限制。

**「有時好有時壞」= 競態或型別不一致。**
90/10 這種比例通常是兩條通路搶同一個狀態（§4.1）；
「Socket 正常、FCM 失效」則多半是型別問題（§3.6 的 `str(bool)` 大寫陷阱）。

**射後不理的 API 沒有錯誤可看。**
`showCallkitIncoming` Dart 端永遠成功。要判斷 CallKit 是否真的建立，只能事後探測 `activeCalls()`。

### 9.5 POCO / MIUI 裝置設定檢查清單

「權限全開」通常**不含**這幾項，要逐項確認：

- 設定 → 應用程式 → Uban → **自啟動（Autostart）**
- 電池 → **無限制**
- 其他權限 → **顯示彈出式視窗**、**後台彈出介面**、**鎖屏顯示**
- Android 14+ → **全螢幕通知權限**（APP 內 `elder_home_screen::_requestPermissions` 會引導）

> 小米／OPPO／華為把「從最近工作列滑掉 = force-stop」，
> force-stop 的 APP 依 Android 規範**收不到任何 FCM**——這是程式無法解決的，只能引導使用者設定。

### 9.6 Windows 建置故障排除

錯誤：`flutter_inappwebview_android:compileDebugJavaWithJavac` 無法刪除
`build/.../javac/.../classes`（檔案鎖定）。

已驗證可恢復的流程：
1. 終止鎖定行程（`java.exe` / `gradle.exe` / `flutter` / `dart`）
2. 刪除 `Uban/mobile_app/build/`
3. `flutter clean` → `flutter pub get` → `flutter build apk --debug`

---

## 10. 修改 SOP

### 10.1 動手前

1. 讀 §7 護欄，確認你要改的東西不在裡面
2. 讀 §2 檔案地圖，確認風險等級
3. 🔴 極高風險檔案：先用 `grep -n` 定位，**不要整檔重寫**
4. 確認你的改動是否跨端（見 §10.2）

### 10.2 跨端契約檢查表

改動涉及下列任一項時，**四條通路都要同步改**（Socket / FCM / prefs / CallKit `extra`）：

- [ ] 有效期（`issuedAt` / `expiresAt` / `kCallValidityMs` / FCM `ttl`）
- [ ] `isVideoCall`（記得用 `parseIsVideoCall` 正規化，§3.6）
- [ ] `senderRole`（三個消費端都驗證，G16）
- [ ] `callId`（去重 token、`_invalidCallIds`、`isSameOngoingCall`）
- [ ] FCM `type`（`monitor-wakeup` 正規化，§6.4）
- [ ] 房間 ID 格式（雙重 prefix 防呆，§3.5）

### 10.3 改完後

```
1. flutter analyze lib                              → 0 error
2. python -m pytest tests/test_call_signaling.py -q → 17 passed（不退步）
3. flutter build apk --debug                        → BUILD SUCCESSFUL
4. 跑 §9.2 真機驗收矩陣中與你改動相關的項目
5. 在 §8 補一筆修復記錄（日期 / 症狀 / 根因 / 修復 / 驗證）
6. 若新增了不可回退的設計 → 在 §7 補一條護欄
7. 若發現本文件與程式碼不符 → 修本文件並在 §7.3 記一筆
8. **把本檔複製到另一個 repo 的鏡像**（見檔首警告），確認兩份內容完全相同
   ⚠️ 用 `diff <(tr -d '\r' < A) <(tr -d '\r' < B)`，**不要用 `diff -q`**——
   `Uban/` 是 CRLF、`uban-api/` 是 LF，`diff -q` 永遠報不同，會讓人以為同步失敗。
9. **若改到「連接／跳轉」語意 → 同步更新雙端 graphify**（2026-08-11 新增鐵律）
   Socket 事件、REST 端點、FCM 欄位、畫面跳轉路由、模組間呼叫關係都算。
   於專案根目錄跑 `/graphify . --update`，再把 `graphify-out/` 複製到
   `Uban/graphify-out/` 與 `uban-api/graphify-out/` 覆蓋。
   純樣式改動（顏色、字體、間距、文案）不觸發本條。
```

> 📌 **使用者常規要求**：「每次更新程式後都記錄在 `CLAUDE_call-monitor.md`，
> 若有重複則簡要合併並由**新覆蓋舊**」。第 5-8 步不是可選的。

### 10.4 新增／修改「監控或警報」端點時的安全檢查表

> 第十七輪稽核的結論：**每個動作都有 REST 與 Socket 兩個入口，只補一邊等於沒補。**

- [ ] 這個端點會不會**寫入**或**觸發推播**？→ 必須做 `is_user_linked_to_elder()` 關係驗證
- [ ] 會不會指定「對哪一台裝置」？→ 必須做 `is_device_of_elder()` 歸屬驗證
- [ ] 同一動作的 **Socket handler** 也補了嗎？（`routers/alert.py` ↔ `services/socket_app.py`）
- [ ] 無權的回應是 **404** 而不是 403 嗎？（G45）
- [ ] 回應 payload 有沒有洩漏未驗證者不該看到的欄位？
- [ ] 是**測試／除錯**用的端點嗎？→ 必須有預設關閉的環境開關（G43）
- [ ] 是**裝置**（非使用者）呼叫的端點嗎？→ 支援 `X-Uban-Device-Token`，且**留空時維持現行行為**
- [ ] 新增的環境變數寫進 `.env.example` 了嗎？（含「為什麼」與「不設定的風險」）

### 10.5 git 規範

- **commit message 一律繁體中文**
- 只在使用者明確要求時 commit / push
- 實際可用的 git repo 有**兩個**：`D:\114project\Uban\.git` 與 `D:\114project\uban-api\.git`
  → 跨端改動要分別 commit
  > ⚠️ `D:\114project\.git` 是**空目錄、無法運作**，不要對它下 git 指令。
  > 這也是本檔必須在兩個 repo 各留一份鏡像的原因。
- 🚫 這兩個 repo **永遠不要跑 `git clean`**

### 10.6 給後續 AI 的最後提醒

這個子系統的每一層兜底、每一個看似冗餘的判斷，
都對應一次真機回報的故障和一輪追查。**它看起來複雜，是因為它真的很複雜。**

如果你覺得某段程式碼「可以簡化」——請先在 §8 找找它是哪一輪加上去的，
以及當時解決的是什麼症狀。找不到才考慮動它，找到了就別動。
