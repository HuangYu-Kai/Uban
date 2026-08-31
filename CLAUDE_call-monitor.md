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
| `elder-devices-update` | S→C | 裝置陣列，每筆裝置含 `id`、`deviceName`、`deviceMode`、`isOnline`、`appState`、`deviceId`、**`elderId`（字串，第二十五輪新增）** | `_broadcast_elder_devices_update`:922（emit :940）／`on_get_elder_devices` 直回 :999 | join(:1333)、delete-device(:1464)、force-logout(:1548)、**disconnect(:1628)**、改名(:2467) 都會廣播。~~只在 join 時廣播~~ 是舊文件的錯誤記載，見 §6.6。家屬端用 `elderId` 丟棄非當前長輩的裝置（`family_main_screen.dart::_applyDeviceList`），見護欄 **G91** |
| `monitor-renamed` | S→該監視機 | `{elderId, oldDeviceName, newDeviceName, deviceId}` | `routers/pairing.py`:398 | 家屬端改名後推送；監視機收到後更新畫面標籤與 `saved_device_name`。與 `elder-devices-update` 同時發出。見護欄 **G57** |
| `monitor-removed` | S→該監視機 | `{elderId, deviceName, deviceId}` | `routers/pairing.py`:359 | **第二十輪新增**（需求 4）。家屬端刪除監視器後推送；監視機收到即 `SessionManager.releaseSession()` → 導回身分選擇畫面。🚫 **必須在 `sio.disconnect(kick_sid)` 之前 emit**，見護欄 **G65**。前端 `signaling.dart::onMonitorRemoved`:96（listener :501），註冊點只有 `elder_screen.dart`:697（`isCCTVMode` 分支內） |
| `delete-device` | C→S | `room`、`targetId` | `on_delete_device`:2025 | 家屬端移除長輩裝置；會對被踢裝置發 `force-logout` |
| `force-logout` | S→C | `{reason}`（`reason` 選填，2026-08-31 第三十七輪新增） | emit :2053（另有 FCM :2064）；另一送出點見 `on_delete_device`（§7.2 G137） | 遠端強制解綁，`reason` 語意見下方說明 |
| `user-joined` / `user-left` / `user-state-changed` | S→C | `id`、`role` 等 | :1139/:1275/:1241 | 房內成員變動 |
| `cctv-alert-ack` | C→S | `alert_id`、`user_id` | `on_cctv_alert_ack`:2083 | 回應 YOLO 告警；回 `cctv-alert-ack-success/failed` |
| `audio-bridge-request` | C→S | — | `on_audio_bridge_request`:2109 | 回 `audio-bridge-response` |
| `leave` | C→S | `room` | `socket_app.py::on_leave` | **2026-08-18 第二十六輪新增**。定向離開單一房間；冪等（不在房間內即安全 no-op）；**不斷 socket**。見護欄 **G92** |
| `elder-zone-update` | S→C | `elder_id`、`device_id`、`from_zone`、`to_zone`、`entered_at`、`previous_dwell_seconds`、`timestamp` | `socket_app.py::_broadcast_elder_zone_update` | **2026-08-18 第二十六輪新增**，第二十七輪轉正式（見 §6.12）。`IPS_ENABLED` 現為 kill-switch，預設開啟。見護欄 **G95**／**G97** |

> **`force-logout` 的 `reason` 欄位（2026-08-31 第三十七輪新增）** — 選填字串，兩個送出點各自帶
> 固定值：`'elder-unbound'`（家屬端解除長輩綁定，來自 `routers/pairing.py`:1361/1369）與
> `'device-removed'`（監控機／裝置被刪除，來自 `services/socket_app.py::on_delete_device`:2734/2746）。
> Socket 與 FCM 兩條路都帶。前端 `signaling.dart::onForceLogout` 簽章為
> `void Function({String? reason})`，`main.dart::handleForceLogout` **只有
> `reason == 'elder-unbound'` 才清除 `last_elder_*` 四個快速登入鍵**（§3.3、護欄
> G24／G125）；**缺漏、`null`、或未知值一律視為「保留」**——這是刻意的安全方向，見護欄
> **G137**。新增任何 force-logout 送出點時，兩條路（Socket 與 FCM）都必須帶上 `reason`，
> 否則前端會退回保守的保留行為，但語意會失真。

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

`type='force-logout'`、`roomId`、**`reason`**（2026-08-31 第三十七輪新增，值與語意見 §3.1
上方「`force-logout` 的 `reason` 欄位」說明）；`priority='high'`。

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
| `GET` | `/monitor_devices?elder_id=&user_id=` | :138 | 回傳與 `elder-devices-update` **完全相同形狀**的清單（直接呼叫 `_get_elder_devices_list`，故每筆裝置同樣帶 **`elderId`**，第二十五輪新增，見 §3.1）。家屬端 `_refreshMonitorDevicesViaHttp()` 每 10 秒打一次，見 §6.6 |
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

> 本節已移出至 `CLAUDE_call-monitor-ui-map.md`（兩份鏡像同步）。只改 UI 樣式／按鈕／跳轉時讀那一份即可；動到信令、通話生命週期或護欄仍必須讀本檔。

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

### 6.12 室內定位（IPS）（2026-08-18 第二十六輪新增、第二十七輪轉正式、2026-08-25 第三十二輪移除家屬端校準介面）

> 重用**既有** CCTV/YOLO 管線（監視機每 2 秒推一幀 → `yolo_detector_service` 做人物偵測），
> 零新推論、零新硬體。核心邏輯在 `services/indoor_position.py`（模組 docstring 內含完整能力
> 邊界），路由在 `routers/ips.py`。
> `IPS_ENABLED` **2026-08-18 第二十七輪起預設開啟**，語意也從「要不要試用」改成「緊急關閉
> 用的 kill-switch」，詳見下方「開關」。
>
> ⚠️ **2026-08-25 第三十二輪：家屬端校準介面已整個移除**（原因與細節見下方「家屬端操作
> 流程」）。**presence 偵測不受影響、繼續運作**；zone 分類則需 `elder_zone_config` 已有
> 多邊形資料才會啟用，見 **G97**。

**運作原理**

```
routers/alert.py::push_cctv_frame（既有 CCTV 推幀端點，見 §6.9）
  └─ YOLO 推論已完成（跌倒/爬行判定）
       ↓（`indoor_position.ips_enabled()` 為 true 時，獨立 try/except 掛鉤，見 :368-373，
       ↓  不影響前面任何步驟的回應）
  1. indoor_position.store_last_frame()（:370）— 快取本次原始影格，供快照端點讀取（見下方
     REST 端點；2026-08-25 起校準 UI 已移除，但端點與快取本身未刪）
  2. indoor_position.process_frame_for_zone()（:371）— **2026-08-25 第三十二輪起分兩層**：
       ├─ 【第一層，無條件】取用同一幀 yolo_detector 內部最新一筆 PersonTrack 的 bbox（不重跑
       │    推論）→ 沒偵測到人（bbox 為 `None`）就直接返回；偵測到人就呼叫 `ZoneTracker.touch()`
       │    更新 presence（純記憶體，不需幾何運算）
       ├─ 尚未校準（load_zones 回傳空陣列）→ **只跳過下面的幾何與分類**（見護欄 **G97**），
       │    `transition` 維持 `None`
       ├─ 【第二層，需已校準】foot_point()：取 bbox 底邊中點，正規化到 [0,1]（腳點比質心更
       │    貼近實際地板位置）
       ├─ classify_zone()：point-in-polygon 逐一比對已校準的區域多邊形，first-match-wins
       ├─ ZoneTracker.update()：連續 ZONE_STABLE_FRAMES=3 次（≈6 秒，2 秒/幀）同一分類才接受，
       │    壓下站在邊界時的來回抖動；未達門檻、或與目前 zone 相同 → 回傳 `transition=None`
       ├─ 穩定切換（`transition` 非 `None`）才：寫入 `elder_zone_event`——**這是唯一仍保留
       │    「只在切換時才做」語意的步驟**
       └─ 【無論是否校準、是否切換，只要這幀偵測到人】`zone_tracker.snapshot()` 組 payload →
            以 `elder-zone-update` 廣播給家屬——**廣播本身與「是否切換」已脫鉤**，見下方
            「Socket 事件」
```

> ⚠️ **順序陷阱（G96，2026-08-18 第二十七輪）**：`store_last_frame` 必須排在
> `process_frame_for_zone` **之前**呼叫（`routers/alert.py:370` 在 `:371` 之前）。後者在
> 「尚未校準」時會提前返回；若快照寫入排在它後面，未校準的監視機就永遠執行不到快照這一步
> → 家屬端校準 UI 永遠看不到畫面 → 永遠無法完成校準，形成死結。

**兩張新表**（`scripts/migrations/011_ips_zones.sql`；`database.py` 已補 SQLite 對應分支，
兩邊 schema 須保持一致）

| 表 | 用途 | 關鍵欄位 |
|----|------|---------|
| `elder_zone_config` | 每個 elder+device 一份，家屬校準後的區域多邊形 | `elder_id`、`device_id`、`zones`（TEXT，JSON）、`UNIQUE(elder_id, device_id)` |
| `elder_zone_event` | 每次穩定判定的區域改變寫一筆 | `elder_id`、`device_id`、`from_zone`、`to_zone`、`dwell_seconds`（FLOAT）、`occurred_at` |

**最近一幀快取（記憶體內，非資料表，2026-08-18 第二十七輪新增）**：`store_last_frame` /
`get_last_frame`（`services/indoor_position.py`）用 `OrderedDict` 做簡單 LRU，鍵為
`elder_id:device_id`（同一監視機只占一筆，新影格覆蓋舊的），上限
`_LAST_FRAME_CACHE_MAX_ENTRIES = 500`——快取的是原始影格 bytes，比 zone 設定的 JSON 快取
重得多，故設上限，超過時淘汰最久未更新的一筆。不落地、服務重啟即清空。

**REST 端點**（`routers/ips.py`，全部經 `call_security.is_user_linked_to_elder()` 驗證，
無權一律回 **404 不是 403**——與 `routers/alert.py::get_alerts` 用同一慣例）

| 方法 | 路徑 | 說明 |
|------|------|------|
| GET | `/api/ips/current/{elder_id}?user_id=&device_id=` | 目前所在 zone、已停留秒數、最後更新時間、**`calibrated` 布林**（2026-08-18 第二十七輪新增，由 `load_zones()` 是否非空推導）；尚無資料回 `zone='unknown'`（非 404，這是合法的「尚無資料」狀態）。`zone='unknown'` 有兩種成因——`calibrated=false`（從未校準）或 `calibrated=true`（已校準但目前不在任何區域內），前端需分開顯示 |
| GET | `/api/ips/zones/{elder_id}?user_id=&device_id=` | 讀取該監視機已校準的區域多邊形；未校準過回空陣列 |
| PUT | `/api/ips/zones/{elder_id}?user_id=&device_id=` | 覆寫區域多邊形設定（家屬端「校準」流程的落地點）；全量覆寫、非局部合併 |
| GET | `/api/ips/snapshot/{elder_id}?user_id=&device_id=` | **2026-08-18 第二十七輪新增**。回傳該監視機最近一次推送的原始影格 bytes（供校準 UI 疊圖）；無快取幀回 **404**（`尚未收到該監視機的影格`）；Content-Type 依檔頭魔數判定（PNG/JPEG，判斷不出來預設 JPEG） |

> ⚠️ **2026-08-25 起，`PUT /api/ips/zones/{elder_id}` 在 App 內已無任何呼叫端**——校準畫面
> 移除後端點仍在、形同孤兒，日後復活功能只需接畫面回來，不必動後端。既有已校準裝置不受
> 影響，`load_zones()` 讀到的仍是移除前最後一次儲存的多邊形。

> 這四個端點的**呼叫本身**皆不受 `IPS_ENABLED` 限制——永遠會成功處理（校準資料讀寫、或
> 回傳目前快取狀態），不會因開關而回錯誤碼。但 snapshot 端點能否讀到**新**影格會被間接
> 影響：`store_last_frame` 與 `process_frame_for_zone` 一起包在 `push_cctv_frame` 的
> `if indoor_position.ips_enabled():` 判斷式內（見上方「順序陷阱」），kill-switch 關閉時
> 兩者都不會執行——snapshot 只是讀不到新資料，已快取的舊影格仍讀得到，直到被 LRU 淘汰或
> 服務重啟。

