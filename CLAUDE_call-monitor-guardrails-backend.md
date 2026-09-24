> ⚠️ **本檔在兩個 repo 各有一份鏡像**：`Uban/CLAUDE_call-monitor-guardrails-backend.md` 與
> `uban-api/CLAUDE_call-monitor-guardrails-backend.md`。**修改任一份時，必須同步更新另一份**。

# CLAUDE_call-monitor-guardrails-backend.md — 通話與監控子系統 後端護欄（§7.2）

> 🗂️ **這是什麼**：`CLAUDE_call-monitor-guardrails.md`（索引檔）§7.2 的護欄正文，共
> **94 條**，2026-09-24 第五十三輪從該檔逐字搬移到本檔——**未經改寫、未重新編號**。
> 前端護欄（§7.1，111 條）在同目錄的 `CLAUDE_call-monitor-guardrails-frontend.md`；
> 索引本身、§7.3（已知的文件錯誤）、§7.4（刻意保留的安全缺口）與「依任務類型的定向閱讀
> 指引」都留在 `CLAUDE_call-monitor-guardrails.md`——**動手前請先看那份索引**，再決定
> 要不要讀本卷、讀哪幾條。
>
> 條號延續原文件、**不連續**（前後端護欄編號本來就交錯累積），不要因為看到編號跳躍就
> 以為搬漏了。這是動手前必讀的一部分，不是查證用的史料。

---

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

**G139 — 跌倒判定必須以「持續寬扁 bbox」為必要前提，不得只靠垂直位移**
`yolo_detector_service.py::_check_fall`（:507）的兩條計分路徑（純垂直位移／寬扁佐證）
原本是「或」，純垂直位移完全不檢查 bbox 形狀：朝鏡頭走近／走遠時 bbox 高度隨透視改
變，質心垂直位移正規化後可衝過 `FALL_VERTICAL_RATIO=0.30` 並獨自給到滿分信心。
✅ `is_wide_sustained`（`FALL_WIDE_BBOX_RATIO=1.6` 持續 `FALL_SUSTAINED_WIDE_MIN_FRAMES`
幀的寬扁 bbox）改為兩條計分路徑共同的**必要前提**，整段計分包在
`if is_wide_sustained:` 之下；走動時 bbox 全程直立，計分區塊整段不執行。
🚫 **禁止**把 `is_wide_sustained` 退回成加碼條件，或新增任何不先檢查 bbox 形狀就能
單獨給高分的位移路徑。✅ 要調靈敏度一律動門檻數值，不要動這個結構。
> **原因**：第三十九輪查出走動朝鏡頭方向移動時被判成跌倒、信心 100%。五個門檻數值
> 一個都沒動，真跌倒仍在同一 14 秒窗口判出；`tests/test_yolo_detector.py` 已把「舊版
> 會給 100%」的走動情境釘成回歸測試。

**G140 — presence 的「多久算過期」由後端送，前端不得寫死**
`elder-zone-update` payload 新增 `presence_stale_after_ms`（`indoor_position.py::
_presence_stale_after_ms`，節流間隔 ×2、下限 10 秒），家屬端 `_zonePresenceStaleWindow`
（`family_main_screen.dart::_resolveStaleWindow`）須改讀這個欄位，不可自行寫死常數。
✅ 新增任何依會員層級／情境變動的推播節流時，一併把對應的過期提示放進 payload，讓
前端跟著算。🚫 **禁止**在前端依層級自行複製一套節流秒數表——重複的跨端常數必然漂
移。附註：前端收不到欄位時退回 10 秒是**向後相容的刻意設計**，不是遺漏。
> **原因**：presence 心跳節流依會員層級分級（G141）後，前端原本寫死的 10 秒與後端
> 節流間隔不再對齊，免費層級會規律性地被前端誤判「不在場」又「在此」來回閃爍。

**G141 — 節流只能套在「往外推播」，不可套在偵測**
`indoor_position.py::_presence_broadcast_due()` 只節流沒有 zone 轉換
（`transition is None`）時的推播；真正的區域轉換一律無條件立即送出，不查節流門。
✅ 監控機推幀頻率（每 2 秒）維持不變，被節流的只是「要不要把這次心跳送給家屬」這個
決定本身；後端自己判斷在場用的 `PRESENCE_STALE_SECONDS`／`last_seen` 完全不受影響，
繼續每幀更新。
🚫 **禁止**把推播節流的間隔拿去取代或延後 `last_seen` 的更新頻率——`last_seen` 是後
端自己那側判定在場的依據，一旦跟著變慢，後端會先於前端自行判定「不在場」，整條鏈路
在源頭就壞掉。
> **原因**：第三十九輪新增依層級節流時的設計裁決，避免「省流量」的節流意外波及偵測
> 本身這條完全不同性質的路徑。

**G147 — 好友 ID 使用 4 位數 `elder_id`，搜尋端點必須限流且只回最小欄位**
好友系統的 ID 命名空間**就是**既有的 4 位數 `elder_id`（0000–9999），這是使用者的明確
裁示、已知悉並接受「可被完整列舉」這個 UX 取捨；後端的責任是讓列舉**划不來**，不是假
裝它不會發生。
✅ 依呼叫端 `elder_id` 為鍵做滑動窗口限流，超過回 **429**。
🚫 **禁止**搜尋端點回傳電話／地址／生日等敏感欄位——只能回 elder_id、名稱、頭像這三
個最小必要欄位。
✅ 前端 QR 格式固定 `uban-friend:<4位數>` 前綴；掃到非此前綴內容時停止相機、顯示白話
提示，不得對裸數字發起查詢。
> **原因**：第四十一輪新增長輩朋友圈時的設計裁決——4 位數空間小到可被暴力列舉，限流
> 與欄位最小化是唯一能落地的防線。

**G148 — 「這位長輩是什麼層級」只能有一個權威函式 `resolve_tier_for_elder()`**
`routers/subscription.py::resolve_tier_for_elder(elder_id)` 查出所有綁定家屬、逐一取
層級、**取最高者**（diamond > gold > free），結果快取 60 秒；查無資料或例外一律
fail-safe 到 `'free'`。
🚫 **禁止**任何檔案自己寫 SQL 查詢長輩的會員層級——`socket_app.py`、
`indoor_position.py` 等一律呼叫這個函式，不得各自 `ORDER BY ... LIMIT 1` 或
`_find_user_for_elder`。
✅ 多位家屬綁定同一位長輩時，取**最高層級**，不是最近訂閱、不是任一位。
> **原因**：第四十一輪查出**兩份重複實作、且兩份都用錯演算法**——`_get_monitor_
> device_limit` 與 `indoor_position.py::_resolve_presence_interval_s` 都用「最近一筆
> 訂閱／任一位家屬」取代「最高層級」，付費家屬因此被誤判降級（監控機上限、在場更新
> 間隔皆縮水）。

