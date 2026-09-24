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
| `lib/services/api_service.dart` | HTTP 層；通話與監控相關 | `declineCall(roomId, senderId, callId)`、`pushCctvFrame()`、`checkAudioBridge(alertId,{userId})`、`_deviceTokenHeader`（`X-Uban-Device-Token`） | 🟡 中 |
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

> 這條**不是通話**，是監控子系統的警報推播（YOLO 偵測與「跌倒測試」端點共用同一條派送路徑）。
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
> （用「跌倒測試」端點連續觸發兩次，第二次沒反應，YOLO 連續偵測也一樣）。
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
| **`pendingLocalRingCall`** | **2026-09-21 第五十一輪新增**。`local_call_notification.dart::_persistTapAsPendingRing`，由 `notificationBackgroundTapHandler` / `consumeLaunchPayload()` 在 `response.actionId == null`（通知本體被點，或螢幕鎖定時系統因 `fullScreenIntent` 自動觸發的 content PendingIntent）時呼叫——**不是**使用者明確按下「✓ 接聽」 | `main.dart::_checkPendingLocalRingCall`（由 `_scheduleLocalRingCallFallback` 排程，冷啟動輪詢 `splashActive`；resume 直接呼叫） | 讀取當下即消費並移除（一次性） | 「備援通知響過但尚未明確接聽／拒接」→ 消費時改顯示 `_showIncomingCallDialog`（接聽／拒接畫面），**不會**直接進房。欄位集合與 `pendingAcceptedCall` 相同（見 G198） |

> **拒接／取消時三個鍵必須一起清**（護欄 #15，指 `pendingAcceptedCall`／`pendingRingCallData`／`pendingRingCall`）。殘留 `pendingRingCallData` 會讓下次冷啟動 `main()` 誤重建 pending → 假來電／角色反轉。`pendingLocalRingCall` 是獨立的第四個鍵，語意與寫入來源都與前三者不同，**不併入**這條「三個鍵一起清」的既有規則，見 G198。

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
 └─ 「跌倒測試」端點（前端按鈕已於第四十七輪移除，僅能由 curl／API 工具觸發）：POST /api/cctv/test-fall
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

**要測「跌倒測試」端點時**（前端按鈕已於第四十七輪移除，改用 curl）：`.env` 設 `CCTV_TEST_FALL_ENABLED=true` → 重啟後端 →
```bash
curl -X POST <baseUrl>/api/cctv/test-fall \
  -F "elder_id=<長輩ID>" -F "device_name=<監視機裝置名稱>"
  # 若後端有設 CCTV_INGEST_TOKEN，另加：-H "X-Uban-Device-Token: <token>"
```
→ 測完**立刻改回 `false`**。
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
| **A. 派送鏈** | 驗證 DB 寫入 → Socket/FCM → 亮螢幕 + 通知 + 朗讀 + 彈窗 | 開 `CCTV_TEST_FALL_ENABLED=true`，用 curl 打 `POST /api/cctv/test-fall`（前端按鈕已於第四十七輪移除，curl 範例見 §6.10） | 家屬端**熄屏**狀態下也要亮起並朗讀。連續觸發兩次要**兩次都有反應**（驗證複合鍵去重沒退化） |
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

> 🚨 **完整護欄清單（目前 G1–G215）已於 2026-09-04 獨立成檔，2026-09-24 第五十三輪
> 再依前端／後端分成兩卷**：
> 索引 **[`CLAUDE_call-monitor-guardrails.md`](CLAUDE_call-monitor-guardrails.md)**
> ／前端卷 **[`CLAUDE_call-monitor-guardrails-frontend.md`](CLAUDE_call-monitor-guardrails-frontend.md)**（§7.1，115 條）
> ／後端卷 **[`CLAUDE_call-monitor-guardrails-backend.md`](CLAUDE_call-monitor-guardrails-backend.md)**（§7.2，100 條）
>
> 遷出原因：主檔逼近 262,144 bytes 的單次讀取上限，一旦超過，子代理就無法一次讀完，
> 而「動手前必須完整讀過本文件」是本子系統第一鐵律——文件過大會讓這條鐵律**在技術上無法遵守**。
> §7 當時佔主檔 55%，是唯一夠大且可獨立閱讀的區塊；護欄檔獨立後持續累積，第五十三輪本身
> 也成長到 200,175 bytes，再依前端／後端拆成兩卷（拆卷原因與定向閱讀指引見索引檔開頭）。
>
> **動到通話／監控程式碼前，索引檔與（依任務類型判斷的）對應卷同樣必讀**，三者是一組的。
> 索引含：分卷說明、「依任務類型的定向閱讀指引」、§7.3 已知的文件錯誤（以程式碼為準）、
> §7.4 已知且刻意保留的安全缺口；§7.1 前端護欄／§7.2 後端護欄的條文本體在兩份卷檔案裡。

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
> 📌 **搬移門檻提示**：本文件中出現的「第 N 輪」，**N ≤ 42** 者其年表條目已遷至
> `CLAUDE_call-monitor-history.md`；**N ≥ 43** 仍在本檔 §8。此門檻會隨每輪搬移而持續調高，
> 調整時只需要更新本處（§8 開頭）的數字。

### 2026-09-24 — 第五十三輪：長輩端鎖屏與語音助理四項真機回報、雙端必填欄位、開發者主控台四項擴充、護欄檔分卷

**背景**

本輪起於長輩端與家屬端多項真機回報，加上使用者要求的三項開發者主控台擴充（食物系統、封禁與帳號管理、可調參數登錄表）。護欄檔本身在第四十二輪獨立成檔後持續累積，本輪成長到 200,175 bytes，再依前端／後端拆成兩卷（`docsplit53b`，見 §7 開頭）。

**長輩端**

1. **鎖屏一般來電延遲**：原先懷疑是 `bringToFront` 沒有覆蓋一般來電——查證後這個假設**不成立**：`signaling.dart` 的 `bringToFront` 與強制音量只掛在 `isEmergency` 分支（:739–740），從未涉入一般來電。真正路徑是 CallKit 在背景 isolate 靜默建立失敗、退回 `LocalCallNotification`，其 `fullScreenIntent: true` 被 Android 系統自動觸發、PendingIntent 指向整個 App（不是特定畫面）——使用者感受到的「解鎖後要在 App 內等很久」，等的其實是 4 秒開機動畫。修法：`splash_screen.dart` 新增一段**只偷看不消費**的檢查，讀 `pendingLocalRingCall`（由 `local_call_notification.dart::_persistTapAsPendingRing` 寫入）判斷是否該跳過開機動畫，但**不** `remove` 這個鍵；真正的消費者仍是唯一的 `main.dart::_checkPendingLocalRingCall`。**這是部分修復**：完整解法需要原生 Android 來電 Activity，不在本輪範圍內。
2. **被殺死時拒接無效**：靜態程式碼審查找不到邏輯錯誤，推測是 `FlutterCallkitIncoming.onEvent` 的事件在被殺死狀態下投遞不可靠。加了 `activeCalls()` 輪詢備援：CallKit 建立後每秒查詢一次，連續兩次查詢皆為空、但背景 `bgDecision` 仍未寫入結果時，視為「隱含拒接」並主動補送 `call-busy`。⚠️ **對 `LocalNotification` 備援那條路無效**——已知缺口，留給下一輪。
3. **幽靈提醒**：根因鏈是 `routers/reminder.py::resolve_repeat_days_trigger()` 對「單次」的判斷為 `(not start_date) or start_date == today`——沒填起始日視為「任何一天都適用」；但全程式碼從未有任何地方在觸發後把 `is_active` 關掉——`main.py::check_remote_reminders_job()` 的去重字典只在同一天內有效，`complete_reminder` 端點只寫 `activity_log` 不碰 `is_active`。結果是這類提醒從建立當天起每天在同一分鐘重新推播、永不停止。「今日 23:03 vs 系統 11:03」查證後**不是時區 bug**——全鏈路都是 24 小時制字串完全相等比對。修法：`check_remote_reminders_job()` 觸發單次提醒後直接把該筆 `is_active` 更新為 0 並廣播 `reminder-sync`；新增 `test_reminder_auto_deactivate.py`。
4. **AI 回覆吐出 JSON 原文**：後端 `routers/ai.py::ai_chat_stream()` 送出的每一行 `data:` 都是 JSON **物件**（`{"chunk": "..."}` 等），前端舊版 `ai_chat_api.dart` 寫 `jsonDecode(payload) as String`，對物件必定拋型別例外，落到 `catch (_) { yield payload; }` 把原始 JSON 字面文字送到畫面上。`elder_chat_tab.dart` 的 SSE 解析一直是對的，所以只有語音助理（`google_assistant_overlay.dart`）這條路壞掉。解析邏輯抽成獨立函式並補上單元測試。
5. **語音辨識自動送出**：`google_assistant_overlay.dart` 的 `onResult` 只要 `finalResult` 為真且有內容就直接呼叫 `_processUserQuery`，長輩沒有機會看到或修正辨識結果；另有第二條路徑（引擎自行判定 `status == 'done'/'notListening'`，例如 `pauseFor` 逾時）先前也是直接送出，只堵住 `onResult` 並不完整。兩條路徑統一改走新的 `_stopListeningForConfirm()` → 確認面板，交由長輩看過文字、按下「送出」才真的呼叫 AI。家屬端 `family_ai_copilot_screen.dart` 原本就只寫回輸入框、從不自動送出，本輪的錯誤只存在於長輩端。
6. 寵物賽季提示改對話框＋大字＋白話說明，取代原本偏技術性的提示文字。
7. 今日頭條在 412×915 量測下由 1 則增為 3 則（widget test 量測，最後一則底線 591.8，可視底線 785）。
8. 新聞捲動提示的文案／字級／顏色調整，並順帶修好該畫面既有的 `RenderFlex` 溢位（360×640 溢 10px、375×667 溢 25px）。
9. 長輩端／家屬端年齡與居住地改為必填。新增 `ElderProfileOnboardingScreen`／`FamilyProfileOnboardingScreen` 強制補填畫面（`PopScope(canPop:false)` 擋返回鍵、fail-open 不擋斷網）；共用判斷抽成 `utils/profile_completeness.dart`。`onboard53` 先把檢查接進 `login_screen.dart`（家屬首次登入）與 `elder_pairing_display_screen.dart`（長輩：配對成功／自主模式／登入上次長輩，三條入口），但漏了「冷啟動偵測到既有 session」這條完全不經過這兩個檔案的路。`callfix53b` 補上這個缺口，新增 `splash_screen.dart::_replaceWithElderDestinationOrOnboarding()` 收斂所有導向 `_resolveElderDestination()` 的既有呼叫點——實際清點是 **4 處**（:363 標準流程、:400 API 失敗回退、:465 `_sprintToPendingCall()` 衝刺通道、:583 `_goNextOrRestoreElder`），比修復當下自己寫的說明文字「三個既有呼叫的地方」還多一個，見下方新增護欄 G209。

**家屬端**

10. 情緒時間軸卡片改走 `Theme.of(context)` 取色，不再寫死顏色常數，並統一卡片間距與對齊。
11. 警示中心新增自訂日期範圍與狀態篩選；後端 `get_alerts` 新增選填的日期區間參數，用 `tw_day_range_to_utc()` 在 Python 端換算，不在 SQL 用 `NOW()`。
12. 加好友方式經查證**確認無需改動**：第五十一輪已改成雙端共用的 4 碼英數字表，第五十二輪已把 QR／掃描／分享做成加好友分頁的預設頁籤。

**開發者主控台**

13. 移除統計卡片的變異數欄位（保留標準差）——變異數對非統計背景的開發者不直觀，且與標準差重複。
14. 使用者列表「編輯」功能重構。查證使用者回報的「只能看到第一位長輩」，發現是**前端寫死 `bound_elders[0]`**，後端 API 其實一直回傳完整陣列。
15. 新增 `pet_food` 食物主表＋`elder_food_grant` 發放帳＋賽季體重承接比例可調（`carryover_ratio`）。除錯過程中發現 `init_sqlite_db()` 的交易陷阱（詳見下方新增護欄 G210）。
16. 新增 `app_settings` 可調參數登錄表，把警報看門狗／YOLO 狀態視窗／TTS／搜尋限流／統計分桶共四組、19 項原本寫死的參數改為開發者主控台可調。
17. 封禁真的擋登入（`routers/auth.py` 的 `/login` 查 `account_ban.is_banned`）、新增永久刪除帳號、長輩獨立管理、寵物食物管理 UI。過程中發現實際資料表是 51 張（先前文件記載 82 張），以及 `elder_fellowship_data`／`get_appearance_list` 兩張表程式碼中已在使用、但 `database.py` 沒有對應的 `CREATE TABLE` 陳述式。

**新增護欄**

本輪新增 **G206–G215**（前端 G206–G209；後端 G210–G215；條文見 §7.1／§7.2）。護欄總數同步更新為 **215**。

**仍然開著**

1. 長輩端鎖屏一般來電只是部分修復，完整解需要原生 Android 來電 Activity（item 1）。
2. 被殺死狀態下、走 `LocalNotification` 備援路徑的拒接仍然無效（item 2）。
3. 帳號刪除的資料表清單（`routers/pairing.py::unbind_elder()`）尚未涵蓋第 41／43／48／49／51／53 輪新增的表，家屬自助解綁到最後一位時會留下孤兒列——已列為下一輪優先事項，見 G214。
4. 封禁對長輩自主帳號無效（該類帳號建立後不再呼叫 `/api/auth/login`）；已決定改走 `force-logout` Socket＋FCM 廣播，排下一輪，見 G215。
5. `elder_fellowship_data`／`get_appearance_list` 兩張表仍缺 `CREATE TABLE` 陳述式（item 17）。

**驗證**：各項修復由對應實作子代理個別跑過 `flutter analyze`／`flutter test`／`py_compile`／`pytest`，細節見各自 commit。**本輪未同步 graphify**（使用者已要求暫停）。

### 2026-09-23 — 第五十二輪：三輪回歸清算——兩個「把整片畫面弄死」的版面陷阱

**背景**