**家屬端操作流程** — **2026-08-25 第三十二輪：整個「設定區域」校準流程已移除**

`zone_calibration_screen.dart` 已刪除，兩個進入點（`family_interaction_tab.dart` 選單、
`family_home_tab.dart` 的「前往設定區域」卡片）一併移除。原因：儲存與取消操作都會拋出
`'_dependents.isEmpty': is not true` 例外，且實測下來使用者不需要房間級粒度的定位。座標
映射護欄 **G98** 隨畫面走入歷史，僅保留原文供日後參考。
🚫 **不代表 IPS 整個下線**：presence 偵測繼續運作，見上方「運作原理」與 **G97**；只是
「在哪個房間」目前沒有 App 內建的設定方式。✅ 2026-08-25 前已校準的監視機不受影響——
`elder_zone_config` 未被清除，`load_zones()` 依然讀得到，zone 分類與廣播照常運作；只有
「從未校準」與「日後新增」的監視機永久停在 `calibrated=false`，除非直接呼叫
`PUT /api/ips/zones/{elder_id}`（見上方 REST 端點）。首頁卡片依 `calibrated` 呈現的四種
狀態**維持不變**，只是「尚未校準」不再附「前往設定區域」的引導動作。

**Socket 事件**：`elder-zone-update`（S→C），完整欄位契約見 §3.1。⚠️ `timestamp` 欄位
（`_build_zone_payload`:522）曾有 naive datetime 轉 epoch 的時區 bug（UTC+8 環境下倒退
8 小時），2026-08-18 第二十七輪已修正，見護欄 **G99**；payload **不帶** `calibrated`，
消費端應視收到推播為已校準（見上方「家屬端操作流程」與 `family_main_screen.dart`）。
⚠️ **2026-08-25 起廣播頻率不再綁定「穩定切換」，且不分是否校準**：只要偵測到人就會廣播，
約每 2 秒一次；`transition` 欄位大多數時候是 `None`，只有真的發生穩定切換才非空。🚫 **不要**
假設收到 `elder-zone-update` 就代表剛發生區域切換——要看 `transition` 是否有值，不能只看
「有沒有收到事件」。唯一仍保留「只在切換時才做」語意的是 **DB 寫入**；未校準裝置的
`transition` 永遠是 `None`，因此永遠不寫 DB，但仍持續收到廣播。

**開關**：`IPS_ENABLED`（`uban-api/.env`），**2026-08-18 第二十七輪轉正式後預設開啟**——
環境變數語意也跟著改變：不再是「要不要試用」的旗標，而是**緊急關閉用的 kill-switch**。設
`IPS_ENABLED=false` 仍會讓 `push_cctv_frame` 呼叫 `ips_enabled()` 時只做單一布林檢查就
返回，回到零 DB 存取、零幾何運算、零 Socket 廣播、對既有 CCTV／跌倒偵測路徑零影響、零延遲
的狀態（見護欄 **G95**）。

預設開啟之後真正扛住風險的是另一道獨立防線：`process_frame_for_zone` 對**未校準**監視機
只跳過幾何運算與 DB 寫入（presence 追蹤與 Socket 廣播仍會執行，2026-08-25 起拆成兩層，見
上方「運作原理」與護欄 **G97**）。推幀節奏是每 2 秒一次，多數監視機在完成校準之前都會長期
處於未校準狀態，這道守衛正是「預設打開仍然安全」的前提。

**四項限制（誠實記錄，轉正式後依然成立，避免疊加過度樂觀的功能）**

1. **覆蓋範圍僅限鏡頭視野**：人一走出畫面，最後已知區域就凍結不動——`process_frame_for_zone`
   對「這幀沒偵測到人」的處理是直接跳過，不會把 zone 改判成 `unknown`。
2. **一台相機＝一個房間視角**：不是多相機融合，也不是三角定位。要做到「全屋」定位，需要在
   每個房間各放一台監視機、各自校準各自的區域多邊形。
3. **需要人工校準**：區域多邊形不是自動產生的，必須有人呼叫 `PUT /api/ips/zones/{elder_id}`
   為每台監視機畫出各房間範圍；畫面座標系會因鏡頭角度、安裝位置而完全不同，換鏡頭或搬動
   鏡頭就要重新校準。**2026-08-25 起 App 內已無呼叫此端點的介面**（見「家屬端操作流程」），
   此限制現已等同「新裝置永遠無法校準」。
4. **精度繼承 YOLO 本身的限制**（遮擋、低光、多人重疊），另外貼近鏡頭或大角度俯視時，
   「腳點」映射到地板的透視誤差會變大。

**方案選擇理由**：之所以選相機（重用既有 YOLO bbox）而非其他室內定位技術——
WiFi RSSI 指紋受 Android 9+ 掃描節流（2 分鐘 4 次）且多數住家訊號源不足以做出可用精度；
BLE beacon 需要每戶額外硬體（列為未來升級路徑）；UWB 成本與 Android 裝置支援度都不划算；
IMU 航位推算漂移嚴重，且長輩常不隨身攜帶手機。相機方案零新推論、零新硬體、重用既有管線，
是當初評估時成本最低的路徑，轉正式後這個判斷依然成立。

---

## 7. 護欄（合併後的唯一權威清單）

> 📌 **搬移門檻提示**：本文件中出現的「第 N 輪」，**N ≤ 35** 者其年表條目已遷至
> `CLAUDE_call-monitor-history.md`；**N ≥ 36** 仍在本檔 §8。此門檻會隨每輪搬移而持續調高，
> 調整時只需要更新這兩處（本節與 §8 開頭）的數字。

> 目前共 **137 條**（G1–G137）：G1–G36 合併自 `CLAUDE.md`（13 條）與 `Uban/CLAUDE.md`（26 條）並去重、
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
> **G86–G91 為 2026-08-17 第二十五輪新增**（前端 5 條：SDP Offer 去重與 `call-request` 去重分離、
> 來電接聽路徑改用回呼帶入的 `roomId` 並套用冪等正規化、`request.send()` 必須消費回應串流、
> `SessionManager.releaseSession()` 呼叫需要逾時、`VideoCallScreen._initCall()` 需在提早 return 前
> 解析完使用者角色；後端 1 條：`elder-devices-update` 需帶 `elderId` 且 `on_disconnect` 須清除
> 該 sid 在所有房間的登記）。
> **G92–G95 為 2026-08-18 第二十六輪新增**（全部後端：Socket 房間定向離開語意（`on_leave`，
> 只離開指名房間、不斷 socket、不得做成「進新房間退所有舊房間」）、警報冷卻期只抑制推播不抑制
> 記錄、後端改動的驗證必須含 import 冒煙測試（`py_compile` 只驗語法抓不到 `NameError`）、
> IPS 掛鉤關閉時必須是零開銷的單一布林檢查、不得影響既有 CCTV/跌倒偵測路徑（**預設值已於
> 第二十七輪由關閉改為開啟**，見 G97）。
> **G96–G99 為 2026-08-18 第二十七輪新增**（IPS 由試做轉正式。後端 3 條：`/cctv/frame` 的
> IPS 掛鉤裡 `store_last_frame` 必須排在 `process_frame_for_zone` 之前、預設開啟後「未校準
> 即刻返回」的守衛不得移除、naive `datetime.utcnow()` 不可直接 `.timestamp()`（會在
> UTC+8 讓 epoch 倒退 8 小時，`elder-zone-update` 的 `timestamp` 欄位曾中招）；前端 1 條：
> 區域校準座標映射須用 `applyBoxFit(BoxFit.contain)` 配 `Image(fit: BoxFit.contain)`，
> 嚴禁 `BoxFit.cover`）。
> **G100 為 2026-08-18 拆檔稽核新增**（前端 1 條：全域音訊焦點必須維持 `none` 模式，
> 以利長輩端語音喚醒與媒體播放共存；本條原本只存在於 `Uban/CLAUDE.md` §6 第 27 條
> （2026-08-04 第十四輪），拆檔逐條核對 §7 時發現權威文件從未收錄，補列）。
> **G101 為 2026-08-18 第二十八輪新增**（前端 1 條：每一條「加入房間」的路徑都必須有對稱的
> 「離開房間」路徑，`joinRoom()` ↔ `leaveRoom()` ＋ `cancelPendingRoom()`）。
> **G102–G106 為 2026-08-19 第二十九輪新增**（全部前端：`Signaling` 單例回呼欄位須用
> `identical()` 守衛歸還、`onConnect` rejoin 須用當下 instance 欄位並逐一 fallback、緊急
> 通話路徑須主動 bring-to-front 喚醒螢幕、配對完成判定須查後端 `used_at` 而非猜測裝置清單、
> `sendCallAccept` 冷啟動情境須放寬等待窗並回傳成功與否）。
> **G107–G110 為 2026-08-20 第三十輪新增**（全部前端：跌倒警報 channel 改用
> `audioAttributesUsage: alarm` + `emergency_siren` 原生音效取代單純 `playSound: true`、
> Android notification channel 建立後不可修改故換聲音／`bypassDnd` 必須換 channel id、
> `setBypassDnd` 僅在建立當下已持有勿擾權限才生效故須雙 channel id 依授權狀態動態重選、
> FCM 背景 headless engine 拿不到 MethodChannel 故背景路徑所需的原生資訊須以
> `SharedPreferences` 橋接）。
> **G111–G118 為 2026-08-23 第三十一輪新增**（前端 G111–G115、後端 G116–G118，條文見
> §7.1／§7.2；本段落先前漏列，2026-08-25 補上）。
> **G119–G122 為 2026-08-25 第三十二輪新增**（前端 G119–G120、G122；後端 G121；內容見本輪
> 年表「新增護欄」小節與 §7.1／§7.2 條文）。
> **G123–G127 為 2026-08-25／2026-08-26 第三十三／三十四輪新增**（前端 G123–G125；後端
> G126–G127；內容見對應年表「新增護欄」小節與 §7.1／§7.2 條文）。
> **G128–G130 為 2026-08-26 第三十五輪新增**（後端 G128–G129；跨端 G130；內容見本輪
> 年表「新增護欄」小節與 §7.2 條文）。
> **G131–G134 為 2026-08-26 第三十六輪新增**（前端 G131、G134；跨端 G132；後端 G133；內容見
> 本輪年表「新增護欄」小節與 §7.1／§7.2 條文）。
> **G135–G137 為 2026-08-31 第三十七輪新增**（後端 G135；前端 G136；跨端 G137；內容見
> 本輪年表「新增護欄」小節與 §7.1／§7.2 條文）。
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
還是自己誤觸；第八輪的拒接回饋（已遷至 `CLAUDE_call-monitor-history.md`）與第十七輪的媒體看門狗失敗回報都依賴它。
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
> **根因**：`bgSub` listener 從第四輪（已遷至 `CLAUDE_call-monitor-history.md`）就存在，但它的壽命等於背景 `FlutterEngine` 的壽命。
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
> 🚫 **不要**改用「一個 bool 旗標」代替：連續重撥兩次時第一次重撥的回呼會把旗標清掉，
> 第二次重撥的看門狗跟著失效。編號單調遞增才不會有 ABA 問題。

**G86 — SDP Offer 的去重狀態必須與 `call-request` 分離**
`signaling.dart:130-131` 的 `_lastProcessedOfferCallId` / `_lastProcessedOfferTime` 專供
`socket.on('offer')` 去重使用，**不得**與 incoming-call 用的 `lastProcessedCallId` 共用。
> **原因**：第二十五輪查出，兩者共用同一去重狀態時，長輩接聽後 2 秒內抵達的 SDP Offer
> 會被誤判為重複的 `call-request` 封包而遭靜默丟棄，WebRTC 永遠無法完成握手。

**G87 — 來電接聽路徑必須使用「來電事件帶進來的 `roomId`」並套用 `comm_elder_` 冪等正規化**
`elder_home_screen.dart` 的接聽處理**禁止**改用 `widget.roomId ?? widget.userId.toString()`。
> **原因**：`widget.roomId` 為 null 時會拿 **user id** 去拼房間名稱，與長輩端 `initState`
> （:106-111）的正規化結果對不上，導致雙端加入不同房間——來電通知照樣跳出，
> 但 WebRTC 永遠連不起來（第二十五輪需求 1）。必須採用回呼帶入的 `roomId`，
> 並套用與 `initState` 相同的正規化邏輯。

