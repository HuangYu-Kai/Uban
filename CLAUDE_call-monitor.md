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
| `lib/screens/elder_screen.dart` | **長輩端**通話畫面（含 CCTV 模式） | `_makeCall()`、`_checkPendingAcceptedCall()`、`_toggleCamera`、`_toggleMute`、`_switchCamera`、`_hangUp`、`_exitCCTVMode`、`_activeCallId`、`friendCallTargetElderId`（建構子參數，非 null 進入好友通話模式：房號組對方的、role 送 `'friend'`，`dispose()` 觸發回房，見 G156／G157） | 🔴 極高 |
| `lib/screens/elder_home_screen.dart` | 長輩主畫面；APP 內來電 dialog | `_onPendingCallChanged`、`_restoreSignalingCallbacks`、`_requestPermissions`（全螢幕權限引導） | 🔴 高 |
| `lib/screens/family_main_screen.dart` | 家屬主畫面；APP 內來電 dialog、裝置上下線、**CCTV 跌倒警報呈現** | `_checkPendingAcceptedCall`、`onElderDevicesUpdate`（2.5s 單向確認，見 G40）、`_isDeviceOnline`、`_knownAlertKeys`、`_cctvAlertDialogOpen`、`_alertTts`、`_offlineConfirmTimer` | 🔴 高 |
| `lib/screens/splash_screen.dart` | 冷啟動導航；接聽兜底最終防線 | `_navigateToNext()`、`_navigateFamilyHome()`、`_isPendingRoleReversed()` | 🔴 高 |
| `lib/screens/friends_screen.dart` | **長輩端撥出入口**（`isVideoCall` 的唯一來源）。現有**兩條**撥出路徑：`_startCall` 走自己的房（撥給家屬）、`_startFriendCall` 走對方的房（撥給好友）——後者會把 `ElderScreen` 導入好友通話模式，房間解析錯誤時的後果見 G157 | `_startCall(friendName, {required bool isVideo})`、`_startFriendCall(friendElderId, friendName, {required bool isVideo})` | 🟠 中高 |
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

> **`join` 的 `role` 欄位（2026-09-04 第四十二輪新增 `friend`）**——已知值：`elder`
> （長輩本人）／`family`（家屬）／`friend`（長輩↔長輩好友通話的**發起端**角色）。
> A 以 `role='friend'` 加入 B 的 `comm_elder_<B的elder_id>` 房——`sio.enter_room`
> 不會離開原本的房，故 A 這條連線同時存在於**兩個**房間。`friend` 只允許進
> `comm_elder_*`，`monitor_elder_*` 一律拒絕（見護欄 **G150**）。
> `friend` **不計入**裝置清單（`_get_elder_devices_list` 等函式一律白名單式判斷
> `role in ('elder', 'family', 'listener', 'family-monitor')`，`friend` 不在其中）；
> 也不計入監控機／IP 額度——額度函式只看 `deviceMode`，`friend` session 依護欄
> **G154** 固定送 `deviceMode='comm'`，天然不落入監控機計數。

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
| `elder-zone-update` | S→C | `elder_id`、`device_id`、`from_zone`、`to_zone`、`entered_at`、`previous_dwell_seconds`、`timestamp`、**`presence_stale_after_ms`（毫秒，2026-09-01 第三十九輪新增，見 §6.12）** | `socket_app.py::_broadcast_elder_zone_update` | **2026-08-18 第二十六輪新增**，第二十七輪轉正式（見 §6.12）。`IPS_ENABLED` 現為 kill-switch，預設開啟。**推播頻率 2026-09-01 起依會員層級節流**（`transition` 有值時仍立即推播，不受節流影響），見護欄 **G95**／**G97**／**G140**／**G141** |

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
            穩定切換（`transition` 非 `None`）一律立即以 `elder-zone-update` 廣播；純
            presence 心跳（`transition` 為 `None`）**2026-09-01 起依會員層級節流**才送，
            見下方「Socket 事件」與護欄 **G140**／**G141**
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
⚠️ **2026-08-25 起廣播頻率不再綁定「穩定切換」，且不分是否校準**：只要偵測到人就會嘗試
廣播；`transition` 欄位大多數時候是 `None`，只有真的發生穩定切換才非空。🚫 **不要**假設
收到 `elder-zone-update` 就代表剛發生區域切換——要看 `transition` 是否有值，不能只看
「有沒有收到事件」。唯一仍保留「只在切換時才做」語意的是 **DB 寫入**；未校準裝置的
`transition` 永遠是 `None`，因此永遠不寫 DB，但仍持續收到廣播。
⚠️ **2026-09-01 第三十九輪起：「偵測」與「往外推播」的頻率分家**——偵測仍是每 2 秒一次
（推幀節奏不變），但**推播**只在 `transition` 非 `None` 時立即送；`transition` 為
`None`（純 presence 心跳，佔絕大多數）時改依會員層級節流（`_presence_broadcast_due()`：
免費 15s／黃金 7s／鑽石 3s），**不再是固定約 2 秒**。payload 新增
`presence_stale_after_ms`（節流間隔 ×2、下限 10 秒，`_presence_stale_after_ms()`），
告訴前端這筆資料多久沒更新算過期；前端 `_zonePresenceStaleWindow` 改讀此欄位，缺漏時
退回 10 秒（向後相容）。後端自己判斷在場用的 `PRESENCE_STALE_SECONDS`／`last_seen`
不受節流影響，繼續每幀更新，見護欄 **G140**／**G141**。

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