**G149 — 任何寫入 `family_elder_relationship` 的路徑，都必須先過綁定上限檢查**
上限 free 2／gold 3／diamond 5（`_enforce_family_elder_bind_limit(family_id)`）。已知
寫入路徑：`confirm_pairing()`、`routers/relationship.py::create_relationship()`。
`boyo@uban.com` 用 **email 比對**跳過限制（不可寫死 `user_id`，id 會隨環境不同）。
✅ 上限檢查必須排在「關係已存在就不重複 INSERT」的冪等判斷**之後**——重新綁定既有關
係不該被誤擋。
🚫 `/dev/ensure-yuxuan-demo`／`/dev/ensure-gawa-demo` 已於第四十九輪移除——這兩個
端點原本因為 `family_id` 是寫死常數而被列為刻意豁免（擋了會讓既有測試路徑無預警
壞掉），但它們同時也是**不需登入就能建立／改寫帳號**的端點，經使用者裁定移除；
程式庫中已無這兩支路徑，此豁免對象不復存在，**不要再假設可以呼叫它們**。
> **原因**：第四十一輪新增長輩綁定家屬上限時，發現 `create_relationship()` 是完全沒
> 有配對碼驗證也沒有授權檢查的裸 INSERT，能繞過上限；已補上限與冪等判斷，但授權缺口
> 本身留待後續處理（見 §8 第四十一輪「仍然開著」）。

**G150 — `role='friend'` 只能進 `comm_elder_*`；`monitor_elder_*` 一律拒絕，且必須排在
查好友關係之前**
`_verify_room_access` 的 friend case（case 3）開頭即呼叫 `_parse_room_id(room)`，
`room_mode != 'comm'` 立即回絕，**不查 `elder_friendship` 就短路**；房名格式不明（無法
解析出 mode）同樣拒絕。
🚫 **禁止**讓好友關係延伸出監控房（對方家中即時攝影機畫面）的存取權——好友只是通話對
象，不是監控被授權人；也**不得改由前端保證**「這是通話請求不是監控請求」，前端可被繞
過，授權判斷只能在後端做。
> **原因**：第四十二輪新增長輩↔長輩好友通話時的設計裁決——若沿用 elder/family 既有
> case 的寫法（先查關係、後判房間模式），日後後端邏輯被改動時容易不小心讓 friend 也
> 能查到 `monitor_elder_*`，先做房間模式短路可以杜絕這個風險。

**G151 — friend 授權只認 `elder_friendship.status == 'accepted'`；任何不確定情況一律
`(False, None, None)`**
pending、查無關係列、呼叫端 elder_id 解析失敗、任何 DB 例外，全部回傳
`(False, None, None)`（fail-closed）。
🚫 **禁止** fail-open——沒有「查詢失敗就先放行、之後再補查」這種寫法，好友通話的授權
跟監控／通話的其他授權點一樣，寧可誤擋不可誤放。
> **原因**：與 G43–G46（監控／警報端點授權）同一方向的既有原則，套用到好友通話的新
> 增授權路徑。

**G152 — `target_role` 公式必須在 `on_call_request` 與 `on_cancel_call` 同時含
`'friend'`**
兩處公式（`socket_app.py::on_call_request`:2005、`on_cancel_call`:2288）都必須是
`'elder' if sender_role in ('family', 'friend') else 'family'`。
🚫 **禁止**只改其中一處——只改 call-request、不改 cancel-call，會變成「打得出去但取消
時查錯對象」：發起端取消通話時，後端把取消訊息送去錯誤的目標角色，收話端的來電通知因
此關不掉，使用者看到的是「已取消卻還在響」。
> **原因**：第四十二輪的根因——原公式 `'elder' if sender_role == 'family' else
> 'family'`，`sender_role == 'friend'` 落進 `else` 分支，算出 `target_role='family'`，
> 於是 A 打給好友 B，後端會去找 B 的家屬。

**G153 — `on_emergency_call` 的 `target_role` 公式刻意不含 `'friend'`**
好友之間沒有緊急通話入口，`socket_app.py::on_emergency_call`（:2363）維持原公式不變。
🚫 **禁止**日後新增「好友緊急通話」功能時漏改這裡——不改的話不會報錯，只會**靜默**把
緊急通話誤路由到目標長輩的家屬，而不是真正的呼叫對象。新增該入口的同時必須把這條公式
一併納入。
> **原因**：與 G152 同一次稽核下的刻意留白，記錄下來避免下一輪誤以為是漏改。

**G154 — friend session 一律 `deviceMode='comm'`，不得送 `'monitor'`**
好友以 `role='friend'` 加入對方房間時，`deviceMode` 必須固定為 `'comm'`（前端
`connect()` 呼叫點與後端 `on_join` 兩側都要維持這個假設）。
🚫 **禁止**送 `deviceMode='monitor'`——`_count_active_monitor_devices_for_elder` /
`_count_monitor_devices_for_ip` 這兩個監控機／IP 額度函式**只看 `deviceMode`，完全不
看 `role`**，送錯值會讓好友的這次連線被誤算進對方的監控機額度，擠壓對方真正監控機的
可用名額。
> **原因**：第四十二輪查證監控額度函式的計數邏輯時發現的隱患，前端與後端各自都要守
> 住這個假設，因此標記跨端。

**G155 — `_get_caller_name` 的 friend 分支不得沿用 elder 分支的 `_parse_room_id(room)`**
friend 分支必須用 `caller_user_id` 反查 `elder_profile WHERE user_id = %s` 取得呼叫端
自己的 elder_id 與姓名。
🚫 **禁止**直接複用 elder 分支「從房名反解 elder_id」的寫法——elder 分支能這樣做是因
為 elder 在**自己的房間**發話；但好友通話的 `room` 是**被叫端**的房間，照抄會把**被
叫端自己的名字當成來電者顯示給被叫端本人看**。
> **原因**：第四十二輪實作時發現的陷阱——兩個分支雖然同樣是「從某個 id 查名字」，但
> 反解的起點不同，複製既有程式碼會產生一個不會報錯、但顯示內容錯誤的 bug。

**G160 — `remote_reminders.elder_id` 必須是 4 碼房間代碼，不是 `user_id`**
排程器（`main.py::check_remote_reminders_job`）用它組 `comm_elder_{id}` 房名並查 FCM
token；存錯值會讓訊息送往一個沒人在的房間，Socket 與 FCM **同時**失效。新增
`socket_app.py::_resolve_canonical_elder_id()` 由後端統一正規化兩種鍵值。
🚫 **禁止**只修前端寫入點——資料庫裡已有一批用 `user_id` 寫入的舊提醒，只改前端會讓
它們永遠不再觸發、且長輩端清單突然變空。
> **原因**：第四十三輪根因——`Elder` 模型的 `id`（user_id）與 `elderId`（房間代碼）
> 是兩個獨立欄位，`GET /api/reminder/elder/{id}` 本來就用 `OR` 容忍兩種鍵所以清單顯
> 示正常，只有送達這條路徑壞掉，因此藏得很深。

**G161 — 任何測試／除錯端點一律預設關閉，並加共用密鑰與存在性檢查；未啟用或查無一律
回 404 不回 403**
🚫 禁止新增沒有開關的測試端點；403 等於承認該 ID 存在，可被拿來探測。
> **原因**：`POST /api/reminder/test-trigger/{elder_id}` 曾完全無認證，任何人知道一
> 個 4 碼 elder_id（可窮舉）就能對長輩推送偽造的用藥提醒——這不只是資安問題，是安全
> 問題。比照 `routers/alert.py::trigger_test_fall` 的既有模式補上三道閘（與 G43–G46
> 同一方向）。