**G88 — 任何 `request.send()` 都必須消費回應串流**
一律接 `http.Response.fromStream(request.send())`，比照既有的 :514、:756、:777。
> **原因**：`package:http` 的底層 client 只有在回應串流被消費後才會 `close()`。
> `api_service.dart::pushCctvFrame`（第二十五輪查出，:1110-1111）曾是全專案唯一的例外，
> 監控機每 2 秒推一幀就洩漏一條連線，累積到行程 socket 耗盡後**所有** HTTP 請求都失敗
> （包括完全不相關的登入），只有殺掉 APP 重開才會恢復。

**G89 — `SessionManager.releaseSession()` 的對外呼叫一律要有 `.timeout()`**
清除本機狀態（斷開 Signaling、清 prefs、`appRole=null`）的步驟**不得**被「通知後端」的步驟卡住。
> **原因**：`session_manager.dart:62,67` 的 `getToken()` 與 `ApiService.releaseSession()`
> 原本都沒有逾時；Dart 的 try/catch 攔不到「掛住不動」，只有逾時能保證後續清理一定執行
> （第二十五輪需求 5）。

**G90 — `VideoCallScreen._initCall()` 必須在任何可能提早 return 的路徑之前解析完使用者角色**
`_resolvedUserRole` 的賦值**不得**排在媒體初始化的 `catch`（:235-251）之後。
> **原因**：一旦媒體初始化失敗提早 `return`，角色會停留在宣告時的預設值 `'family'`（:107），
> 導致 `_buildFallbackHome()`（:567）把長輩導向家屬端主畫面（第二十五輪需求 6）。

**G98 — 區域校準的座標映射必須用 `applyBoxFit(BoxFit.contain, ...)` 配 `Image(fit: BoxFit.contain)`**
`zone_calibration_screen.dart::_imageRectWithin()`（:166）算出的 letterbox 矩形，必須與畫面
上 `Image` widget（:441）用的 `BoxFit` **完全一致**；點擊須先確認落在該矩形內才正規化
（:181-182），矩形外一律忽略，**不得**鉗制回邊界再收。
> **原因**：`BoxFit.contain` 保留完整影像、四周留白（letterbox），`BoxFit.cover` 會裁切
> 畫面——兩者「畫面座標 → 正規化座標」的換算公式不同。疊圖或點擊任一邊改用 `BoxFit.cover`
> 而未同步換算，座標會無聲偏移，YOLO 判定的 zone 會悄悄跟畫面對不上，且不會有任何編譯期
> 或執行期警告（第二十七輪）。

**G100 — `main.dart` 啟動時必須將全域音訊焦點設為 `none`，不可改回預設的獨佔模式**
`lib/main.dart` 啟動階段必須呼叫 `AudioPlayer.global.setAudioContext(AudioContext(android: const AudioContextAndroid(stayAwake: true, contentType: AndroidContentType.music, usageType: AndroidUsageType.media, audioFocus: AndroidAudioFocus.none)))`（現行位置 `main.dart:635`）。
🚫 **禁止改回**預設的獨佔焦點模式（`gain` / `gainTransient`）。
**原因**：長輩端全時語音喚醒（`SpeechToText`）運作時，若播放器強搶音訊焦點，系統會發出
`AUDIOFOCUS_LOSS_TRANSIENT`（-2），造成新聞播放與 TTS 自動暫停。設為 `none` 才能讓媒體播放
與語音喚醒並行共存。
> 與 **G77** 互相依賴：G77 提示音那句「全域已設為 `none`，單獨覆寫會讓提示音把通話音訊壓掉」
> 正是**依賴本條成立**才有意義——提示音播放器不得自行覆寫這項全域設定。
> 本條原本只存在於 `Uban/CLAUDE.md` §6 第 27 條（2026-08-04 第十四輪），2026-08-18 拆檔稽核
> 時發現權威文件從未收錄，補列為 G100。

**G101 — 每一條「加入房間」的路徑都必須有對稱的「離開房間」路徑**
`joinRoom()` ↔ `leaveRoom()` ＋ `cancelPendingRoom()`（後者處理 socket 未連線時排進
`_pendingRooms`、稍後才補加入的情境）。
🚫 **不可依賴**「反正最後會斷線，後端 `on_disconnect` 會清掉」——那是隱性依賴，斷線流程
一改就無聲洩漏。
⚠️ `leaveRoom()` 必須排在 `clearSession()` / `forceDisconnect()` **之前**，否則 socket 已斷、
呼叫直接 no-op。
⚠️ CCTV 的 `returnByPop` 返回路徑要用 `monitor_elder_` 前綴守衛，不可無條件 leave（該旗標是
通用的，會誤退通話房）。
> **原因**：第二十八輪查出三條獨立的房間洩漏路徑（CCTV 監控檢視返回、監視機退出、家屬
> 儀表板監聽），全部源於「加入房間」與「離開房間」不對稱——只顧加入卻忘了對應的離開，
> 或誤以為斷線會順帶清理。詳見第二十八輪年表。

**G102 — `Signaling` 單例的回呼欄位必須在 `dispose()` 時用 `identical()` 守衛歸還**
`onCallRequest`／`onCancelCall`／`onEmergencyCall`／`onElderDevicesUpdate` 等回呼欄位在
`Signaling` 單例上只有一份，最後賦值者獨佔。任何畫面指派後，必須在 `dispose()` 用
`identical()` 確認自己仍是持有者才歸還。
🚫 **不可無條件** `= null`——會誤清接手畫面（下一個指派者）的回呼。
🚫 **不可略過歸還**——閉包會持續指向已卸載的 State，回呼開頭常見的 `if (!mounted) return;`
會**靜默**吞掉之後每一通來電，沒有任何 log 或 UI 徵兆。
> **原因**：第二十九輪查出 `family_dashboard_screen.dart` 與 `family_dashboard_view.dart` 都
> 指派了自己的 `onCallRequest` 閉包，但從不歸還，離開畫面後閉包仍占用該欄位，之後所有來電
> 都被靜默吞掉。`role_selection_screen.dart::_checkLoginStatus()` 只要 `elders.isNotEmpty`
> 就會導向這兩個畫面，可達性比原先認為的更廣。

**G103 — `onConnect` 的 rejoin 必須用當下的 instance 欄位，不可用閉包捕捉時的參數**
`_registerSocketListeners()` 內的 `onConnect` 處理常式，重新加入房間時必須讀取當下的
`_currentRoomId`／`_role`／`_deviceName`／`_deviceMode` 等 instance 欄位並逐一 fallback
（例如 `_currentRoomId ?? roomId`），不可直接使用 `onConnect` 閉包在**第一次建立** socket
時捕捉到的區域變數。
⚠️ `leaveRoom()` 會把 `_currentRoomId` 清成 `null`，rejoin 邏輯絕不可把 `null` 傳進
`_asyncJoin`。
> **原因**：`connect()` 的「重用現有連線」分支不會重新註冊監聽器，因此 `onConnect` 閉包
> 長期綁定第一次建立時的舊參數。切換長輩後，一旦斷線自動重連，就會把 socket 加回**舊
> 長輩**的房間，而 Dart 端的 `_currentRoomId` 卻仍宣稱在新房間，後端在新房間找不到該
> sid、判定不可達而把來電退回 FCM（第二十九輪）。

**G104 — 緊急通話路徑必須主動呼叫 bring-to-front 喚醒螢幕**
`main.dart::_autoAcceptEmergencyCall` 與 `elder_screen.dart::_handleEmergencyAccept` 都必須
呼叫 `MethodChannel('com.example.app/bring_to_front')`（`MainActivity.forceBringToFront()`），
且必須 `await` 並捕捉例外（`try/catch` 或 `.catchError`）。
🚫 **同步 `try/catch` 對 `invokeMethod` 無效**——`invokeMethod` 的例外是非同步丟出的，同步
`try/catch` 接不到（見 **G49**）。
> **原因**：全專案唯一會 `setShowWhenLocked(true)` + `setTurnScreenOn(true)` 蓋過鎖屏、
> 點亮螢幕的機制，只掛在 `_navigateToVideoCall` 長輩分支與 `_handleAcceptedCallFromBackground`
> 兩個**一般來電專用**的呼叫點上；緊急通話因 `_showIncomingCallDialog` 開頭短路，從未走到
> 這兩處，也沒有任何其他地方補上——「螢幕未開啟」不是壞掉，是從來沒有實作（第二十九輪）。

**G105 — 監控配對完成的判定必須查後端 `monitor_setup_code.used_at`**
前端必須輪詢 `GET /api/pairing/monitor_setup/status?code=&user_id=`，以 `used == true` 作為
配對完成的唯一信號。
🚫 **不可用**「裝置清單裡是否出現某個名稱」推測完成與否。
> **原因**：裝置名稱輸入框預設值固定為「客廳攝影機」，而 `monitor_device_binding` 是永久
> 紀錄、`_get_elder_devices_list` 的階段 0 補洞會讓同名裝置**永遠**出現在清單裡。只要該
> 長輩曾用預設名綁過一次，2 秒輪詢的第一個 tick 就會命中舊裝置、誤判成功，對端完全不需要
> 任何動作，且確定性可重現（第二十九輪）。曾考慮把判定收緊成「必須是新名稱」，但會打壞
> 同名重綁（監視機恢復原廠後用同名重綁，永久綁定紀錄讓清單永遠不會出現新名稱，彈窗將
> 永不結束），故採後端真實信號而非前端猜測。

**G106 — `sendCallAccept` 的等待窗在冷啟動情境必須放寬，且必須回傳成功與否**
`sendCallAccept` 是 `Future<bool>`，新增 `maxWait` 參數（一般路徑維持既有的 10 秒不變）；
緊急通話路徑（`_handleEmergencyAccept`）必須傳 **30 秒**並 `await` 結果。
🚫 **不可靜默放棄**——送不出去時，畫面必須顯示實話，不可讓使用者一直卡在「接通中」。
> **原因**：`sendCallAccept` 是回報「已接聽」的唯一手段。被殺死裝置的冷啟動（Firebase +
> engine + AndroidIntent + splash + `ElderScreen` 掛載）經常超過原本的 10 秒等待窗，導致
> 接聽從未真正送出，家屬端因此一路等到 60 秒逾時（第二十九輪）。

**G107 — 跌倒警報 channel 必須用 `audioAttributesUsage: alarm` 搭配 `emergency_siren` 原生 raw 資源，不可只給 `playSound: true`**
`cctv_alert_notification.dart` 的 `AndroidNotificationDetails` 必須同時提供
`sound: RawResourceAndroidNotificationSound('emergency_siren')` 與
`audioAttributesUsage: AudioAttributesUsage.alarm`。
🚫 **不可只給 `playSound: true`**——沒有 `sound:`／`audioAttributesUsage` 會退回系統預設的
通知提示音，掛在 NOTIFICATION 音量軌，短、小聲，且會被勿擾模式直接靜音。
⚠️ `RawResourceAndroidNotificationSound` 讀的是原生 `android/app/src/main/res/raw/`，**不是**
Flutter asset；音檔只放進 `assets/sounds/` 而沒有另外複製一份到 `res/raw/`，通知會靜默無聲、
不報錯。
> **原因**：第三十輪稽核發現跌倒警報 channel 只給了 `playSound: true`，對照
> `local_call_notification.dart` 早已正確設定 `sound:` + `audioAttributesUsage`，兩者待遇
> 不對等（第三十輪）。

**G108 — Android notification channel 建立後不可修改；改聲音／音訊屬性／`bypassDnd` 一律要換 channel id 並刪舊的**
channel 一旦在裝置上建立過，系統會**靜默忽略**之後對同一 channel id 再次呼叫
`createNotificationChannel()` 想更改的聲音、`AudioAttributes`、`bypassDnd` 等欄位。
🚫 **不可**期待「只改設定值」對已安裝裝置生效。
✅ 正確做法：換一個新 channel id，並主動刪除舊 id（含所有 legacy 版本）。
> **原因**：第三十輪把跌倒警報 channel 從只有 `playSound: true` 升級為 `alarm` +
> `emergency_siren` 時，若不換 id，所有已安裝裝置都會停留在舊聲音設定，升級對他們形同沒
> 發生（第三十輪；`MainActivity.kt::ensureAlertChannel()` 因此固定使用
> `uban_cctv_alert_v3` / `uban_cctv_alert_v3_dnd`，並清除 `uban_cctv_alert` /
> `uban_cctv_alert_v2` 兩個 legacy id）。