本輪起因是使用者實機回報 10 項問題，並要求判讀第四十九／五十／五十一輪的取捨。結論是不
整批回退：三輪各有正確的修復，問題集中在兩個版面陷阱與幾件修了一半的事。

**1. 長輩端所有通話房黑屏、完全無法操作（本輪最嚴重）**

根因：第五十一輪依護欄 **G199 的字面要求**，在 `elder_screen.dart` 的 `Stack` children 裡
插入 `const AssistantHiddenZone(child: SizedBox.shrink())`。`RenderStack._computeSize()`
的規則是「只要有任何非 `Positioned` 子元件，`Stack` 就由它們決定尺寸；全部都是
`Positioned` 時才退回吃滿 `constraints.biggest`」，而 `Scaffold` 的 body 拿到的是寬鬆約束
（min 為 0）——原本 children 全是 `Positioned.fill`，多了這個 0×0 的非 Positioned 子元件
後，**整個 `Stack` 塌成 0×0**，視訊與所有按鈕變零尺寸、沒有任何 hit-test 目標。家屬掛斷時
長輩端是被程式自動 pop、不需點擊，因此使用者觀察到的「只能由家屬掛完電話才恢復」完全
吻合。

修法：改為 `AssistantHiddenZone` 包住整個 `Scaffold`（純 pass-through，不影響版面）；**並
改寫 G199 本身**——原條文等於教下一個人再犯同一個錯。

證據：`test/screens/elder_screen_stack_sizing_test.dart` 先重現舊結構得到 `Size.zero`，再
驗證新結構等於螢幕尺寸。

**2. 家屬「資料」分頁整片空白且所有按鍵失效**

根因：第五十輪（commit `688a2a1`）把 `Flexible` 包在 `SliverList` 項目內的**垂直
`Column`** 直接子節點上。`Flexible`／`Expanded` 出現在主軸無界的 Flex 底下會丟
`RenderFlex children have non-zero flex but incoming height constraints are unbounded`，
而且**發生在 layout 階段而非 build 階段**——第五十一輪為此新增的 `ErrorBoundary` 只包得住
build 期間的同步呼叫，完全攔不到；例外炸穿 `SliverList`／`Viewport`，整條
`CustomScrollView` 那一影格的版面計算全毀，於是畫面空白且沒有 hit-test 目標。

全 App 掃描 47 處 `Flexible`／`Expanded`，確認只有這一處誤用；`elder_chat_tab.dart:905` 有
同款形狀但整支是無人引用的死碼，未動並留註記。

**3. 今日頭條實機看不到（已失敗三輪）**

後端新聞 API 實測有真實資料（2026-09-22 的中央社新聞），問題純在版面：第五十輪把新聞卡從
精簡列改成大圖直式，整張被推出第一屏；第五十一輪加的「還有更多」提示沒有解決「長輩不會
主動下滑」的問題。本輪改回精簡列（縮圖 76px），並以 widget test 在 `360x640` 與
`412x915` 量測標題座標證明已落在第一屏內（412×915 時 top=352.8、第一屏可視底線 785）。
**教訓：三輪都在猜「是不是被擠到下面」，沒有人去量。**

**4. 語音助理：備援從寫出來那天就是死碼**

Ollama 主機回 502 時，`services/ollama_service.py` 把例外吞掉、把錯誤字串當成正常回覆
`yield` 出去，呼叫端 `routers/ai.py` 的 Gemini 備援永遠不會被觸發，長輩直接聽到「對話服務
異常: (status code:502)」。另查出串流版的備援判斷用字串前綴 `"(流式服務出錯:"` 偵測，而
實際產生的是 `"(對話服務異常:"`，兩者從來對不上。修法：改為 raise（以 `has_yielded` 區分
「未送出內容→raise 讓備援接手」與「已送出一半→友善收尾不重講」）；Gemini 最終兜底不再把
英文 SDK 錯誤唸給長輩；`/pet_greeting` 補上原本沒有的 try/except。

**5. 麥克風錄到助理自己的 TTS**

`google_assistant_overlay.dart` 的問候語用 `setCompletionHandler` 加一個
`Future.delayed(2500ms)` 兜底，兩者賽跑；而語速被設為 0.5，一句問候常講不完 2.5 秒，兜底
先到就在助理還在講話時開麥克風，把喇叭聲錄成使用者輸入（使用者實例：助理問「怎麼了嗎，
蛙」→ 辨識成「怎麼了媽媽」）。改為單一 `_speakAndWait()` 判定，並加雙向防呆（開口前先停
STT、開聽前先停 TTS）。

**6. 喚醒詞關不掉**

設定對話框讀 `?? true` 與 `globals.dart`／首頁的 `?? false` 不一致，一存檔就寫回開啟；且
第五十一輪之前的版本會在每次載入首頁時**強制寫入 true**（不是使用者的選擇）。改為一致，並
加版本化一次性遷移 `wake_word_pref_reset_v52`，冷啟動路徑與設定頁各一份。

**7. 家屬警示中心**

已結案（含四種 `resolution_source`）仍顯示可按的「誤報」——已改為唯讀徽章；未結案收斂成
單一 `PopupMenuButton`；新增本週／本月／全部時間篩選，後端 `get_alerts` 新增選填
`days`（用 `now_utc()` 在 Python 端算起點，不在 SQL 用 `NOW()`）。

**8. 雙端加好友**

功能從未被刪除（第五十一輪反而把代碼驗證從「只能 4 位數字」放寬成 4 碼英數字），真正缺
的是**社群分頁裡的入口**。兩端都補上；家屬端新增 QR 顯示／掃描／分享。另修一個真的會發生
的 bug：家屬朋友圈在載入中或載入失敗時會把「加好友」入口一起蓋掉——網路一抖就找不到入口。

**9. 家屬首頁冷啟動競態（本輪任務一）**

已滑掉的警示清單是非同步讀取，卡片會在載入完成前先畫一次。`family_main_screen.dart::
initState()` 呼叫 `_loadDismissedAlertKeys()` 不 await——App 冷啟動 → 首頁「最新警示」卡片
先畫一次（此時過濾集合是空的）→ 已滑掉的警示出現 → 幾百毫秒後才被過濾掉。新增
`_dismissedKeysLoaded` 旗標：讀取完成（不論成功或失敗）前，`HomeAlertPreviewCard` 一律不
渲染任何警示項目，也不顯示「目前沒有任何警示」（那句話在旗標為 false 時無法被驗證是否
成立），改用中性的「警示讀取中…」骨架，沿用既有空狀態的版面結構只換圖示與文字。已排除
一次性副作用疑慮：`HomeAlertPreviewCard`／`HomeAlertItem` 是純 `StatelessWidget`，朗讀
（`_alertTts`）與 `WakelockPlus` 皆由 `_handleCctvAlert`（Socket `cctv-alert` 事件）觸發，
與這張卡片的渲染時機完全無關，因此這次閃現純粹是視覺問題。

**新增護欄**

本輪新增 **G200–G205**（前端 G200、G203、G204、G205；後端 G201–G202；條文見
§7.1／§7.2）。護欄檔（`CLAUDE_call-monitor-guardrails.md`）開頭護欄總數同步更新為
**205**。

**驗證**：`flutter analyze` 88 issues／0 error；`flutter test` 93 passed／0 failed；後端
`py_compile` 全過；AI 備援隔離腳本 8/8。**本輪未同步 graphify**（使用者已要求暫停）。

### 2026-09-22 — 第五十一輪（續）：語音助理全域入口，與它對通話畫面的讓位規則

**症狀**：使用者回報「長輩端語音助理叫不出來」。

**根因**：助理只有兩個呼叫點，兩個都活在 `ElderHomeScreen` 的 `Stack` 裡
（喚醒詞監聽與隨身救生圈 FAB，`elder_home_screen.dart`:549-586；另一處是
`elder_tabs/profile/dialogs/ai_assistant_settings_dialog.dart`:130），
只覆蓋 5 個分頁。任何 `Navigator.push` 出去的畫面——通話房、監控、
新聞播放器、配對頁——都沒有入口。

**修復**（見 **G199**）：

- 新增 `widgets/global_assistant_button.dart`：可拖曳、放開吸附最近邊、
  閒置 5 秒收成半透明小圓點的浮動麥克風鈕；位置（以可用區域比例儲存，
  換裝置／轉向都不會跑到畫面外）與收邊狀態存 SharedPreferences
  （`assistant_fab_dx` / `assistant_fab_dy` / `assistant_fab_collapsed`）。
- 掛在 `main.dart` 的 `MaterialApp.builder`（`Stack(fit: StackFit.expand, …)`，
  用 `expand` 讓 Navigator 拿到與改動前完全相同的全螢幕緊約束，不動任何
  既有畫面的版面）。**沿用既有的 `navigatorKey`**，沒有新增全域導航機制。
- **不重做助理邏輯**：`ElderHomeScreen` 在 `initState` 把既有的
  `_triggerGoogleAssistantOverlay` 登記到 `elderAssistantLauncherNotifier`，
  浮動鈕只負責呼叫；`dispose` 時用 `==` 比對自己仍是持有者才清空（同 G102）。
  喚醒詞暫停、畫面情境注入、`autoCall` 撥號接手因此仍只有一份實作。
  登記者是長輩端首頁，所以這顆鈕**只在長輩端登入後存在**——家屬端與登入前
  畫面上 notifier 是 null，什麼都不會畫。
- **通話安全**：`AssistantHiddenZone`（同檔）是一個零尺寸標記 widget，活著
  的期間浮動鈕讓位。已放進 `elder_screen.dart`（通話房／CCTV）、
  `camera_screen.dart`（監控）、兩處來電響鈴 dialog
  （`elder_home_screen.dart` 與 `main.dart` 的 `_showIncomingCallDialog`），
  以及助理面板自己（`google_assistant_overlay.dart::show()`）。
  刻意用 widget 樹上的標記，**沒有**去動這些畫面的 `initState`/`dispose`
  （§5.4 列為「絕對不要碰」）。來電 dialog 只是在最外層多包一層，
  接聽／拒接的按鈕、`_activeCallDialogContext` 的 guard 與
  `.then((_) => …)` 重置全部未動。

**順帶修好的既有回歸（護欄 G59）**：`elder_home_screen.dart::
_loadAssistantSettings` 每次載入都把語音喚醒旗標**強制寫回 `true`**
（長輩在設定頁關掉，下次進首頁又被打開，麥克風恢復成無限開開關關），
且 `globals.dart` 的 `wakeWordEnabledNotifier` 預設值也被改成過 `true`——
兩處都違反 G59「預設關閉、禁止把預設值改成 true」。現在首頁只讀不寫，
預設值改回 `false`，唯一寫入點回到設定頁。

**順帶修好的第二件事**：`CommunityApi.getCommunityPosts` 把連線失敗吞掉回
`[]`，使 `CommunityService.getPosts`（第五十輪改成「遠端成功即為單一真相」）
**分不出「離線」與「後端說一則都沒有」**——離線時會拿空清單覆蓋本機快取，
長輩沒網路時發的貼文下次載入就消失，`lastFetchWasOffline` 也永遠是 false
（離線提示從不出現）。改為 **null＝呼叫失敗、空清單＝真的沒貼文**，
`getPosts` 只在 null 時退守快取。唯一呼叫點是 `community_service.dart`。

**驗證**：`flutter analyze lib` **0 error**（88 issues，與本輪基準相同）、
`flutter build apk --debug` 成功、`flutter test` **54 passed**
（`community_service_test.dart` 原本 3 項失敗：它斷言的是第五十輪已移除的
寫死歡迎貼文，且每次都真的打正式站等逾時；已改為用 `HttpOverrides` 強制
離線並改斷言「離線且無快取時回空清單」，整組測試從 60 秒降到 5 秒）。
本輪未接觸後端。

### 2026-09-21 — 第五十一輪：備援通知的 `actionId == null` 被誤判為「已接聽」，長輩端第一通來電未經同意直接開視訊

**症狀**：長輩端**第一通**來電時，App 沒有經過長輩同意就直接開啟視訊通話；
第二通以後才會正常出現接聽／拒接畫面。

**根因**：`services/firebase_bg_handler.dart::showFullScreenCallkit`（約
:202-233）在原生 CallKit 建立失敗（輪詢 8×250ms 仍未確認 `activeCalls()`
非空）時，才退到 `LocalCallNotification.show(data)` 補發備援來電通知——冷
啟動／App 剛被殺死時原生外掛通常還沒暖機，第一通因此幾乎必定走這條路，
第二通以後 CallKit 已暖機就不會。`services/local_call_notification.dart`
的 `show()`（:109-182）發出的備援通知帶 `fullScreenIntent: true`，只定義
兩顆 action（`actionAcceptId` / `actionDeclineId`）。舊版
`notificationBackgroundTapHandler`（:294-310）與 `consumeLaunchPayload()`
（:266-284）只把 `response.actionId == actionDeclineId` 當拒接，**其餘一切
（含 `actionId == null`）都落到 `_persistTapAsAccepted`**，直接寫
`pendingAcceptedCall`——而 `actionId == null` 涵蓋「通知本體被點」與「螢幕
鎖定時系統因 `fullScreenIntent` 自動觸發的 content PendingIntent」兩種情況，
**兩者都不是使用者主動按下「✓ 接聽」**。`main.dart::_bootstrap()`
（約 :139-162）讀到 `pendingAcceptedCall` 後，`elder_home_screen.dart::
_onPendingCallChanged`（約 :1010-1078）會直接把長輩送進 `ElderScreen`，
全程沒有出現接聽／拒接畫面。對比組：CallKit 路徑本來就要求原生確認
`isAccepted == true` 才算接聽（`main.dart::_checkInitialCall` /
`actionCallAccept`，見 G10），是整條通話系統裡**唯一**沒有這道確認的接聽
路徑。

**修復**（見 **G198**）：

- 新增 SharedPreferences 鍵 `pendingLocalRingCall`——語意是「備援通知響
  過，但使用者尚未明確接聽／拒接」，欄位集合與 `pendingAcceptedCall` 相同
  （`roomId`/`senderId`/`callId`/`issuedAt`/`expiresAt`/`senderRole`/
  `isVideoCall`/`timestamp`），與 `callId` 綁定、讀不到就當過期丟棄（比照
  `lastProcessedCallId` 的純資料模式，**沒有**在 `Signaling` 單例新增顯示
  狀態旗標，見 G27）。