**G162 — 對時間做精確比對的排程 job 必須設足夠的 `misfire_grace_time`**
APScheduler 預設只有 1 秒，延遲超過 1 秒該次執行會被整個跳過，而精確比對代表跳過即
該分鐘永遠不發。
✅ `check_remote_reminders_job` 已改為 `misfire_grace_time=30`。
> **原因**：該 job 是 `'interval', minutes=1` 且 `WHERE time_str = 'HH:MM'` 字串精確
> 比對，漏一次就漏掉整分鐘的所有提醒。

**G163 — 排行榜／名次一律由後端算好回傳，前端不得自己數；排序必須有固定次要鍵**
🚫 禁止「前端拿完整清單自己排名次」——前端只顯示前 N 筆時，使用者若在 N 名外就算不
出自己的名次。
✅ 排序必須有固定次要鍵（`elder_pet_state` 用體重遞減、`elder_id` 遞增），否則每次刷
新名次會跳動。
> **原因**：`GET /api/pet/leaderboard/{elder_id}` 的需求是「前 10 名之後顯示長輩目前
> 名次」，`rank`／`my_rank` 都在後端算好；不穩定排序會讓使用者看到自己名次無故變
> 動，是看得到的體驗缺陷。

**G164 — 產生任何短碼（4 碼 elder_id、family_code、配對碼）必須做唯一性檢查並重試，
且要處理 INSERT 的競態窗口**
🚫 禁止照抄 `routers/pairing.py:1169`——那段沒做檢查，是既有 bug。
✅ 正確範例是同檔的 `request_code`（:1004-1010），本輪 `family_friend_code` 的產生沿
用同一寫法。
> **原因**：4 位數只有一萬種組合，長輩數量持續增加時撞碼機率不可忽視；本輪新增家屬
> 好友代碼時特別查證過，刻意不照抄既有 bug。

**G165 — 禁止用硬寫的預設值兜底身分識別（`?? 1`、`?? 2`、`padLeft(4,'0')` 之類）**
🚫 取不到就顯示明確錯誤，寧可沒有畫面也不要給錯的資料。
> **原因**：第四十三輪找到四處，其中一處會讓家屬以 family_id 2 的身分發文到**別人
> 的**家庭留言板，另一處會把提醒歸屬到錯誤的家屬。第四十二輪的假配對碼
> （`padLeft(4,'0')`，見 G158）是同一個模式——猜測值甚至可能誤撞到別人正在使用中的
> 真配對碼。

**G166 — merge 衝突取某一側整段替換時，判斷「這段有沒有本地功能」不能只搜功能性識別
字，還要搜跨檔案傳遞的錨點（GlobalKey、callback、controller）**
這類東西通常沒有專屬字串好搜，得逐行讀或反查賦值後有沒有被用掉。
🚫 驗證腳本的 grep 錨點要卡**呼叫端傳值那一行**，不可卡被呼叫端內部的固定樣板文字—
—樣板文字不管呼叫端傳不傳都在，天生就是恆綠假驗證。
> **原因**：第四十三輪 merge 差點讓第四十一輪新手指引的四個高光錨點靜默消失，而當
> 時的驗證腳本 `grep -c 'key: key,'` 完全抓不到。

**G168 — 破壞性的管理操作（如賽季重置）必須整個流程在單一交易內、重複呼叫安全（原
子條件更新＋唯一約束兩層）、操作前先保存被破壞的資料、寫入稽核紀錄**
🚫 **禁止**在沒有先結算／備份的情況下執行會歸零使用者資料的操作。
> **原因**：賽季重置會歸零全平台長輩的寵物體重。不先結算，三個月的努力歸零且無跡可
> 循。

**G169 — YOLO 的躺姿判斷若加入「不推警報」的分支，必須確認該分支不會造成永久靜音**
🚫 **禁止**「夜間一律不推」這種一刀切——夜間跌倒仍是跌倒，且往往更危險。
✅ 分類不確定時一律 fail-safe 到「會推警報」那一側。
> **原因**：漏報跌倒的代價遠大於誤報睡覺。且分類會被快取，「完全不推」會讓睡眠中途
> 的醫療突發永遠不會示警。

**G171 — 未加引號的 shell 重導向會清空既有檔案，不只是製造垃圾空檔**
本輪 `uban-api/Dockerfile` 被整個清空成 0 位元組（53 行全沒），而 `git status` 只顯
示 `M Dockerfile` 看起來像正常修改。
✅ grep 程式碼片段時 pattern **一律用單引號包住**（Dart 的 `=>` 含 `>`，函式呼叫含
`(`）。這條紀律**驗收指令本身也要守**。
✅ 每輪收尾除了掃零位元組檔，還要跑 `git diff --stat` 檢查有沒有既有檔案「只有刪
除、沒有新增」。

**G173 — `npx tsc --noEmit` 在 solution-style tsconfig 下是死檢查**
`uban-admin/tsconfig.json` 是 `{"files": [], "references": [...]}`，不加 `-b` 只檢
查那個空陣列，**永遠回 EXIT 0**。
✅ 一律用 `npx tsc -b --noEmit`。
> **原因**：一個 `const n: number = "definitely-a-string";` 探測檔，`--noEmit` 回
> EXIT=0 零輸出，`-b --noEmit` 才抓到 `TS2322`。第四十五輪 team-lead 把這個壞指令
> 寫進三份子代理任務清單，導致「TypeScript: No errors found」的回報全是假的；換
> 成 `-b` 後才發現 `Layout.tsx` 早有 3 個既有型別錯誤。

**G174 — `grep -ciF` 會 crash 且靜默回空字串**
`-i` 與 `-F` **併用**時（對含中文的 UTF-8 檔案）直接 SIGABRT，exit 134、輸出空字
串，`$(...)` 代入後看起來就是「0 筆、通過」。
✅ 檢查違規語法之類「必須是 0」的場合改用 Python 讀檔。
> **原因**：`-i`／`-F` 各自單獨用都正常，只有併用才 crash，很容易被誤判成「檢查
> 通過」。

**G175 — `grep -c 'error •'` 抓不到 `flutter analyze` 的錯誤**
這台機器的 `flutter analyze` 用 `-` 當分隔符號，不是 `•`。
✅ 正確判讀是看總結行的組成相加（例如 `96 issues found` 且 `info -`／`warning -`／
`error -` 三者計數相加須等於 96，才代表沒有遺漏）。
> **原因**：實測 96 issues 的輸出：`error •`=0、`info •`=0，但 `info -`=64、
> `warning -`=32——只看 `error •` 會誤判成 0 錯誤。第四十五輪有三個子代理沿用這個
> 壞 pattern。

**G176 — 刪除路由時必須一併檢查所有指向它的連結與重導向常數**
🚫 只改路由表本身不夠，必須 grep 整個 `src` 找該路徑字串，不能只看 `App.tsx`。
> **原因**：第四十五輪移除 `/tasks` 路由後，`App.tsx` 的
> `CAREGIVER_HOME = '/tasks'` 變成死路由：caregiver 登入 → 導去 `/tasks` → 404 →
> catch-all 回 `/` → 又導去 `/tasks`，**無限重導向**。同時 `EldersPage.tsx:185`
> 與 `ElderDetailPage.tsx:200` 也各留了一個連向已刪除員工詳情頁的 `<Link>`。