**G109 — `setBypassDnd(true)` 只在 channel 建立當下已持有勿擾權限才生效，必須用雙 channel id 依當前授權狀態動態重選**
`flutter_local_notifications` 的 `AndroidNotificationChannel` 沒有 `bypassDnd` 參數，須走原生
`NotificationManager` API；且 `setBypassDnd(true)` **只在建立當下**已持有
`ACCESS_NOTIFICATION_POLICY`（勿擾政策存取）授權才會生效，事後授權不會回溯套用——疊加
**G108**「channel 不可變」，代表不能「先建一次、之後再翻旗標」。
🚫 **不可**只建一個 channel 就想在使用者授權後翻轉 `bypassDnd`。
✅ 正確做法（`MainActivity.kt::ensureAlertChannel()`）：維護兩個 channel id
（`uban_cctv_alert_v3` 無 bypass／`uban_cctv_alert_v3_dnd` 有 bypass），每次 `onCreate`
**與 `onResume`** 都重新查 `isNotificationPolicyAccessGranted`，建立對應那個、刪除另一個。
⚠️ `onResume` 是必要的一環，不可只在 `onCreate` 判斷一次——使用者從系統設定頁授權完返回
App 時，channel 必須立刻升級成 bypass 版本，不必等下次冷啟動。
> **原因**：`ACCESS_NOTIFICATION_POLICY` 是特殊權限，使用者必須自己到系統設定手動授予，
> 授予的時間點與 App 的 channel 建立時間點天生不同步（第三十輪）。

**G110 — FCM 背景 handler 的 headless engine 拿不到 MethodChannel；背景路徑需要的原生資訊必須經 `SharedPreferences` 橋接**
FCM 背景 handler 跑在獨立的 headless `FlutterEngine`，**不會**執行
`MainActivity.configureFlutterEngine()`，因此任何手動註冊的 MethodChannel（例如查詢當前
生效的 channel id）在純背景冷啟動時都呼叫不到，`invokeMethod` 必定丟
`MissingPluginException`。
🚫 **不可**只用「MethodChannel 查詢失敗就退回硬編 fallback id」——那個硬編 id 可能正是已被
**G109** 邏輯刪除的錯誤（非 bypass）channel，`flutter_local_notifications` 會依
`AndroidNotificationDetails` 的 metadata **重新建出**一個沒有 `bypassDnd` 的同名 channel；
通知照樣會出來（因此極難察覺），但繞過勿擾這個唯一目的悄悄失效。
✅ 正確做法（`cctv_alert_notification.dart::_ensureInit()`）：三段解析——①
MethodChannel 可用時查原生，並把結果寫回 `SharedPreferences`（key
`uban_active_alert_channel_id`）；② MethodChannel 問不到時讀這份快取（前景成功查詢時
寫入，背景 isolate 讀得到）；③ 連快取都沒有才退回硬編 fallback。
> **原因**：第三十輪查出這正是「螢幕關著、App 被殺、長輩跌倒」——本功能存在理由的核心
> 情境——會讓繞過勿擾靜默失效的路徑（第三十輪）。

**G111 — 強制開啟只限長輩端；角色守門必須 fail-closed，且用連線當下的 `_role`**
`signaling.dart:612` 的 `bringToFront`／強制音量、`main.dart` 的 `AndroidIntent` 冷啟動只能
掛在 `role == 'elder'` 分支，守門用**連線當下的 `_role`**，不可用 SharedPreferences 的
`user_role`/`saved_role`（第十六輪漂移史）。家屬端一律禁止；來電響鈴不算強制開啟，雙端可留。
詳見 `CLAUDE.md` §3.1 第 13 條。

**G112 — `safeNavigateBack` 的「已離開」旗標只能以回傳值 latch，不可提前設**
🚫 **禁止**在呼叫導航前就把 `_navigatedAway = true`——導航若被拒（路由已非
`ModalRoute.isCurrent`），旗標會提前鎖死，畫面永久卡住、之後任何導航嘗試都被自己攔下。必須
先導航、依實際結果才設旗標；函式**改回傳 bool** 供呼叫端判斷（第三十一輪教訓，見 §8）。

**G113 — `force-logout` 事件全專案只能有一個處理器**
唯一擁有者是 `main.dart::handleForceLogout`。🚫 **禁止**任何畫面另外監聽並各自
`pushAndRemoveUntil`——兩個處理器搶不同目的地會互相打斷，其中一次 `_navigatedAway` 提前
latch（見 **G112**）即整條死鎖。

**G114 — `showOverLockScreen` 與 `restoreLockScreen` 必須成對，後者排 `dispose()` 第一句**
進入通話房須由 Dart 主動呼叫 `showOverLockScreen`，不可只靠原生
`onCreate`/`onNewIntent`（漏掉 CallKit resume 路徑）。`restoreLockScreen` 要排在對應畫面
`dispose()` **第一個陳述式**，不可只掛在單一「正常掛斷」函式——按返回鍵等其他離場路徑會
整個跳過，App 永久蓋在鎖定畫面上（隱私缺陷）。

**G115 — 不得再加回任何硬編 IP 的降級 fallback**
`signaling.dart` 的 `_overrideServerUrl`、`api_service.dart` 的 `10.0.2.2` 一類「連線失敗就
切寫死位址」機制一律禁止——這類位址通常只在模擬器可路由，實機會連線永久失聯且無法自動
恢復；暫時性失敗一律交回 library 內建重連（socket.io）或逾時重試。

**G119 — 撥話端逾時看門狗不可混淆「沒人接」與「已接聽但協商中」；已接聽後絕不可 `sendCancelCall`**
`video_call_screen.dart::_armConnectTimeout` 的逾時判斷必須區分「對方是否已接聽」
（新增旗標 `_remoteAccepted`）與「是否已連線」（`_callConnected`／`onPeerConnected`）：
`onCallAcceptedByRemote` 到達時必須作廢原本的 20 秒等待窗，改武裝 30 秒協商窗；`_retryCall`
必須把 `_remoteAccepted` 歸零，重撥才會重新等待對方接聽。
🚫 **禁止**在 `_remoteAccepted == true` 之後的逾時處理仍呼叫 `sendCancelCall`——已接聽的通話
逾時是連線失敗，不是沒人接，文案與行為都不可比照「無人接聽」。
> **原因**：第三十二輪查出 `onCallAcceptedByRemote` 只做 `createOffer`、完全不碰 20 秒計時器，
> 導致對方已接聽、仍在協商時，20 秒一到照樣 `sendCancelCall` 並顯示「對方沒有接聽」——這正
> 是使用者回報的「自動強制切斷後端通話 socket」。媒體經日本 Coturn 中繼，TURN allocation＋
> ICE gathering 常態超過 15 秒，20 秒窗太窄，改為 30 秒。長輩端看門狗守衛是 `_status` 字串
> 比對、接聽時已被改寫而自我作廢，稽核後未發現同一 bug，但也因此沒有協商逾時；刻意不補，
> 現行方向（不誤殺可用通話）比誤殺更安全。

**G120 — 在線判定與撥號目標一律只取通訊機；監控機不得計入 `isOnline`，也不得成為 `_elderSocketId`**
`family_main_screen.dart::_applyDeviceList` 的 `online`／`onlineSid` 必須由 `commDevices`
（`deviceMode != 'monitor'`）推導，不可對整份 `devices` 清單（含監控機）取 `any`/`firstWhere`。
🚫 **禁止**讓監控機連線就顯示「長輩在線」，也**禁止**把 `_elderSocketId` 指向監控機的 sid。
⚠️ 無 `deviceMode` 欄位的裝置一律歸入通訊機——誤判成「打不通」比誤判成「可打」傷害小。
> **原因**：第三十二輪查出監控機一連上，家屬端就顯示長輩在線，撥出卻打不通；更嚴重的是
> `_elderSocketId` 取「第一台在線設備」，可能命中監控機，導致撥出的通話被指向監控機而非
> 通訊機。`monitors` 清單與 2.5 秒 online→offline debounce 不受影響。

**G122 — `MainActivity.override fun finish()` 是全域攔截，任何結束路徑都會清掉 Recents 的 Task**
`MainActivity.kt` 的 `finish()` 覆寫統一呼叫 `finishAndRemoveTaskCompat()`（`isTaskRoot` 為
防呆，非 root 時退回 `super.finish()`）。
⚠️ **這不是通話專屬邏輯**——任何呼叫 `finish()` 的路徑（連續按返回鍵離開 App、其他功能的
正常結束）都會一併清掉 Task 記錄。
🚫 新增任何會觸發 `finish()` 的呼叫前，必須先確認「結束後 Task 從 Recents 消失」這個副作用
對該路徑是可接受的。
> **原因**：第三十二輪為解決「App 卡在背景滑不掉」，替兩個通話畫面新增 `finishAndRemoveTask`
> （只在 `_enteredWhileLocked` 為真時呼叫，見年表），但 `MainActivity.finish()` 覆寫本身是
> 全域的，影響範圍不限於通話。確切成因**未經實機證實**（需要 `adb shell dumpsys activity
> recents` 證據），本條只約束程式碼明顯缺失修好後的副作用邊界。

**G123 — `isEmergency` 是一詞二義，不得單獨作為分流依據**
`isEmergency` 同時標記兩件不同的事：真正的緊急通話，以及 CCTV 監控檢視——
`family_interaction_tab.dart:1894`、`family_main_screen.dart:1026` 呼叫
`startMonitoring` 時都以 `isEmergency: true` 硬寫進 offer。
🚫 **禁止**任何新行為只依 `isEmergency` 做判斷——那等於同時對「這是緊急通話」與
「這是監控檢視」下決定。需要區分兩者時必須併看 `monitorViewOnly`，或另立獨立訊號。
> **原因**：第三十三輪把 ICE `iceTransportPolicy` 的 relay-only 決策綁在
> `isEmergency` 上；第三十四輪查出監控檢視也會把 `isEmergency` 設為 true，於是
> 監控連線被迫 relay-only，拿不到 relay 候選時 ICE 立即失敗（「點進監控直接顯示
> 無法連線」）。修法：新增獨立訊號 `preferRelay`，`_resolveIceTransportPolicy`
> 簽章改為 `{required bool preferRelay}`（結構性防止再犯），全專案只在
> `video_call_screen.dart:323` 一處計算為
> `widget.isEmergency && !widget.monitorViewOnly`。

**G124 — `call-accept` 的 fallback 路徑必須帶齊本通電話的屬性；查無記錄一律視為緊急**
`onCallAcceptedByRemote` 尚未註冊時，`signaling.dart` 的後備路徑仍會呼叫
`createOffer`；呼叫時必須查得到本次撥出當下記錄的 `isEmergency`／`preferRelay`，
🚫 **不可**讓兩者吃函式預設值（`false`）頂替。
✅ 查無本次撥出記錄時一律視為**緊急**：誤判為一般會重現「長輩被跳過無條件接聽」
的 bug 並牴觸 **G81**；誤判為緊急只是少跳一次一般通話的提示。`preferRelay` 不比
照此規則、刻意固定傳 `false`——這條 fallback 不知道 `monitorViewOnly`，鏡射會讓
監控重蹈 **G123** 的覆轍。
> **原因**：第三十四輪查出 `signaling.dart:557-565` 的 fallback 呼叫
> `createOffer` 不帶 `isEmergency`，只在家屬端 `_initCall()` 尚未註冊完
> `onCallAcceptedByRemote` 的空窗觸發——長輩端無條件自動接聽（**G81**）讓
> `call-accept` 幾毫秒就回來，恰好卡進這個空窗；一般通話要等人手動按接聽，早就
> 錯過這段空窗，故只在緊急通話重現。修法：新增與 `_currentCallId` 配對的純資料
> 欄位記錄本次撥出是否緊急，fallback 依 callId 比對查詢。

**G125 — session 清除必須分兩層；`last_elder_*` 只有家屬端 `force-logout` 可清**
`session_manager.dart` 的 `_sessionKeys`（無條件清除）與 `_quickLoginKeys`（快速
登入記憶，僅 force-logout 才清）必須分開維護；`releaseSession()` 需要
`preserveQuickLogin` 參數，只有長輩自己主動登出時傳 `true`。
🚫 **禁止**把 `_quickLoginKeys` 併進 `releaseIfBound()` 的殘留判斷
（`_sessionKeys.any(...)`）——併入後身分選擇頁會把「刻意保留的快速登入鍵」誤判
成殘留 session，用預設參數（`preserveQuickLogin: false`）重新呼叫一次，把剛保留
的鍵清掉，保留形同虛設。
> **原因**：這是 **G24** 的重申——G24 早就明文寫著這四個鍵只有家屬端
> `force-logout` 才可清。第二十輪把四份分歧的登出實作收斂成單一入口時，把
> `last_elder_*` 放進了無條件清除的鍵集合，讓 G24 被破壞了十三輪之久，直到
> 第三十四輪才因「長輩登出後無法快速登入同一長輩」被溯源修復。第十三輪設計的
> `_quickLoginSameElder` 邏輯其實從未壞過，只是被斷了輸入。