- `local_call_notification.dart`：新增 `_persistTapAsPendingRing()`。
  `notificationBackgroundTapHandler` 與 `consumeLaunchPayload()` 改為三分支：
  `actionId == actionDeclineId` → 拒接；`actionId == actionAcceptId` → 呼叫
  既有 `_persistTapAsAccepted()`；其餘（`== null`）→ 呼叫
  `_persistTapAsPendingRing()`。`fullScreenIntent: true` 與兩顆 action
  按鈕維持不變（鐵律 #13 明文允許來電響鈴畫面例外）。
- `main.dart`：新增 `_checkPendingLocalRingCall()` 讀取並消費該鍵——有效期
  判斷比照 `pendingAcceptedCall`（`kCallValidityMs`）、跳過已由其他通路
  `lastProcessedCallId` 處理過的 callId、若已有 `pendingAcceptedCall` 待
  導航就不疊加彈窗；符合條件才呼叫**既有的** `_showIncomingCallDialog`
  （原本只給 FCM 前景備援與 Socket `onCallRequest` 用），讓使用者自己按
  接聽／拒接，不重做一套 UI。新增 `_scheduleLocalRingCallFallback()`，
  比照既有 `_scheduleRecoveryCodeFallback` 的模式輪詢 `splashActive`
  （200ms/次，上限 20s）後才消費，避免 dialog 在 Splash 冷啟動導航塵埃
  落定前彈出被 `pushReplacement` 打斷（G13）；冷啟動於 `initState()` 排程，
  回前景（`AppLifecycleState.resumed`）直接呼叫一次（此時 Splash 已結束
  無需再等）。
- **刻意沒做**：緊急通話（`type == 'emergency-call'`）完全不動——
  `firebase_bg_handler.dart::showFullScreenCallkit` 本來就只在
  `if (!isEmergency)` 分支內才呼叫 `LocalCallNotification.show()`，緊急
  通話從未經過備援通知這條路，故 `local_call_notification.dart` 與
  `_checkPendingLocalRingCall` 都不需要（也不應該）另外判斷
  `isEmergency`，程式碼裡已加註解說明這個不變式。CallKit 路徑、
  `signaling.dart`、FCM 背景 handler 的角色守門（`AndroidIntent` 只在
  `role == 'elder' && type == 'emergency-call'`，鐵律 #13）一律未動。

**驗證**：`flutter analyze lib` 0 error（本輪新增程式碼無新增警示）。
本輪未接觸後端，`uban-api` 迴歸套件未受影響（見 §10 的例行指令）。

### 2026-09-17 — 第四十九輪：警報狀態機、時間基準統一、誠實性收尾

**背景**

本輪延續使用者一份 14 項的待辦清單。與通話／監控子系統相關的是 item 2、
3、5、6、7、8、11、12（其餘 item 1、9、10、13、14 屬排程提醒、管理端與寵
物子系統，已於本輪較早的檢查點完成，不在本檔範圍）。另加上本輪過程中查出
的幾項誠實性與資料正確性問題（通知文案分流、G102 違規、`activity.py` 資料
外洩、用藥打卡誠實性、健康與情緒圖表假資料、節氣顯示、鐵律 #1 同類問題、
測試環境誤連正式庫）。

⚠️ **兩項本輪未完成、下一輪必須接手**：
- **item 5 的「App 在背景」情境**——長輩在背景撥出視訊時進得了房但 WebRTC
  連不上。需要 Android 實機先診斷才能確定是哪一層被系統凍結；方案 A（重用
  `flutter_callkit_incoming` 內建的 `phoneCall` 前景服務）已核准但未實作。
  **不可在沒有實機的情況下盲改**。
- **item 4（正式庫清理／「蛙」的好友／E2E 貼文測試）**——腳本與備份已備
  妥，但卡在兩件事：正式主機的 Tailscale 節點金鑰過期（整台連不上），以及
  刪除 16 個帳號與 52 篇測試貼文屬不可逆操作、需要使用者明確授權。

**item 12 警報狀態機（本輪最大項）**

根因：`POST /api/alerts/{id}/acknowledge` 與 Socket `cctv-alert-ack` 在本
輪之前**呼叫次數為 0**，`acknowledged`／`resolved` 從未被寫入過，每一筆警
報永遠停在 `active`——`routers/developer_users.py::_risk_level()` 的「活
躍警報」因此等於「這位長輩曾經跌倒過」，全平台長輩一律被判定高風險。第二
個根因藏在 `services/yolo_alert_dispatcher.py::_insert_alert()`：對同一長
輩＋同裝置＋同類型的既有列是 UPSERT，每次重新偵測都把 `detected_at` 洗成
`NOW()`——持續發生中的跌倒（最該升級的情境）永遠不會老化。新增
`first_detected_at`，只在真正新建時寫入，作為 2 小時逾時判斷唯一正確的起
算點。

三態沿用既有字串 `active`／`acknowledged`／`resolved`，不新增列舉值。新增
`services/alert_state.py`，由 REST（`routers/alert.py`）與 Socket
（`services/socket_app.py::on_cctv_alert_ack`／`on_audio_bridge_request`）
**共用同一個函式**，讓 G44（兩路徑行為一致）由程式結構保證，不再只靠人工
對齊。

新增 `services/alert_watchdog.py`（每分鐘排程）：待處理每 **10 分鐘**重
推、從 `first_detected_at` 起滿 **2 小時**升級給開發者（處理中照樣計
時）、處理中閒置 **20 分鐘**退回待處理，三個數字都是使用者拍板。

合併窗口本身也踩過兩次坑：家屬一開監控畫面，警報就轉 `acknowledged`；若
合併只認 `active`，同一次跌倒 15 秒後（`FALL_COOLDOWN_S`）再被偵測就會另
開新列、重複推播。但只放寬成「未結案就合併」又會讓新跌倒併進幾天前的舊
列、沿用舊 `first_detected_at`，一建立就被判逾時。最終採「未結案 **且**
上次偵測在 `SAME_EVENT_WINDOW_MINUTES=30` 分鐘內」。
→ 新護欄 **G191**

誠實性：`_broadcast_alert()` 改回傳 `{socket_targets, socket_sent,
fcm_targets, fcm_sent}`；主控台「聯絡家屬」在 0 個對象時必須明講沒有可推
播的家屬裝置，不得顯示「已通知」。
→ 新護欄 **G193**

舊警報處理依使用者裁示「上線時自動結案」：migration 014
（`014_alert_state_machine.sql`）的 backfill 0 把「本輪之前建立、仍未結
案」的警報一次轉 `resolved` ＋ `resolution_source='legacy_auto'`，排在補
`first_detected_at` 的 backfill 之前——判定依據是「新程式碼的兩條 INSERT
路徑都一定寫 `first_detected_at`，所以第一次執行時 NULL 的就是舊資料」，
並以 `tests/test_alert_insert_paths.py`（AST 靜態掃描）守住這個前提。
→ 新護欄 **G195**

開發者決策端點 `POST /api/developer/alerts/{id}/decision`：聯絡家屬（立即
重推）／建議報醫（只記錄，回傳長輩地址與家屬姓名 email，並明講系統沒有留
存電話號碼）／結案。**不做任何電話號碼設計**（使用者明確要求）。

看門狗執行模型：DB 巡檢一律同步跑在排程執行緒，只有重推那一步橋接主事件
迴圈（通話信令共用該迴圈）；非阻塞 `threading.Lock` 防重入；提醒採「先用
條件式 UPDATE 蓋 `last_reminder_at`（比對原始舊值、`rowcount==1` 才算搶
到）、再送」。
→ 新護欄 **G192**

**item 11 時間基準統一**

使用者裁示統一存 UTC。`database.py` 每次取得 MySQL 連線都
`SET time_zone='+00:00'`；SQLite wrapper 的 `NOW()` 由
`datetime('now','localtime')` 改為 `datetime('now')`；新增
`services/time_utils.py`（`now_utc`／`now_tw`／`to_tw`／`assume_utc`／
`utc_epoch_seconds`／`tw_day_range_to_utc`）。

修好的確定 bug：`routers/alert.py` 的 `last_frame_at` 由 SQL `NOW()` 寫
入，卻用 Python `utcnow()` 相減——若 MySQL session 是 +08，`age_seconds`
約 −28500，`recent_frame` 恆為 False，**監視機持續推幀卻永遠回報「沒有裝
置在推流」**，疑為歷史上大量「監控清單空白」故障的同類病灶。
`services/yolo_alert_dispatcher.py` 也有兩處同樣的 `utcnow().timestamp()`
問題；多處 `DATE()`／`CURDATE()` 日期分桶改為台灣日曆日換算成 UTC 區間
（此 bug 是雙向的，台灣 00:00–08:00 兩邊都會歸錯天）。

未做：DATETIME→TIMESTAMP 的欄位型別變更——本機只有 SQLite，wrapper 一律忽
略 `ALTER TABLE ... MODIFY`，在這台機器上測不出任何結果；`call_record`／
`subscription_status` 在 MySQL 完全沒有建表程式碼，真實型別必須先拿到正
式庫的 `DESCRIBE`。

**item 2／3 幽靈帳號與家人綁定**

`routers/pairing.py::create_autonomous_elder` 的 `elder_name` 原本預設
`"長輩朋友"`，而前端自主模式從未傳這個參數——預設值被當成真名寫進
`elder_profile`，這就是正式庫「長輩朋友」幽靈帳號與「0.0」帳號的成因。改
為必填＋基本合法性檢查（至少一個字母／中文字、長度 ≤40），不合格回 400。

移除兩支**不需登入**就能建立／改寫帳號的端點
`/api/pairing/dev/ensure-yuxuan-demo`、`/dev/ensure-gawa-demo`（共 294
行）與前端四個死呼叫；移除長輩配對畫面的「登入宇璿」測試鍵與「無 session
就自動登入宇璿」的退路。

`sandbox/run_autonomous_sandbox.py` 新增 fail-closed 防護：掃 `build/web`
底下的 `.js` 找正式站主機名稱，找到就拒絕啟動；**掃不到任何 `.js` 檔也拒
絕**（例如 `--wasm` 建置看不懂）。判斷依據是用 `dart compile js -O4` 實測
過 `String.fromEnvironment` 的 defaultValue 會以明文字串留在輸出中。

item 3：長輩「我的」分頁開配對對話框時，兩個呼叫點都沒傳
`explicitElderId`，對話框退回猜 `caregiver_id ?? last_elder_id`；兩鍵都
讀不到時 id 為 null，後端照樣回一組看起來正常的配對碼，家屬確認時
`confirm_pairing()` 因為配對碼沒有 `creator_id` 而走「新長輩註冊」分支，
建出一個長輩看不到的幽靈帳號、家屬被綁到幽靈上（沒有 crash、沒有錯誤，綁
定就是沒發生）。改為兩個呼叫點明確傳入，解析不到改 fail-closed。

**item 5／6 通話**

「螢幕關閉後約 2 秒斷線」的根因是全專案**沒有任何 CPU 層級 wake lock**
（唯一的是只撐 10 秒、用途是喚醒螢幕的 `SCREEN_BRIGHT_WAKE_LOCK`）。
`MainActivity.kt`／`elder_screen.dart`／`video_call_screen.dart` 補上
`PARTIAL_WAKE_LOCK`，並補齊 release（先前只有 acquire，全專案
`releaseCallWakeLock` 呼叫處是 0）。監控機那份尤其重要——CPU 被掛起會讓
YOLO 推幀靜默停止。

「一方掛斷、另一方卡在等待中」：`services/socket_app.py::on_disconnect`
從未查 `call_registry`、也從未通知通話對象（只 emit 前端無人監聽的死事件
`user-left`）。改為延遲 `_DISCONNECT_CALL_GRACE_SEC=17` 秒再通知，比前端
既有 15 秒重連寬限期略長，避免破壞「訊令瞬斷不該立即殺死通話」的既有設
計。

未修：長輩在 App 背景時撥出視訊「進得了房但 WebRTC 連不上」。需要 Android
實機先診斷，方案 A（重用 `flutter_callkit_incoming` 內建的 `phoneCall` 前
景服務）已核准但尚未實作。

**item 7／8 AI 助理誠實性**

`services/tools_service.py::notify_family_SOS` 原本只用長輩自己的 4 碼
`elder_id` 查 `family_elder_relationship`，而派送端
`yolo_alert_dispatcher` 查同一件事用的是三向 OR（該表的 `elder_id` 實際
存在「存成 user_id」的資料形狀）。後果是反方向的說謊——謊稱「你沒有綁定
家人」、直接叫長輩自己打 119，即使同一位長輩跌倒時派送鏈其實找得到家屬。

五條「最終只能叫長輩打 119」的分支全部先推開發者主控台
（`services/developer_escalation.py`，migration 013
（`013_escalate_emergency_alerts.sql`）的 `escalated_to_developer`／
`escalated_at`／`escalation_reason` 三欄，與 item 12 共用同一張表）。

語音撥號：`widgets/google_assistant_overlay.dart` 原本完全不解析任何動作
標記（連既有的 `[VIDEO_ID:xxx]` 都會被原文念出來）。新增
`[AUTO_CALL:video|audio]` 與 `[AUTO_CALL_FRIEND:...]` 解析，由**長輩端自
己**建構 `ElderScreen(autoCall: true)`，後端不代替長輩發起 WebRTC offer。

確認語的安全網：`flutter_tts` 4.2.5 沒開 `awaitSpeakCompletion` 時
`speak()` 一開始念就返回，畫面會在長輩聽到「我幫您打電話給某某」之前就跳
走；而直接開 `awaitSpeakCompletion` 更糟——兩個 `onError` 多載都只設
`speaking=false`、從不呼叫 `speakCompletion()`，TTS 一出錯 Future 永遠不
返回、撥號被卡死。改為 `_speakAndWait()`：完成與錯誤兩個處理器加 8 秒逾
時兜底。