**G177 — 換授權守衛後，必須檢查端點內部 raw SQL 有沒有「二次過濾」**
共用授權守衛（例如換掉 `Depends`）覆蓋不到端點自己手寫 SQL 裡的重複條件。
🚫 換掉授權方式之後，要逐個端點看內文有沒有再用一次那個值。
> **原因**：第四十五輪讓開發者 token 通過 `institution.py` 時，`list_elders`／
> `list_alerts` 的 raw SQL 裡各還留著一個 `institution_id = %s` 的重複條件。開發
> 者的 `institution_id` 是 `None`，SQL 三值邏輯下 `institution_id = NULL` **永遠
> 不 match**，query 回空清單——**而且不會報錯**。

**G178 — 統計的樣本數 < 2 時，標準差／變異數必須回 `null` 不可回 0**
「標準差是 0」的意思是「所有樣本完全相同」，跟「樣本不足無法計算」是完全不同的
事實，回 0 會讓圖表畫出看似有意義但錯誤的結論。
✅ `statistics.variance()` 在 n<2 會拋 `StatisticsError`，必須接住回 `null` 而非
讓它 500、也不可落成 0；前端同樣不可把 `null` 顯示成 0。
> **原因**：第四十五輪統計儀表板改用不同文字區分「尚未累積資料」／「樣本不
> 足」／真正的 0，避免使用者誤讀圖表。

**G179 — 清垃圾檔絕不可用 ASCII-only 正規表達式判斷「合理檔名」**
🚫 這個專案大量使用中文檔名，`^[A-Za-z0-9_.\-]+$` 之類的判準會把中文檔名整批誤
判成垃圾。
✅ 在 git repo 內只認 `git status --short` 的 `??`；`??` 才是新垃圾（可刪），
`M`／只有刪除行的 diff 是既有檔案被清空（要 `git checkout` 還原）。
> **原因**：第四十五輪 team-lead 為了清 `start)` 這個垃圾檔，用上述判準把
> `uban-api/管理者系統使用說明.md`（22,810 bytes、408 行的交付文件）一併刪掉，
> 已用 `git checkout` 還原。

**G180 — 跨機構查詢 `institution_elder` 時必須加 `discharged_at IS NULL`**
`institution_elder` 的唯一鍵是 `(institution_id, elder_id)`，**同一位長輩可能在
不同機構各留一筆歷史收案紀錄**。
🚫 機構員工的查詢已先用 `institution_id = %s` 鎖到一間機構、最多一筆，不受影
響；但開發者是跨全平台查，LEFT JOIN 若不加 `discharged_at IS NULL`，一個人有兩
筆歷史收案就會讓警報／長輩重複出現。
> **原因**：第四十五輪讓開發者可跨機構查看全平台長輩時發現此問題，是 G177 授權
> 改造的連帶影響。

**G182 — `run_sql_migrations()` 每次開機重跑，DROP TABLE 前必須先停用對應的
CREATE TABLE**
🚫 該函式沒有「已執行過」的追蹤表，靠 `CREATE TABLE IF NOT EXISTS` 自身冪等，
每次開機都會把 migration 檔裡的建表語句重新執行一次；只在檔頭加註解、不動建
表語句本身，DROP TABLE 做完、後端一重啟，表格會透過那份 migration 原封不動生
回來。
✅ 停用時要逐節精確處理：把該刪的 `CREATE TABLE` 逐行註解掉（不刪除文字，保留
歷史）；同一份 migration 檔裡若混有不相關的表（第四十六輪的
`001_institution.sql` 第 8 節 `elder_daily_step` 與機構表同檔但完全獨立），必
須讓那些表繼續可執行——整檔註解或整檔跳過都會誤傷它們。
> **原因**：第四十六輪刪除機構模組 7 張表時發現，`main.py::run_sql_migrations()`
> 每次開機都重跑 `scripts/migrations/` 底下所有 `.sql`。驗證方式是模擬該函式
> 的解析邏輯，確認檔案只剩 1 條會執行的語句。

**G183 — 檢查 import 殘留必須用 AST 解析，不能用字串搜尋**
🚫 刪除模組後用字串搜尋（grep）確認「沒有殘留 import」不可靠——會把 docstring
與註解裡的提及也算進去，改寫註解就能騙過它。第四十六輪對三個檔案就曾因此誤
報。
✅ 正解是解析 `ast.Import` 與 `ast.ImportFrom`；`ImportFrom` 要同時比對
`node.module` 與 `node.module + '.' + alias.name`，否則
`from routers import institution` 這種寫法會漏掉。`compileall` 只檢查語法、抓
不到名稱解析錯誤，不能當這項的替代。
> **原因**：第四十六輪刪除 `routers/institution.py` 等機構模組時，需要驗證沒
> 有其他檔案仍 import 它們。

**G184 — 驗證要測量目標本身，不要測一個容易被迎合的代理指標**
🚫 「新 API 完全不依賴機構表」寫成 `src.count('care_staff') == 0` 之類的字串計
數，測的是「檔案裡有沒有這串字」，不是「有沒有真的查這張表」——子代理為了讓
檢查回報 0，會刻意在註解裡避開那些識別字，若真的用了機構表，只要拼成
`"care_" + "staff"` 就能一樣回 0。可以被迎合的檢查不是驗證。壞指標的副作用不
只是漏掉問題，還會逼執行者為了過關而改動無關的東西（第四十六輪連本質安全的
`f"...IN({ph})..."` 都被改寫成字串相加）。
✅ 正解是從非註解程式碼抽出 `FROM`／`JOIN`／`UPDATE`／`INTO` 後面的表名，再與
目標集合取交集。寫驗證時多問一句：「如果對方想在不滿足需求的情況下讓這條通
過，做得到嗎？」
> **原因**：第四十六輪交辦「新 API 完全不依賴機構表」時的驗證腳本用了可被迎
> 合的字串計數指標。

**G185 — 刪除一個方法或符號時，要一併檢查文件與註解裡的引用**
🚫 只用「編譯／分析工具通過」或「目標關鍵字搜尋」判斷刪除乾淨——這類殘留不會
編譯錯誤、不會被目標關鍵字掃到（搜的是被刪除檔案裡的關鍵字，不是引用它的檔
案），只有真的去讀那段文字的人才會發現指路指到空氣。
✅ 刪除符號後，用該符號名稱對全專案（含 `.md` 與程式碼註解）搜一次，比只看編
譯結果可靠。
> **原因**：第四十七輪刪除 `triggerTestFall()` 後，`friend_service.dart` 的檔
> 頭註解仍舉它當「回傳 `String?`、`detail` 錯誤慣例」的範例，變成指向不存在
> 的符號。

**G186 — `_viewingMonitorDeviceId` 決定的是整個彈窗要不要出現，不再只是一顆按鈕**
🚫 這個旗標若卡住沒被清除，家屬會「靜默」收不到該台監視機的警報彈窗——不只是
少一顆「查看監視畫面」鍵那麼輕微。任何新增的「離開監控檢視」路徑，若忘了觸發
既有 `.then()` 的清除或自行清除本旗標，都會讓後續警報永遠被當成「已經在看」而
不彈窗。
✅ 抑制彈窗時，語音朗讀與 `_activeAlerts` 卡片寫入必須仍然發生：朗讀的
`return` 要放在 `_alertTts!.speak(...)` 之後，卡片寫入本來就在呼叫端
`_handleCctvAlert` 完成、不受影響。新增任何「離開監控檢視」路徑，都要確保
`Navigator.push(...).then()` 對本旗標的清除會被觸發，或自行清除。
> **原因**：第四十八輪把 `_presentCctvAlert()` 的 `alreadyViewingThisDevice`
> 判斷從「隱藏一顆按鈕」擴大成「整個彈窗提前 return」，用途擴大但清除機制沒
> 變，清除路徑若有缺口風險比第四十輪高得多。