**G131 — 通話兩端不得各自獨立決定 `iceTransportPolicy`**
任一端在 SDP 送出後才因本機探測結果重建 PeerConnection，會清掉已到達的遠端候選，
兩端候選集因此不對稱、配不出可用 pair；哪端失敗會隨網路／Doze 狀態翻轉。
✅ 要引入非 `'all'` 的 policy，必須先讓兩端在**任一端 commit 前**協商一致，不能靠
各自讀本機快取各自決定。
🚫 **禁止**任何一端在 SDP 送出後因本機探測結果不理想就片面重建 PeerConnection。
> **原因**：第三十六輪查出三輪疊加的 `'relay'` 優化在真機仍讓一端 ICE 失敗且失
> 敗端隨情境翻轉，整組移除回退 `'all'`。**安全關鍵路徑的效能優化，失敗模式是
> 「有時候不通」＝系統失效**。

**G134 — `Signaling` 上任何「沒有 UI 也會自行動作」的 fallback，都必須查驗 `_invalidCallIds`**
`call-accept` 監聽器在 `onCallAcceptedByRemote` 為 null（畫面已 dispose）時會靜默
走 fallback 呼叫 `createOffer()`，建立帶存活媒體流卻無 UI 的 PeerConnection；
`call-request`／`cancel-call`／`emergency-call` 都有查驗 `_invalidCallIds`，唯獨這
個 fallback 沒有。
✅ Singleton 上每條「回呼為 null 時自行動作」的 fallback，都要比照補上
`_invalidCallIds` 查驗——這在後端同類修復（**G133**）後仍必要，因為它是零網路往
返的本機同步檢查，補的是跨連線訊息順序不定留下的殘餘窗口。
🚫 `_closePeerConnection()` 不可省略 try/catch：三個呼叫端皆 fire-and-forget，中
途拋出會讓 `peerConnection = null` 執行不到，留下永遠半拆解的連線；歸零須以
`identical()` 守衛，避免舊通話延遲關閉誤清新連線。
> **原因**：掛斷後對方才接聽的殘留場景中，收話端看得到撥話端視訊卻沒有畫面撐
> 著——真因是這條 fallback 建立了無 UI 的 PeerConnection。

**G136 — 權限請求必須在隱私權政策同意之後，且必須 `await` 到完成才導航**
`splash_screen.dart` 的 `_replaceWith` 用 `Navigator.pushReplacement`，移除的是導
航堆疊**最上層**的 route——若權限對話框（`barrierDismissible: false` 的
`showDialog`）恰好在那個位置，會被靜默換掉，`await showDialog` 無例外返回，畫面
直接消失，程式碼完全無感。
✅ 任何在啟動流程中彈出的對話框，導航到下一頁之前都必須先 `await` 到它關閉，並
在 `await` 之後重新檢查 `mounted` 才能導航；權限請求必須排在隱私權政策同意**之
後**（先同意再要權限，順序不可顛倒）。
🚫 新增「啟動時彈出對話框」的路徑之前，必須確認它不會與 splash 的導航搶同一個
route 位置。
> **原因**：第三十七輪查出隱私權畫面把系統權限對話框整個換掉，使用者看不到權限
> 警告，首次使用因此拿不到相機／麥克風，第一次通話雙端都可能連不上。
> ⚠️ `elder_screen.dart:436` 的 `_checkPermissions()` 未 `await` 是已知潛在競
> 態，**刻意保留**——`initState` 加 `await` 會擋住冷啟動接聽鏈（🔴 極高風險，見
> §2 檔案地圖），修好本條後這條競態理論上不再觸發，若日後仍有回報再處理。

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

**G91 — `elder-devices-update` 的每筆裝置必須帶 `elderId`；`on_disconnect` 必須清掉該 sid 在所有房間的登記**
前端依 `elderId` 丟棄不屬於目前長輩的 payload（空清單仍照常套用）。
`on_disconnect`（`socket_app.py`:1692）內**不可** `break`。
> **原因**：`_switchElder` 只清前端快取，但雙端都沒有 `leave`/`leave_room` 動作，家屬端 sid
> 會同時留在新舊兩位長輩的房間；舊長輩一有裝置異動就會廣播到這個 sid，而
> `_applyDeviceList` 原本不檢查 payload 屬於哪位長輩（第二十五輪需求 8）。`break` 只清掉
> 第一個符合的房間，多房間殘留的 sid 會被永久留下。

**G92 — Socket 房間必須有明確的離開語意；`leave` 必須是定向的**
`leave` 只離開呼叫端指名的那一個房間，**不得**實作成「join 新房間就退掉所有舊房間」。
🚫 **禁止**把 `leave`／`leave_room` 做成隱含在 `join` 裡的自動行為。
**原因**：`signaling.dart::joinRoom()` 用 role `'listener'`／deviceName `'Dashboard_Listener'`
讓家屬端能同時關注多位長輩（多長輩儀表板），依賴同一條 socket 能同時待在多個房間；
一刀切的「進新房間退所有舊房間」會直接打死這個功能。
離開時必須同步清 `rooms_manager`、`room_fcm_tokens` 該筆的 `socketId`/`appState`，
並持久化 `user_fcm_token.app_state='background'`——`_get_target_sockets_and_tokens` 的
Layer C 讀的正是 DB 的 `app_state`，房間已離開卻在 DB 留著 `foreground`，就是本專案反覆
出現的「收不到來電」那一類殘留狀態。見 `socket_app.py::on_leave`（:1557）、
`signaling.dart::leaveRoom()`（:799）、`family_main_screen.dart::_switchElder`（:961）。

**G93 — 警報冷卻期只抑制推播，不得抑制記錄**
`dispatch_yolo_alert`（`services/yolo_alert_dispatcher.py`）的 `_insert_alert` 一律執行，
冷卻期只跳過 Step 2（Socket）與 Step 3（FCM）。
🚫 **禁止**把冷卻判斷挪到 `_insert_alert` 之前，或讓冷卻期直接 `return None` 跳過整個
dispatch。`last_fall_alert_at`／`last_crawl_alert_at`／`last_inactivity_alert_at`
（`yolo_detector_service.py`）只在**未被抑制**時更新，否則持續事件會不斷重新起算冷卻而永遠
推不出去。
**原因**：舊行為在冷卻窗口內直接 `return None`，發生在 dispatch 之前，DB、Socket、FCM
全都沒有——冷卻期內的第二次真實跌倒完全船過水無痕，連記錄都不留。

**G94 — 後端改動的驗證必須包含 import 冒煙測試，不能只跑 `py_compile`**
`python -m py_compile` **只驗語法**，抓不到 `NameError`／缺 import——這類錯誤只在
真正 import 該模組時才會現形。
🚫 **禁止**把 `py_compile` 全數通過當成「後端可以啟動」的證據。
驗證必須額外跑 `python -c "from main import app"`：開機失敗會在此處噴出堆疊。
⚠️ `main.py` 最後一行把 `app` 包成 `socketio.ASGIApp`，FastAPI 本體在
`app.other_asgi_app`，要取路由表（例如數路由數量）得走這個屬性。
**原因**：`routers/ai.py`:1491 的 `class FamilyCopilotChatRequest(BaseModel):`
全檔沒有 pydantic import，`NameError: name 'BaseModel' is not defined` 讓整個後端
無法啟動，而 `py_compile` 對此完全沒有反應，屬於「宣稱完成但從未執行過」的同一種病
（與第二十五輪查出的 Flutter 編譯錯誤同類）。

**G95 — IPS 掛鉤關閉時必須維持「單一布林檢查即返回」，且絕不可影響既有 CCTV/跌倒偵測路徑**
`services/indoor_position.py::ips_enabled()`（**2026-08-18 第二十七輪起預設 `true`**，
`IPS_ENABLED=false` 是緊急關閉用的 kill-switch，見 G97）；`routers/alert.py` 的
`push_cctv_frame` 呼叫 IPS 掛鉤時必須包在**獨立**的 `try/except` 內，任何內部失敗只記警告。
🚫 **禁止**讓 IPS 的例外被外層 `except` 誤判成本次推幀是 `server_error`。
🚫 **禁止**合併或改寫 `/cctv/frame` 既有的兩條早退路徑（`yolo_disabled`、
`busy_frame_dropped`）。
**原因**：`push_cctv_frame` 是跌倒偵測（YOLO）與現在 IPS 共用的同一個熱路徑端點，
`IPS_ENABLED=false` 時掛鉤必須是單一布林檢查就返回——零 DB、零幾何運算、零 Socket
廣播——任何額外開銷或例外洩漏都會拖累或中斷本來就承擔著跌倒警報派送的既有端點。
（2026-08-18 第二十七輪：預設值由 `false` 改為 `true`，但本條「關閉時零開銷」的行為本身
不變，只是觸發它的預設狀態反轉；未校準時的行為改由 G97 負責——**2026-08-25 第三十二輪起
G97 已從「完全零開銷」修正為「presence 追蹤與 Socket 廣播照跑、只有幾何運算與 DB 寫入這段
維持零開銷」，勿再引用本條舊敘述去佐證「未校準＝完全不做事」或「未校準就收不到
`elder-zone-update`」，見 G97。**）

**G96 — `/cctv/frame` 的 IPS 掛鉤裡，`store_last_frame` 必須排在 `process_frame_for_zone` 之前**
`routers/alert.py::push_cctv_frame`（:368-371）的 `if indoor_position.ips_enabled():` 區塊
內，呼叫順序**不得**顛倒。
🚫 **禁止**把 `store_last_frame` 移到 `process_frame_for_zone` 之後，或讓兩者共用同一個
提前返回條件。
**原因**：`process_frame_for_zone` 在該監視機「尚未校準」（`load_zones` 回傳空陣列）時會
提前返回（見 G97）；若快照寫入排在它後面，未校準的裝置就永遠執行不到快照寫入這一步——
家屬端校準 UI 因此永遠看不到畫面，永遠無法完成校準，形成「無快照 → 無法校準 → 永遠未
校準」的死結（第二十七輪）。

**G97 — `process_frame_for_zone` 的「未校準」早退只跳過幾何運算與 DB 寫入，presence 追蹤與 Socket 廣播不受影響**
`services/indoor_position.py::process_frame_for_zone`（:526）**2026-08-25 第三十二輪起分兩層**：
第一層無條件執行——偵測到人就呼叫 `ZoneTracker.touch()` 更新 presence，最後不論是否校準、
是否發生切換，都會 `zone_tracker.snapshot()` 組 payload 並廣播 `elder-zone-update`（見
「Socket 事件」）；`load_zones()` 回傳空陣列（**尚未校準**）時只早退中間這段幾何與分類——
`foot_point()`、`classify_zone()`、`ZoneTracker.update()` 的穩定切換判斷——因此 `transition`
恆為 `None`，寫入 `elder_zone_event` 這個 DB 步驟（只在 `transition` 非 `None` 時才跑）也
連帶不會執行。
🚫 **禁止**移除或延後這段幾何/分類早退（例如改成「先解出多邊形判定才問有沒有 zones」），也
**禁止**把 `touch()` 與最後的 snapshot／廣播塞進這道早退之後——後者會讓校準功能移除後
`load_zones()` 恆為空的監視機，presence 永久回不了「有沒有人」，見 §6.12。
🚫 **不要**誤以為「未校準就收不到 `elder-zone-update`」——會收到，只是 `transition` 恆為
`None`、從不觸發 DB 寫入；不能用「有沒有收到這個 Socket 事件」判斷校準狀態。
**原因**：CCTV 推幀節奏是每 2 秒一次，多數監視機長期處於未校準狀態；`IPS_ENABLED` 預設開啟
（第二十七輪，見 G95）後，若移除幾何/分類守衛，等同對所有未校準監視機每一幀都做無謂的幾何
運算與 DB 寫入嘗試。第一層與廣播之所以無條件執行，是因為第三十二輪移除家屬端校準介面
（`zone_calibration_screen.dart`）後 `load_zones()` 對多數監視機恆為空，若一併被早退擋住，
「長輩目前在此處」會永久回報不到資料，見 §6.12。2026-08-25 前的版本是完全零開銷（含零
Socket 廣播），之後改為「零幾何與 DB 開銷，presence 與廣播照跑」，見 G95 更正註記。