## 7. 護欄

> 🚨 **完整護欄清單（G1–G159）已於 2026-09-04 獨立成檔**：
> **[`CLAUDE_call-monitor-guardrails.md`](CLAUDE_call-monitor-guardrails.md)**
>
> 遷出原因：主檔逼近 262,144 bytes 的單次讀取上限，一旦超過，子代理就無法一次讀完，
> 而「動手前必須完整讀過本文件」是本子系統第一鐵律——文件過大會讓這條鐵律**在技術上無法遵守**。
> §7 當時佔主檔 55%，是唯一夠大且可獨立閱讀的區塊。
>
> **動到通話／監控程式碼前，護欄檔與本檔同樣必讀**，兩者是一組的。
> 護欄檔含：§7.1 前端護欄、§7.2 後端護欄、§7.3 已知的文件錯誤（以程式碼為準）、
> §7.4 已知且刻意保留的安全缺口。

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
> 一律以下方「📌 搬移門檻提示」為準——此處不重複標注輪次名稱，避免重複維護導致分歧。
>
> 📌 **搬移門檻提示**：本文件中出現的「第 N 輪」，**N ≤ 40** 者其年表條目已遷至
> `CLAUDE_call-monitor-history.md`；**N ≥ 41** 仍在本檔 §8。此門檻會隨每輪搬移而持續調高，
> 調整時只需要更新本處（§8 開頭）的數字。

### 2026-09-04 — 第四十二輪：假配對碼、護欄獨立成檔、長輩↔長輩好友通話

**背景**

延續第四十一輪「仍然開著」清單的兩項：item 1 的 `padLeft` 猜測配對碼、item 2 的
「好友之間無法互相撥打電話」。另外處理主檔逼近讀取上限的問題（§7 護欄獨立成檔）。

**項目 A（前端）假配對碼**

`elder_profile_tab.dart::_showFamilyPairingDialog` 原本用
`widget.userId.toString().padLeft(4, '0')` 當配對碼、塞進自製的
`UBAN_PAIR:<userId>:<code>` QR 格式——第四十一輪已記錄過這是猜測值，但本輪查證後發現
問題比原先以為的更嚴重：
- `elder_profile.elder_id`（varchar(4) PK，配對用）與 `user_id`（int）是**兩個獨立欄
  位**，`padLeft` 出來的數字跟真正的配對碼毫無關聯；
- `UBAN_PAIR:` 這個 QR 格式**全專案沒有任何地方消費**；家屬端 `QrScannerScreen` 掃到
  的是裸字串，直接當配對碼送出；
- 因此不只是「輸入會失敗」——那個猜測值**還可能誤撞到別人正在使用中的真配對碼**。

修法：改走 `ApiService.requestPairingCode()`（照抄
`elder_pairing_display_screen.dart::_requestNewCode()`），QR 改成裸碼（無前綴），顯示
`expires_in_seconds` 倒數。失敗五種情況（`snapshot.hasError`／`result == null`／
`result['status'] == 'error'`／`code == null`／`code.isEmpty`）一律顯示白話錯誤＋
「重新取得配對碼」鍵，**絕不用猜測值兜底**。對話框加了一句說明區分「給家人綁定用的
臨時配對碼」與「好友 ID」——兩者被混為一談正是本 bug 的根源。
→ 新護欄 **G158**

**項目 B — §7 護欄獨立成檔**

新增 `CLAUDE_call-monitor-guardrails.md`（兩份鏡像，G1–G149，含 §7.1/§7.2/§7.3/§7.4）；
主檔 261,793 → 116,954 bytes，§7 改為指向該檔的指標區塊。

遷出原因：主檔逼近 262,144 bytes 的單次讀取上限，一旦超過，子代理就無法一次讀完，而
「動手前必須完整讀過本文件」是本子系統第一鐵律——文件過大會讓這條鐵律**在技術上無法
遵守**。§7 當時佔主檔 55%。