家屬端排程助理（`routers/ai.py::family_copilot_chat` 的
`QUERY_ELDER_STATUS`）原本心情分數、用藥狀態、活動狀態全部由模型自由發
揮，規則備援更直接寫死「今日用藥全數完成」「正在客廳休息放鬆」、
`mood_score=90`。改為 Python 端先查真實資料、`status_summary` 由 Python
組出、模型只負責轉述；`mood_score` 改為 null（沒有任何真實依據）。並新增
家屬端麥克風輸入（辨識結果只填進輸入框，**不自動送出**；不加任何背景常駐
監聽）。

未做：長輩端「語音排行程」——`TOOL_MAP` 沒有建立提醒的工具，需要另外設計
「小嘎念出行程、長輩確認」的流程，留待下一輪。

**通知文案依類型分流**

`lib/services/cctv_alert_notification.dart::show()` 原本標題與內文一律寫
「🚨 偵測到跌倒」「XX 可能跌倒，請立即查看監視畫面」，完全不看
`alertType`——長輩對小嘎開口求救（`sos_voice`，**沒有**監視畫面）時，家屬
在背景收到的卻是跌倒通知還被叫去看監視畫面。改為六類型 × 首次／提醒共
12 組文案。channel 的 `name`／`description` 一併更新（**`_channelId` 不
可改**，改了等於建新 channel，使用者既有設定全部失效）。
→ 新護欄 **G196**

**G102 違規（本輪查出的既有缺陷）**

`elder_screen.dart::dispose()` 與 `elder_home_screen.dart::dispose()` 無
條件把 `Signaling` 單例的回呼設為 null。長輩結束通話走
`globals.dart::safeNavigateBack()` → `navigator.pop()`，首頁在
`Navigator.push(...).then()` 的 microtask 裡重新綁定，**但 ElderScreen
的 `dispose()` 要等退場動畫結束才執行**——順序是「首頁先重新綁定 → 通話
畫面才清成 null」，於是長輩每講完一通電話，首頁就再也收不到主動關懷訊
息，直到 App 重啟。改為 G102 要求的 `identical()` 守衛。
→ 新護欄 **G197**

**其他**

- 🚨 `routers/activity.py` 資料外洩：`family_id` 是 Optional，沒帶就完全
  跳過綁定檢查；解析不到長輩時 fallback 成「全系統最新建立的那位長輩」，
  再不行寫死 `elder_user_id = 13`，然後回傳完整 `activity_log`。合法家屬
  打錯一個字就會看到陌生長輩的紀錄。改為解析不到回 404、不 fallback。
- 用藥打卡誠實性：`completeElderReminder` 的三個呼叫點原本兩個是
  `unawaited(...)`、連回傳值都不等，API 失敗照樣寫入本機「已完成」，三個
  畫面一起顯示已完成，長輩反而比修之前更無從察覺。改為讀 bool，失敗回退
  樂觀更新（含收回小豬已經講出口的「打卡成功」台詞）。
- 健康與情緒圖表移除全部假資料：心率／血壓／血糖全庫零欄位，保留版面顯
  示「--」且不畫任何曲線；身高體重新增 `elder_body_metrics` 時間序表真實
  串接；情緒改為「近期負面情緒關注事件」列表（`happy`／`calm` 從不落地，
  連續曲線在資料上不可能成立）。
- 節氣：`almanac_data_helper.dart::getCurrentJieQi()` 的 fallback 是死碼
  （判斷條件與 `getJieQi()` 完全相同），節氣徽章一年約 358 天不出現；另
  修 5 個節氣的簡體字。
- 鐵律 #1 同類問題：新聞三個畫面寫死正式站網址（也會讓沙盒防護對每一個建
  置誤判）、`pet_studio_screen.dart` 兩處寫死 `ElderHomeScreen(userId:
  1)`。
- `tests/conftest.py` 預設 `DISABLE_DB=true`：`.env` 的 `DB_HOST` 指向正
  式庫、`load_dotenv()` 不覆蓋既有環境變數、autouse 的 `cleanup_db` 每個
  測試前後都會 DELETE——原本任何人跑 pytest 都可能直接寫到正式資料庫。
  → 新護欄 **G194**

**已知限制（本輪刻意不改）**

`sos_voice` 與 CCTV 警報共用同一個固定通知 ID 8811，時間相近時後到的會覆
蓋前一則；持續中的跌倒每 15 秒推播一次是既有設計。

**新增護欄**

本輪新增 **G191–G197**（狀態機合併窗口 G191；排程執行模型 G192；推播誠
實性 G193；測試環境 G194；一次性 migration 判定 G195；通知文案分流
G196；G102 守衛時機 G197；條文見 §7.2）。護欄檔
（`CLAUDE_call-monitor-guardrails.md`）開頭護欄總數同步更新為 **197**。

**驗證**：隔離 SQLite 腳本 25/25；`pytest tests/test_call_signaling.py`
41 passed（與基準一致）＋ `test_alert_insert_paths.py` 3 passed；
`flutter analyze` 0 error／87 issues；`tsc -b --noEmit` 0 錯誤；
`npm run build` 成功。**本輪未同步 graphify**（使用者已要求暫停）。

### 2026-09-16 — 第四十八輪：警報彈窗抑制、溢位修正、監控清單消失根因、管理端資料表與主題、隱私權政策

**背景**

使用者提出六項需求：(1) 家屬正在觀看某台監控機的即時畫面時，該台監視機的緊急警
報不要再彈窗打斷，改成只朗讀提醒；(2) 修正使用者截圖回報的 RenderFlex 溢位
（`RIGHT OVERFLOWED BY 1.6 PIXELS`）；(3) 管理端網頁補上深色／淺色主題切換，並
把兩個除錯區塊改成可搜尋清單而非手動輸入 ID——使用者原話：「否則管理者記不住大
量使用者資料，還要開資料庫來看，那不如直接在資料庫操作就好」；(4) 刪除隱私權政
策裡的「能否拒絕」條款；(5) 確認 `Uban/` 與 `uban-api/` 兩個 repo 皆為 private，
不用擔心 `.env`；(6) 排查遠端監控裝置清單偶爾整個消失、切換分頁再切回來才恢復的
問題。

**項目 A（前端）家屬正在觀看該台監控時，緊急警報只朗讀不彈窗**

`family_main_screen.dart::_presentCctvAlert()`：把既有的 `alreadyViewingThisDevice`
判斷從「決定要不要顯示『查看監視畫面』鍵」提前到「3) 朗讀」之後、「4) 彈窗」之
前，同一台正在被觀看時直接 `return`，不再跳出 `AlertDialog`。

四個不可破壞的前提，逐一驗證過：
- 語音 `_alertTts!.speak(...)` 在 return **之前**已執行，不受影響；
- `_activeAlerts.insert` 是呼叫端 `_handleCctvAlert` 在呼叫本方法**之前**就完成
  的，警報卡片高亮不受影響；
- 只比對**同一台** `deviceIdStr`——家屬在看 B 房間即時畫面時，A 房間的跌倒警報
  **仍會正常彈窗**；
- `_cctvAlertDialogOpen` 只在 return 之後才設 `true`，旗標狀態對
  `_isSafeToShowFamilyTutorial()` 維持一致，不會讓教學誤判成「彈窗開著」。

連帶簡化：原本 `canView` 判斷式裡的 `!alreadyViewingThisDevice` 在提前 return 之
後恆為 `true`，已拿掉這個多餘判斷（走到那一行時 `alreadyViewingThisDevice` 必為
`false`）。

**關鍵風險**：`_viewingMonitorDeviceId` 的用途因此被擴大——它原本（第四十輪）只
決定要不要隱藏一顆按鈕，現在決定的是**整個彈窗要不要出現**。旗標若卡住沒被清
除，家屬會**靜默**收不到該台監視機的警報彈窗，比第四十輪的「多一顆按鈕」風險高
得多。已同步更新 `_openMonitorViewForDevice()` 設值處的註解，說明任何新增的
「離開監控檢視」路徑都必須確保 `.then()` 對本旗標的清除會被觸發，或自行清除。
→ 新護欄 **G186**

**第四十輪只做了一半**：當時的年表把需求記成已完成，但實際只拿掉了「查看監視畫
面」鍵，彈窗本身照樣彈出——這輪才是真正做完。

**項目 B（前端）刪除溢位指示**

使用者截圖顯示 `family/family_interaction_tab.dart`「遠端視訊監控」卡片有
`RIGHT OVERFLOWED BY 1.6 PIXELS`。三處修正：
1. `_alertTypeLabel(...)` 警報類型徽章 → 包 `Flexible` ＋ `maxLines: 1` ＋
   `overflow: TextOverflow.ellipsis`；
2. `'長輩在此'` 徽章（11pt）→ 同上；
3. `'觀看 CCTV'` 按鈕 → 文字包 `Flexible` 並加 `ellipsis`、縮小 padding／icon、
   取消預設最小按鈕尺寸。

**機制**：外層 `Row` 裡 `Expanded(裝置名稱)` 只能吸收「扣掉其他元素固有寬度後還
剩下的」空間；一旦「按鈕＋管理選單」固有寬度總和本身就超出卡片可用寬度一點點，
`Expanded` 再怎麼收縮也救不了——溢位量正是那一點點，與截圖的 1.6px 相符。兩個徽
章的成因同源但更隱蔽：徽章本身固定寬度、緊跟在 `Flexible(裝置名稱)` 後面，裝置
名稱可以收縮到 0 但徽章不行；系統字體放大（textScale）時徽章文字變寬，比窄螢幕
更容易踩到。

**項目 C（管理端＋後端）深色／淺色主題 ＋ 資料表顯示內容**

- **主題**：「系統／亮／暗」三顆按鈕從側欄 `sidebar-footer` 搬到頂欄
  `topbar-actions`（`Layout.tsx`）。原因：`index.css` 在 <900px 媒體查詢把
  `.sidebar-footer` 設 `display: none`，窄螢幕上原本的位置根本看不到。
  `useTheme()` 設置／移除 `document.documentElement` 的 `data-theme` 並寫入
  `localStorage['uban_admin_theme']`。
- **資料表**：`AccountsPage.tsx` 原本兩個區塊都要手動輸入 ID 才查得到東西，正是
  使用者抱怨的點。改成：`TierSection` 改為可搜尋／排序的長輩清單（沿用
  `/developer/users`，`queryKey ['elders']` 與 `EldersPage` 共用快取），點選後才
  進詳情；`BanSection` 接上 `prefill`／`onConsumePrefill` props，可從
  `TierSection` 的家屬列點「查封禁狀態」直接帶入，另加一份同樣沿用 `['elders']`
  快取的長輩帳號可搜尋清單，手動輸入入口保留。
- **後端補兩行**：`routers/developer_users.py` 的 `/users` 與
  `/users/{elder_id}` 回應 dict 各補 `"user_id": ...`——SQL 本來就已
  `SELECT ... user_id`（還拿去 JOIN `activity_log`／`call_record`），組回應時漏
  放，導致前端拿不到長輩本人的帳號編號；`types.ts` 的 `ElderRow`／
  `ElderDetail` 各補 `user_id: number`。
- 已確認 `PetSeasonsPage.tsx` 的 `viewingSeason` 是清單點選觸發，不受本輪影響，
  不需改。

**項目 D（前端）刪除隱私權政策的「能否拒絕」條款**

`lib/data/privacy_policy_content.dart` 刪掉 10 行 `'**能否拒絕**：…'`（218 →
208 行）。驗證：其餘四類（收集什麼／為什麼／怎麼保護／保存多久）各維持 10 條、
`PrivacyPolicySection(` 維持 16 個、全 `lib/` 224 個 `.dart` 檔 `能否拒絕` 殘留
0 處。

**項目 E（無程式碼改動）repo 私有性確認**

使用者確認 `Uban/` 與 `uban-api/` 兩個 repo 皆為 private。據實記錄：`.env` 仍在
git 追蹤中，含 `DB_PASSWORD`、`PINECONE_API_KEY`、`GEMINI_API_KEY`、
`REVENUECAT_WEBHOOK_SECRET`、`DEVELOPER_PASSWORD_KEY`——repo 若日後轉為 public
或對外分享，必須先處理這份檔案。

**項目 F（前端）遠端監控裝置清單偶爾整個消失的根因**

**根因（本輪最重要的發現）**：`ApiService.fetchMonitorDevices()` 的實作是
`fetchMonitorDevicesOrNull() ?? const []`（見護欄 G78）。任何請求失敗／逾時／後
端短暫異常都被這層包裝**吞成「成功，但清單是空的」**，型別上與「這位長輩真的一
台監視機都沒有」**完全無法分辨**；而 `_applyDeviceList()` 對兩者一視同仁，一律
`setState(() => _monitorDevices = monitors)` 覆蓋。每 10 秒一次的 HTTP 交叉驗證
只要逾時一次，畫面就被洗成空的，直到下一輪（最快 2.5 秒的 Socket 輪詢或 10 秒後
的下一次 HTTP）才補回來——使用者回報的「切走再切回來就恢復」，其實是**剛好等到
了下一輪成功的刷新**，清單一直都在自我修復，不是切分頁這個動作本身修好了它。

**修法**：`family_main_screen.dart` 的 HTTP 交叉驗證路徑加
`if (devices.isEmpty) return;`，空陣列視為暫時性異常、不套用。

**為什麼不會弄壞離線偵測**（必須寫清楚，否則下一個人會誤判這條修改很危險）：真
正的「裝置被刪除」走後端 `_broadcast_elder_devices_update` 即時推播、以及本檔刪
除按鈕成功後的本地 `removeWhere`，兩者都**不經過**這條 HTTP 路徑；「上線→離
線」由 `_applyDeviceList` 自己的 2.5 秒 debounce 負責，不受本次修改的條件影響。
→ 新護欄 **G187**

**另一則觀察：鐵律 #14 的例行 8 畫面檢查，在設計上抓不到本輪這處溢位**

