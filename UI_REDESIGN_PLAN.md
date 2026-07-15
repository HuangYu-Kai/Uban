# Uban UI 改造接力計劃 (HANDOFF)

---

## ✅ 第三階段：毛玻璃設計語言 + 長輩端細修（**長輩端已完成並實機驗證**，2026-07-15）

分支 `newui`。`flutter analyze lib` = 0 error。**完整更新日誌見 `README.md`（2026-07-15 條目）**，此處只留接力重點。

**長輩端全部完成（實機截圖驗證四分頁 OK）**：
- ✅ 毛玻璃元件 `lib/widgets/glass_card.dart`。
- ✅ 首頁 `elder_tabs/elder_home_tab.dart`：**三層封面**（第一層 teal `55B695→FFFFFF`／第二層 `DFFFF4→FFFFFF` 偏左露圓角／第三層 sheet `DDE6DE` 圓角20）＋右上浮動**會員徽章+頭像**（徽章圖已放 `assets/images/pig_badge_gold|silver|bronze.png`＝金太陽/銀/銅豬；頭像 `assets/images/user_avatar.png`；目前固定顯示「金豬會員」）＋毛玻璃日期卡＋單一大頭條（優先有圖、點卡=聆聽頁、看更多=聆聽頁自動展開列表）。
- ✅ 導覽 4 分頁 `首頁/電話/聊天/我的`（`elder_home_screen.dart` IndexedStack 0/1/2/3，bar 固定）。
- ✅ 電話分頁 `friends_screen.dart`（每位家人右側「電話(語音)+視訊」圓鈕）。
- ✅ 聊天分頁 `elder_chat_screen.dart`：AI 名「**小嘎**」、無標題無頭像、平底背景 `F1F5F9`、**WeChat 式「按住 說話」語音輸入**（`speech_to_text`，按住即時顯示辨識文字、放開送出）＋鍵盤切換。**ZenPond `zen_pond/` 保留未刪**。
- ✅ 個人頁 `elder_profile_tab.dart` 登出鈕固定最底（避開導覽列）。
- ✅ `news_listen_player_screen.dart` 加 opt-in `startExpanded`（看更多→進場自動展開列表面板）。

**下一棒待辦**：
- 🔲 **子女端（家屬端）整體套此設計語言**——使用者本輪明確指示「先不要動」，之後再做。
- 🔲 **接後端資料**（見 README「🔌 待接後端資料」）：會員等級（金/銀/銅豬切換）、健康資料、步數/活動量同步——**長輩端與子女端共用**，請設計共用欄位/端點。

**測試備註**：登入會跳 CCTV（後端 `hasCommDevice`，非 bug，連 `pm clear` 也一樣）。要進長輩首頁測試用 App 內建 dev-bypass：`flutter run --dart-define=DEV_BYPASS_LOGIN=true --dart-define=DEV_BYPASS_USER_ID=4 --dart-define=DEV_BYPASS_USER_NAME=gawa --dart-define=DEV_BYPASS_ROLE=elder`。模擬器 DNS 要 `-dns-server 8.8.8.8`（否則 API TimeoutException）；debug APK 180MB，模擬器磁碟易爆，必要時 `emulator -wipe-data` 冷開。

---

## 🔄 第二階段：整體設計語言重做（進行中，2026-07-14）

使用者追加需求：**整體設計語言重新設計**，主色維持 teal，**新聞（代誌報給你知）功能保留**，客群＝**不太會用手機的獨居長輩**。決策：兩端都重做／長輩首頁大幅簡化成大按鈕直列／導覽列圖示+大字標籤／頭條區改「單一大頭條 + 唸給我聽 + 看更多」。

**已完成**：
- ✅ `app_theme.dart` 新增 `ElderScale`（適老化字級/大按鈕高84/圖示40）。
- ✅ 新增共用元件 `lib/widgets/elder_action_button.dart`（全寬大按鈕）。
- ✅ 長輩導覽列 `elder_home_screen.dart`：圖示+大字標籤（首頁/聊天/我的），加 `onNavigateToChat` callback。
- ✅ 長輩首頁 `elder_home_tab.dart` 重做：問候 header→大日期卡→大按鈕(打電話給家人/和小雲聊天)→單一大頭條新聞卡(大圖+大標+全寬「唸給我聽」+看更多)。移除輪播控制與自動跳頁，新聞抓取/TTS 保留。清掉約 1100 行死碼（1690→564 行），0 error。