🔴 **搬移過程中 G2 的禁令句一度被漏掉**：「不可改回直接強推單一路徑：會重現『接聽後回
主頁、不進通話房』」這句在驗收比對時發現漏搬、已補回。記這一筆是因為少了那句，G2 就
只剩「描述程式碼做什麼」，失去「不可改回什麼」的禁令——那句才是它之所以是護欄的理由；
下一次任何文件搬移都要對這種「說明句」與「禁令句」分開核對，不能只比對標題還在不在。

§8 開頭的「搬移門檻提示」原本寫「這兩處（本節與 §8 開頭）」，§7 那份隨遷出消失後已改
為單數說法。三份 `CLAUDE.md` 的指標同步更新（根目錄、`Uban/CLAUDE.md`、
`uban-api/CLAUDE.md`）。

**項目 C／D — 長輩↔長輩好友通話**

**後端**（`services/socket_app.py`）：新增 `friend` 角色。A 以 `role='friend'` 加入 B 的
`comm_elder_<B>` 房（`sio.enter_room` 不會離開原本的房，A 因此同時在兩個房裡），完全
重用既有 `call-request`／`offer`／`answer`／`candidate`／`end-call` 事件，**沒有新增
任何 Socket 事件**。

- `_verify_room_access` 新增 case 3（`role == 'friend'`），排在既有 case 1（本人
  elder）／case 2（family 關係）之後，不影響那兩條。
- **comm-only 防線**：`_parse_room_id(room)` 得到 `room_mode != 'comm'` 即拒絕，且在
  查好友關係**之前**就短路——好友關係沒有理由延伸出監控房的存取權。
- 解析呼叫端自己的 elder_id：`SELECT user_id, elder_id FROM elder_profile WHERE
  user_id = %s OR elder_id = %s`（沿用既有函式對 `user_id` 雙格式容忍的寫法）；
  `caller_elder_id != elder_id_from_room` 才查關係（擋自我配對）。
- 正規化排序用 `routers.friend._normalize_pair` 的**區域 import**（比照
  `_get_monitor_device_limit` 匯入 `routers.subscription` 的既有模式），避免模組頂層
  雙向匯入，也避免兩處各寫一套排序而靜默查到不同的 `(low, high)`。
- 只有 `status == 'accepted'` 放行；pending／查無關係／解析失敗／任何 DB 例外，一律
  `(False, None, None)`——**fail-closed**。
- 🚨 **`target_role` 公式是本輪根因**：`on_call_request`（:2005）與 `on_cancel_call`
  （:2288）改成 `'elder' if sender_role in ('family', 'friend') else 'family'`。原公式
  `'elder' if sender_role == 'family' else 'family'` 會讓 `sender_role == 'friend'`
  落進 `else`，算出 `target_role='family'`——A 打給好友 B，後端會去找 **B 的家屬**當
  接收方。兩處必須一起改：只改 call-request 會變成「打得出去但取消時查錯對象」，收話
  端的來電通知關不掉（第四十輪修過的同款症狀）。`on_cancel_call` 原有的多餘三元式一併
  化簡（語意不變）。
- `on_emergency_call`（:2363）的公式**刻意不改**，只加註解——好友之間沒有緊急通話
  入口。
- `_get_caller_name` 新增 `elif sender_role == 'friend'` 分支。⚠️ **陷阱**：不能沿用
  elder 分支的 `_parse_room_id(room)`——elder 分支能反解是因為 elder 在**自己的房間**
  發話，但好友通話的 room 是**被叫端 B** 的房間，照抄會把**被叫端自己的名字當成來電
  者顯示給被叫端本人看**。改用 `caller_user_id` 反查 `elder_profile WHERE user_id = %s`
  才是真正的呼叫端。
- 顯示名稱 fallback 改為 `"長輩" if sender_role in ('elder', 'friend') else "家人"`
  （原本 friend 會顯示「家人」，B 會誤以為是家人打來的）；`on_emergency_call` 那處刻意
  沒改。

已查證 `friend` **不會**被誤算成裝置（全部是白名單式角色判斷，不需要改動）：
`_get_elder_devices_list`（三個階段）、`_broadcast_elder_devices_update`、
`_broadcast_elder_zone_update`、`on_client_state`、`has_comm_elder_device` 都是
`role == 'elder'` 或 `role in ('family','listener','family-monitor')`；
`_count_active_monitor_devices_for_elder`、`_count_monitor_devices_for_ip`、
`_cleanup_monitor_ip_on_disconnect` 只看 `deviceMode` 完全不看 role；`on_join` 的監控
／IP 上限那段是 `device_mode=='monitor' and role=='elder'` 雙條件。