例行檢查的判準是「同列有 **≥18pt** 標題且同列還有其他元素」，但項目 B 那處溢位
的 `'長輩在此'` 徽章是 **11pt**，遠低於門檻。本輪獨立跑了一次 8 畫面靜態掃描
（長輩端首頁／電話／社群／聊天／我的，家屬端首頁／互動／資料），共 27 處符合字
級判準，逐一核對後**沒有一處需要動手**（多數是固定短標籤如 `'安全登出'`、
`'留言'`、單一 emoji，且所在 `Row` 多為 `MainAxisSize.min` 或置中對齊）——也就
是說例行檢查跑出「乾淨」的同時，使用者眼前正有一處真實溢位。

**結論：例行檢查是必要但不充分的，不能因為它通過就宣稱畫面沒有溢位。** 小字級但
固定寬度的元件（徽章、按鈕、圖示）擠在同一列時，同樣會溢位，而且更難用靜態判準
抓到。
→ 新護欄 **G190**

**附註（本輪流程事故，兩則）**

1. 項目 C 用 `npx tsc` 檢查型別錯誤，帶顏色的輸出把 ANSI 色碼夾在檔名與行號之
   間（`src/x.tsx` 後接跳脫序列才是行號），讓針對「檔名:行號」的 grep pattern
   靜默回空、看起來像零錯誤。改用 `tsc --pretty false` 後才抓到實際結果。
   → 新護欄 **G188**
2. 項目 C 的 `BanSection` 用 `useRef` 記錄「`prefill` 這個值已消費過」，但只在
   消費時設定該 ref，沒有在 `prefill` 歸零的分支一併重置——`null → N → null →
   N` 的第二次會被誤判成重複消費而不觸發。已在歸零分支一併重置 ref。
   → 新護欄 **G189**

**新增護欄**

本輪新增 **G186–G190**（跨端 G186；前端 G187；流程 G188；管理端 G189；流程／UI
G190；條文見 §7.2）。護欄檔（`CLAUDE_call-monitor-guardrails.md`）開頭護欄總數
同步更新為 **190**。

### 2026-09-13 — 第四十七輪：移除監控機的「跌倒測試」按鈕

**背景**

使用者要求移除監控機（CCTV 模式）畫面上的「跌倒測試」按鈕。這顆按鈕自第十七輪加
入以來，一直標註為「暫時性測試入口，YOLO 可實測後即可移除」。

**做了什麼（前端 -147 行）**

`elder_screen.dart` 刪除 `_testFallSending` 旗標、`_sendTestFallAlert()` 方法、按
鈕 UI（`Positioned` 區塊），共 -87 行；`cctv_alert_api.dart` 刪除
`triggerTestFall()`；`api_service.dart` 刪除委派方法、檔頭註解移除「跌倒測試」字
樣；`friend_service.dart` 檔頭註解原本舉 `triggerTestFall` 當「回傳 `String?`、
`detail` 錯誤慣例」的範例，改舉同慣例的 `saveZoneConfig`。

**後端一律保留不動**：`POST /api/cctv/test-fall`、
`call_security.test_fall_enabled()`、`.env.example` 的
`CCTV_TEST_FALL_ENABLED=false`、護欄 G43 全部維持原狀。理由：§9 除錯手冊把這個端
點列為驗證「跌倒警報派送鏈」（DB 寫入 → Socket/FCM → 家屬端熄屏也要亮起並朗讀）
的手段，刪掉按鈕後仍可用 curl 觸發，保留可測性；端點依 G43 預設關閉、關閉時回
404，無安全風險。

**關鍵風險**：被刪的按鈕與「退出監視機」**相鄰**，而後者是長輩退出 CCTV 模式的唯
一出口。刪錯會讓監控機變成無法離開的畫面。驗收時逐行核對了 `git diff`：三段都是
純刪除、無任何 `+` 行，前後的 `Positioned` 直接接上；反向檢查「退出監視機」的引
用仍全部存在（4 處）。

**連帶影響**（容易漏的一類）：`friend_service.dart` 的檔頭註解引用了被刪除的方法
當程式碼慣例範例。這種殘留不會編譯錯誤、不會被目標關鍵字掃到（搜的是被刪除檔案
本身的關鍵字，不是引用它的其他檔案），只有真的去讀那段註解的人才會發現指路指到
空氣。
→ 新護欄 **G185**

**同步更新的其他文件**：`CLAUDE_call-monitor-ui-map.md` 原本記載「跌倒測試」按鈕
的那一列整列刪除（該文件的定位是「按鈕在哪、按了跳去哪」，留一列指向不存在的按
鈕會誤導只看表格的人，尤其它原本緊貼「退出監視機」），下方說明區塊濃縮成歷史註
記而非整段刪除，保留「後端端點還在、可 curl 測、G43 開關不能亂動」這些仍有效的
事實；本檔 §6.9 派送鏈圖、§6.10 測試方法、§9.2 驗收矩陣也都改成 curl 指令，欄位
名稱對照 `routers/alert.py::trigger_test_fall()` 的簽章（`elder_id`、
`device_name`）核對過。

**新增護欄**

本輪新增 **G185**（跨端；條文見 §7.2）。護欄檔（`CLAUDE_call-monitor-
guardrails.md`）開頭護欄總數同步更新為 **185**。

### 2026-09-13 — 第四十六輪：機構管理端完全移除

**背景**

使用者要求「刪除機構管理端的所有設計（包含資料表、管理介面）」，並裁定兩件事——
除錯用的 API **搬到開發者命名空間**（不是連功能一起砍）、**移除機構員工登入**
（管理端只剩開發者帳號能進）。

**項目 A（後端）新增 `routers/developer_users.py`**

5 支唯讀端點取代原本的機構端點，全走 `Depends(get_current_developer)`：
`GET /api/developer/users`（取代 `/institution/elders`）、
`GET /api/developer/users/{elder_id}`（取代 `/institution/elders/{id}`）、
`GET /api/developer/users/{elder_id}/metrics`、
`GET /api/developer/users/{elder_id}/timeline`、
`GET /api/developer/alerts`（取代 `/institution/alerts`）。改以 `elder_profile`
為主表，不再依賴機構收案關聯。回傳移除了 `room_no`／`care_level`／`enrolled_at`
／`primary_staff`／`assigned_staff`，timeline 少了 `kind="task"` 事件。

**項目 B（前端）管理端改接**

三個除錯頁面改打新端點；`LoginPage` 移除身分切換只剩開發者登入；`session.ts`
刪除 `StaffSession`；側欄警報徽章從 `/institution/overview` 改打
`/developer/alerts?status=active`——刻意不用 `by_type` 總和，那是「近 N 天全部狀
態的次數分布」，拿來當「目前待處理」的角標會把已結案的舊警報也算進去。
`CareLevelBadge` 與 `Overview` 型別因無使用者一併移除。

**項目 C（後端）刪除機構程式碼（共 2384 行）**

刪除 `routers/institution.py`（982 行）、`routers/institution_ops.py`（1033
行）、`routers/institution_common.py`（231 行）、`auth_staff.py`（138 行），四
者共 2384 行；另刪除 `scripts/seed_demo_institution.py` 與
`tests/test_institution.py`。`routers/admin.py` 的
`require_admin_or_developer()` 從「先手動 decode JWT 判斷 `typ`、developer 與
staff 走兩條路徑」簡化成只驗開發者 token。`ALGORITHM`／`SECRET_KEY`／`security`
**不需要搬移**——`auth_developer.py` 本來就有同名同值的定義，改 import 來源即
可，避免產生第三份密鑰定義。

**項目 D（資料庫）刪除 7 張表（實際筆數）**

依外鍵順序（先子表後父表）逐條 DROP，零失敗、不需
`SET FOREIGN_KEY_CHECKS=0`：`care_task`（684 筆）、`care_shift`（128 筆）、
`institution_elder`（20 筆）、`staff_elder_assignment`（20 筆）、`care_staff`
（8 筆）、`shift_swap_request`（6 筆）、`institution`（1 筆）。9 張保護表
（`elder_profile` 26、`user_account_data` 34、`emergency_alerts` 50、
`call_record` 1242、`activity_log` 7099、`developer_account` 3、
`elder_daily_step` 1800、`family_elder_relationship` 26、`subscription_status`
9）筆數一筆未變。

★★ **意外發現①：migration 每次開機重跑，只加註解會讓刪表白做**

`main.py::run_sql_migrations()` **每次開機都重新執行** `scripts/migrations/` 底
下每一個 `.sql`，**沒有「已執行過」的追蹤表**，靠 `CREATE TABLE IF NOT EXISTS`
自身冪等。所以只在 `001_institution.sql` 檔頭加註解、不動內文的話，**DROP
TABLE 做完、後端一重啟，7 張表會透過那份 migration 原封不動生回來**。

處理：把第 1–7 節的 `CREATE TABLE` 逐行註解掉（不刪除任何文字，歷史完整保
留），**但第 8 節 `elder_daily_step` 完全保留可執行**——那張表與機構表同檔但完
全獨立，整檔註解或整檔跳過都會誤傷它。驗證：模擬 `run_sql_migrations()` 的解析
邏輯，確認該檔只剩 1 條會執行的語句。
→ 新護欄 **G182**

**★★ 意外發現②：開發者原本看不到 6 位真實使用者**

管理端查的是 `institution_elder`（機構**收案**長輩），不是 `elder_profile`（全
平台）。對正式庫唯讀實測：26 位長輩中有 20 位被收案，**6 位（`2917`、`0343`、
`7993`、`6160`、`9053`、`5327`）從未被任何機構收案，開發者完全看不到**，其中
`6160` 與 `5327` 還有共 3 筆真實警報也查不到。而且清單上沒有任何提示說少了人。

這直接牴觸管理端的定位（「開發者對個別使用者除錯」）。修法：
`institution_common.py` 的兩個函式與 `institution.py` 的 `list_elders()`／
`list_alerts()` 各自拆成機構員工／開發者兩段獨立 SQL，開發者那半改以
`elder_profile`／`emergency_alerts` 為主表 LEFT JOIN，並加
`discharged_at IS NULL` 避免同一位長輩在不同機構的歷史收案紀錄造成資料重複。
（這幾支後來隨機構模組一起刪除，能力由 `developer_users.py` 承接。）

**★ 過程中修掉的兩個靜默失敗**

- `list_elders`／`list_alerts` 的 raw SQL 裡各還有一個 `institution_id = %s`
  的重複過濾。開發者傳 `None` 進去，SQL 三值邏輯下 `institution_id = NULL`
  **永遠不 match**，query 回空清單**而且不報錯**。共用授權守衛覆蓋不到端點自
  己手寫的 SQL。→ 已是護欄 G177，本輪未新增。
- 前端 `isFullScope()` 放行 admin 或 supervisor，但後端 `admin_stats` 的機構員
  工門檻是 `require_staff_role("admin")`。督導進得去統計頁但三支 API 全
  403，畫面卻顯示每張圖各自的「尚未累積資料」空狀態——**看起來像沒資料而不是
  沒權限**。新增 `RequireAdminOrDeveloper` 守衛（重用既有 `isAdmin()`，語意與
  後端門檻天然對齊）。

**測試沒有降低強度**

三個測試檔原本各有一條「caregiver 角色 token → 403」，測的是 `auth_staff.py`
的 `ROLE_RANK` 角色分級——那個概念隨本輪移除而不存在，硬留著只能靠假造一個不存
在的角色系統來測。改成 `test_legacy_staff_shaped_token_rejected`：偽造一個形狀
與舊機構員工 token 相同的 JWT，斷言仍然 401，**守的是「`auth_staff.py` 刪除後
不能留後門」**。其餘 401 斷言全部原樣保留。

**附帶解除的資安疑慮**：舊文件反覆警告「demo 管理員密碼寫死在
`seed_demo_institution.py`」，隨 `care_staff` 表刪除自動失效——那個帳號已不存
在。

**過程事故（驗證方法論，兩則）**

1. 檢查刪除模組後有無殘留 import 時，字串搜尋把 docstring 與註解裡的提及也算
   進去、且可被改寫註解騙過，三個檔案因此誤報。改用 AST 解析 `ast.Import`／
   `ast.ImportFrom`（`ImportFrom` 要同時比對 `node.module` 與
   `node.module + '.' + alias.name`，否則 `from routers import institution`
   這種寫法會漏掉），`compileall` 只驗語法、抓不到名稱解析錯誤，不能替代。
   → 新護欄 **G183**
2. 驗證「新 API 完全不依賴機構表」時，最初寫成
   `src.count('care_staff') == 0`——測的是「檔案裡有沒有這串字」，不是「有沒
   有真的查這張表」。子代理誠實回報它為了讓檢查回報 0 而刻意在註解裡避開那些
   識別字；真正風險是若其實用了機構表，只要拼成 `"care_" + "staff"` 就能一樣
   回 0。壞指標的副作用不只漏掉問題，還逼執行者為了過關而改動無關的東西（本
   輪連本質安全的 `f"...IN({ph})..."` 都被改寫成字串相加）。改用從非註解程式
   碼抽出 `FROM`／`JOIN`／`UPDATE`／`INTO` 後面的表名、與目標集合取交集。
   → 新護欄 **G184**

**新增護欄**

本輪新增 **G182–G184**（後端 G182；流程 G183–G184；條文見 §7.2）。護欄檔
（`CLAUDE_call-monitor-guardrails.md`）開頭護欄總數同步更新為 **185**。

### 2026-09-11 — 第四十五輪：新手教學捲動、管理端轉開發者定位、統計儀表板、開發者帳號、隱私權政策

**背景**

使用者提出五項需求：(1) 新手教學指引無法自動捲動到目標位置——目標在畫面下方需
捲動才看得到時，教學不會把它捲進視野；(2) 管理員網頁改為開發者定位——不再是長
照機構管理端，改為開發者對個別使用者除錯、賦予權限、接收 BUG；(3) 開發者統計儀
表板——雙端年齡／居住地／緊急警報推送／緊急通話／誤報次數，至少 8 張圖含交叉比
對與熱力圖，另需敘述統計；(4) 三組開發者最高權限帳號——資料庫加密儲存，但網頁
上三人可互看明碼、只能改自己的密碼；(5) 隱私權政策——改成勾選同意才能使用
App，超連結彈出完整政策，內容須涵蓋所有觸及個資的功能。