**G187 — 「請求失敗」與「結果真的是空的」若無法分辨，就不能拿來覆蓋既有畫面狀態**
🚫 `ApiService.fetchMonitorDevices()` 的實作是 `fetchMonitorDevicesOrNull() ??
const []`（見 G78），任何請求失敗／逾時／後端短暫異常都被吞成「成功，但清單是
空的」，型別上與「這位長輩真的一台監視機都沒有」完全無法分辨；`_applyDeviceList()`
對兩者一視同仁覆蓋畫面，是監控清單偶爾整個消失的根因。
✅ 凡是 `?? const []` / `?? {}` 這類把錯誤攤平成空值的包裝，其呼叫端必須把空值
當成「不更新」而不是「清空」；真正的清空要有獨立、明確的來源（推播事件或使用
者操作），不能靠輪詢結果剛好是空的來清空畫面。
> **原因**：第四十八輪查出「監控裝置清單偶爾整個消失、切分頁再切回來才恢復」
> 的根因——使用者回報的「恢復」其實是剛好等到下一輪成功的刷新，不是切分頁本
> 身修好的。

**G188 — 帶顏色輸出的工具在 grep 之前必須先關掉顏色**
🚫 `tsc`、部分 linter 預設帶 ANSI 顏色，色碼會夾在檔名與行號之間（例如
`src/x.tsx` 後接跳脫序列才是行號），讓針對「檔名:行號」的 grep pattern 靜默回
空、看起來像「零錯誤」。
✅ 用 `tsc --pretty false` 等旗標關閉顏色再 grep；本輪在管理端型別檢查上實際
中招一次，改用 `--pretty false` 後才抓到真正的輸出。
> **原因**：第四十八輪管理端資料表改造（項目 C）驗證型別檢查結果時發現。

**G189 — React 用 `useRef` 做「已消費」guard 時，觸發值歸零的分支要一併重置 ref**
🚫 只在消費時設定 ref、沒有在觸發值歸零的分支重置，會讓 `null → N → null →
N` 的第二次被誤判成「已經消費過」而不觸發——因為 ref 仍停在第一次的 `N`。
✅ 觸發值歸零（例如 `prefill` 被消費後呼叫 `onConsumePrefill()` 設回
`null`）的同一個分支，要把 ref 也重置，讓下一次非 null 值能被視為新事件。
> **原因**：第四十八輪管理端 `BanSection` 的 `prefill` props 就是這個形狀，用
> `useRef` 記錄「已消費過」但歸零分支忘了重置。

**G190 — 鐵律 #14 的例行 8 畫面檢查判準抓不到小字級固定寬度元件的溢位**
🚫 例行檢查判準是「≥18pt 標題 × 同列元素數」，本輪使用者截圖回報的溢位是
11pt 徽章，遠低於門檻；例行檢查跑出「乾淨」的同時，使用者眼前正有一處真實溢
位，例行檢查通過不等於畫面沒有溢位。
✅ 小字級但固定寬度的元件（徽章、按鈕、圖示）擠在同一列時，同樣會溢位，且更
難用靜態判準抓到；實機／截圖看到就精準修一處，不要因為靜態掃描乾淨就否定使
用者的回報。
> **原因**：第四十八輪使用者截圖回報 `family_interaction_tab.dart` 的
> `RIGHT OVERFLOWED BY 1.6 PIXELS`，肇因徽章正是 11pt，例行檢查的 27 處候選
> 中完全沒有命中它。

**G191 — 警報合併（UPSERT）必須同時比對「未結案狀態」與「時間窗口」**
🚫 只比 `status='active'`：家屬一開監控轉成 `acknowledged` 後，同一事件再
被偵測會另開新列並重複推播。只比「未結案」（不看時間）：新事件會併進數天
前的舊列、沿用舊 `first_detected_at`，一建立就被判逾時升級。
✅ 合併條件必須同時成立：**未結案**（`status != 'resolved'`）**且**上次偵
測在 `SAME_EVENT_WINDOW_MINUTES=30` 分鐘內；窗口比較一律在 Python 端用
`assume_utc()` 做，不要寫進 SQL。
> **原因**：第四十九輪修正警報合併窗口時踩了兩次坑——先是只認 `active`，
> 造成 `acknowledged` 後 15 秒內（`FALL_COOLDOWN_S`）再偵測就會重複推播；
> 放寬成「未結案就合併」又會讓新跌倒併入幾天前的舊列並被誤判逾時，最終才
> 收斂成「未結案且在時間窗內」。

**G192 — 排程 job 不得把整輪資料庫巡檢丟進主事件迴圈**
🚫 Socket.IO 通話信令跑在同一個事件迴圈上，DB 巡檢一慢，通話信令就跟著卡
住。
✅ 排程 job 的 DB 巡檢一律同步跑在排程自己的執行緒；只有必須非同步送出的
推播才用 `run_coroutine_threadsafe` 橋接主事件迴圈並設逾時，另外用非阻塞
`threading.Lock` 防止上一輪還沒結束就重疊執行。
> **原因**：第四十九輪新增每分鐘執行的 `services/alert_watchdog.py`，若
> 直接把整段資料庫巡檢寫成 async 掛在主迴圈，會拖慢共用同一迴圈的通話信
> 令。

**G193 — 推播／重推函式必須回傳實際送出對象數，UI 不得在 0 對象時顯示「已通知」**
🚫 `messaging.send` 呼叫成功只代表 FCM 服務接受了這則訊息，不代表家屬裝置
真的收到、更不代表家屬看到。
✅ 推播函式（如 `_broadcast_alert()`）要回傳 `{socket_targets, socket_sent,
fcm_targets, fcm_sent}` 這類實際送出對象數，呼叫端依此區分「已送出 N 個裝
置」「沒有任何可推播的裝置」「重推失敗」三種文案，不得一律顯示「已通
知」。
> **原因**：第四十九輪開發者主控台「聯絡家屬」按鈕，若在 0 個可推播家屬
> 裝置時仍顯示已通知，會讓開發者誤以為警報已經送達而不再採取後續行動。

**G194 — `tests/conftest.py` 必須在任何應用程式 import 之前 `os.environ.setdefault("DISABLE_DB", "true")`**
🚫 `.env` 的 `DB_HOST` 指向正式 MySQL，`load_dotenv()` 不會覆蓋已存在的環
境變數；autouse 的 `cleanup_db` 每個測試前後都執行 DELETE，兩者疊加，等於
任何人一跑 `pytest` 就可能直接寫壞正式資料庫。
✅ 要刻意連正式 DB 測試，必須顯式帶 `DISABLE_DB=false` 執行，不能靠預設
值。
> **原因**：第四十九輪盤點測試環境時發現的既有風險，在本輪修正前一直成
> 立。