**前端**（`elder_screen.dart` 6 處、`friends_screen.dart` 3 處）：
- `ElderScreen` 新增 `final String? friendCallTargetElderId;`（預設 `null`；**`null`
  時行為零回歸**）；`_formattedRoomId` 條件式非 null 時組**對方的**
  `comm_elder_<對方>`；`connect()` 的 role 條件式 `'friend'`／`'elder'`，`deviceMode`
  維持 `'comm'`。
- 🚨 **`sendCallRequest`（:1587）與 `sendCancelCall`（:1657）送出的 `role` 欄位也必須
  條件式**——原本硬寫 `'elder'`，後端公式就會算出 `target_role='family'`，來電被送去
  對方的家屬。這是與後端 target_role 公式**同一個根因的前端半邊**，漏改任何一邊都等於
  沒修。
- `dispose()` 加回房邏輯：`leaveRoom(對方房)` → `connect(自己的房, 'elder',
  deviceMode: 'comm')`。選 `dispose()` 是因為它是所有離場路徑（掛斷／對方掛斷／忙線
  ／斷線／逾時選離開）的唯一共同匯合點；「重新撥打」不會觸發它（同一個 State 原地重
  試，房間不變，本來就該如此）。
- `friends_screen.dart` 新增 `_startFriendCall(friendElderId, friendName, {required
  isVideo})`，房間解析走 `widget.roomId` → prefs `elder_room_id`，**絕不退回
  `widget.userId`**（那是 caregiver_id，本專案踩過的坑）；好友卡片加
  `Icons.videocam_rounded` 的 IconButton，排在「解除好友」之前（正面動作優先於破壞性
  動作）。
- `:329-335` 那句「撥打電話：刻意不放，既有通話只支援長輩↔家屬」的過時註解已改寫成
  現況說明。
→ 新護欄 **G150–G157**

**項目 E — 長輩端首頁日期卡片在大字級下溢位（鐵律 #14 例行檢查發現）**

⚠️ **這個檔案不是通話／監控檔**（`elder_home_tab.dart` 不在 §2 檔案地圖內）——之所以記在
這裡，是因為溢位判準護欄 **G142** 就在護欄檔中，本輪的發現直接延伸自它，新護欄 **G159**
也因此收在同一份文件。

**檔案**：`Uban/mobile_app/lib/screens/elder_tabs/elder_home_tab.dart`

**怎麼發現的**：鐵律 #14 規定每輪必須靜態核對雙端 8 個標籤主介面的溢位。本輪掃描 8 個畫
面得到 19 處靜態可疑，逐一評估後判定只有這一處是真風險——其餘多是字面常數短標籤且同列
有 `Spacer()` 吸收。

**症狀**：長輩把系統字體調大時，首頁最顯眼的日期卡片會出現黃黑斜紋溢位條。

**根因**：
- 該 `Row` 左欄（國曆 44pt + 星期 26pt）與右欄（農曆 24pt + 節氣 22pt）**都沒有**
  `Flexible`／`Expanded`。
- 中間的 `Spacer()` **只吸收多餘空間，內容塞滿時提供零緩衝**——這是誤以為「有 Spacer
  就安全」的典型陷阱。
- **全專案沒有任何 `textScaler`／`textScaleFactor` 覆寫**（`lib/` 全目錄 grep 零命中），
  App 完全跟隨系統字體大小。而會把字體調大的正是這個 App 的長輩使用者。
- 可用寬度比初估更窄：除了卡片自身的 `EdgeInsets.symmetric(horizontal: 24)`，外層
  `_buildElderDateCard()` 還包了一層 `Padding(20, 0, 20, 130)`——320dp 螢幕實際只有
  **232px**。
- 農曆字串最長是 **5 碼**不是 4 碼：`lunar-1.7.8` 的 `getMonthInChinese()` 遇**閏月**會回
  「闰」+ 月名（2 碼），加上 `getDayInChinese()` 固定 2 碼與「月」字，閏年會出現
  「闰腊月廿九」。

**修復**：把該 `Row` 從 `_buildElderDateCard()` 抽成獨立的 `ElderDateSummaryRow`
（`StatelessWidget`，同檔案末尾），內部用 `LayoutBuilder` 取得可用寬度、`TextPainter`
依當下 `TextScaler` **精確量測**左右兩欄各自需要的寬度：
- **塞得下** → 回傳與抽出前**完全相同**的 `Row + Spacer + Column`（同一段程式碼路徑，
  1.0 倍外觀零改變是結構保證，不是目測）。
