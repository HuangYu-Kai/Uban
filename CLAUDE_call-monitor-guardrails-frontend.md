> ⚠️ **本檔在兩個 repo 各有一份鏡像**：`Uban/CLAUDE_call-monitor-guardrails-frontend.md` 與
> `uban-api/CLAUDE_call-monitor-guardrails-frontend.md`。**修改任一份時，必須同步更新另一份**。

# CLAUDE_call-monitor-guardrails-frontend.md — 通話與監控子系統 前端護欄（§7.1）

> 🗂️ **這是什麼**：`CLAUDE_call-monitor-guardrails.md`（索引檔）§7.1 的護欄正文，共
> **111 條**，2026-09-24 第五十三輪從該檔逐字搬移到本檔——**未經改寫、未重新編號**。
> 後端護欄（§7.2，94 條）在同目錄的 `CLAUDE_call-monitor-guardrails-backend.md`；
> 索引本身、§7.3（已知的文件錯誤）、§7.4（刻意保留的安全缺口）與「依任務類型的定向閱讀
> 指引」都留在 `CLAUDE_call-monitor-guardrails.md`——**動手前請先看那份索引**，再決定
> 要不要讀本卷、讀哪幾條。
>
> 條號延續原文件、**不連續**（前後端護欄編號本來就交錯累積，例如本卷含 G1–G28、
> G37–G42……缺號的部分在後端卷），不要因為看到編號跳躍就以為搬漏了。
> 這是動手前必讀的一部分，不是查證用的史料。

---

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
| 跌倒警報彈窗「查看監視畫面」<br>首頁「最新警示」CCTV／跌倒項目 | `family_main_screen.dart::_openMonitorViewForDevice`<br>（2026-08-31 第三十八輪抽出，供上述兩條入口共用；呼叫端分別是 `_presentCctvAlert()` 與 `FamilyHomeTab.onOpenMonitorView`） |

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

**G138 — CCTV 檢視的建構參數只能有一份，新入口一律呼叫 `_openMonitorViewForDevice`**
`family_main_screen.dart` 這一側的 `VideoCallScreen(monitorViewOnly: true, ...)` 只准出
現在 `_openMonitorViewForDevice()` 內；任何新的「開啟監控檢視」入口都必須呼叫它，不得自
己再拼一份。這組參數有 7 個彼此相依的欄位（`roomId` 用 `monitor_elder_<elderId ?? id>`、
`targetSocketId` 必須是**該裝置自己的 id** 而非 `_elderSocketId`、`isEmergency: true`、
`autoStart: true`、`returnByPop: true`、`monitorViewOnly: true`、`monitorDeviceName`），
少一個或拿錯 socket 就會連到錯的裝置，或卡在「連線中」。
🚫 反面教材：`FamilyHomeTab.onOpenMonitorView` 這條入口在第三十八輪之前**宣告了、消費端
也寫好了、但父層從未傳入**，功能靜默不存在了不知道多少輪——**宣告一個回呼不等於接上
它**。新增這類「父層注入」的參數時，必須同時確認所有建構點都傳了。
> 同一次稽核用「宣告了回呼、但所有建構點都沒傳」這條規則掃全 App，只有這一個中標；可
> 作為日後的檢查手法。

**G142 — 溢位判準是「字級 × 同列元素數」，不是「字串是否動態」**
同列有 ≥18pt 標題又有徽章／箭頭／按鈕時，標題就必須包 `Flexible` +
`overflow: TextOverflow.ellipsis`；短字級標籤、已包在 `Expanded` 內、或同列無其他
元素的獨立標題可以跳過。
🚫 **禁止**用「字面字串長度有上限」當跳過理由——第三十九輪的溢位掃描就是用這個判
準漏掉「家庭生活時光牆」（22pt）與「AI 照護共創助理」（18pt + 徽章）兩處，使用者
實機截圖直接證實溢位。
⚠️ 本條不豁免鐵律 14「不得一次全改」——找到一處、精準修一處，並記錄為什麼跳過其
餘的。
> **原因**：第四十輪使用者截圖點出家屬端互動分頁卡片溢位，經複查全部 14 處
> `fontSize>=18` 才發現上一輪的跳過理由本身就是錯的。
> 延伸見 **G159**（大字級／`textScaler` 情境下改用等比縮小，`Spacer()` 不算防線）。