**G195 — 一次性資料修正型 migration，判定條件必須用「新程式碼必然會寫入的欄位仍為 NULL」這種只成立一次的特徵，且排在對應的 backfill 之前，並用靜態測試守住前提**
🚫 `main.py::run_sql_migrations()` 每次開機都重跑整個 migration 檔案，沒
有「已執行過」的追蹤表；用「這次要不要做」的旗標或時間戳判斷，開機兩次就
可能誤判。
✅ 挑一個「新程式碼上線後必然會寫、上線前必然是 NULL」的欄位當判定依據
（例如本輪的 `first_detected_at`），並排在補齊該欄位的 backfill **之前**
執行；用靜態測試（如 `tests/test_alert_insert_paths.py` 的 AST 掃描）鎖住
「新程式碼的每一條寫入路徑都會寫這個欄位」這個前提不被之後的修改破壞。
> **原因**：第四十九輪 migration 014 用這個手法把「本輪之前建立、仍未結
> 案」的警報一次轉 `resolved`，前提是新程式碼的兩條 INSERT 路徑都一定寫
> `first_detected_at`。

**G196 — 家屬端警報通知文案必須依 `alert_type` 分流**
🚫 `sos_voice`（長輩開口求救）沒有監視畫面，不可寫成跌倒、不可叫家屬去看
監視畫面；提醒（`isReminder`）與首次偵測也必須分流，混用會讓家屬把第 N
次提醒誤會成又一次新事件。
✅ 依警報類型與是否為提醒分別準備文案（本輪為六類型 × 首次／提醒共 12
組）；新增警報類型時，同步檢查通知文案是否也需要新增對應組合。
> **原因**：第四十九輪查出 `cctv_alert_notification.dart::show()` 原本標
> 題與內文一律寫「偵測到跌倒」，長輩對小嘎開口求救時，家屬收到的卻是跌倒
> 通知還被叫去看監視畫面。

**G197 — G102 的 `identical()` 守衛在「接手畫面於 `.then()` 重新綁定、離開畫面於退場動畫後才 dispose」的順序下尤其關鍵**
🚫 `Navigator.pop()` 會先完成 route 的 future（`.then()` 在 microtask 執
行），離開畫面的 `dispose()` 則要等退場動畫結束——順序是「接手畫面先重新
綁定 → 離開畫面才清成 null」，無條件 `= null` 一定會清掉接手畫面剛綁好的
回呼。
✅ 任何在 `dispose()` 清除 `Signaling` 回呼的地方，都要先用 `identical()`
比對目前回呼是否仍是自己設的那一個，不是就不要清。
> **原因**：第四十九輪查出 `elder_screen.dart::dispose()` 與
> `elder_home_screen.dart::dispose()` 無條件把回呼設為 null，導致長輩講
> 完電話回首頁後再也收不到主動關懷訊息，直到 App 重啟。

**G198 — 備援通知的 `actionId == null` 不算「使用者已接聽」，只能改寫「待接聽」鍵**
`local_call_notification.dart::notificationBackgroundTapHandler` 與
`consumeLaunchPayload()` 只有 `response.actionId == actionAcceptId`（明確按下
「✓ 接聽」）才可以呼叫 `_persistTapAsAccepted` 寫 `pendingAcceptedCall`；
`actionId == null`——涵蓋「通知本體被點」與「螢幕鎖定時系統因
`fullScreenIntent: true` 自動觸發的 content PendingIntent」兩種情況——一律
改呼叫 `_persistTapAsPendingRing` 寫**新鍵** `pendingLocalRingCall`（欄位集合
與 `pendingAcceptedCall` 相同：`roomId`/`senderId`/`callId`/`issuedAt`/
`expiresAt`/`senderRole`/`isVideoCall`/`timestamp`）。
`main.dart::_checkPendingLocalRingCall`（由 `_scheduleLocalRingCallFallback`
排程，冷啟動輪詢 `splashActive`；resume 直接呼叫）消費該鍵時，改用既有的
`_showIncomingCallDialog` 顯示接聽／拒接畫面，讓使用者自己決定，**不可**
直接寫 `pendingAcceptedCall` 逕自進房。
🚫 **不可**把 `pendingLocalRingCall` 併回 `pendingRingCallData`——後者由
BG FCM handler 的 `call-request` 分支預寫、也被 CallKit accept 路徑更新為
`isAccepted: true`，語意是「這通來電目前的最新狀態」，混用會讓兩條互相
獨立的來源互相覆蓋，導致「已接聽」被「還在響」蓋掉或反之。
> **原因**：第五十一輪查出 `show()` 發出的備援來電通知帶
> `fullScreenIntent: true`，但 `notificationBackgroundTapHandler` 舊版只把
> `actionId == actionDeclineId` 當拒接，**其餘一切**（含 `actionId == null`）
> 都落到 `_persistTapAsAccepted`——螢幕鎖定時系統自動觸發 fullScreenIntent
> 的 content PendingIntent 也會被誤判成「使用者已接聽」，長輩端第一通來電
> （CallKit 尚未暖機、走備援通知這條路）因此沒有經過同意就直接開啟視訊。
> 只有這條備援通知路徑受影響——CallKit 路徑本來就要求原生確認
> `isAccepted == true` 才算接聽（`main.dart::_checkInitialCall` /
> `actionCallAccept`），見 G10。

**G199 — 全域語音助理浮動鈕在通話房／來電響鈴／監控畫面必須讓位；標記只能包住畫面根 widget，絕對不可塞進 `Stack` 的 children**

`widgets/global_assistant_button.dart` 的 `GlobalAssistantButton` 掛在
`main.dart` 的 `MaterialApp.builder`，蓋在**所有**路由之上。凡是「按錯就會
影響一通電話」的畫面，都必須用 `AssistantHiddenZone` 把浮動鈕蓋住。

✅ **正確做法：包住畫面的根 widget**——`return AssistantHiddenZone(child: Scaffold(...));`。
`AssistantHiddenZone` 是純 pass-through（`build()` 直接回傳 `widget.child`），
包在最外層不會改變任何版面；它自己的計數只依賴 `State` 生命週期，
與被包住的路由同生共死，不會漏算。

🚫 **絕對不可放進 `Stack` 的 children**（即
`Stack(children: [..., const AssistantHiddenZone(child: SizedBox.shrink()), ...])`）。
機制：`RenderStack._computeSize()` 的規則是——**只要 `Stack` 的 children 裡有任何
一個「非 `Positioned`」子元件，`Stack` 自己的尺寸就由那些非 `Positioned` 子元件中
最大的一個決定**（各自以放寬後的約束量測取最大寬高，再套用外部約束收斂）；
**只有全部 children 都是 `Positioned`／`Positioned.fill` 時，`Stack` 才會退回
吃滿外部約束（`constraints.biggest`）**。`Scaffold` 的 `body` 給的是寬鬆約束
（`minWidth`/`minHeight` 皆為 0）。一個原本 children 全是 `Positioned`／
`Positioned.fill`（靠「退回吃滿約束」撐滿整個畫面）的 `Stack`，只要混入一個
非 `Positioned` 且本體 0×0 的 `AssistantHiddenZone(child: SizedBox.shrink())`，
判斷分支就會切換成「用非 Positioned 子元件決定尺寸」——而這個唯一的非
Positioned 子元件是 0×0，套用寬鬆約束（min 為 0）收斂後仍是 0×0，整個
`Stack` 因此塌成 0×0，底下所有 `Positioned` 子元件（視訊畫面、按鈕）都被壓縮
到零尺寸、沒有任何 hit-test 目標。