**項目 A（前端）新手教學支援自動捲動**

`lib/widgets/spotlight_tutorial.dart`：目標元件在畫面下方需捲動才可見時，原本的
高光提示不會把它捲進視野。改成 `await Scrollable.ensureVisible(alignment: 0.3,
duration: 300ms)` 捲動完成**後**才重新量測高光矩形；新增遞增 `_updateToken`，避
免使用者在捲動完成前連按「下一步」時，上一步的過期量測覆蓋新步驟的結果。
`alignment` 選 0.3 而非置中的 0.5，因為提示卡片 `maxHeight` 可達螢幕 55%，置中會
與高光區重疊。既有三種 fallback（無目標步驟／元件未 layout／目標不在任何
`Scrollable` 內）全部保留。

**項目 B（前端）管理端網頁改為開發者定位**

`uban-api/uban-admin/`：移除 `TasksPage`／`SchedulePage`／`StaffPage`／
`StaffDetailPage` 四個機構營運頁面，連同其路由、導覽項目、專用型別（9 個）一併
移除。導覽重構為「數據總覽」＋「使用者除錯」「系統管理」「問題回報」三組；
`LoginPage` 改成可切換「機構員工／開發者」兩種身分登入。後端
`routers/institution.py`／`institution_ops.py` **刻意保留不動**，只拆前端——這
個決定是可逆的，日後若仍需要機構端功能，不必重寫後端。

★ 刪路由留下一個陷阱：`App.tsx` 的 `CAREGIVER_HOME = '/tasks'` 在 `/tasks` 路由
移除後變成死路由——caregiver 登入 → 導去 `/tasks` → 404 → catch-all 導回 `/` →
又導去 `/tasks`，**無限重導向**。`EldersPage.tsx:185` 與
`ElderDetailPage.tsx:200` 也各留了一個連向已刪除員工詳情頁的 `<Link>`。刪路由必
須 grep 整個 `src` 找該路徑字串，不能只看 `App.tsx`。
→ 新護欄 **G176**

**項目 C（後端＋前端）開發者統計儀表板**

`routers/admin_stats.py`（新檔，559 行）新增 3 支唯讀端點（`/demographics`、
`/alerts?days=`、`/calls?days=`），`uban-admin/src/pages/overview/`（5 個新檔）
撐起 10 個圖表卡片，含 3 張熱力圖（縣市×行政區、縣市×警報類型、星期×時段）與 1
張年齡層×誤報率的雙軸組合圖。

★ 樣本數 <2 時，標準差／變異數改回傳 `null` 而非 0——「標準差是 0」代表「樣本完
全相同」，跟「樣本不足無法計算」是不同的事實，回 0 會讓圖表畫出看似有意義但錯
誤的結論。`statistics.variance()` 在 n<2 會拋 `StatisticsError`，接住後回
`null`；前端不把 `null` 顯示成 0，改用「尚未累積資料」／「樣本不足」與真正的 0
分開呈現。
→ 新護欄 **G178**

**項目 D（後端＋前端）三組開發者最高權限帳號**

`services/dev_crypto.py`、`auth_developer.py`、`routers/developer.py`、
`scripts/seed_developer_accounts.py`、`uban-admin/src/pages/
DeveloperAccountsPage.tsx`：雙欄位設計——`password_hash`（passlib
scrypt/bcrypt，供登入驗證）＋ `password_cipher`（AES-GCM 可逆加密，供三人互看明
碼）。金鑰走環境變數 `DEVELOPER_PASSWORD_KEY`，缺金鑰時**直接拋例外，絕不
fallback 成明文儲存**。改密碼端點 `POST /accounts/me/password` 的身分完全來自
token、路徑上沒有 `dev_id` 參數，**結構上就不可能改到別人的密碼**。

**項目 E（前端）隱私權政策**

`lib/data/privacy_policy_content.dart`（新檔）、`lib/widgets/
policy_detail_dialog.dart`（新檔）：政策內容抽成單一權威來源（15 章節，每節含
「收集什麼／為什麼／怎麼保護／保存多久／能否拒絕」），首次安裝關卡與註冊頁共用
同一份內容。`prefsKey` 升版 `_v1` → `_v2`，逼舊使用者重新同意新版本。**完全沒有
動 `splash_screen.dart` 與 `main.dart`**——同意狀態的鍵是常數，啟動流程只是照舊
引用它，不需要改動流程本身。

**項目 F（後端＋前端）緊急通話與誤報埋點**

`services/socket_app.py` 的 `on_call_request`／`on_emergency_call` 各自的
`INSERT INTO call_record` 分別補上 `is_emergency=0`／`is_emergency=1`（僅 6 增／
6 刪，其餘邏輯未動）。新增 `POST /api/alerts/{alert_id}/false-alarm`，授權邏輯
照抄同檔既有的 `acknowledge_alert`，無權一律回 404（沿用 G45）。家屬端
`alert_center_screen.dart` 新增「這是誤報」的二次確認操作，供項目 C 的誤報統計
取用。

**項目 G（後端）資料層**

`database.py` 新增 9 個欄位／1 張新表：`user_account_data` 加 `age`／
`residence_city`／`residence_district`；`elder_profile` 加後兩者；
`emergency_alerts` 加 `is_false_alarm`／`false_alarm_marked_by`／
`false_alarm_marked_at`；`call_record` 加 `is_emergency`；新表
`developer_account`。`ALLOWED_UPDATE_FIELDS` 白名單同步補上新欄位。Migration 寫
在 `scripts/migrations/012_round45_stats_and_developer.sql`，**本輪只寫檔、未對
正式庫執行 DDL**。

**項目 H（前後端）雙端年齡／居住地詢問**

`routers/user.py`、`elder_profile_edit_screen.dart`、`family_settings_view.dart`：
長輩端**原本就有**城市／行政區輸入與 GPS 反查，但存檔時被拼接成單一字串塞進既
有的 `location` 欄位，讀取時再用 `indexOf('市')` 切回來——這正是項目 C 統計做不
出來的根因，結構化資料從未真正落地過。本輪改為**額外**寫入新的結構化欄位
（`residence_city`／`residence_district`），`location` 原本的拼接寫法保留不
動，避免影響既有讀取路徑。家屬端則是從零新增三個選填欄位（手動輸入，無
GPS）。兩端輸入介面都加註「僅供統計、可不填寫」的說明。

**項目 I（前端）例行溢位檢查**

依根 `CLAUDE.md` 第 14 條做了雙端 8 個主介面的例行溢位檢查，**含重構後的子
樹**（`elder_tabs/profile/`：3 個 dialog＋7 個 widget；`family/home/`：7 個
widget＋2 個 sheet＋1 個 dialog），另加本輪新增 UI 的 3 個檔案。

修正 4 處（全部包 `Flexible` ＋ `maxLines: 1` ＋
`overflow: TextOverflow.ellipsis`，並附理由註解）：
`elder_tabs/profile/widgets/storybook_header_card.dart:63`
（`'$greetingTitle，$userName'` 25pt，同列有「守護中」徽章，`userName` 長度
不可控）、`elder_community_screen.dart:618`（留言作者名，
`ElderScale.caption`＝18pt，同列有角色徽章＋`Spacer`＋時間）、
`family/family_data_tab.dart:1016`（`elder.displayName` 20pt，同列有「長輩
端: Exxx」徽章）、`elder_tabs/elder_chat_tab.dart:1194`（**固定字串**
`'正在為您想辦法...'` 28pt w900，同列有 36px spinner＋22px 間距）。

★ 最後一處是固定字串仍然要修——這正是第 14 條「判準是**字級 × 同列元素
數**，不是字串是不是動態」的案例。實算：360dp 螢幕扣掉氣泡
`padding: horizontal 26`（52px）、spinner 36px、間距 22px 後剩約 250dp，而
8 個中文字 × 28pt ≈ 266dp，會溢位。

另有 5 處列出但判定不修：`'今日頭條'` 26pt、`'分享近況'` 30pt、`'留言'`
30pt、`'受關照長輩檔案'` 18pt 等——**關鍵差異是它們同列有 `Spacer`**。
`Spacer` 是彈性元件，會**吸收**剩餘空間而非爭搶，只要固定元素總和不超過可
用寬度就不會溢位；真正危險的是**固定元素緊鄰**的結構（像思考泡泡的
spinner ＋ 間距 ＋ 大字，三者都有固定寬度需求）。這個「有無 `Spacer`」的判
準補進第 14 條目前只講「字級 × 同列元素數」、未區分同列元素是彈性還是固定
的空缺。
→ 新護欄 **G181**

★★ **意外發現①：修好一個正在正式環境線上壞著的 500 bug**

`routers/user.py::update_profile()` 的 `update_fields`／`update_values` 兩個
list **從未初始化**，但下面有大量 `.append()` 呼叫——AST 掃描 `HEAD` 版本確認初
始化次數為 **0**，任何呼叫必定 `NameError` → 500。`POST
/api/user/profile/{user_id}` 正是長輩資料編輯頁「儲存」按鈕打的端點，代表**只要
遇到長輩帳號，這個端點在正式環境過去一直是壞的**——長輩資料編輯的儲存功能從未
真正成功過。本輪項目 H 順手一併修正。

★★ **意外發現②：開發者看不到 6 位真實使用者**

管理端的「使用者列表」與「警報中心」原本查的是 `institution_elder`（機構**收
案**長輩），不是 `elder_profile`（全平台長輩）。對正式庫唯讀實測：
`elder_profile` 共 **26 位**，`institution_elder` 收案中僅 **20 位**，未收案而
開發者原本完全看不到的有 **6 位**（elder_id：2917、0343、7993、6160、9053、
5327），其中 **6160** 與 **5327** 有真實警報紀錄共 **3 筆**，開發者原本也查不
到。

修法：`routers/institution_common.py` 的 `institution_elder_ids()`／
`assert_elder_in_institution()`，以及 `routers/institution.py` 的
`list_elders()`／`list_alerts()`，各自拆成「機構員工」與「開發者」兩段獨立
SQL；開發者那半改以 `elder_profile`／`emergency_alerts` 為主表 LEFT JOIN，不再
受限於收案關係。**機構員工那半的 SQL 與參數逐字未變**（用「逐一比對 alert_id
集合」而非只比對數量驗證過，避免退化成假驗證）。

過程中發現並修正兩個連帶問題：

- 開發者 token 通過 `institution.py` 時，這兩支端點內部的 raw SQL 裡各自還留著
  一個 `institution_id = %s` 的重複條件——開發者的 `institution_id` 是
  `None`，SQL 三值邏輯下 `institution_id = NULL` **永遠不 match**，查詢靜默回
  空清單、**不會報錯**。共用授權守衛換掉 `Depends` 覆蓋不到端點自己手寫的 SQL
  二次過濾。
  → 新護欄 **G177**
- `institution_elder` 的唯一鍵是 `(institution_id, elder_id)`，同一位長輩可能
  在不同機構各留一筆歷史收案紀錄。機構員工查詢已先用 `institution_id = %s` 鎖
  到一間機構、最多一筆；但開發者是跨全平台查，LEFT JOIN 若不加
  `discharged_at IS NULL`，一位長輩有兩筆歷史收案就會讓警報／長輩重複出現。
  → 新護欄 **G180**

**附註（本輪流程事故，三則）**

1. team-lead 驗收三份子代理任務清單時，用 `npx tsc --noEmit` 檢查 TypeScript 型
   別錯誤，三份回報皆「No errors found」。`uban-admin/tsconfig.json` 是
   solution-style（`{"files": [], "references": [...]}`），不加 `-b` 只檢查空陣
   列、**永遠回 EXIT 0**。實測探測檔驗證：`const n: number =
   "definitely-a-string";` 用 `--noEmit` 回 EXIT=0 零輸出，換成 `-b --noEmit`
   才抓到 `TS2322`；重跑後發現 `Layout.tsx` 早有 3 個既有型別錯誤。
   → 新護欄 **G173**
2. 檢查中文檔案的違規語法時用 `grep -ciF` 直接 SIGABRT（exit 134、輸出空字
   串），`$(...)` 代入後看起來像「0 筆、通過」；`flutter analyze` 的錯誤計數用
   `grep -c 'error •'` 也抓不到——這台機器的輸出用 `-` 分隔不是 `•`，正確判讀要
   看總結行「N issues found」與 `-` 計數相加是否一致。
   → 新護欄 **G174**、**G175**
3. team-lead 為了清 `start)` 這個垃圾檔，用 `^[A-Za-z0-9_.\-]+$` 當「合理檔
   名」判準，**把 `uban-api/管理者系統使用說明.md`（22,810 bytes、408 行的交付
   文件）一併判定為垃圾並刪除**——這個專案大量使用中文檔名。已用 `git
   checkout` 還原。往後清垃圾檔只認 `git status --short` 的 `??`（`??` 才是新
   垃圾，`M` 或只有刪除行的 diff 是既有檔案被清空，要還原不是要刪）。
   → 新護欄 **G179**

**查證但未修的既有問題（供下一輪參考）**

1. **封禁（`account_ban`）自第四十四輪起只做記錄，本輪仍未在登入流程強制生
   效**——與開發者帳號一樣走 `routers/admin.py`，尚未接上。
2. **付費皮膚購買流程仍未接金流**（第四十四輪已記錄，本輪未變動）。
3. **`health_report_service.dart` 仍是死碼**（第四十四輪已記錄，本輪未變動）。

**新增護欄**

本輪新增 **G173–G181**（流程 G173–G175、G179；管理端 G176；後端 G177、G180；跨
端 G178；前端 G181；條文見 §7.1／§7.2）。護欄檔（`CLAUDE_call-monitor-
guardrails.md`）開頭護欄總數同步更新為 **181**。

### 2026-09-09 — 第四十四輪：分支合併與重構修復、寵物賽季制、管理者系統擴充、YOLO 睡眠誤報

**背景**

本輪工作分兩層：先合併 `origin/main` 帶來的大規模模組化重構、排除其自帶的編譯錯誤，
再處理使用者提出的第三～七項需求——寵物養成賽季制、賽季重置與付費皮膚、管理者系統擴
充、家屬端 BUG 回報、YOLO 區分跌倒與睡覺，以及作品提案規劃書改寫。

