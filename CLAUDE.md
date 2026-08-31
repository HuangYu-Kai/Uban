# CLAUDE.md（`Uban/` — Flutter 前端）

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## 🚨 動手前必讀

> **在修改任何「視訊通話 / 來電通知 / 監控（CCTV）」相關的 Dart 程式碼之前，
> 必須先完整閱讀 [`CLAUDE_call-monitor.md`](CLAUDE_call-monitor.md)。**

該檔案是通話與監控子系統的**唯一權威參考**。本檔案不再記載通話／監控細節——
以前寫在這裡的 §2.2 Signaling/WebRTC 流程、§2.3 FCM→CallKit 喚醒鏈、§2.4 角色差異、
§5 修復記錄、§6 的護欄清單，**全部已遷移過去**（並已修正其中的路徑錯誤與自相矛盾條目）。

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

只改 UI 樣式（顏色、字體、間距）也**必須**先看 `CLAUDE_call-monitor-ui-map.md`（原
`CLAUDE_call-monitor.md` §5，2026-08-25 起獨立成檔）——那一份文件就是為了讓只動 UI 的人
不必讀完整條信令鏈也能安全改動而寫的。

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
pytest tests/test_call_signaling.py -q   # 通話迴歸套件，目前 17 passed（會隨測試增加而成長，以套件當下實際輸出為準）
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
| **按鈕在哪、按了跳去哪、可以安全改什麼** | `CLAUDE_call-monitor-ui-map.md`（原 §5，2026-08-25 起獨立成檔） |
| 監控機／CCTV／裝置角色指派 | §6 監控子系統 |
| **137 條護欄（絕對不可單點修改）** | §7 |
| 這段程式碼為什麼長這樣（37 輪修復年表；近期輪次在 §8，第一至三十五輪在 `CLAUDE_call-monitor-history.md`） | §8 |
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

### 2.7 家庭親友圈社群時光牆 (Community Wall)

長輩與家屬雙向生活動態與照片分享系統：
- **封閉式隱私**：僅配對家庭成員與親屬可見，後端依 `family_elder_relationship` 自動解析親屬圈。
- **後端端點** (`routers/community.py`)：`GET /api/community/posts`、`POST /api/community/posts`、`POST /api/community/posts/{id}/like`、`POST /api/community/posts/{id}/comments`、`POST /api/community/upload`。
- **資料表** (`database.py`)：`community_posts`、`community_comments`、`community_post_likes`。
- **前端入口**：
  - 長輩端：底部導覽列第 3 頁 `[ 👥 社群 ]`（`ElderCommunityScreen`，大字體 24pt + 一鍵快捷發文 + 拍照上傳 + 大按鈕關心 ❤️）。
  - 家屬端：`FamilyInteractionTab` 綠色旗艦卡片 `[ 家庭生活時光牆 ]`。
- **離線韌性**：`CommunityService` 優先遠端 API，離線退守 `SharedPreferences` 本機快取。
- 詳細技術規格見 [`docs/technical/COMMUNITY_ARCHITECTURE.md`](docs/technical/COMMUNITY_ARCHITECTURE.md)。

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
   **子代理中斷時的處置（不得跳過）**：子代理因 session limit（額度或上下文用盡）而失敗時，**不可改由 Opus 自行動手把剩下的工作做完**。正確做法是——① 檢查該子代理已經完成到哪一步、產出了哪些檔案；② 把這份進度連同「還剩什麼」寫進新的任務描述；③ 用這份描述重新派發 Sonnet 子代理接續。若仍不足，就縮小每個子代理的工作量（切更小的塊、拆更多批）再派，而不是自己接手。
   **唯一例外**：子代理持續 idle-running（反覆空轉、不寫檔、不回報，重派後仍無進展）時，才可由 Opus 直接執行，並須在報告中說明為何走了例外路徑。