**待續**：
- 🔲 長輩端其餘畫面（個人頁/朋友/ZenPond 聊天）套 ElderScale。
- 🔲 家屬端整體套統一設計語言。
- 🔲 實機截圖驗證新首頁。

---

## ✅ 進度更新（2026-07-14，分支 `newui`）

**四項需求決策已定案**：主色統一 **teal `0xFF59B294`**、建 design tokens + 全 App 套用、朋友列表放**長輩端撥號為主**、背景 GPS 邏輯不動（只移 UI）。

**已完成**：
1. ✅ 新建 `lib/theme/app_theme.dart`（`AppColors`/`AppSpacing`/`AppRadius`/`AppTextStyles` + `buildAppTheme()`），`main.dart` 已改用。
2. ✅ 移除養豬系統 UI：`elder_home_screen.dart` 拿掉 `DesktopPet`/`_petKey`/`checkExpeditionDiscovery`/import；`elder_profile_tab.dart` 移除 `_buildGameEntryCard()`。寵物/game 檔案保留為死碼（未 push，`game_service` 尚被 leaderboard/admin/test 引用，故不刪檔）。
3. ✅ 移除長輩端地圖 UI：`elder_profile_tab.dart` 刪 `_buildRealMap()` + 「今日步行軌跡」區塊 + 死掉的 `_TrackingStateChip`/`_routeAccentColor`/`_defaultCenter`；**保留** Geolocator/`_routePoints`/背景定位/`_movementState`。
4. ✅ 新建 `lib/screens/friends_screen.dart`（長輩端全畫面、撥號為主，沿用 `ApiService.getPairedFamily` + `ElderScreen` 通話入口）；`elder_home_tab.dart` 的「朋友」箭頭鈕改開此畫面（`_openFriendsScreen`），刪除原本的 bottom-sheet 死碼。
5. ✅ 家屬端主色統一：全專案 `0xFF2563EB`（35 處/10 檔）→ `0xFF59B294`。

`flutter analyze lib` = **0 errors**。

**未完成 / 待續**：
- 🔲 task2 深化：其餘硬編碼色（如家屬端次要藍 `0xFF3B82F6` 12 檔、各畫面 grey/bg 字面值）逐步改引用 tokens。目前只統一了主品牌色，尚未全面 token 化。
- 🔲 實機視覺驗證：需後端連線 + 已配對帳號才能進到長輩/家屬主畫面（splash 有 `DEV_BYPASS_*` dart-define 可回填登入，但仍需有效 userId + 後端）。

---

> 給下一個 session 的 Claude：使用者要求「只改 UI、不動功能程式碼」，且工作方式是 **先提改進建議、經使用者確認後再動手**。使用者正在設定終端「螢幕錄製」權限，之後會讓你用 `screencapture -x <path>` 抓螢幕再 Read 圖片來看畫面。
>
> 專案：`/Users/huangyukai/Desktop/115207/Uban/mobile_app`（Flutter），暫存區 = session scratchpad。

---

## 一、使用者的四項需求

1. **整體風格統一** — 全 App 視覺一致（配色 / 字體 / 間距 / 圓角）。
2. **移除養豬系統** — 就是「小豬桌寵 + 遠征捡寶」那整套寵物養成。
3. **移除地圖位置顯示的 UI，但功能保留在後台跑** — 家屬要能看獨居長輩的「移動軌跡 / 活動量」等數據。若背景 GPS 太耗電，改用手機本身收集的資料（步數 / 活動辨識）即可。
4. **朋友列表 → 新增一個新畫面**。

**硬性限制**：只改 UI，不要動到功能邏輯程式碼。

---

## 二、已探勘的現況（檔案定位，省去重新搜尋）

### 主題 / 設計系統
- **沒有集中的 design tokens 檔**。主題內嵌在 `lib/main.dart:1168` 的 `ThemeData`：
  - `seedColor = 0xFF59B294`（主色，藍綠 teal）
  - 字體 `GoogleFonts.notoSansTcTextTheme`
  - `useMaterial3: true`