**項目 A（前端）合併 origin/main 的大規模模組化重構**

`origin/main` 做了一次大重構：`main.dart` -699 行、`elder_profile_tab.dart` -2187
行、`family_home_tab.dart` -3726 行、`api_service.dart`（2038 行）拆成 9 個模組
（`services/api/*.dart`）、FCM 背景處理器抽成 `services/firebase_bg_handler.dart`。

合併本身**零衝突**（本地只領先一個文件 commit）。但合併後 `flutter analyze` 出現 29
個 error——**這些是 `origin/main` 自己帶進來的，不是合併造成的**。三類：

1. **缺 import**（5 個）：搬進來的程式碼用到 `jsonDecode`／`defaultTargetPlatform`，
   沒帶 `dart:convert` 與 `flutter/foundation.dart`。
2. **相對路徑層數算錯**（17 個：`storybook_stage_card.dart` 11 個、
   `home_alert_preview_card.dart` 6 個）：`storybook_stage_card.dart` 在
   `elder_tabs/profile/widgets/`，`../../` 只回得到 `elder_tabs/`，但目標在
   `screens/` 底下，要 `../../../`；`home_alert_preview_card.dart` 同類問題。
3. **抽出時遺失區域變數**（7 個）：`todayStr`／`cs`／`isDark` 定義在另一個方法內，
   被搬到 `_buildUnifiedTimelineCategoryCards()` 的程式碼取不到。

★ **這一項最重要的教訓**：`storybook_stage_card.dart` 的 11 個錯誤中，3 個是
import 路徑錯（`uri_does_not_exist`）、8 個是符號未定義（`PetGrowthState` 2 個、
`ActorMood` 4 個、`HandDrawnPigletActor` 與 `PetGrowthScaleCard` 各 1 個）。原本
判斷「修好 3 個路徑，8 個符號錯誤會一起消失」，實際只消掉 4 個（`PetGrowthState`
2 個＋`HandDrawnPigletActor`、`PetGrowthScaleCard` 各 1 個）——剩下 4 個
`ActorMood` 是另一個獨立問題：這個 enum 定義在 `animated_piglet_actor.dart`，而
`hand_drawn_piglet_actor.dart` 雖然 import 了它但**沒有 `export`**，**Dart 的
import 不會傳遞可見性**。這是把「症狀數」當成「根因數」的誤判。正確做法是先修、
再跑 analyze、再補——而不是照推論一次寫完就宣稱好了。
→ 新護欄 **G167**

第 3 類的日期字串必須**逐字複製**原本的補零寫法。格式一旦不同，`rawDate == todayStr`
會恆假，「今日生活動態」的日期標籤靜默失效，而**編譯是綠的**。

★ 大型重構還留下一個掃描盲點：`family_home_tab.dart` 從 3726 行被掏空到 289 行，內
容搬進 `family/home/widgets/`——本輪跑既有的 RenderFlex 溢位掃描（見根 `CLAUDE.md`
鐵律 #14）時，家屬首頁一度回報「無可疑處」，但那只是因為掃描掃到的是空殼，真正的內容
已經不在原檔案裡。所有「逐檔掃描」的例行檢查在大型重構後都要重新確認涵蓋範圍。
→ 新護欄 **G172**

**驗證**：三類共 29 個 error 逐一排除，`flutter analyze` 恢復乾淨。

**項目 B（前後端）寵物養成賽季制（第三項需求）**

- 新增 `pet_stage_threshold` 表：五階段門檻改為**線性等距，每階 20 公斤**
  （0/20000/40000/60000/80000 公克），取代原本寫死在 Dart 的非線性值（15/35/65/90
  公斤）。放進資料表是為了讓管理者調整而不必改程式碼。
- 新增 `pet_season` 表：一季三個月，惰性建立。
- `routers/pet.py` 新增 `GET /thresholds`、`GET /season`、`GET
  /food-unlocks/{elder_id}`。
- 前端新增 `pet_progress_service.dart`，**本地 fallback 用的是同一組新線性值**——否
  則離線與連線時會顯示不同階段。
- 食物解鎖從「只認步數」改成「步數**或**用藥打卡」。修正前「或按時服藥」只是顯示文
  字，承諾了做不到的事。
- ⚠️ 運動解鎖**預留但未啟用**：`activity_log` 的 `exercise` 事件全專案只有讀取端、
  **沒有任何寫入路徑**，納入會變成永遠不成立的死條件。

**項目 C（後端）賽季重置與付費皮膚（第四項需求）**

- 新增 `pet_season_settlement` 表保存每季結算。**重置前必須先結算**——否則排行榜歷
  史全部消失、長輩三個月的努力歸零且無跡可循。
- `POST /api/admin/pet-seasons/reset` 全程在單一交易內，任一步失敗即整個 rollback。
- **重複呼叫防護兩層**：對 `pet_season.status` 做 `UPDATE ... WHERE status='active'`
  的原子條件更新（只有 `rowcount==1` 才繼續）＋ `UNIQUE(season_no, elder_id)`。並發
  測試用 `threading.Barrier` 讓兩個 thread 同時打，連跑五次穩定。
  → 新護欄 **G168**
- 體重重置目標 **1250 公克**，來源是前端 `pet_growth_state.dart` 的預設起始值（實際
  讀檔確認）。
- 新增 `pet_skin`／`elder_pet_skin_ownership`／`elder_pet_skin_selection` 三張表。擁
  有權判斷唯一權威在 `routers/pet.py::_elder_owns_skin()`。
- 購買流程本輪不做（金流）。接上點：付費成功回呼只需 INSERT 進 ownership 表。

**項目 D（前後端）管理者系統擴充（第四項需求）**

⚠️ **管理者系統本來就存在且已部署**（`uban-admin/` 掛在 `/admin`，實測回 200），本輪
是擴充不是從零建。

- 新增 `bug_report`／`account_ban`／`admin_action_log` 三張表。
- `routers/admin.py` 17 個端點，`/api/admin/*` 全部以
  `Depends(require_staff_role("admin"))` 保護。
- `POST /api/bug-report` 供 App 提交（刻意未認證，因此加了長度上限、頻率限制、回報
  者存在性驗證）。
- 管理端新增三個頁面：BUG 回饋、帳號管理、寵物賽季與皮膚。
- ⚠️ **封禁本輪只做記錄，尚未在登入流程強制生效**。登入是所有使用者的必經路徑，在
  本輪同時進行多項改動時動它風險過高。

**項目 E（前端）家屬端 BUG 回報（第五項需求）**

放在家屬端「資料」分頁最下段的獨立群組。

★ **一個值得記的設計決定**：刻意**不用 `ApiService.post()` 門面**——那支門面只在
200/201 回傳 body，其餘狀態碼一律吞掉、呼叫端拿不到 `statusCode`，而這支端點的
404／429／422 需要分開顯示。另外 422 的 `detail` 是 Pydantic 錯誤**清單**不是字
串，直接轉述給使用者會是一串英文物件，所以四種錯誤都用寫死的白話文案。
→ 新護欄 **G170**

**項目 F（後端）YOLO 區分跌倒與睡覺（第七項需求）**

**症狀**：躺著靜止 15 秒即推 `prolonged_inactivity` 警報，睡覺必然觸發。

**修法**：新增 `_classify_lying_entry()`，由 bbox 長寬比的過渡歷史判斷「進入躺姿」
是驟然（跌倒）還是漸進（主動躺下）。gradual 改用坐立的兩小時門檻，abrupt 維持 15
秒。

★ **刻意不選「gradual 就完全不推」**：分類會被快取，一旦判成 gradual，整段睡眠期間
就**永久靜音**——萬一使用者在睡眠中途發生醫療突發（中風、呼吸停止）而不再移動，這條
路徑永遠不會有第二次機會示警。用長門檻而非靜音，保留一道安全網。

★ **Fail-safe 方向**：歷史不足以判斷進入速度時一律當成 abrupt（會推警報）。**漏報
跌倒的代價遠大於誤報睡覺**——一位跌倒的長輩沒被偵測到可能躺數小時無人知曉，誤報一次
睡覺只是一則不必要的通知。證據不足時偏向推警報。也**明文禁止**「夜間一律不推」這種
一刀切——夜間跌倒仍是跌倒，而且往往更危險。
→ 新護欄 **G169**

**項目 G（文件）作品提案規劃書改寫（第六項需求）**