**G159 — 全 App 未鎖 `textScaler`，大字級文字必須能等比縮小，`Spacer()` 不算防線**
本專案 `lib/` 全目錄**沒有任何** `textScaler`／`textScaleFactor` 覆寫，畫面完全跟隨系統字體大小。
- **G142 的「≥18pt」門檻是以 1.0 倍為前提**——系統字體調大時所有寬度等比放大，安全邊際會同步消失。
- 🚫 **禁止**用「同列有 `Spacer()`」當作不會溢位的理由——`Spacer()` 只吸收**多餘**空間，內容塞滿時緩衝為零。
- 🚫 **禁止**用「字串長度有上限」當跳過理由（這點 G142 已經講過，但本輪的日期字串**確實**有上限、**仍然**溢位，是同一個錯誤判準的第二次實例）。
- ✅ **≥40pt 的展示型文字**（日期、數字、標題）溢位時應**等比縮小**（`FittedBox` + `BoxFit.scaleDown`），**不要**用 `TextOverflow.ellipsis`——把「12月31日」截成「12月3…」比溢位更糟。
- ✅ 需要判斷「塞不塞得下」時，用 `LayoutBuilder` + `TextPainter` **實際量測**，不要用 `Flexible` 配猜出來的 flex 比例——flex 先分配空間再看內容，比例猜錯會在**空間其實足夠時**也壓縮內容。
- ⚠️ `Spacer()` 本身就是 `Expanded(flex: 1)`：若把同列其他欄也包成 `Flexible(flex: 1)`，三者會各分到 1/3 寬度。
> **原因**：把系統字體調大的正是長輩使用者，這是本 App 的**主要**族群，不是邊緣情境。第四十二輪實測：長輩端首頁日期卡片在 320dp/1.3 倍下溢位 239~270px。

**G143 — CCTV 檢視的「正在觀看哪一台」狀態只能放畫面 State，不得放進 `Signaling` 單例**
`family_main_screen.dart` 的 `_viewingMonitorDeviceId` 在 `_openMonitorViewForDevice()`
（G138 認定的唯一 CCTV 檢視建構點）push 前設值、`.then()` 內清空；跌倒警報彈窗的
「查看監視畫面」鍵只在**同一台**裝置時隱藏，不同台仍要能點進去。
🚫 **禁止**把這類「使用者正在看哪個畫面」的旗標放進 `Signaling` singleton——
`isIncomingCallDialogVisible` 已有導致長輩端冷啟動失敗而被回退的事故史；需要跨路
徑協調時比照 `_activeCallId` 的模式：與具體識別碼綁定、讀不到就退回安全預設。
> **原因**：第四十輪新增「已在觀看該監視機時不再顯示查看鍵」，選擇畫面 State 而非
> 全域旗標是刻意的架構決策，避免重蹈覆轍。

**G144 — 任何「通話被取消／逾時」的處理點，必須同時清 CallKit／備援通知／pending prefs 三面**
CallKit 用 `endAllCalls()`（包 try/catch）、備援通知用
`LocalCallNotification.cancel()`、再清三個 pending prefs 鍵——少一個就會留下響不停
或殘留的殭屍通知／狀態。
🚫 **禁止**只改 `Signaling` 的全域回呼欄位就視為完工——畫面層（例如
`elder_home_screen.dart` 對長輩端的覆寫版）若也定義了同名回呼，會蓋掉全域版，兩份
都要正確處理三面清除。
> **原因**：第四十輪查出 `main.dart` 的 `onCancelCall` 與 `elder_home_screen.dart`
> 的長輩端覆寫版都只停提示音、關 App 內對話框，未關 CallKit 響鈴畫面也未關備援通
> 知，導致撥出端逾時後收話端的來電通知留在畫面上。