**G99 — naive `datetime.utcnow()` 不可直接呼叫 `.timestamp()`**
需要 epoch（Unix timestamp）時一律使用 timezone-aware 的
`datetime.datetime.now(datetime.timezone.utc).timestamp()`。
🚫 **禁止**用 `datetime.datetime.utcnow().timestamp()`：`.timestamp()` 會把 naive
datetime 當**本地時間**解讀，在 UTC+8 環境下會讓 epoch 整整倒退 8 小時。
只做「datetime 相減」（算時長）或 `.isoformat()`（純字串化）的 naive 用法**不受影響、
不必改**——問題只發生在 naive datetime 轉 epoch 這一步。
**原因**：`services/indoor_position.py::_build_zone_payload`（:522）原本寫
`int(datetime.datetime.utcnow().timestamp())`，本機實測 `naive.timestamp()` 與真實
UTC epoch 的 delta 恰好 `-28800` 秒（＝-8 小時，正是 UTC+8 偏移）——`elder-zone-update`
每一則推播的 `timestamp` 都被記錄成 8 小時前。第二十七輪查出當時無可見症狀（前端消費的
是 `entered_at` 而非 `timestamp`），屬於等下一個消費者踩的定時炸彈。
跨語言傳遞 ISO 字串時有對應的另一面，不屬本條約束但同源，一併記錄：Python 端 naive
`.isoformat()` 不帶時區尾碼，到了 Dart 的 `DateTime.parse` 會被當**本地時間**解析；
接收端（例如 `family_main_screen.dart::_parseUtcIso`:464）必須在缺時區尾碼時補 `Z`。

**G116 — `unbind_elder` 必須驗關係、scoped delete、剩餘綁定歸零才刪帳號**
`is_user_linked_to_elder` 不符一律回 **404**；`family_elder_relationship` 等清理須帶
`family_id` 條件，不可只用 `elder_id`；cleanup 白名單內帶 FK 的表要排在被參照表**之前**；
剩餘綁定歸零才可刪 `elder_profile`，單一交易。

**G117 — YOLO stub 模式必須回 `yolo_unavailable`，不可與 `no_event` 混淆**
模型載入失敗時，推幀端點須能區分「沒推論」與「推論了但沒偵測到」，用獨立狀態
（`yolo_unavailable`）並提供 `health()`／狀態查詢端點。🚫 禁止載入失敗靜默退化成看似正常的
`no_event`。

**G118 — 後端喚醒訊息只送純 `data` payload，不得帶 `notification` block**
通話／警報類 FCM（`emergency-call`、`cctv-alert` 等）一律 `messaging.Message(data={...})`，
不得帶 `notification` block——那會讓系統通知匣接管、繞過前端角色守門（見 **G111**）。詳見
`CLAUDE.md` §3.1 第 14 條。

**G121 — 「不透明 id」不等於匿名；以 `device_id`／`elder_id` 為鍵的端點一律要走授權檢查**
`device_id = crc32(f"{elder_id}|{device_name}")`（`monitor_identity.py`）**不是**匿名化，
只是編碼。`elder_id` 只有 4 位數（10,000 種可能）、`device_name` 來自很小的固定集合，整個
組合空間小到離線幾秒就能暴力反解——`crc32` 是無鹽雜湊，不具抗碰撞或抗反查設計，不該被當成
保密手段。
🚫 **禁止**以「這個 id 只是內部識別碼、外部看不出對應到誰」為由讓端點免驗證——這個假設在小
空間鍵下不成立，測試與型別檢查都不會提醒你，只有讀程式碼的人自己動手推算輸入空間才抓得到。
✅ 以 `device_id`／`elder_id` 為鍵、回傳**指名對象**狀態的端點一律要經
`call_security.is_user_linked_to_elder()`，無權回 **404**（比照 **G45**，不是 403）；只有
回傳**完全不指名任何對象**的全域狀態才可免驗證。
> **原因**：第三十一輪新增的 `recent_diagnostics` 掛在無驗證的 `GET /cctv/yolo_status` 上，
> 文件當時宣稱 `device_id` 這個鍵「不足以定位到特定家庭」——第三十二輪查出這個宣稱是錯的，
> 洩漏的是 `person_detected` 近即時狀態，等同「這位長輩此刻在不在鏡頭前」。新增任何「看似
> 不透明」的鍵之前，務必自問：這個 id 的輸入空間夠大到不能離線枚舉嗎？答不出來就當作可以
> 被反解，一律驗證。修復：`yolo_status` 回歸只帶偵測器全域狀態；診斷拆到
> `GET /cctv/yolo_diagnostics/{elder_id}?user_id=`，經 `is_user_linked_to_elder()`，無權
> 回 404。

**G126 — 復原／移機類深連結必須提供可手動輸入的代碼退路**
瀏覽器對沒有使用者手勢的 custom scheme（如 `uban://`）跳轉有攔截政策（例如
Chrome），且該政策不在我們控制範圍內；即使 Manifest、後端頁面、App 端三層各自
正確，「瀏覽器 → App」那一跳仍可能被攔下。
✅ 提供深連結的頁面（如 `/recovery`）必須同時具備：可見按鈕作為使用者手勢入口、
Android 上改用 `intent://`（帶 `package` 與 `browser_fallback_url`）取代純
custom scheme、以及**不依賴任何跳轉機制**的手動輸入代碼退路。
> **原因**：第三十四輪查出復原連結打不開 App，Manifest（宣告 `uban://recovery`）、
> 後端 `/recovery` HTML（`main.py`）、Dart 端（兩種格式都接）三層各自驗證都正確，
> 問題出在 Chrome 擋下沒有使用者手勢的 custom scheme 跳轉——這是三層各自驗證都
> 測不到的一層。⚠️ 這是機率最高的推測，未在實機上確認「瀏覽器→App」那一跳就是
> 唯一失敗點；手動輸入退路才是真正的保障。

**G127 — 診斷類端點若以 `device_id` 或 `elder_id` 為鍵就必須授權；`crc32` 不是匿名鍵**
延續 **G121**：任何回傳「指名對象」狀態的診斷端點，只要鍵是 `device_id`／
`elder_id`，一律視為可反解到特定家庭，必須經 `is_user_linked_to_elder()`，無權
回 **404**（比照 **G45**）。
🚫 **禁止**以「這個鍵是雜湊過的、看起來不透明」為由跳過驗證——`device_id =
crc32(f"{elder_id}|{device_name}")`，`elder_id` 只有 4 位數（10,000 種可能）、
`device_name` 集合極小，`crc32` 是無鹽雜湊，離線幾秒即可枚舉反解；洩漏的是近
即時的「這位長輩此刻在不在鏡頭前」。
> **原因**：第三十三輪稽核 `routers/alert.py` 診斷端點時，再次確認
> `recent_diagnostics` 掛在無驗證端點上、以「`device_id` 不足以定位到特定家庭」
> 為由略過授權——這正是 **G121** 判定過為錯誤的同一種宣稱。修復：需授權的診斷
> 維持在 `GET /cctv/yolo_diagnostics/{elder_id}?user_id=`，經
> `is_user_linked_to_elder`，無權回 404；`/cctv/yolo_status` 只回傳不指名對象
> 的全域狀態。

**G128 — 權重／模型／資源檔一律用「模組相對」推導的絕對路徑，不得依賴行程工作目錄**
`YOLO("yolov8n.pt")` 這類寫法是相對路徑，相對的是**行程的工作目錄**，不是模組所在目錄；
啟動指令一改（uvicorn 的執行目錄、容器 `WORKDIR`），路徑就找不到，且往往在遠端環境才會
觸發，本機開發時可能剛好目錄一致而測不出來。
✅ 一律用 `os.path.dirname(os.path.abspath(__file__))` 推導絕對路徑；載入前先
`os.path.isfile()` 檢查，檔案不存在時直接在錯誤訊息中報出**檢查過的完整路徑**，讓看不到
伺服器的人也能行動。
🚫 **禁止**讓函式庫在找不到本地檔案時自行連網下載——有出網的機器會靜默下載成功、反而
遮蔽部署問題；無出網的機器則只留下一段無法行動的 traceback。
> **原因**：第三十五輪查出 `yolo_detector_service.py:132` 用相對路徑載入 YOLO 權重檔，
> uvicorn 若不是從 `/app` 啟動就找不到，`ultralytics` 找不到本地權重會嘗試連網下載，無
> 出網環境直接拋例外——監控機畫面連續三輪回報「偵測器未載入」，真因到此輪才定位。

**G129 — 廣播給「家屬端」的 socket 事件必須同時掃 `comm_elder_<id>` 與 `monitor_elder_<id>` 兩個房間**
家屬開啟 CCTV 檢視時通常沿用既有連線的房間登記，伺服器端不一定在監控房內；只掃單一房間
會表現成「有時有用有時沒用」——比完全無效更難查，因為第一時間看起來像修好了。
✅ 比照 `socket_app.py::_broadcast_elder_devices_update`／`_broadcast_elder_zone_update` 的
既有掃法：兩個房間都掃，角色篩選 `role in ('family', 'listener', 'family-monitor')`。
🚫 新增任何要通知家屬端的廣播時，**不得**只掃其中一個房間就視為完成，也不能只在單一裝置
上測過就當作驗證充分。
> **原因**：第三十五輪查出監控機自行退出時，正在觀看的家屬端收不到任何通知——
> `DELETE /api/pairing/monitor_device` 只把 `monitor-removed` 送給被踢的裝置自己，家屬端
> 只能靠 WebRTC 自行逾時才會發現，App 在後台時更久。

**G130 — 授權參數宣告成 `Optional` 且預設 `None` 時，前端缺傳即是確定性 404，不是「可能失敗」**
`user_id: Optional[int] = Query(None)` 接 `if user_id is None or not
is_user_linked_to_elder(...): raise HTTPException(404)`——前端少傳這個參數，FastAPI 的
預設值直接決定了結果，型別檢查與後端測試都不會攔到「前端忘記傳」這件事，因為兩邊各自看
都合法。
✅ 新增或修改這類端點時，必須逐一核對**所有**前端呼叫點都有傳齊必要參數，不能只驗證
後端邏輯本身。
🚫 前端 `_safeDecode` 不檢查 HTTP status、直接解 body，404 的 `{"detail": ...}` 沒有
`status` 鍵於是被當成一般失敗回傳 `false`——症狀是按鈕靜默無效，不會拋出例外提醒開發者。
> **原因**：第三十五輪查出家屬端「刪除監視機」按鈕自第十九輪加上授權以來就從未成功過，
> `family_main_screen.dart` 的呼叫點沒有傳 `userId`，每次都確定性地收到 404。

**G132 — 驗證必須能夠失敗**
在權重檔所在目錄測試「路徑是否還依賴 CWD」、在有出網的機器測試「是否還會連網下
載」，這類檢查在修復沒生效時依然會通過——設計上不可能變紅，毫無鑑別力。
✅ 收工前自問：這項驗證在修復沒生效的世界裡會不會失敗？答不出「會」就換一個真正
能失敗的檢查。
🚫 **禁止**把「跑過一次、沒報錯」當成「驗證過了」——永遠會綠的檢查比沒有檢查更
糟。
> **原因**：第三十五輪的 YOLO 修復「實測通過」是在權重檔所在目錄執行的，舊相對
> 路徑在那裡本來就會成功；換一個工作目錄立刻看到連網下載的證據。

**G133 — 掛斷必須讓 callId 立即失效，且 `call-accept` 必須查驗**
`on_cancel_call` 會 `_mark_call_cancelled`，但只擋「還沒接聽就取消」；已響鈴或已
接通的電話被掛斷（`on_end_call`）同樣要讓 callId 失效，否則對方稍後接聽仍會被當
成有效通話轉發。
✅ `on_end_call` 與 `on_cancel_call` 都要 `_mark_call_cancelled`；`on_call_accept`
須在轉發前查驗 `_cancelled_call_ids`，命中就以 `call-busy`（`reason:
'cancelled'`）回覆**收話端**。
🚫 前端 `_invalidCallIds` 的同步檢查不可因後端已擋而省略——Socket.IO 跨連線訊息
無順序保證。
> **原因**：撥話端已掛斷、收話端才接聽並重撥後，只有收話端進房且看得到無聲視
> 訊——根因是 `on_call_accept` 從未查詢 `_cancelled_call_ids`。