改寫 `D:\114project\Documents\` 的提案書，讓內容符合實際系統。發現並修正兩處過譽：

1. **「每週 AI 情緒與作息分析報告」**（出現三處，含**商業模式的付費賣點**）——前
   端有 `health_report_service.dart`（21.5 KB，含週報／月報 PDF 產生器）但**零引
   用**，是寫好沒接上的死碼。改寫成真實存在的每日新聞語音播報。
2. **「緊急時顯示 GPS 定位」**——警報**不帶座標**。GPS 本身存在且完整
   （`getPositionStream` + 卡爾曼濾波 + 路徑持久化），但那是**戶外散步路徑記錄**，
   與緊急定位是兩回事。

**附註（本輪流程事故）**

驗證修復時，一個未加引號的 shell 重導向把 `uban-api/Dockerfile` 整個清空成 0 位元
組（53 行全沒），而 `git status` 只顯示 `M Dockerfile`，外觀上像是正常修改，已復
原。
→ 新護欄 **G171**

**查證但未修的既有問題（供下一輪參考）**

1. **室內定位的區域校準介面已於 2026-08-24 下架**（產品決策），`load_zones()` 現在
   對幾乎所有裝置恆回空陣列。程式碼裡的具名區域分類（客廳／廚房）邏輯完整且測試通
   過，但**沒有任何操作介面能設定它**。實際運作的是更粗的「是否在鏡頭前」那一層
   （依訂閱層級 15／7／3 秒更新）。
2. **`health_report_service.dart` 是死碼**（21.5 KB，零引用）。要嘛接上，要嘛刪
   除，留著會讓人以為週報功能存在。
3. **`activity_log` 的 `exercise` 事件只有讀取端、沒有寫入端**，導致
   `food-unlocks` 的運動計數恆為 0。
4. **`tests/test_institution.py` 需要 `DB_HOST=100.73.39.14` 才能跑**
   （`institution`／`care_staff` 表只存在於正式 MySQL）。未設時會有 31 個
   `no such table` 錯誤，那是**環境相依行為不是回歸**。

**新增護欄**

本輪新增 **G167–G172**（前端 G167、G170、G172；後端 G168–G169；流程 G171；條文見
§7.1／§7.2）。護欄檔（`CLAUDE_call-monitor-guardrails.md`）開頭護欄總數同步更新為
**172**。

### 2026-09-05 — 第四十三輪：分支合併、排程提醒送達根因、社群整合、寵物排行榜、家屬好友系統

**背景**

延續第四十一、四十二輪的既有修復，先把本地 `main` 與 `origin/main` 合併，再處理使用者
第五項需求（家屬好友系統）與過程中新發現的「家屬設定的排程提醒，長輩端完全收不到」。

**項目 A（前端）本地 main 與 origin/main 合併**

`uban-api` 合併零衝突；`Uban` 有 4 處衝突：
1. `elder_home_screen.dart` 的 import——兩邊各自新增，三個 import（本地
   `spotlight_tutorial`、遠端 `elder_reminder_manager` 與
   `local_reminder_notification`）全部保留。
2. `elder_profile_tab.dart` 舊寵物卡片（`_showTasksModal` 與
   `_buildUnifiedPetAndGoalCard`，529 行）——取遠端的繪本風新設計取代。
3. `_buildActionCard` 的 `Material`——合併兩側：保留本地的 `key: key,`（第四十一輪
   新手指引的 GlobalKey 錨點，丟失會靜默失效），顏色與圓角取遠端的新設計與橫屏自適應。
4. 版面重構——以遠端的橫／直屏自適應版面為準，把第四十一輪的 `_buildMyFriendIdCard()`
   遷入直屏滑動流（活力雙環之後、快捷列之前）；橫屏刻意不放，該分支原註解標明是
   「零滾動設計」，插入這張卡片會破壞平板座充模式的版面意圖。

★ **這次 merge 最危險的不是那 4 個衝突區，而是衝突之外**：遠端重寫「我的」版面時，新
元件（`_buildStorybookPetStageCard`、`_buildTodayTasksHandmadeSection`）**沒有 `Key`
參數**，`_buildActionCard` 的呼叫端也沒傳值，導致第四十一輪新手指引的四個高光錨點
（`petKey`／`tasksKey`／`familyPairingKey`／`aiAssistantKey`）在新版面中**全部失去掛
載點**。`flutter analyze` 綠、`flutter build` 綠、測試綠，**指引就是標不到東西**——完
全靜默。已為前兩者新增 `Key? key` 參數，並在橫直屏共 8 個呼叫點補上傳值。

更值得記的是：當時用來驗證的腳本 `grep -c 'key: key,'` 抓不到這個問題。它檢查的是
`_buildActionCard` 函式定義裡那行固定樣板文字，跟呼叫端有沒有真的傳入 `widget.xxxKey`
無關——四個錨點全部消失，那個 grep 一樣會回報「有找到」。這是典型的恆綠假驗證。
→ 新護欄 **G166**

**驗證**：`flutter analyze` 0 error、`flutter test` 44 passed、`flutter build apk
--debug` 成功；第四十至四十二輪的既有修復（`endAllCalls` try/catch、取消來電清 prefs、
好友通話、日期卡片溢位防護、真配對碼流程）皆確認存活。

**項目 B（後端）排程提醒送達根因**

**症狀**：家屬設定的排程提醒，長輩端 App 前景無彈窗、背景／螢幕關閉也無通知——**兩者
皆無**。

**根因**：`remote_reminders.elder_id` 這欄**必須存 4 碼房間代碼**，因為
`main.py::check_remote_reminders_job` 拿它組房名並查 FCM token：
```python
emit_threadsafe('remote-reminder', payload, to=f"comm_elder_{elder_id}")
elder_tokens_map = _get_all_known_fcm_tokens(f"comm_elder_{elder_id}", 'elder', None)
```
但家屬端寫入的是 **`user_id`**。`Elder` 模型的 `id`（= user_id）與 `elderId`
（= `elder_profile.elder_id`，房間代碼）是兩個獨立欄位，註解本已寫明，呼叫點卻傳錯。
於是訊息送往一個**沒人在的房間**，Socket 與 FCM 兩條路同時失效——**一個根因，兩個
症狀**。

★ **為什麼這個 bug 藏得住**：`GET /api/reminder/elder/{id}` 本來就用 `OR` 同時容忍
`elder_id` 與 `user_id` 兩種鍵，所以**長輩端的提醒清單顯示得出來**，看起來像有在運
作，只有「送達」壞掉。

**修復**：
- 後端 `services/socket_app.py` 新增 `_resolve_canonical_elder_id()`，
  `check_remote_reminders_job` 呼叫它把兩種格式都正規化成 4 碼 elder_id。
- **為什麼修在後端**：資料庫裡已經有一批用 `user_id` 寫入的舊提醒，只修前端會讓它們
  永遠不再觸發、且長輩端清單突然變空。後端正規化同時救回新舊資料，也不怕前端哪天又
  送錯。
- 解析失敗印出帶原始值的警告後跳過，不靜默略過。
- 前端三處一併改對：`family_home_tab.dart`（`elder.elderId ?? elder.id.toString()`）、
  `remote_care_hub_screen.dart`、`elder_profile_tab.dart`（讀取端也要用解析後的
  elder_id，並處理非同步時序）。
→ 新護欄 **G160**

**同批修的兩件事**：

- **測試端點無認證**：`POST /api/reminder/test-trigger/{elder_id}` 原本完全沒有授權
  也沒有開關，任何人知道一個 4 碼 elder_id（一萬種，可窮舉）就能對該長輩推送**偽造
  的用藥提醒**（「吃下午降壓藥 💊 溫開水送服一顆」）。比照
  `routers/alert.py::trigger_test_fall` 加三道閘（開關預設關閉／共用密鑰／存在性），
  未啟用一律回 404 不回 403。⚠️ 這不只是資安問題——叫長輩吃不該吃的藥是安全問題。
  `services/call_security.py` 新增 `reminder_test_trigger_enabled()`。
  → 新護欄 **G161**
- **排程可能整分鐘漏掉**：`check_remote_reminders_job` 是 `'interval', minutes=1` 而
  查詢對分鐘做字串精確比對，APScheduler 的 `misfire_grace_time` 預設只有 **1 秒**，
  負載稍高延遲超過 1 秒該分鐘就被整個跳過。改為 `misfire_grace_time=30`。
  → 新護欄 **G162**

**驗證**：新增 `tests/test_pet_leaderboard.py`（8 條）與提醒正規化測試 1 條，相關測試
共 **135 passed**。

**項目 C（前端）長輩社群加「家人／朋友」頂部標籤**

原本是兩個彼此分離的畫面（社群分頁的家庭圈、電話分頁再進一層的朋友圈）。把
`elder_friend_feed_screen.dart` 的全部邏輯與 UI 抽成 `FriendFeedBody`（不含
Scaffold／AppBar），`ElderFriendFeedScreen` 改為薄殼包住它——**獨立畫面與新標籤頁共用
同一份**，之後改一處兩邊同時生效。

`ElderCommunityScreen` 新增 `showFriendTab`（預設 `false`），為 `true` 時 `AppBar` 掛
`TabBar`（家人／朋友）、body 改 `TabBarView`，第二頁直接放 `FriendFeedBody`；
`TabController` 只在 `true` 時建立。`elder_home_screen.dart` 的長輩端呼叫點傳 `true`。

**家屬端（`family_interaction_tab.dart`）刻意不傳這個參數**走預設 `false`，行為與改動
前相同——家屬不應看到長輩的朋友圈，那是長輩之間的社交。`friends_screen.dart` 既有的
朋友圈進入點完全未動。

**項目 D（前後端）好友寵物排行榜**

寵物重量原本是**純本機 SharedPreferences**，後端一張相關的表都沒有。新增
`elder_pet_state`（MySQL 與 SQLite 兩分支都建）與 `routers/pet.py` 兩個端點
（`POST /state` 上傳體重、`GET /leaderboard/{elder_id}` 回傳「自己 + 已接受好友」的
完整排名）。

★ 兩個設計決定值得記：
- **名次由後端算好回傳**（`rank`、`my_rank`）。前端只顯示前 10 筆時，自己若在 10 名
  外就**數不出來自己第幾名**，而需求正是「第十位後顯示長輩目前名次」。
- **排序有固定次要鍵**（體重遞減、`elder_id` 遞增）。不穩定排序會讓長輩每次刷新看到
  自己的名次跳動——這是使用者看得到的體驗缺陷，不只是內部實作細節。
- 只列出**已同步過狀態**者，用 `JOIN` 而非 `LEFT JOIN` 補預設值，避免從未開過寵物介
  面的好友以預設 1250g「冒充有寵物」。
→ 新護欄 **G163**

前端：新增 `pet_leaderboard_service.dart`（串接兩個端點）與 `pet_leaderboard_card.dart`
（預設前 10 名、可展開全部、自己那列明顯標示、顯示與上一名的體重差；自己在 10 名外時
於第 10 名後獨立顯示自己的名次）。`pet_studio_screen.dart` 新增 `userId` 參數，內部以
`FriendService.resolveMyElderId` 換取權威的 4 碼 elder_id；進入寵物介面與三個改變體重
的動作各同步一次；初次同步**等本機存檔與 elder_id 解析兩個非同步流程都到齊**才觸發，
避免搶在存檔套用前把預設值傳上去；全程 fire-and-forget，失敗只記 log，不影響本機存檔
與動畫。邊界情況（`my_rank` 為 `null`、僅自己一人上榜、載入失敗）各有明確文案與重試，
不用猜測值兜底。

**驗證**：`flutter analyze` 0 error（121 info／36 warning，與基準一致）、
`flutter test` 44 passed、`flutter build apk --debug` 成功。

**項目 E（前後端）家屬好友系統（與長輩對等）**

家屬只是 `user_account_data` 的一列，**沒有像 `elder_profile.elder_id` 那樣的 4 碼代
碼**，無法沿用「用 ID 加好友」的體驗。

新增獨立表 `family_friend_code` 惰性產生代碼（**不在 `user_account_data` 加欄位**——
那是登入認證的核心表；**也不直接用 `user_id` 當代碼**——它是連號的，等於開放全站帳號
窮舉），加上 `family_friendship`／`family_friend_post`／`family_friend_post_comment`／
`family_friend_post_like` 四張關聯表與 `routers/family_friend.py`（11 個端點，安全語意
比照 `routers/friend.py`：`/search` 限流、`/respond` 驗證收件人身分且一律回 404 不回
403、拒絕即刪列不留 rejected 狀態、不可加自己、重複邀請回 409），全部獨立於
`community_posts`。代碼產生做唯一性重試迴圈並處理 INSERT 競態窗口（30 次都撞才回
500，不會靜默回一組撞碼的代碼）。
→ 新護欄 **G164**

前端：新增 `family_friend_service.dart`（對接 11 個端點，429 限流由前端統一顯示「查詢
太頻繁，請稍後再試」，不透出原始錯誤碼也不靜默失敗）、`family_friend_feed_body.dart`
（結構比照 `FriendFeedBody` 但改走一般字級 `AppTextStyles` 而非長輩專用放大字級
`ElderScale`）、`family_add_friend_screen.dart`（我的代碼／搜尋加好友／好友管理三個分
頁）。`ElderCommunityScreen` 加 `familyTabLabel`（預設 `'家人'`）與 `friendTabContent`
（預設 `null`，朋友分頁內容為 `friendTabContent ?? FriendFeedBody(...)`），家屬端傳
`'家庭'` 與 `FamilyFriendFeedBody`。**長輩端呼叫點（`elder_home_screen.dart`）完全未
修改**，不傳這兩個參數而吃預設值——零回歸由「不存在」保證，比顯式傳預設值更不易被誤
改。加好友入口放在朋友標籤內的入口卡（含待處理邀請角標），不動 `AppBar` 結構，長輩端
的 `AppBar` 因此保證零異動。

三個資料來源（家庭圈 `community_posts`、長輩朋友圈 `friend_post`、家屬朋友圈
`family_friend_post`）互不相通，家屬看不到長輩的朋友圈。

**驗證**：後端新增 `tests/test_family_friend.py`（19 條），相關測試共 **154 passed**
（必補的五條在陽春版實作下先確認為紅——`IntegrityError` 或斷言失敗，非 import 失敗那
種假紅——改正後轉綠）；前端 `flutter analyze` 0 error（120 info／36 warning）、
`flutter test` 44 passed、`flutter build apk --debug` 成功，三個新檔在 analyze 報告中
零命中。

**項目 F — 清掉四處硬寫預設值兜底**

本輪在專案裡找到**四處**「取不到就用猜測值」的寫法，全部移除，一律改為顯示明確錯誤並
不開畫面／不開對話框：
- `remote_care_hub_screen.dart:221` 的 `?? 2`——查不到長輩就靜默把提醒設給 user_id 為
  2 的長輩。
- `family_interaction_tab.dart:1354` 的 `?? 2`——家屬會以 family_id 2 的身分發文到
  **別人的**家庭留言板。
- `family_interaction_tab.dart:211` 的 `?? 1`——提醒被歸屬到 family_id 1。
- `family_home_tab.dart:3607` 傳錯欄位（`elder.id` 而非 `elder.elderId`）——雖非 `??`
  形式，但同一類「用錯的值頂替」，後端排程用房間代碼查 FCM token，兩個欄位多數情況
  下數值不同。
→ 新護欄 **G165**

**查證但未改動的結論（供下一輪參考，不要誤「清理」）**

1. **`routers/pairing.py:1169` 建立長輩帳號時的撞碼風險**：
   `elder_id_short = generate_random_code(4)` **沒有做唯一性檢查**就直接 INSERT，而同
   檔 `request_code`（:1004-1010）有正確的重試迴圈。4 位數只有一萬種組合，目前已有
   26 位長輩，撞碼機率約 3%。撞到會是 PRIMARY KEY 衝突導致建立帳號失敗（**會報錯，
   不是靜默壞掉**），所以本輪未修，但下次動到那段時應一併處理。本輪的
   `family_friend_code` 代碼產生**刻意沒有照抄這段**，用的是 `request_code` 的正確
   寫法加上 INSERT 競態處理（見 G164）。

2. **本機 `.env` 的 `DB_HOST` 指向正式 Tailscale MySQL**（`100.73.39.14`）：在
   `uban-api/` 直接跑 `pytest` 是**打在正式資料庫上**，不是本機 SQLite（`database.py`
   只在連不上 MySQL 時才 fallback）。本輪的家屬好友測試（`tests/test_family_friend.py`）
   就是這樣跑的：沿用 `tests/test_friend.py`（第四十二輪既有）立下的防護**模式**——
   保留字 email 尾綴 ＋ 模組級 fixture 前後都 `_purge()`——但**改用自己專屬的尾綴
   `@ubanff.qa`**（`test_friend.py` 用的是 `@uban.qa`，兩者刻意不同以免互相占用），
   才沒有互相污染也沒有留下殘留，跑完另外下 SQL 覆核為 0。**⚠️ 下一個寫後端測試的人
   必須知道這件事**，不要預設「本機一定是 SQLite」，新增保留字尾綴前也要先確認沒被
   其他測試檔用掉。

3. **正式庫現況（2026-09-05 實測）**：26 位長輩；`elder_friendship` 1 筆（宇璿 `6160`
   ↔ 蛙 `5327`，本輪用真實 API 建立的測試好友關係）；`elder_pet_state`、
   `family_friend_code`、`family_friendship`、`family_friend_post` 皆 0 筆。（長輩）
   好友 API 的 10 個端點**已部署在遠端**（`openapi.json` 可查）。

**新增護欄**

本輪新增 **G160–G166**（後端 G160–G162、G164；跨端 G163、G165；流程 G166；條文見
§7.2）。護欄檔（`CLAUDE_call-monitor-guardrails.md`）開頭護欄總數同步更新為 **166**。

⚠️ **graphify 已連續兩輪未同步**：本輪新增 `routers/pet.py`（2 個端點）與
`routers/family_friend.py`（11 個端點）、`ElderCommunityScreen` 的分頁路由重構
（`showFriendTab`／`friendTabContent`／`familyTabLabel`）、`family_friend_service.dart`
／`pet_leaderboard_service.dart` 等新的模組間呼叫關係，依鐵律 #10 屬於「連接／跳轉」
語意變更，理應同步 `Uban/graphify-out/` 與 `uban-api/graphify-out/`；查證
`graphify-out/` 的檔案時間仍停在 2026-08-30／31，晚於本輪改動（2026-09-05／06），且
第四十二輪的年表已記過同一件事——**已連續兩輪未執行 `/graphify . --update`**。下一輪
處理時請一併帶上。

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
# ⚠️ .env 的 DB_HOST 指向正式 MySQL，conftest.py 的 autouse cleanup_db 每個
#    測試前後都會 DELETE，直接跑 pytest 可能寫到正式資料庫（見 G194）。
#    conftest.py 已預設 DISABLE_DB=true，仍建議明確帶上。
DISABLE_DB=true python -m pytest tests/test_call_signaling.py -q   # 目前基準：41 passed，不可退步
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
| 12 | `.env` 開 `CCTV_TEST_FALL_ENABLED=true` → 用 curl **連續觸發兩次** `POST /api/cctv/test-fall`（前端按鈕已於第四十七輪移除，指令見 §6.10） | 家屬端（含**熄屏**狀態）**兩次都**亮螢幕 + 通知 + 朗讀 + 彈窗。改回 `false` 後再打 → HTTP 回應 404，`detail` 為「測試端點未啟用（請在後端 .env 設定 CCTV_TEST_FALL_ENABLED=true）」 |

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
1. flutter analyze lib → 0 error
2. DISABLE_DB=true python -m pytest tests/test_call_signaling.py -q → 41 passed（不退步）
3. flutter build apk --debug → BUILD SUCCESSFUL
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