- **塞不下** → `FittedBox(fit: BoxFit.scaleDown)` 包住同樣兩欄整體等比縮小，**不裁切、
  不用 ellipsis**（日期被截成「12月3…」比溢位更糟）。
- 寬度無界時（`!available.isFinite`）走「塞得下」分支——`FittedBox` 在無界寬度下沒有
  意義。

**為什麼不用 `Flexible` 配固定 flex 比例**：flex 是**先分配空間、再看內容**，與各欄實際
需要多寬無關。比例沒抓準會出現「其實兩欄相加塞得下，卻因分配錯誤把寬的那欄壓縮」，違反
「1.0 倍外觀不得改變」。而且 `Spacer()` 本身是 `Expanded(flex: 1)`，若把兩欄也包成
`Flexible(flex: 1)`，三者會**各分到 1/3 寬度**，左欄立刻變形。量測式判斷沒有這個問題，
因為「塞不塞得下」與「要不要縮小」用的是同一份即時量測結果。

**踩到的編譯陷阱**：這個檔案已 `import 'package:intl/intl.dart'`，intl 自己有一個同名但
沒有 `.ltr` 的 `TextDirection` class，裸寫 `TextDirection.ltr` 會撞名編譯失敗。改用
`Directionality.of(context)`，順帶更精確地跟隨 ambient 方向。

**測試**：新增 `Uban/mobile_app/test/screens/elder_tabs/elder_home_tab_date_card_test.dart`
（8 個測試）——320dp × {1.0, 1.3, 2.0} 倍字級 × {5 碼閏月農曆, 4 碼平年農曆} 共 6 個溢位
案例，加上兩個結構性證明：650dp 寬度充足時用 `find.byType` 確認**完全沒進** `FittedBox`
分支（比比對像素更直接地證明外觀零改變）、2.0 倍確實改走 `FittedBox` 且沒有任何 `Text`
用 ellipsis。

**紅綠驗證**（本輪特別要求，因為靜態目視不是有效驗證）：把 `ElderDateSummaryRow.build()`
內容暫時換回舊版後跑測試，**8 個裡 7 個紅**，全是 `RenderFlex overflowed by N pixels`——
320dp/1.0x 溢位 131~155px、1.3x 溢位 239~270px、2.0x 溢位 491~539px。復原後 8 個全綠，
全專案 44 個測試亦全過。

⚠️ **測量環境的但書**：測試沙箱無網路，`google_fonts` 抓不到 Noto Sans TC 而退回系統
fallback 字型，每個 CJK 字元量出來是 1 em（「豆腐塊」寬度），比正式環境的 Noto Sans TC
**更寬**。所以「1.0 倍就溢位」這個門檻**不能直接套用到正式環境**。但這不影響修法的正確
性——修法是**執行期量測**，會自動適應實際使用的字型；而測試證明的是「不論字型多寬都不會
溢位」，比固定門檻更強。

→ 新護欄 **G159**

**查證但未改動的結論（供下一輪參考，不要誤「清理」）**

1. **friend 的 FCM token 會出現在對方房裡，但無害**：`on_join` 的 token 登記
   `if fcm_token:` 沒有角色守衛，A 以 friend 身分加入 B 的房時，A 的 token 會被寫進
   `room_fcm_tokens[comm_elder_B]` 及 DB（`role='friend'`）。看起來像隱患，但三層取用
   全部濾角色：記憶體房名位置鍵 `if info.get('role') == 'elder':`、記憶體 user_id 內
   容鍵補掃 `if info.get('role') != 'elder': continue`、DB Layer C 的 SQL
   `WHERE role = 'elder' AND (...)`。`_purge_stale_reverse_mode_token` 也有
   `if role == 'elder':` 守門，friend 不會誤刪自己房間的登記。**看到 friend 的 token
   躺在別人房裡不要清理它**，清了不會讓任何事變好，可能弄壞上面這幾條路徑。
2. **回房 `connect()` 不帶 `fcmToken` 是安全的**：`elder_screen.dart` dispose() 回房呼
   叫 `connect(ownRoomId, 'elder', ...)` 沒有帶 `fcmToken`（它是 `_initElderMode()` 的
   區域變數，dispose() 取不到），但 `signaling.dart::_asyncJoin` 有自動補抓
   （`effectiveToken ??= await FirebaseMessaging.instance.getToken()`），送到後端的
   join 仍帶著真 token。**不需要為此把 fcmToken 存成 state 欄位**。
3. **斷線重連在通話中與通話後都正確**：`reconnect()`（signaling.dart :315-324）與
   `onConnect` handler（:370-393）的 rejoin 都讀 `_currentRoomId`／`_role` 的**當下
   instance 欄位**（G103 既有模式），好友通話進行中斷線會正確回到對方的房，結束後會
   正確回到自己的房。殘留窗口：導航觸發到 `dispose()` 執行之間那一瞬間斷線，會短暫加
   回對方的房——判斷為可接受（比 G102 既有窗口更短），未處理。