**G135 — YOLO／模型載入失敗訊息必須帶原始例外內容，不得回退固定字串**
`ImportError` 同時涵蓋「套件真的沒裝」與「套件裝了、其相依 import 失敗」（例如
`libGL.so.1` 等系統庫缺失）兩種完全不同的情境，混成同一句固定文字會讓診斷連續多
輪走錯方向。
✅ 例外處理必須用 `except ImportError as e` 並把 `str(e)` 帶進 `_load_error`（或
等效欄位），保留原始例外內容給不具伺服器權限的使用者核對。
🚫 **禁止**因此改用 `pip uninstall opencv-python` 或強制重裝 headless 版——
ultralytics 對它有硬相依，移除可能讓 pip 相依檢查失敗而中斷建置，`deploy.yml` 的
`set -e` 會讓部署中止、舊容器繼續服務舊程式碼。`Dockerfile` 新增的
`libgl1 libglib2.0-0` 安裝層也不可移除。
> **原因**：第三十七輪查出監控機畫面顯示「ultralytics 未安裝」，但套件其實有
> 裝，是硬寫的固定字串蓋掉了真正的 `ImportError`（相依的非 headless opencv 缺系
> 統庫）。使用者不是伺服器管理員、讀不到後端日誌，這行字是他唯一的診斷來源。

**G137 — `force-logout` 的 `reason` 是契約的一部分，前端只能在明確值時才清快速登入鍵**
新增任何 force-logout 送出點都必須帶 `reason`（Socket 與 FCM 兩條路都要）；前端
只有 `reason == 'elder-unbound'` 時才可以清除 `last_elder_*` 四個快速登入鍵，
`reason` 讀不到、為 `null`、或是未知值（例如 `'device-removed'`）一律保留。
✅ 判斷方向必須保守：不確定就保留，不確定就不清。這四個鍵只是「上次登入的長輩是
誰」的便利記憶，清掉造成的是使用者體驗損失，不是安全風險，沒有理由冒進。
🚫 **禁止**在新增的 force-logout 送出點漏帶 `reason`——漏帶不會讓前端出錯（會退
回保守的保留行為），但語意會失真，且會讓下一個排查同類問題的人誤以為這條路徑也
會清鍵。
> **原因**：第三十七輪查出監控機執行「退出監控模式」時，`elder_screen.dart` 先
> 呼叫 `deleteMonitorDevice`、才以 `preserveQuickLogin: true` 呼叫
> `releaseSession()`，但後端對被刪除的裝置自己送出的 force-logout 繞一圈回到同
> 一台裝置，被前端當成「長輩關係解除」而把剛保留的快速登入鍵清掉——這是使用者第
> 三次回報同一症狀，前兩輪（第三十四、三十五輪）都沒能根治。

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
| 12 | `Uban/CLAUDE.md` 第九輪（已遷至 `CLAUDE_call-monitor-history.md`）記錄中段插入了 `## 環境要求` + `## 🚫 絕對不可改動區塊` 片段 | 結構損毀，非有意內容 | `Uban/CLAUDE.md`:452-458 |
| 13 | `signaling.dart` 的 **`_configuration`** 看起來是 ICE / TURN 設定 | **死碼，完全沒有被使用**（`flutter analyze` 有 `unused_field` 警告）。真正生效的是 **`_generateDynamicTURNConfig()`**，由 `_createPeerConnection` 呼叫 | **2026-08-10 實測 :157**（第十七輪記的 :116 已漂移）；`_showCallkitIncoming` 死碼在 **:610**（原記 :542） |
| 14 | §3.1 / §6.6 / §6.7 稱「`elder-devices-update` **只在 join 時廣播**，disconnect 不廣播」 | **會廣播**。join(:1333)、`delete-device`(:1464)、`force-logout`(:1548)、**disconnect(:1628)**、改名(:2467) 都呼叫 `_broadcast_elder_devices_update` | `socket_app.py`:1628 |
| 15 | §6.6 宣稱有「**15 秒 staleness watchdog**」 | **從來不存在**（全 `lib/` grep 無此物）。前端只有 2.5 秒 Socket 輪詢 + 10 秒 HTTP 交叉驗證 | `family_main_screen.dart` grep |
| 16 | §6.6 宣稱有「每 10 秒 HTTP API 交叉驗證」 | 第十七／十八輪**確實不存在**（憑空記載）；**2026-08-10 第十九輪 A4 才真正實作出來** | `family_main_screen.dart`:338 `_refreshMonitorDevicesViaHttp` |
| 17 | §6.8 記 `_exitCCTVMode` 在 `elder_screen.dart`:795 | 實際在 **:910**（入口鈕 :1098） | grep |
| 18 | `uban-api/CLAUDE.md`：通話迴歸套件「須維持 **15 passed**」 | 實測為 **17 passed**——測試數量會隨改動增加而成長，這個數字本來就不是寫死的常數，權威依據永遠是套件當下的實際輸出，不是文件裡的舊快照。**2026-08-18 第二十六輪已就地更正** | `python -m pytest tests/test_call_signaling.py -q`；`uban-api/CLAUDE.md` |

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

> 🗂️ **較舊的輪次已遷出**（確切範圍以下方「📌 搬移門檻提示」為準；含 2026-06-07「通話／監控十項修復」、2026-07-10「Socket
> 通話信令回歸直接轉發」、2026-07-14「第一輪來電通知六項修復」三則早期未編號條目，以及
> 2026-08-03「文件重整」一則）。
>
> **為什麼**：本檔已成長到超過工具單次讀取上限（256 KB），使「動手前必須完整讀過本文件」這
> 條鐵律在技術上無法遵守；把最舊的輪次移出，讓主文件回落到讀取上限之內。
>
> **搬去哪裡**：`CLAUDE_call-monitor-history.md`（逐字搬移，未經改寫）。兩份鏡像位置為
> `Uban/CLAUDE_call-monitor-history.md` 與 `uban-api/CLAUDE_call-monitor-history.md`。
>
> 本節（§8 修復年表）依規則只保留**下一個接手者判斷現況所需**的輪次，不設固定輪數；其餘輪次會由舊而新遷往
> `CLAUDE_call-monitor-history.md`（逐字搬移，編號與內容不變）。目前確切從第幾輪開始接續，
> 一律以下方「📌 搬移門檻提示」為準——此處不重複標注輪次名稱，避免兩處各自漂移。
>
> 📌 **搬移門檻提示**：本文件中出現的「第 N 輪」，**N ≤ 35** 者其年表條目已遷至
> `CLAUDE_call-monitor-history.md`；**N ≥ 36** 仍在本檔 §8。此門檻會隨每輪搬移而持續調高，
> 調整時只需要更新這兩處（本節與 §8 開頭）的數字。

### 2026-08-26 — 第三十六輪：真機八項回報 —— relay 全面回退、YOLO 修復從未落地、掛斷競態

**背景**

使用者真機八項回報。最重要的一項：三輪疊加的 relay-only 優化在真機四種情境下仍讓
緊急通話連不上，整組回退；另查出上一輪記載的 YOLO 修復其實從未接上、掛斷後對方才
接聽會留下無 UI 的殭屍連線、快速登入與移機深連結仍殘留問題。以下依
[回歸回退]／[監控]／[通話]／[Session] 分類記錄。

**根因與修復**

**[回歸回退] — 本輪最重要的一項**

1. **relay-only 全面回退**（`signaling.dart` / `video_call_screen.dart`）：第三十三
   ～三十五輪三輪疊加 `iceTransportPolicy: 'relay'`、`preferRelay` 解耦、offer 前
   relay 候選檢查＋重建安全網，**真機仍然失效**：四種情境（螢幕開／關 × App 存活／
   被殺死）下雙端都進房，但其中一端 ICE 失敗，失敗端還會翻轉。
   根因是設計層面的，非實作瑕疵：兩端各自讀本機 TURN 快取、各自決定 policy，各自
   探測失敗就重建 PeerConnection 並清掉已到達的遠端候選，失敗端隨網路／Doze 狀態
   翻轉。要做對須讓兩端在 commit 前協商一致，代價與收益不成比例，因此整組回退。
   修復：整組移除（8 欄位、4 方法、`onConnect` 探測觸發、兩端可行性重建、
   `onIceGatheringState` handler），`iceTransportPolicy` 回到無條件 `'all'`。
   `preferRelay` 參數刻意保留但接到空處——它正確區分「真人通話」與「CCTV 監控」，
   刪掉會讓下次重做的人重踩一次坑。→ **G131**

**[監控]**

2. **YOLO 權重路徑修復從未落地**（`yolo_detector_service.py`）：第三十五輪記載已
   完成，實際上只有 docstring 與兩個未被引用的常數落地，`_load_model()` 本體仍是
   `YOLO("yolov8n.pt")`——部署出去的是**修復的說明，不是修復本身**。本輪真正接
   上：`YOLO_WEIGHTS_PATH`（選填）→ `os.path.abspath()` → `os.path.isfile()`
   預檢，不存在就設 `_load_error` 並 return，絕不呼叫 `YOLO(...)`。
   ⚠️ 上一輪「實測」在 `uban-api/`（權重檔所在目錄）執行，舊相對路徑在那裡本來就
   會成功，測試設計上不可能失敗；換一個工作目錄立刻看到連網下載。→ **G132**

3. **載入失敗原因送到監控機螢幕**（`routers/alert.py` / `api_service.dart` /
   `elder_screen.dart`）：`_load_error` 先前只寫伺服器日誌，使用者碰不到，連續三
   輪卡在「知道失敗、不知道為什麼」。`POST /api/cctv/frame` 的 `yolo_unavailable`
   分支一併回傳，前端 `CctvPushResult` 顯示在 CCTV 畫面。未分類的 `str(e)` 限長
   200 字元、壓單行、redact 帳密；完整原文仍寫伺服器日誌。

**[通話]**

4. **掛斷後對方才接聽：後端從未阻斷**（`socket_app.py` / `signaling.dart`）：網路
   慢導致通知遲到，撥話端掛斷、收話端才接聽並重撥後，**只有收話端進房，卻看得到
   撥話端無聲的視訊**。缺口：(a) `on_cancel_call` 有 `_mark_call_cancelled`，
   **`on_end_call` 沒有**；(b) **`on_call_accept` 從未查詢
   `_cancelled_call_ids`**。修復：`on_end_call` 補標記；`on_call_accept` 轉發前查
   驗，以 `call-busy`（`reason: 'cancelled'`）回覆**收話端**。已查證
   offer/answer/ice-candidate 不帶 `callId`，擋住 `call-accept` 即完整收斂點。
   → **G133**

5. **無 UI 的 PeerConnection 洩漏**（`signaling.dart`）：真因是 `call-accept`
   fallback 在 `onCallAcceptedByRemote` 為 null（畫面已 dispose）時仍靜默呼叫
   `createOffer()`，建立無畫面的連線；已補上 `_invalidCallIds` 查驗，並為
   `_closePeerConnection()` 加 try/catch＋`identical()` 守衛，避免中途拋出留下
   永遠半拆解的連線。→ **G134**

**[Session]**

6. **快速登入仍然遺失**（`session_manager.dart`）：第三十四／三十五輪已讓
   `_handleLogout`／`_exitCCTVMode` 傳 `preserveQuickLogin: true`，症狀依舊。稽核
   未能指認具體 writer，改採涵蓋整類問題的修法：`releaseIfBound()` 改傳
   `preserveQuickLogin: true`——保險絲不該重新決定上游政策。已查證不影響家屬端強
   制解綁（`handleForceLogout` 走自己的手動清除，不經過 `releaseIfBound()`）。

7. **移機助手連結卡在身分選擇頁**（`main.dart`）：`/recovery` 改 `intent://` 後
   App 確實被喚起，但復原碼未被處理——確認對話框的 `Future.delayed(300ms)` 被同
   時間 Splash 的 `pushAndRemoveUntil` 連路由一起移除。修復：復原碼暫存，200ms
   輪詢等 `splashActive` 轉 false 才消費；每次輪詢都 latch，看過待接來電就放棄復
   原碼（漏接來電比復原提示遲到嚴重）。