**G145 — 任何寫入 `user_role='elder'` 的登入路徑，都必須同時寫 `last_elder_*`**
快速登入的還原邏輯只讀 `last_elder_*` 這組鍵；新增或修改登入入口（包含開發用的快速
登入按鈕、深連結／復原代碼登入等）時，只要該路徑會把使用者設為長輩身分，就必須同
步呼叫 `_rememberLastElder(...)` 並寫入 `last_elder_device_role`。
🚫 **禁止**只在「清除端」修快速登入問題就視為根治——漏寫的是「寫入端」，症狀卻只
在「清除後登不回去」才會被看見，容易讓人誤判成清除邏輯的 bug 而修錯地方。
> **原因**：這是本輪耗時最久的一項——第三十五、三十七、三十九輪各自修對了一個清
> 除端的真 bug，但使用者實際走的登入路徑（開發用「登入宇璿」按鈕）從未寫入這組
> 鍵，前後拖了五輪才靠畫面診斷定位。全專案掃出的第三條缺口（深連結復原登入）已一
> 併補上。

**G146 — 新手教學不得干擾來電與警報，且被守門擋下時不得標記為「已看過」**
長輩端顯示教學前必須查 3 條守門（`mounted`／`pendingAcceptedCall.value == null`／
`!_isIncomingCallDialogOpen`）；家屬端多查 3 條（`!_cctvAlertDialogOpen`／
`_activeAlerts.isEmpty`／`_viewingMonitorDeviceId == null`）。**每一個教學入口都要重新
查一次**，不能只在最外層查一次就當全程有效——CCTV 警報卡片不是阻擋式彈窗，
`_activeAlerts` 非空時使用者仍可自由切換分頁。
✅ 完成旗標只在教學**真正跑完**才寫入 SharedPreferences；被任何一條守門擋下時本輪不
寫旗標，下次仍會嘗試顯示。
🚫 **禁止**在預設選中的分頁上假設 `_onNavTap` 一定會被呼叫——開機預設選中的分頁使用
者不需要點它，主介面教學跑完後必須主動串接「目前選中分頁」對應的教學，並在串接前重
新檢查一次守門條件。
> **原因**：第四十一輪新增雙端步驟式新手指引時，發現首頁教學因為上述兩個理由（守門
> 會被繞過、預設分頁不觸發切換事件）而永遠不會顯示。

**G156 — 好友通話時，前端送出 `role` 的三個地方必須全部是 `'friend'`**
`connect()`、`sendCallRequest`（`elder_screen.dart`:1587）、`sendCancelCall`
（`elder_screen.dart`:1657）三處送出的 `role` 欄位，好友通話情境下都必須是
`'friend'`，不可沿用硬寫的 `'elder'`。
🚫 **禁止**只改其中一兩處——漏改任何一處，後端 `target_role` 公式就會算出
`target_role='family'`（見 G152），來電被送去對方的家屬而不是對方本人。
> **原因**：第四十二輪的根因前端半邊——`sendCallRequest` 與 `sendCancelCall` 原本各
> 自硬寫 `role: 'elder'`，即便 `connect()` 已經改成條件式，這兩處沒有同步改，等於沒
> 修。

**G157 — 好友通話結束必須 `leaveRoom(對方房)` 後重新以 `role: 'elder'` `connect` 自己
的房**
`ElderScreen.dispose()` 是所有離場路徑（掛斷／對方掛斷／忙線／斷線／逾時選離開）的唯
一共同匯合點，好友通話的回房邏輯必須放在這裡：先 `leaveRoom(對方房)`，再
`connect(自己的房, 'elder', deviceMode: 'comm')`。
🚫 **禁止**省略這一步——`Signaling` 是單例，不做這一步的話，這位長輩結束好友通話後
仍停留在對方的房間裡，之後再也收不到自己家人的來電，**沒有任何錯誤訊息，純粹靜默失
效**。
> **原因**：第四十二輪設計好友通話回房邏輯時的關鍵決策——選 `dispose()` 而非個別掛
> 斷分支，正是因為只有它能保證涵蓋全部離場路徑；「重新撥打」不觸發 `dispose()`，但
> 那是因為同一個 State 原地重試、房間本來就沒變，不需要回房。