9. **每次更動完成後必須清除不必要的空白檔案** — 收尾前掃一次工作目錄，刪除本次作業產生的零位元組檔、只剩空白字元的殘留檔、以及空的暫存目錄（例如中途建立後未使用的 stub、被清空但忘了刪的檔案）。**不要刪除**專案本來就需要的空檔案（如 `__init__.py`、`.gitkeep`、`py.typed`、空的 `__init__.dart`）。判斷準則：該檔是否被任何程式碼、設定或建置流程引用；有引用就留下。
10. **修改連接／跳轉等邏輯時，必須同步更新雙端 graphify 檔案** — 只要動到 Socket 事件、REST 端點、FCM 欄位、畫面跳轉路由、模組間呼叫關係等「連接與跳轉」語意，除了照常回寫 `.md` 文件外，**還要同步更新 `Uban/graphify-out/` 與 `uban-api/graphify-out/`**（兩端內容相同）。做法：於專案根目錄執行 `/graphify . --update`（增量重建，只重掃變更檔），再把 `graphify-out/` 複製到上述兩處覆蓋。純樣式改動（顏色、字體、間距、文案）不觸發本條。
11. **除非專案結構有重大變更，否則對 graphify 一律採最小變動** — 「重大變更」指新增／刪除模組、大規模搬移目錄；未達此門檻時，一律用 `/graphify . --update` 增量重建（只重掃變更檔），不要做整包重建，不要為了「順手」重跑分群、重編社群標籤或重新產生 HTML，也不要動 `graphify-out/` 底下與本次變更無關的產物。本條**不豁免**第 10 條的同步義務——第 10 條規定「連接／跳轉邏輯變更時必須同步更新雙端 graphify-out」，本條只約束**怎麼做**（增量、最小差異），兩條並不矛盾。使用者可隨時要求**暫停** graphify 更新；暫停期間本條與第 10 條皆暫時不適用，但完成回報時必須明講「本輪未同步 graphify」。
12. **每輪年表寫進 `CLAUDE_call-monitor.md` §8 之後，必須立刻把主檔容納不下的輪次搬到 `CLAUDE_call-monitor-history.md`；留下哪些的唯一判準是「下一個接手的 agent 看得懂自己要做什麼」，不再計算留幾輪** — 原因：主檔一旦超過 **256 KB**，子代理就無法一次讀完，而「動手前必須完整讀過本文件」是通話／監控子系統第一鐵律；文件過大會讓這條鐵律在技術上**無法遵守**。256 KB 是工具的硬上限、不是慣例，所以「§8 該留什麼」改由**接手者的需求**決定：留下**仍然開著的問題**、**上一輪剛動過因而可能回歸的區域**、以及**「為什麼長成這樣」還會左右下一次決策的根因**；已結案且不再影響現行程式碼的輪次，即使很新也可以搬走。搬移方式：**逐字搬移，不得改寫或摘要**；以**標題全文**為錨點，不要依賴行號（多代理併發編輯時行號會漂移）；搬完後 `Uban/` 與 `uban-api/` 兩份主檔鏡像、兩份歷史檔鏡像都必須各自維持 **byte-identical**。搬移一律**由最舊的一端往新的搬**，讓 §8 保持連續區間，主檔內**兩處**「搬移門檻提示」（§7 護欄標題下方、§8 開頭指標區塊）才能維持單一門檻數字的寫法；若某個較舊的輪次因接手者仍然需要而必須留下、導致保留範圍不連續，就把那兩處改成明列實際保留的輪次。**除了主檔這兩處，`CLAUDE_call-monitor-history.md` 表頭的「收錄範圍」與「早期修復年表（第一輪 – 第 N 輪）」標題也必須同步更新**——歷史檔曾因為漏改而宣稱「第二十八輪以後仍在主檔 §8」，把查第 28–33 輪的人指到錯誤的檔案。另外，**三份 `CLAUDE.md`（根／`Uban/`／`uban-api/`）裡的「N 條護欄」總數與「已累積 N 輪」也要同步**——護欄數曾從第三十一輪一路停在 118 沒人改，直到第三十七輪才發現主檔早已是 137。以上這些是全檔**唯一**需要跟著調整的地方；主檔 §8 開頭「🗂️ 較舊的輪次已遷出」那句**刻意不寫數字**，不要再幫它補上範圍。**不要**為此逐一修改內文中上百處的「第 N 輪」引用。⚠️ 真正逼近讀取上限的是 §8 以外的內容（資料契約、護欄、除錯手冊，且隨護欄持續累積）——本條只讓 §8 不再膨脹；若主檔日後仍逼近上限，下一刀要切的是 **§7**（§5 已於 2026-08-25 獨立成
`CLAUDE_call-monitor-ui-map.md`，不再算在主檔內），不是修復年表。
13. **「強制開啟」只准長輩端使用，家屬端一律禁止** — 在使用者沒有主動操作的情況下把 App 拉到前景或蓋過鎖定畫面（`bringToFront`、`AndroidIntent` 冷啟動、強制把系統音量轉滿），只有長輩端可以保留；家屬端一律不行。理由：長輩身處困境時必須能被聯繫到，不能只靠一般提示音等當事人自行反應；家屬手機若被無故拉到前景或音量被強制轉滿，對懂資訊科技的使用者而言，跟流氓軟體／惡意軟體的行為難以區分。落地：`lib/main.dart` 全檔僅存一處 `AndroidIntent` 啟動，限定在 `role == 'elder' && type == 'emergency-call'` 分支內；`lib/services/signaling.dart:612` 的 `bringToFront` 與強制音量共用同一個 `final bool isElderDevice = _role == 'elder';` 守門——用連線當下的 `_role`，不用 SharedPreferences 的 `user_role`/`saved_role`（那對鍵有第十六輪記載的漂移史，見 `CLAUDE_call-monitor.md`）。**例外**：來電響鈴畫面（CallKit、`fullScreenIntent: true` 的來電通知）雙端皆可保留——使用者必須主動接聽才會進入通話，屬於標準來電 UX，不算未經同意的強制開啟。**不算強制開啟**：`showOverLockScreen`／`setShowWhenLocked` 只是讓使用者自己已經打開的畫面在鎖定畫面上可見，沒有啟動 App，雙端皆可用。家屬端的緊急事件（例如跌倒警報，見 `lib/services/cctv_alert_notification.dart:222`）一律走高優先級通知：鬧鐘音量、繞過勿擾、鎖屏可見（`visibility: NotificationVisibility.public`）皆可保留，但不得 `fullScreenIntent: true`、不得 `AndroidIntent` 啟動、不得無角色判斷地 `bringToFront`，也不得強制改變裝置音量。新增任何會在 App 被殺死／背景時喚起畫面的路徑前，必須確認它有角色守門，且守門要 **fail-closed**（判斷不出角色就不要喚起）。