- 各畫面**硬編碼顏色**很常見：`0xFFF1F5F9`（背景灰）、`0xFF59B294`（主色）、`0xFFFF7043`（橘，強調/警示）。

### 養豬系統（要移除）
- `lib/widgets/desktop_pet.dart` — 小豬桌寵本體，用 `assets/images/pig_2d_*.png`。
- 內嵌位置：`lib/screens/elder_home_screen.dart:288-295`（`DesktopPet`，僅首頁 tab 顯示）。
- 遠征玩法：`elder_home_screen.dart` 的 `checkExpeditionDiscovery()`（每 500 步撿寶）、`_petKey`、`_lastDiscoveredSteps`。
- 遊戲入口卡：`lib/screens/elder_tabs/elder_profile_tab.dart:990` `_buildGameEntryCard()`。
- 其他整套檔案：
  - `lib/screens/pet_profile_screen.dart`（33KB，寵物圖鑑/檔案）
  - `lib/screens/pet_room_view.dart`（19KB，寵物房間）
  - `lib/screens/pet_interaction_screen.dart`
  - `lib/controllers/pet_controller.dart`
  - `lib/models/pet_status.dart`
  - `lib/widgets/flying_food.dart`（餵食動畫）
- ⚠️ 注意：`ZenPond`（禪意池塘 `lib/screens/zen_pond/`）是**獨立的聊天/日記 tab**，不是養豬系統的一部分 —— **需向使用者確認是否保留**（我判斷保留）。

### 地圖 / GPS（UI 移除、後台保留）
- 全在長輩「個人頁」`lib/screens/elder_tabs/elder_profile_tab.dart`：
  - `_buildRealMap()`（約 line 665）：`FlutterMap`，高 380，`PolylineLayer`（軌跡）＋ `MarkerLayer`。→ **要移除的 UI**。
  - build 內「今日步行軌跡」區塊約 line 907-925。→ **要移除的 UI**。
  - `_buildDailyGoalRing()`（line 562，今日步數環）、步行距離 stat（line 631）→ 這是「活動量」呈現，**可能要保留**（步數不是地圖）。
  - **後台 GPS 邏輯（要保留、不能動）**：`Geolocator`、`_routePoints (List<LatLng>)`、`_buildLocationSettings()`（line 267，`allowBackgroundLocationUpdates: true`）、`Permission.activityRecognition`、上傳 route 的邏輯。
- 相關套件（`pubspec.yaml`）：`geolocator ^14.0.2`、`geocoding ^4.0.0`、`geolocator_android ^5.0.2`、`flutter_map ^8.2.2`。

### 聯絡人 / 朋友列表
- `lib/screens/contacts_screen.dart`（370 行）**已存在**：聯絡人列表 + 撥打電話（`Contact` class、`_showCallConfirmation()`）。
- 使用者要的是**新的「朋友列表」畫面** —— 與現有 contacts 的關係、放哪端、要做什麼，**需確認**（見下方待確認事項）。

### 導航結構
- **長輩端** `elder_home_screen.dart`：`IndexedStack` 三個 tab = `[ElderHomeTab, ZenPondScreen(聊天/池塘), ElderProfileTab]`，自訂浮動導覽列（home / chat / person 三顆圓鈕，主色 `0xFF59B294`）。
- **家屬端** `family_main_screen.dart`：**尚未確認結構**（上次被打斷）。家屬相關畫面在 `lib/screens/family/`（有 `ai_hub_screen`、`health_trends_screen`、`alert_center_screen`、`family_home_tab`、`family_data_tab` 等）。

---

## 三、下次開工「第一步」要補查的事（被打斷未完成）