**G158 — 配對碼一律走 `ApiService.requestPairingCode()`，禁止用 `user_id`／`elder_id`
的衍生值兜底**
家人綁定用的臨時配對碼是後端產生的限時碼，只能透過 `requestPairingCode()` 取得。
🚫 **禁止**用 `user_id` 或 `elder_id` 的任何衍生值（例如 `padLeft(4,'0')`）當配對碼顯
示或兜底——取碼失敗時要顯示白話錯誤＋重新取得的入口，寧可沒有號碼也不要給錯的：猜測
值不只是「輸入會失敗」，還可能誤撞到別人**正在使用中**的真配對碼。
> **原因**：第四十二輪修復 `elder_profile_tab.dart::_showFamilyPairingDialog`——第四
> 十一輪 item 3 已經記錄過這個 `padLeft` 猜測法是 bug，本輪確認它同時也混淆了「配對
> 碼」與「好友 ID」兩個完全不同的概念，一併修正。

**G167 — Dart 的 import 不傳遞可見性**
A import B、B import C，不代表 A 看得到 C 的符號（除非 B 有 `export`）。
🚫 修 import 錯誤時，**禁止**用「修好幾個路徑就會消失幾個錯誤」的推論一次寫完，必須
修完**重跑 analyze 再看剩幾個**。
> **原因**：本輪 `storybook_stage_card.dart` 的 11 個錯誤中，3 個是 import 路徑
> 錯、8 個是符號未定義。原本判斷「修好 3 個路徑，8 個符號錯誤會一起消失」，實際
> 只消掉 4 個——剩下 4 個 `ActorMood` 是另一個獨立問題：這個 enum 定義在
> `animated_piglet_actor.dart`，而 `hand_drawn_piglet_actor.dart` 雖然 import 了
> 它但沒有 `export`。這是把症狀數當成根因數的誤判。

**G170 — 需要分辨 HTTP 狀態碼的呼叫不可走 `ApiService` 的門面方法**
那些門面只在 200/201 回傳 body，其餘狀態碼一律吞掉，呼叫端拿不到 `statusCode`。
✅ 需要分辨時直接用 `http.post()`／`http.get()`。
⚠️ FastAPI 的 422 `detail` 是 Pydantic 錯誤**清單**不是字串，**禁止**直接轉述給使用
者。

**G172 — 重構把檔案內容搬到子目錄後，既有的掃描腳本會產生假陰性**
✅ 大型重構後，所有「逐檔掃描」的例行檢查都要重新確認涵蓋範圍。
> **原因**：本輪的溢位掃描對家屬首頁回報「無可疑處」，實際是因為
> `family_home_tab.dart` 從 3726 行被掏空到 289 行、內容搬進
> `family/home/widgets/`——掃描掃的是空殼。

**G181 — 長輩端的 `ElderScale` 常數本身就踩在 18pt 門檻上，只 grep `fontSize:`
會整批漏掉**
`ElderScale.caption`＝18pt、`.body`＝22pt、`.button`＝28pt、`.sectionTitle`＝
30pt（定義在 `lib/theme/app_theme.dart:105/135/142/148/156`）。
🚫 長輩端任何用 `ElderScale.xxx` 包**動態文字**的 `Row`，即使程式碼裡看不到寫
死的 `fontSize:` 數字，也已經符合第 14 條的 ≥18pt 條件；**只搜 `fontSize:` 會
整批漏掉這類案例**。
✅ 做溢位檢查時，除了搜 `fontSize:`，還要搜 `ElderScale.`（以及家屬端對應的
theme 常數）。
✅ 同列若有 `Spacer`，風險顯著降低（它吸收餘裕而非佔用空間）；**固定元素緊
鄰**（icon／spinner + 固定間距 + 大字文字）才是高風險結構。
> **原因**：第四十五輪就是靠這個發現才抓到 `elder_community_screen.dart:618`
> 的留言作者名——它表面上只有 `style: ElderScale.caption`，用
> `grep 'fontSize:'` 掃描完全掃不到。