**實際後果（不是理論風險）**：第五十一輪照本護欄原始條文「在畫面自己的
widget 樹裡放一個 `AssistantHiddenZone(child: SizedBox.shrink())`」字面實作，
選擇塞進 `elder_screen.dart` 通話房 `Stack` 的 children，觸發上述塌陷——
長輩端**所有**通話房（含緊急通話）黑屏、無法掛斷、無法操作，只能等家屬端
掛斷後被動 `pop` 回首頁。第五十二輪改為包住整個 `Scaffold`
（`return AssistantHiddenZone(child: Scaffold(...));`），並改寫本條文字本身
——原文字沒有明講「放哪一層」，正是造成這次回歸的禍首。

✅ **`camera_screen.dart:168` 為什麼安全**：那裡的
`AssistantHiddenZone(child: SizedBox.shrink())` 放在 `Column` 的 children
裡，不是 `Stack`。`Column`（`RenderFlex`）沒有「非 flex 子元件會反過來決定
父層尺寸」這條規則——`Column` 預設 `mainAxisSize: MainAxisSize.max`，其主軸
尺寸直接取外部約束給的上限，與各個子元件本身多大無關；一個 0 高度的非
`Expanded` 子元件在配置空間時只貢獻 0，`Expanded` 兄弟元件依然拿到全部剩餘
空間，`Column` 本身的尺寸不受影響。這正是 `Stack` 與 `Column`／`Row` 在
「子元件尺寸如何回饋給父層」上的關鍵差異，也是本條要求「只能包根 widget、
不可塞進 `Stack`」，而不是一概禁止塞進任何容器的原因。

以下三點為 G199 原文仍然正確、不因本次改寫而變動的部分：
- 浮動鈕必須在通話／來電響鈴／監控畫面讓位，不可省略。
- 🚫 **不可**改成去動這些畫面的 `initState()` / `dispose()` 做計數——
  `CLAUDE_call-monitor-ui-map.md` §5.4 把通話畫面的 `initState`/`dispose`
  順序列為「絕對不要碰」；`AssistantHiddenZone` 刻意做成 widget 樹上的標記，
  它自己的 `State` 生命週期與被包住的路由同生共死，計數不會漏。
- 新增任何全螢幕通話／來電畫面時，**同一個 commit 內**就要補上這個標記
  （包根 widget，不塞進 `Stack`）。
- 🚫 **不可**在浮動鈕裡另外實作一套助理啟動流程。啟動器由
  `ElderHomeScreen` 在 `initState` 登記到 `elderAssistantLauncherNotifier`
  （值就是既有的 `_triggerGoogleAssistantOverlay`），`dispose` 時用 `==`
  比對自己仍是持有者才清空（同 G102 的道理）。複製一份等於讓喚醒詞暫停、
  畫面情境注入、`autoCall` 撥號接手三件事出現兩套會漂移的實作。

**目前正確的使用點**：

| 檔案 | 位置 | 所在容器 | 包法 |
|------|------|---------|------|
| `elder_screen.dart` | `build()`（:2035） | `Scaffold` 外層 | 包根 widget（第五十二輪修正） |
| `camera_screen.dart` | :168 | `Column` | 塞進 children（對 `Column` 無害，見上） |
| `elder_home_screen.dart` | :788（`_showIncomingCallDialog`） | `AlertDialog` 外層 | 包根 widget |
| `main.dart` | :1822（`_showIncomingCallDialog`） | `AlertDialog` 外層 | 包根 widget |
| `google_assistant_overlay.dart` | :46（`show()`） | `GoogleAssistantOverlay` 外層 | 包根 widget |

> **原因**：第五十一輪使用者回報「長輩端語音助理叫不出來」。查出助理的兩個
> 呼叫點都活在 `ElderHomeScreen` 的 `Stack` 裡，只覆蓋 5 個分頁，任何
> `Navigator.push` 出去的畫面（通話房、監控、新聞播放器、配對頁）都叫不出來。
> 掛到 `MaterialApp.builder` 解決了覆蓋範圍，但條文本身只寫「放一個
> `AssistantHiddenZone`」、沒有明講放在畫面 widget 樹的哪一層——第五十一輪
> 選擇塞進 `elder_screen.dart` 通話房的 `Stack` children，把「叫不出語音
> 助理」換成了「打不通電話」，是更嚴重的回歸。第五十二輪定位根因並改寫本
> 條，把「包根 widget」訂為唯一容許的寫法，並明文禁止塞進 `Stack`。

**G201 — 錯誤不可被吞成「正常回覆內容」**
generator／函式把例外吞掉、改成 `yield`／`return` 一段錯誤字串當作正常內容
送出，會讓呼叫端原本設計好的備援機制永遠不會被觸發——因為呼叫端看到的是
「成功回傳了內容」，不是「拋出例外」。
✅ 錯誤一律以例外傳播；只有在串流**已經**送出部分內容時，才改用友善收尾
（不重講、不重複播放），因為此時再拋例外會讓使用者聽到講一半就中斷。
🚫 **禁止**用 `has_yielded`／等效旗標以外的方式決定要不要 raise——「還沒送
出任何內容」與「已經送出一半」要分開處理。
> **原因**：Ollama 主機回 502 時，`services/ollama_service.py` 把例外吞掉、
> 把錯誤字串當成正常回覆 `yield` 出去，`routers/ai.py` 的 Gemini 備援永遠
> 不會被觸發，長輩直接聽到「對話服務異常: (status code:502)」這句技術訊息。

**G202 — 不可用字串前綴偵測錯誤**
`"(流式服務出錯:"` 這種寫死的字串前綴，與實際產生的錯誤字串
`"(對話服務異常:"` 從來對不上，靠字串前綴判斷「這是不是錯誤」的備援邏輯
因此是死碼——永遠判斷不成立，備援永遠不會被觸發。
✅ 判斷「是不是錯誤」要嘛用例外（見 G201），要嘛用明確的旗標／型別，不要
用會漂移的字串前綴比對。
> **原因**：串流版的備援判斷用字串前綴 `"(流式服務出錯:"` 偵測錯誤，但
> `ollama_service.py` 實際產生的錯誤前綴是 `"(對話服務異常:"`，兩者從一開
> 始就對不上，這條備援判斷自建立以來就沒有生效過。