**新增護欄**

本輪新增 **G150–G159**（後端 G150–G153、G155；跨端 G154；前端 G156–G159；條文見
§7.1／§7.2）。護欄檔（`CLAUDE_call-monitor-guardrails.md`）開頭護欄總數同步更新為
**159**。

**驗證**

- 後端：`pytest tests/test_call_signaling.py tests/test_friend.py -q` — **54 passed**
  （基準 38，新增 16 條）。
- 前端：`flutter analyze lib` — **0 error / 34 warning / 120 info**（與基準一致，兩個
  改動檔零新增問題）；`flutter build apk --debug` — 成功。

⚠️ **graphify 尚未同步**：本輪動到 Socket 授權邏輯（`_verify_room_access` 新增 friend
case）、`target_role` 路由公式、配對碼取得流程、`friends_screen.dart` 新增撥打入口，
依鐵律 #10 屬於「連接／跳轉」語意變更，理應同步 `Uban/graphify-out/` 與
`uban-api/graphify-out/`；查證 `graphify-out/` 的 `GRAPH_REPORT.md` 最後修改時間仍停
在 2026-08-30／31，晚於本輪改動的 `socket_app.py`／`elder_screen.dart`
（2026-09-04），**尚未執行 `/graphify . --update`**。下一輪處理時請一併帶上。

### 2026-09-04 — 第四十一輪：使用者八項需求 —— 會員層級真相、雙端新手指引、長輩朋友圈

**背景**

這一輪**不是 bug 修復**，是使用者直接在 main 本地分支提出的八項功能需求（不再開新分
支開發）。以下依 item 1–5、7、8 記錄（item 6 是鐵律 14 的規則修改本身，已直接回寫至
三份 `CLAUDE.md`，不在此重複）。

**item 1（前端）最新警示展開後看不到展開前的訊息**

根因：首頁預覽合併**三個**來源（`activeAlerts` 即時警報、`emergency_alerts` 持久化
表、`activity_log`），而 `AlertCenterScreen` 只收 `elderName`／`elderId`，自己去載
**預測型健康警示**——展開前後根本是兩批資料。
修法：`activeAlerts`（Socket 即時狀態）改由參數傳入；另外兩個**由 `AlertCenterScreen`
自己抓**（它本來就在 `initState` 載資料）。**刻意選「畫面自己抓」而非全部用參數
傳**——`ai_hub_screen` 沒有自己的即時警報來源，若改成全部用參數傳，那條入口會永遠只
能拿到空陣列，等於保留同一個 bug 的另一半。三個建構點全部更新。
🚧 **踩到的陷阱**：`family_home_tab` 用的 `elderIdStr` 是 4 位數房間 ID
（`Elder.elderId`），而 `AlertCenterScreen.elderId` 是 DB int（`Elder.id`）——兩者不
同，弄錯會抓到空清單。實作時另開 `elderRoomId` 參數解決。

**item 2（前端）雙端步驟式高光新手指引**

**自建元件、零新套件**：`lib/widgets/spotlight_tutorial.dart`。遮罩用 `CustomPaint` +
`Path.combine(PathOperation.difference)` **真的挖洞**（非貼圖近似）；SharedPreferences
讀寫全包 try/catch，**讀失敗視為已完成直接跳過**（寧可讓使用者少看一次教學，也不能
擋住長輩使用 App）。長輩端 6 個教學點、家屬端 4 個，字級可由參數覆蓋。
🚨 **來電／警報守門**：家屬端比長輩端多查 `!_cctvAlertDialogOpen` 等 3 條——CCTV 警報
卡片**不是阻擋式彈窗**，`_activeAlerts` 非空時使用者仍可切分頁，所以每一個教學入口都
要重新檢查一次，不能只在最外層查一次就當全程有效；完整條件見 G146。被守門擋下時**不
會**誤標成「已看過」。
🧩 **`IndexedStack` 陷阱**：分頁在第一次 build 時就全部 layout 完畢，各分頁的
`initState` 跑在「使用者其實還沒點過這個分頁」的時間點，**不能拿來偵測「第一次切
入」**。偵測邏輯因此拉到父層。
🔴 **首頁教學曾經永遠不會顯示**（雙端皆有此坑）：首頁是開機預設選中的分頁，使用者**
不需要點它**，原本掛在 `_onNavTap(0)` 上的觸發永遠不會被呼叫。修法：主介面教學跑完
後接續串接「目前選中分頁」對應的教學，並重新檢查一次守門條件，用當下的
`_selectedIndex` 判斷，而非寫死索引 0。
→ 新護欄 **G146**