### 3.2 通話與監控

**完整規則見 [`CLAUDE_call-monitor.md`](CLAUDE_call-monitor.md) §7（137 條護欄）。**
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

通話與監控子系統的完整修復年表（2026-06-05 起，已累積 37 輪）已逐條核對，內容全數存在於
[`CLAUDE_call-monitor.md`](CLAUDE_call-monitor.md) §8（近期輪次）與
[`CLAUDE_call-monitor-history.md`](CLAUDE_call-monitor-history.md)（第一至三十五輪，含本節原本
記載的全部早期輪次），故不再於本檔重複列出。部分項目在遷移後已修正過期或錯誤的敘述（例如不
存在的 `MonitorViewScreen`、已作廢的有效期數字），一律以上述兩份文件的現行版本為準。

---

## 6. 🚫 絕對不可改動區塊（給後續 AI）

> 全部 27 條護欄（原編號 1–27）已逐條核對，確認等價內容已存在於
> [`CLAUDE_call-monitor.md`](CLAUDE_call-monitor.md) §7（G1–G100，合併後的唯一權威清單，含
> §7.1 前端／§7.2 後端／§7.3 已知文件錯誤／§7.4 刻意保留的安全缺口），故不再於本檔重複列出。
> 部分條目的數值已於後續輪次更新（例如來電有效期 120s → 60s），一律以 §7 現行版本為準。
>
> 原第 27 條（全域音訊焦點共存）2026-08-18 拆檔稽核時發現權威文件從未收錄，已補列為
> **G100**（§7.1 前端護欄）；本檔至此已無任何未搬移的例外。

