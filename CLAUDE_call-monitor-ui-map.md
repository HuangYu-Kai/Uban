# 通話/監控 UI 按鈕與跳轉地圖

給「只改 UI、不懂信令」的人看的畫面與按鈕跳轉地圖。本檔於 2026-08-25 從 `CLAUDE_call-monitor.md` 分離出來（原 §5），因主檔逼近 256 KB 單次讀取上限。護欄見主檔 §7；通話生命週期見主檔 §4。

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

### 5.6 家屬端首頁「最新警示」（2026-08-17 第二十五輪新增）

> 位置：家屬端「首頁」分頁 →「最新警示」區塊（`family_home_tab.dart::_buildAlertPreview`）。

三個資料來源，依優先序疊加顯示：

| 順序 | 來源 | 型態 | 細節 |
|------|------|------|------|
| 1（最高） | `activeAlerts` | 即時 | Socket `cctv-alert` 推播，存於記憶體 |
| 2 | `_emergencyAlerts` | 持久化 | `ApiService.getEmergencyAlerts` → `GET /api/alerts/{elder_id}` → `emergency_alerts` 表 |
| 3 | `_realLogs` | 持久化 | `activity_log` 表 |

- **去重**：若某 `alert_id` 已出現在即時清單 `activeAlerts`，`_emergencyAlerts` 裡的同一筆**不重複顯示**。
  後端對同一 `elder + device + alert_type` 的 active 警報是 **UPSERT**、沿用同一 `alert_id`，
  這正是前端去重比對的依據。
- **空狀態**：三個來源皆空時顯示空狀態文案，**不再**顯示假資料——舊的 `_mockAlerts` 已移除。
- 🚫 `GET /api/alerts/{elder_id}` 的 `user_id` 為必填 query 參數；呼叫者與該 `elder_id` 無關係時回
  **404**，不是 403（與 §3.8／**G45** 的授權慣例一致）。

---