**item 3（前後端）長輩朋友圈社群**

家庭圈與朋友圈**完全分離**。好友 ID **就是現有的 4 位數 `elder_id`**（使用者裁示，
已知悉並接受可被列舉的風險）。後端新表 `elder_friendship`（正規化排序，一段關係只存
一列）＋ `friend_post`／`friend_post_comment`／`friend_post_like`，新 router
`routers/friend.py`。
**刻意另建表，而非在 `community_posts` 加一個 `scope` 欄位**：使用者要求「家庭圈保持
現在原樣」，而 `community_posts.family_id` 是 `NOT NULL`，若要共用就得把它改成可空、
加 `scope`、再改動所有既有查詢——**任何一處漏加 `scope='family'` 過濾，都會讓朋友貼
文漏進家庭圈**。獨立建表的代價是按讚／留言各自多寫一份，換來的是家庭圈風險為零。
🚨 **搜尋端點限流**：`elder_id` 只有 4 位數（0000–9999），可被完整列舉。以呼叫端
`elder_id` 為鍵做滑動窗口限流，超過回 **429**；搜尋結果**只回最小欄位**（elder_id、
名稱、頭像），**不回電話／地址／生日**。
**前端**：`friend_service.dart`、朋友分頁的真實內容、`elder_add_friend_screen.dart`
（我的 QR／掃描／ID 搜尋三合一，不做多層跳轉）、`elder_friend_feed_screen.dart`（單欄
時間軸、大按鈕、載入更多分頁）、「我的」頁面顯示自己的 ID。
QR 格式固定為 `uban-friend:<4位數>`——掃到非此前綴的內容時停止相機並顯示白話提示，
不會拿裸數字誤查。
好友之間的「打電話」**刻意未做**：撥打功能只認 `comm_elder_<elder_id>` 房間，轉發對
象由後端依**配對關係**解析，整條路徑目前只支援長輩↔家屬，沒有長輩↔長輩。要做的話得
動 `socket_app.py`／`signaling.dart`（本輪禁改）。**寧可沒有那顆鍵，也不要放一顆按不
通的電話鍵。**
🔴 **實作時發現的既有 bug（本輪未修，先記錄）**：`elder_profile_tab.dart:1921` 用
`widget.userId.toString().padLeft(4, '0')` 猜測 elder_id，但 `elder_profile.elder_id`
（varchar(4) PK）與 `user_id`（int）其實是**兩個獨立欄位**，`padLeft` 只是巧合式假
設。該值目前用在「補綁定家人」對話框（:1977 顯示、:1987 編進
`UBAN_PAIR:userId:elderCode` 的 QR）。朋友系統**全面改用權威來源**
`GET /api/user/profile/{userId}` 回傳的 `elder_id` 欄位（見
`FriendService.resolveMyElderId`）。⚠️ 這代表現在「我的」頁面會同時出現**兩個 4 位
數**（可能有誤的配對碼、正確的好友 ID），對長輩使用者是混淆源，下一輪應該處理。
→ 新護欄 **G147**

**item 4（前端）長輩端電話頁加「家人／朋友」分頁**

專案原本**沒有任何 TabBar／分段控制的既有慣例**（grep 過 `TabBar`／`TabController`／
`ToggleButtons`／`ChoiceChip` 全部落空），沿用 `elder_home_screen.dart::
_buildNavItem` 的視覺語彙（大字級、大圖示），改用 Flutter 內建的 `TabBar` 元件，不引
入新套件。「家人」分頁的內容**逐位元組不變**。

**items 5／7／8（後端）會員層級與各種上限**

🔴 **item 7 是本輪最重要的發現**：`_get_monitor_device_limit` **早就在做「長輩繼承家
屬層級」，但演算法本身是錯的**——`ORDER BY r.start_date DESC LIMIT 1` 取的是「**最近
一筆訂閱記錄所屬的家屬**」，而不是「**層級最高的家屬**」。一位長輩若同時被免費與鑽
石兩位家屬綁定、且免費那筆記錄比較新，**這位長輩就會被誤判成免費會員**（監控機上限
5→2 台、在場更新間隔 3→15 秒）。**方向完全相反——付費家屬被降級了。**
而且 `indoor_position.py::_resolve_presence_interval_s` 裡藏著**同一個 bug 的第二份
獨立實作**（`_find_user_for_elder` 只 `LIMIT 1` 取任一位家屬）。
修法：新增**單一權威函式** `routers/subscription.py::resolve_tier_for_elder(elder_id)`
——查出所有綁定的家屬、逐一取層級、**取其中最高者**（diamond > gold > free），結果快
取 60 秒，查無資料或發生例外一律 fail-safe 到 `'free'`。原本的兩處重複實作全部收斂過
去，並補上「多位家屬取最高層級」的測試，把這條行為釘死。另外抽出
`tier_device_limit(tier)`，取代 `socket_app.py` 自己複製的一份對照表。
**item 5**：`_enforce_family_elder_bind_limit(family_id)`，上限 free 2／gold 3／
diamond 5。`boyo@uban.com` 用 **email 比對**（而非寫死 `user_id`，因為 id 會隨環境不
同而不同）跳過此限制。
  ⚠️ **實際落點與原始判斷不同**：原本以為要擋的兩處 INSERT 是