8. **`monitor_pairing_screen.dart` 導航堆疊殘留**（第三十一輪漏掉的同型呼叫點）：
   配對成功後 `pushReplacement` 把 `IdentificationScreen` 留在底下，改用
   `pushAndRemoveUntil`。

**尚未收斂**

- 初次通話 WebRTC 連不上、第二通才正常（延續自第三十五輪）：relay 與 TURN 探測已
  移除，症狀是否消失待實機確認；剩餘假設為 `_elderSocketId` 由 2.5 秒輪詢填入，
  太早撥出可能指向 null 或舊 sid。
- 長輩端背景存活時，緊急通話只喚醒 App、不進視訊房間（延續自第三十四輪）。

**新增護欄**

本輪新增 **G131–G134**（前端 G131、G134；跨端 G132；後端 G133；條文見 §7.1／
§7.2）。§7 開頭護欄總數同步更新為 **134**。

**驗證**

- `flutter analyze lib` — **0 error**（141 項 info/warning 為既有技術債）。
- `python -m py_compile services/socket_app.py routers/alert.py yolo_detector_service.py`
  — exit 0。
- `python -c "from main import app; print('IMPORT_OK')"` — **IMPORT_OK**。
- `pytest tests/test_call_signaling.py -q` — **17 passed**。
- YOLO 權重載入從 `D:\114project`（非 `uban-api`）執行 — `loaded=True
  err=None`，輸出無任何「Downloading」。

⚠️ 以上為靜態關卡與開發機測試，緊急通話四種情境與監控機畫面狀態仍須實機驗收。連
接／跳轉語意變更的 graphify 同步狀態由對應的實作子代理負責，不在本次文件任務範圍
內。

---

### 2026-08-31 — 第三十七輪：真機五項回報 —— YOLO 訊息說謊、權限對話框被隱私權畫面換掉、force-logout 清掉快速登入

**背景**

使用者真機五項回報，外加一項延續自第三十四輪、本輪未處理的舊懸案。其中兩項是
「顯示的錯誤原因跟真正根因對不上」的診斷類回報（YOLO 載入失敗訊息、監控清單
高光）；一項（權限對話框被隱私權畫面換掉）牽出同一根因的另一個症狀（第一次使用
App 時雙端 WebRTC 可能連不上），故合併記錄；一項（force-logout 清掉快速登入）
是使用者第三次回報同一症狀、前兩輪（第三十四、三十五輪）都沒能根治的舊案。以下
依 [監控]／[啟動]／[通話]／[Session] 分類記錄。

**根因與修復**

1. **[監控] YOLO 載入失敗訊息在說謊**（`yolo_detector_service.py`、`Dockerfile`、
   `routers/alert.py`）：使用者監控機畫面顯示「偵測器未載入 / yolo_unavailable /
   **ultralytics 未安裝**」，但 `requirements.txt:72` **確實有**
   `ultralytics>=8.4.105`。根因是 `_load_model()` 的 `except ImportError:` 把例
   外物件整個丟掉，硬寫固定字串 `'ultralytics 未安裝'`。`requirements.txt` 自己
   的註解（第 60-61 行）就寫著 ultralytics 硬相依 opencv-python(>=4.6)；
   `from ultralytics import YOLO` 會連帶 `import cv2`，非 headless 的 opencv 需
   要系統庫 `libGL.so.1`，pytorch 基底映像沒有 → 拋的**也是** `ImportError` →
   被同一個 except 接住、標成「套件沒裝」。**套件裝了，是它的相依 import 失
   敗。** 這與第三十五／三十六輪的 CUDA `.numpy()` 是**同一種失敗模式**：例外
   處理器把失敗原因標錯，害診斷連續多輪走錯方向。
   修復：(a) `except ImportError as e` → `self._load_error = f'ultralytics 匯
   入失敗: {e}'`，保留原始訊息；(b) `Dockerfile` 在 pip 安裝層之前新增獨立的
   一層 `apt-get install libgl1 libglib2.0-0`（純新增，既有的
   `sed -i -E '/torch|.../d'` 與 pip 安裝順序逐字未動，那行有第十九輪記載的
   歷史原因，不可調整）；(c) `routers/alert.py::_sanitize_load_error()` 的模
   組註解原本聲稱「ImportError 分支是固定字串、內容受我們控制、安全」，被 (a)
   推翻，一併更正。
   **刻意不做**：沒有 `pip uninstall opencv-python` 或強制重裝 headless 版
   ——ultralytics 對它有硬相依，移除可能讓 pip 相依檢查失敗而中斷建置，
   `deploy.yml` 的 `set -e` 會讓部署中止、舊容器繼續服務舊程式碼（第十九輪記
   載過的根因）。裝系統庫是純加法。→ **G135**

2. **[啟動] 隱私權畫面把權限對話框整個換掉**（`main.dart`、
   `privacy_policy_screen.dart`）：使用者回報「初始安裝的權限開啟警告被跳出的
   隱私權覆蓋」。根因：`main.dart` 啟動的 `addPostFrameCallback` 原本無條件呼
   叫 `VideoCallPermissionService.requestOnFirstUse(context)`，該服務在關鍵權
   限缺失時會 `showDialog`（`barrierDismissible: false`）。同時
   `splash_screen.dart::_goNext()` 呼叫 `_replaceWith(PrivacyPolicyScreen())`，
   而 `_replaceWith` 用的是 **`Navigator.pushReplacement`——它移除的是導航堆
   疊最上層那個 route**，正好就是那個對話框。`await showDialog` 靜默返回、不
   拋任何例外，程式碼完全無感。順序本身也是錯的：在使用者看到隱私權政策**之
   前**就先跳系統權限請求。
   修復：`main.dart` 改成只在「已同意隱私權政策」時才請求（讀 prefs 失敗一律
   略過，保守）；`privacy_policy_screen.dart` 在寫入同意狀態後、
   `pushAndRemoveUntil` **之前** `await requestOnFirstUse(context)`，await 完
   成後重新檢查 `mounted` 才導航。→ **G136**

3. **[通話] 第一次使用 App 時雙端 WebRTC 連不上**（與第 2 項同一根因）：使用者
   回報「長輩端發起通話時，第一次使用 App 時雙端的 WebRTC 可能會無法連線」。
   根因就是第 2 項：首次使用拿不到相機／麥克風 → `openUserMedia` 沒有軌道 →
   WebRTC 連不上；第二次啟動權限已在才正常。**為什麼是「雙端」**：家屬端
   `video_call_screen.dart` **完全沒有自己請求權限**，唯一來源就是被換掉的那
   個 `requestOnFirstUse`；長輩端 `elder_screen.dart:436` 雖有
   `_checkPermissions()`，但**沒有 `await`**（fire-and-forget），`initState`
   繼續往下跑去開媒體，與系統權限對話框賽跑。「可能」正是因為這是競態，取決
   於使用者多快按下允許。
   **本輪刻意不動長輩端那個未 await 的呼叫**（記為已知潛在風險）：
   `elder_screen` 是 🔴 極高風險、冷啟動接聽路徑有五層兜底，在 `initState` 加
   `await` 會擋住整條鏈，正是本專案反覆踩到的單點修改。修好第 2 項後，權限在
   隱私權同意當下就取得，任何通話發生時 `_checkPermissions()` 已是 no-op，競
   態不會觸發。若日後有證據顯示它仍會觸發，再處理。→ 併入 **G136**

4. **[Session] 監控機退出後失去快速登入**（`socket_app.py`、`main.dart`、
   `signaling.dart`）：使用者第三次回報：「由長輩通訊帳號登出轉換成監控設
   備，再轉換回長輩通訊帳號時已無先前長輩帳號的 session 留存」（前兩輪即第
   三十四、三十五輪都動過同類問題，症狀依舊）。根因是一個**自造的迴圈**：
   `elder_screen.dart::_exitCCTVMode` 先呼叫 `ApiService.deleteMonitorDevice(...)`、
   **之後**才 `SessionManager.releaseSession(preserveQuickLogin: true)`（順序
   刻意，有註解記載）。後端 `on_delete_device` 收到刪除請求後，**對這台裝置
   自己送出 force-logout**（Socket + FCM 雙路），而 `main.dart` 兩個
   force-logout 處理器的清除清單裡**包含 `last_elder_*` 四個鍵**。裝置刻意用
   `preserveQuickLogin: true` 保住的鍵，被自己送出的刪除請求繞一圈回來清掉。
   修復：後端 `on_delete_device` 的兩個送出點都加 `reason: 'device-removed'`
   （`routers/pairing.py` 的解綁路徑早已帶 `reason: 'elder-unbound'`，未
   動）；前端 `Signaling.onForceLogout` 簽章改為
   `void Function({String? reason})`、Socket handler 加 `data is Map` 防呆解
   析 reason；`handleForceLogout({String? reason})` 與背景 FCM handler 都改
   成**只有 `reason == 'elder-unbound'` 才清 `last_elder_*`**。
   **判斷方向刻意保守**：reason 讀不到／空／未知值一律**保留**快速登入鍵。理
   由：這四個鍵只是「上次登入的長輩是誰」的便利記憶，清掉會造成實際回報的困
   擾；`elder-unbound` 是唯一明確該清的情境。session 本體（`caregiver_id`／
   `access_token`／`user_role` 等）**不受影響，一律照舊全清**。→ **G137**

5. **[監控] 監控機列表的兩種高光 —— 本輪零改動**（`family_interaction_tab.dart`）：
   使用者要求「人在監控畫面時給該監控機高光」與「跌倒警報要有紅色緊急高
   光」。查證結果：`_buildMonitorDeviceCard`（約 line 1700-1780）**兩種高光
   都已完整實作且接線正確**——`hasActiveAlert` → 卡片底色 `0xFF3F1D1D` 深紅
   ＋紅底警報徽章；`isElderPresent` → 底色 `0xFF083344` 青色＋「長輩在此」徽
   章；三態優先序為 警報 > 目前所在 > 一般。`activeAlerts` 有從
   `family_main_screen.dart`（`_handleCctvAlert` 寫入）傳入，`device_id` /
   `deviceId` 兩種欄位名都有處理。**這兩項是被 YOLO 沒跑起來卡住的**
   （`present` 與警報都來自偵測結果），不是 UI 缺失。ultralytics 一旦 import
   成功即會亮。**下一輪若使用者仍回報看不到高光，先確認 YOLO 是否已真的在
   跑，不要去改那個檔案。**

**尚未收斂**

- 長輩端 App **背景存活**時收到緊急通話，只會喚醒 App 而**不會進入房間**。第
  三十四輪查出但未解，本輪未處理。

**新增護欄**

本輪新增 **G135–G137**（後端 G135；前端 G136；跨端 G137；條文見 §7.1／
§7.2）。§7 開頭護欄總數同步更新為 **137**。

**驗證**

- 程式碼由實作子代理完成並驗收通過；文件代理另行以 `grep`／`Read` 對照原始碼
  逐項核對五項回報的關鍵事實，包括 `yolo_detector_service.py::_load_model()`
  的 `except ImportError as e` 與 `f'ultralytics 匯入失敗: {e}'`、
  `Dockerfile` 新增的 `libgl1 libglib2.0-0` 安裝層、`main.dart` 改為讀取隱私
  權同意狀態後才呼叫 `requestOnFirstUse`、`privacy_policy_screen.dart` 在
  `pushAndRemoveUntil` 前 `await` 該呼叫、`socket_app.py::on_delete_device`
  與 `routers/pairing.py` 的 `force-logout` emit 均已帶上對應的 `reason`、
  `signaling.dart::onForceLogout` 簽章與 `main.dart::handleForceLogout` 的
  `reason == 'elder-unbound'` 判斷、
  `family_interaction_tab.dart::_buildMonitorDeviceCard` 的 `hasActiveAlert`
  ／`isElderPresent` 高光邏輯，均確認存在且與本輪敘述一致。
- `flutter analyze lib` — **0 error**（144 項 info/warning，較上一輪 141 項
  略增，屬既有技術債變動，非本輪新增邏輯錯誤）。
- 後端 `py_compile`／`pytest tests/test_call_signaling.py`／
  `flutter build apk` 等完整驗收由實作子代理於各自任務中完成，不在本次文件
  任務重跑範圍內。

連接／跳轉語意變更的 graphify 同步狀態由對應的實作子代理負責，不在本次文件任
務範圍內。

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