用只讀 grep 確認（指令範例）：
```bash
cd /Users/huangyukai/Desktop/115207/Uban/mobile_app/lib
# 1. ZenPond 到底是什麼功能
grep -n "class \|標題\|title\|日記\|diary\|聊天\|chat" screens/zen_pond/zen_pond_screen.dart | head
# 2. ContactsScreen 在長輩端還是家屬端被 push
grep -rn --include="*.dart" "ContactsScreen" screens/
# 3. 家屬端目前有沒有地圖/軌跡 view（決定移除地圖後家屬在哪看數據）
grep -rln --include="*.dart" -e "FlutterMap" -e "移動軌跡" -e "步行軌跡" screens/family/
# 4. 家屬端導航結構
grep -n "Tab\|IndexedStack\|_pages\|class " screens/family_main_screen.dart | head -25
```

---

## 四、待使用者確認的關鍵決策（動手前用 AskUserQuestion 問）

1. **地圖移除後、家屬在哪看軌跡/活動量？** 若家屬端目前沒有對應 view，要不要新做一個「活動摘要卡 / 簡易軌跡」給家屬？
2. **背景資料來源**：保留背景 GPS（較耗電、軌跡精準），還是改用手機步數/活動辨識（省電、只有活動量沒有精準軌跡）？使用者傾向「太耗電就用手機資料」。
3. **朋友列表新畫面**：放長輩端還是家屬端？要做什麼（加好友 / 看在線狀態 / 聊天 / 撥號）？和現有 `contacts_screen.dart` 是取代還是並存？
4. **ZenPond（禪意池塘聊天）保留嗎？**（判斷：保留，因為它不是養豬系統。）
5. **風格統一範圍**：建立集中 design tokens（`lib/theme/app_theme.dart` 或 `lib/utils/app_colors.dart`）+ 全 App 套用（工程量大），還是 tokens + 只統一最常見畫面？

---

## 五、建議的實作計劃（確認後執行）

### A. 風格統一
- 新建 `lib/theme/app_theme.dart`：定義 `AppColors`（primary 0xFF59B294、bg 0xFFF1F5F9、accent 0xFFFF7043、text/grey 階層）、`AppSpacing`、`AppRadius`、`AppTextStyles`。
- 在 `main.dart` 用這些 tokens 建 `ThemeData`（含 elevatedButton / card / appBar theme）。
- 逐畫面把硬編碼色替換成 tokens（先做長輩三個 tab + 家屬主要畫面）。

### B. 移除養豬系統
- `elder_home_screen.dart`：拿掉 `DesktopPet`（288-295）、`_petKey`、`checkExpeditionDiscovery` 及相關 state。首頁 tab 少了小豬後檢查版面是否需補白。
- `elder_profile_tab.dart`：移除 `_buildGameEntryCard()` 及其呼叫。
- 移除/退役檔案（先確認無其他引用）：`pet_profile_screen.dart`、`pet_room_view.dart`、`pet_interaction_screen.dart`、`pet_controller.dart`、`models/pet_status.dart`、`widgets/desktop_pet.dart`、`widgets/flying_food.dart`。移除前 `grep` 交叉引用。
- `pubspec.yaml` 的 `assets/images/pig_*` 可留可清（先留，避免其他地方引用報錯）。

### C. 移除地圖 UI、保留後台
- `elder_profile_tab.dart`：只刪 build 中「今日步行軌跡」地圖區塊 + `_buildRealMap()`。
- **保留** 所有 `Geolocator` / `_routePoints` / `_buildLocationSettings` / 背景定位 / 上傳邏輯（純功能，不動）。
- 步數環 `_buildDailyGoalRing`、步行距離 → 視為「活動量」，保留（可重新排版）。
- 若決策 2 選「改用手機資料」→ 這屬於功能調整，需另外和使用者確認範圍（本計劃預設先只動 UI）。

### D. 朋友列表新畫面
- 依決策 3 新建 `lib/screens/friends_screen.dart`（或 elder/family 對應目錄），沿用統一後的 design tokens。
- 若與 contacts 並存，導覽列/入口要加相應按鈕。

---

## 六、工作原則提醒
- **先建議、後動手**（使用者明確要求）。
- **只改 UI，不動功能邏輯**（尤其：WebRTC signaling、GPS 背景記錄、API service 一律別碰）。
- Git commit 訊息要用**繁體中文**（見 `CLAUDE.md`）。此 repo 有 git，動手前先確認分支。
- 每完成功能要更新 `README.md` 與 `docs/`（見 `CLAUDE.md` 開發程序要求）。