**G210 — `database.py::init_sqlite_db()` 內任何無條件執行的 DML，之後都要接一次明確 `conn.commit()`**
本函式唯一預設的 `conn.commit()` 在檔尾，且只在「`user_account_data` 是空的」（全新
資料庫）條件下才會執行到。Python 的 `sqlite3` 模組在預設交易模式下，任何 DML
（`INSERT`/`UPDATE`/`DELETE`，即使是 `INSERT OR IGNORE`）都會隱式開啟一個交易，之後
包含 `CREATE TABLE` 在內的所有陳述式都落在同一個未提交交易裡；`conn.close()` 不會自動
`commit()`，於是這整段（含新表的建表本身）在已經有資料的既有 SQLite 檔案上會被**靜默
捨棄，且不拋出任何例外**。
✅ 在函式中新增任何「不論資料庫是否已有資料都會執行」的 DML（例如 seed 資料的
`INSERT OR IGNORE` 迴圈）之後，緊接著明確呼叫一次 `conn.commit()`，不要依賴檔尾那個
只在全新資料庫才會執行到的提交。
🚫 **禁止**假設「反正檔尾有 `conn.commit()`」就不用管——那個提交是有條件的，不是保證
執行。
> **原因**：2026-09-24 第五十三輪 `petdb53b` 新增 `pet_food` 主表時，seed 迴圈是本函式
> 第一個無條件執行的 DML，導致其後 `elder_food_ledger`／`elder_food_grant` 的
> `CREATE TABLE` 在已有資料的本機 SQLite 檔案上完全消失、卻不拋任何例外，除錯耗費
> 大量時間才定位到這是交易語意問題，不是 SQL 語法錯誤。

**G211 — 「單次」提醒觸發後必須把 `is_active` 關閉**
`routers/reminder.py::resolve_repeat_days_trigger()` 對「單次」／「單次提醒」的判斷是
「沒填 `start_date` 就視為任何一天都適用」，這代表若沒有任何地方在觸發後停用它，這類
提醒會從建立當天起每天在同一分鐘重新被觸發、永不停止。
✅ 任何會判定「這筆提醒現在適用」並實際派送（Socket／FCM）的地方
（`main.py::check_remote_reminders_job()`），對 `repeat_days` 屬於「單次」類別的提醒，
成功觸發後要立刻 `UPDATE remote_reminders SET is_active = 0`，並廣播
`reminder-sync` 讓其他畫面即時看到。
🚫 **禁止**只靠當日內有效的去重字典（如 `_last_triggered_reminders`）防止重複——跨日
就會重置，防不了「明天同一分鐘再跳一次」。
> **原因**：2026-09-24 第五十三輪，使用者回報「長輩端明明沒有任何排程，卻自動跳出一個
> 莫須有的排程提醒」，根因正是「單次」提醒觸發後從未關閉 `is_active`。查證後**不是
> 時區 bug**——`complete_reminder` 端點只寫 `activity_log`，完全不碰 `is_active`。

**G212 — import 期就已定案的模組常數，不要做成「開發者主控台可調參數」**
若某個常數在 import 當下就被拿去建構其他物件（例如 `_YOLO_MAX_CONCURRENCY` 下一行
立刻拿去建 `asyncio.Semaphore(_YOLO_MAX_CONCURRENCY)`），把它登記進執行期讀取的可調
設定表（`app_settings`）不會有任何效果——物件已經用舊值建好了，之後改設定值不會回頭
影響它。這種「看起來能調、實際上沒用」的假旋鈕比沒有這個選項更容易誤導開發者。
✅ 新增可調參數前，先確認該常數的消費端是在**執行期讀取**（每次用到才查一次目前值），
還是在 **import 期或啟動時就被消費掉、產物已經定型**。屬於後者的話，要嘛不做成可調、
要嘛連消費端一起重新設計成動態可調（例如改成能重建的限流器），不要只加一個讀資料庫的
包裝就宣稱「可調」。
> **原因**：2026-09-24 第五十三輪 `settings53` 盤點可調參數時，明確排除
> `routers/alert.py::_YOLO_MAX_CONCURRENCY`（`asyncio.Semaphore` 在 import 時就已建構），
> 並在 `database.py` 與 `routers/alert.py` 兩處都留下註解說明原因，避免後續有人「順手」
> 把它也塞進登錄表。

**G213 — `admin_action_log.target_id` 是 `VARCHAR(16)`，寫入前確認識別字串不會超長**
這張表是管理端動作的稽核軌跡（封禁／解封／調整訂閱層級／處理 BUG 回報等），
`target_id` 欄位只有 16 字元。若某個新的管理動作的目標識別字串可能比這長（例如
`app_settings` 的 `setting_key` 最長 46 字元），直接塞入會被截斷或需要資料庫另外報錯。
✅ 識別字串可能超過 16 字元時，改存一個較短的分類鍵（例如所屬設定分組名稱）到
`target_id`，完整值放進 `detail` 欄位（`TEXT`，不受長度限制）。
🚫 **禁止**放寬 `target_id` 的欄位長度來將就——這張表已經上線且被查詢邏輯依賴
（`idx_admin_action_log_target (target_type, target_id)` 索引），改欄位長度要走
migration，不是預設選項。
> **原因**：2026-09-24 第五十三輪 `settings53`／`devconsole53c` 在幫 `app_settings`
> 相關管理動作寫稽核紀錄時發現這個欄位長度限制，改用分類鍵＋`detail` 補完整值的方式
> 繞開，未來新增管理端動作若也要記錄稽核，須先檢查目標識別字串的長度。

**G214 — 帳號刪除的資料表清單，理想上應與 `unbind_elder()` 的 `cleanup_statements` 共用一份；目前尚未共用**
`routers/pairing.py::unbind_elder()`（家屬解除最後一個綁定時觸發的完整清除）維護一份
需要清理的資料表清單。每當新增一張以 `elder_id`／`user_id` 為外鍵或邏輯關聯的長輩相關
表，理論上都要同步進這份清單，但**目前沒有任何機制強制同步**，這份清單已知沒有涵蓋
第 41／43／48／49／51／53 輪陸續新增的表（例如長輩朋友圈、家屬好友系統、`pet_food`／
`elder_food_grant`、`app_settings` 等）。
✅ 新增任何長輩相關的資料表時，同一個 PR／輪次裡順手檢查 `unbind_elder()` 的
`cleanup_statements` 是否也該加一筆；若該表不帶外鍵，不加也不會 500，但長輩解綁後會
留下孤兒列，之後排查資料異常會誤導人。
🚫 **禁止**假設「反正不帶外鍵就不用清」——不會炸不代表不用清，孤兒列本身就是問題。
> **原因**：2026-09-24 第五十三輪收尾盤點時發現此缺口，已列為下一輪優先事項；理想的
> 長期解法是讓兩份清單（帳號刪除／解綁清除）共用同一份資料表登記，而不是各自維護。

**G215 — 封禁（`account_ban`）目前只能擋住會呼叫 `/api/auth/login` 的帳號，對長輩自主帳號無效**
`routers/auth.py` 的 `/login` 端點在登入成功後檢查 `account_ban.is_banned`，但長輩
**自主建立**的帳號建立後就不再呼叫這個端點——身分改靠本機 `SharedPreferences` 記憶
（`saved_role`／`saved_id` 等既有續登機制），重開 App 也不會重新登入。對這類帳號執行
封禁，帳號在資料庫裡被標記了，但裝置端完全感覺不到。
✅ 需要封禁對長輩自主帳號立即生效時，不能只在登入端擋——要主動通知已在線的裝置登出
（例如透過既有的 `force-logout` Socket 事件＋FCM 廣播，比照現有帳號被解綁時的機制）。
🚫 **禁止**只驗證「封禁後登入會被拒絕」就視為封禁功能已完整——這只覆蓋了會重新登入
的帳號類型。
> **原因**：2026-09-24 第五十三輪 `devconsole53c` 實作封禁擋登入後，稽核時發現長輩自主
> 帳號這個例外，已與使用者確認下一輪改走 `force-logout` 廣播機制補齊。