`/dev/ensure-yuxuan-demo`／`/dev/ensure-gawa-demo` 這兩個**開發測試端點**
（`family_id` 是寫死常數），但真正的配對流程其實是 `confirm_pairing()`。dev 端點
**刻意不擋**——擋了會讓「登入宇璿」這條測試路徑無預警壞掉。
  另外補上一個缺口：`routers/relationship.py::create_relationship`
（`POST /api/relationship/`）是**完全沒有配對碼驗證、也沒有授權檢查的裸 INSERT**，
能繞過上限。已補上限檢查，以及「關係已存在就不重複 INSERT」的冪等判斷（上限檢查排在
冪等判斷**之後**——重新綁定既有關係不應該被誤擋）。**這個授權缺口屬於既有設計、不是
本輪引入的，本輪未處理，先記錄。**
**item 8**：`_resolve_ip_monitor_device_limit()` 取代原本寫死的 `>= 5`。上限＝該 IP
底下**層級最高**的那位長輩對應的「每長輩監控機上限」平方（free 2²=4／gold 3²=9／
diamond 5²=25）。候選集合**必須包含呼叫當下這台裝置所屬的 elder**——它此刻還沒寫進
`monitor_device_ip`，若不加入，同一 IP 底下第一台鑽石裝置會被誤判成 free。查不到層級
一律 fail-safe 到 **free 的 4 台**（最嚴格的一檔），不得退到最寬鬆的一檔。
⚠️ **兩份上限常數刻意不共用**（`_FAMILY_ELDER_BIND_LIMITS` 與 `devices_max`）：兩個不
同業務規則只是數值剛好相同，硬共用會讓日後改一邊時誤傷另一邊。
→ 新護欄 **G148**、**G149**

**踩到的環境陷阱（兩件，值得記錄）**

1. **共享 shell 的 cwd 會被併發代理帶走**——某個代理的 bash session 曾被另一個代理的
   `cd` 帶到別的目錄，導致驗收指令跑錯地方。之後所有派工都改成要求每條指令自帶絕對
   路徑前綴。
2. **正式 MySQL 有 `elder_profile.user_id` 的外鍵，本機 SQLite schema 沒有鏡射這個約
   束**——只在正式環境才會出現的限制，本機測試看不出來。

**仍然開著**

1. `elder_profile_tab.dart:1921` 的 `padLeft` 猜測法（見 item 3）——「我的」頁面現在
   同時有兩個 4 位數並存，需要下一輪處理。
2. 好友之間無法互相撥打電話（需要動 `socket_app.py`／`signaling.dart`，本輪禁改）。
3. `elder_chat_screen.dart::_handleCallLinkClick` 建構 `ElderScreen` 時直接用
   `userId.toString()` 當房號，沒做 `comm_elder_` 前綴正規化、也沒讀 `elder_room_id`
   兜底；目前找不到呼叫點，可能是死碼，待確認。
4. 第四十輪 item 3（長輩在 App 外拒接無反應）**仍待實機驗證**——已加獨立通知 ID
   8802 的回饋，三種可能結果都能藉此定位。
5. `routers/relationship.py::create_relationship` 缺乏配對碼驗證與授權檢查（見
   item 5）——本輪只補了上限，授權缺口留待後續處理。

**新增護欄**

本輪新增 **G146–G149**（前端 G146；後端 G148–G149；跨端 G147；條文見 §7.1／§7.2）。
§7 開頭護欄總數同步更新為 **149**。

**驗證**

- `flutter analyze lib` — **0 error**。
- `flutter build apk --debug` — 成功。
- 後端 `pytest`（items 5/7/8 針對性測試 + 朋友系統新測試）— **96 passed**。

連接／跳轉語意變更（新增 `routers/friend.py` 10 個端點、朋友分頁跳轉）的 graphify 同
步狀態由對應的實作子代理負責，不在本次文件任務範圍內。

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