**G200 — `Flexible`／`Expanded` 只能放在「主軸有界」的 Flex 直接子節點**
放在捲動清單項目（`SliverList` item）內的垂直 `Column` 直接子節點上會丟
`RenderFlex children have non-zero flex but incoming height constraints are
unbounded` 例外，且這個例外發生在 **layout 階段**，build 期的
`ErrorBoundary`／`try/catch` 完全攔不到——例外會炸穿整條
`SliverList`／`Viewport`，讓那一影格的版面計算全毀，畫面因此空白、沒有任何
hit-test 目標。
🚫 修鐵律 #14 的溢位時，可收縮應該包在 `Row` 的直接子節點上；**不可**包在
捲動清單項目內垂直 `Column` 的直接子節點上。
> **原因**：第五十輪把 `Flexible` 包在 `SliverList` 項目內的垂直 `Column`
> 直接子節點上；第五十一輪新增的 `ErrorBoundary` 只包得住 build 期間的同步
> 呼叫，完全攔不到 layout 期例外。家屬「資料」分頁因此整片空白、所有按鍵
> 失效，且連錯兩輪（第五十、五十一輪）都沒被抓到，直到第五十二輪才定位。

**G203 — TTS 播放期間不得開啟 STT**
語音助理的問候語若用 `setCompletionHandler` 搭配一個固定時長的
`Future.delayed` 逾時兜底，兩者是在賽跑——語速調慢（例如 0.5 倍速）時一句
問候常常講不完兜底設定的秒數，兜底先到就會在助理還在講話時開啟麥克風，把
喇叭正在播放的 TTS 聲音錄成使用者輸入。
✅ 開口前先停 STT、開始聽之前先停 TTS，雙向都要防呆；用單一「開口」入口
（例如 `_speakAndWait()`）統一判定播放是否真正結束，不要讓 completion
handler 與逾時兜底各自獨立運作。
> **原因**：`google_assistant_overlay.dart` 的問候語用 `setCompletionHandler`
> 加一個 `Future.delayed(2500ms)` 兜底，語速 0.5 時常講不完 2.5 秒，兜底先到
> 就在助理還在講話時開麥克風。使用者實例：助理問「怎麼了嗎，蛙」被辨識成
> 「怎麼了媽媽」。

**G204 — 使用者看得到的關鍵內容必須在第一屏，且要用 widget test 量座標證明**
「是不是被擠到下面」這種版面問題**不能靠推測**——同一個問題可以連續好幾輪
都在猜、都猜錯，因為每一輪看到的症狀相同（使用者說看不到），但沒有人真的
去量測座標，於是每一輪都在原地打轉。
✅ 用 widget test 在目標裝置尺寸下實際量出元件的 `top`／可視區底線，用數字
證明它落在第一屏內，不要用「應該有改善」這種主觀判斷結案。
> **原因**：長輩端首頁的今日頭條連續三輪都被回報「實機看不到」——第五十輪
> 把新聞卡從精簡列改成大圖直式，把它推出第一屏；第五十一輪加的「還有更多」
> 提示沒解決「長輩不會主動下滑」的根本問題；直到第五十二輪才有人在
> `360x640` 與 `412x915` 兩種尺寸下用 widget test 實際量出座標，改回精簡列
> 並證明標題落在第一屏內。

**G205 — 非同步載入的「已讀／已滑掉」過濾集合，必須在載入完成前抑制渲染**
用來過濾「使用者已經處理掉的項目」的集合，若是從本機儲存（例如
`SharedPreferences`）非同步讀回來的，讀取完成前這個集合是空的——畫面若在
這段空窗期先渲染一次，會讓使用者已經滑掉／已讀的項目重新出現，即使幾百
毫秒後就會被過濾掉，使用者仍會覺得「它又跑回來了」。
✅ 額外維護一個「是否已載入完成」的旗標，載入完成前完全不渲染依賴該過濾
集合的項目，也不要顯示「目前沒有內容」這種當下還無法確認真假的文案，改用
中性的載入中骨架；成功與失敗兩種結尾都要讓旗標翻正，不能只顧成功路徑。
🚫 **禁止**用「不 await、初始為空集合、之後 setState 補上」這種寫法就當作
已經處理好競態——那正是問題本身，不是修法。
> **原因**：`family_main_screen.dart::initState()` 呼叫
> `_loadDismissedAlertKeys()` 不 await，App 冷啟動時「最新警示」卡片會在這
> 個非同步讀取完成前先畫一次，此時 `_dismissedAlertKeys` 還是空集合，導致
> 使用者上一個 session 已經滑掉的警示重新閃現，幾百毫秒後才被濾掉。修法見
> `_dismissedKeysLoaded` 旗標與 `HomeAlertPreviewCard.dismissedKeysLoaded`
> 參數。

