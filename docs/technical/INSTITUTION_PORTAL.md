# 機構管理端網頁 (Institution Admin Portal) 技術設計與實作紀錄

* 建立日期：2026-08-03
* 最近更新：2026-08-03
* 適用版本：v1.2.0
* 負責組件：後端 (uban-api) + 機構管理端網頁 (React SPA, `uban-api/uban-admin`)
* 文件狀態：**已實作並通過本機端到端驗證（2026-08-03）；尚未部署至正式環境**

> Uban 原本只有長輩端與家屬端兩個 Flutter App。本模組新增「賣給日照中心／
> 照護機構」的對外管理網頁：機構人員在桌機上檢視旗下所有長輩的圖表化數據，
> 並管理護工的排班、打卡、工時、換班與派工任務。

---

## ❶ 名詞定義 (Glossary)

| 名詞 | 意義 |
|------|------|
| 機構 (institution) | 購買 Uban 的日照中心／照護機構，是所有查詢的租戶邊界 |
| 機構員工 (care_staff) | 機構內的帳號，分 `admin`（管理員）／`supervisor`（督導）／`caregiver`（照服員） |
| 收案 (institution_elder) | 某位長輩由某機構照顧的關係；`discharged_at` 非 NULL 代表已結案 |
| 主責指派 (staff_elder_assignment) | 護工 ↔ 長輩的負責關係，一位長輩只有一位 `is_primary` |
| 班次 (care_shift) | 某員工在某日某班別的排班，含打卡上下班 |
| 派工任務 (care_task) | 針對某長輩的照護待辦，可指派給護工，`staff_id` 為 NULL 代表待派工 |
| 風險分級 (risk_level) | 後端依互動／未接來電／警報即時算出的 high／medium／low |

---

## ❷ 功能背景與設計初衷 (Objectives & Background)

### 為了解決什麼痛點

1. **既有兩端都是「單一長輩」視角**。家屬端一次只看一位長輩，機構要同時盯 20＋
   位獨居長輩，需要「整院視角 + 風險排序」，否則異常會被淹沒。
2. **既有的趨勢圖全是假資料**。`health_trends_screen.dart`、
   `emotion_timeline_screen.dart`、`alert_center_screen.dart` 都是
   `_generateMockData()`，後端從來沒有對應的聚合端點。本模組是系統第一次
   把 `activity_log` / `call_record` / `emergency_alerts` 真的聚合成圖表。
3. **護工排班完全沒有系統**。20 張既有資料表裡沒有任何機構／人員／班表概念。
4. **警報沒有整院清單**。`routers/alert.py` 只支援 `GET /api/alerts/{elder_id}`，
   機構人員無法一眼看到「現在全院有幾件待處理」。

### 為什麼機構員工要獨立一套帳號與 JWT

家屬帳號在 `user_account_data`，機構員工在 `care_staff`，**刻意不共用**。
若共用，任何家屬拿到的 token 都能打 `/api/institution/*`。
現在機構 token 的 payload 帶 `typ: "staff"`，`get_current_staff()` 一律驗這個
欄位，家屬 token 因為沒有它而必定 401（見 ❼）。

---

## ❸ 系統架構與資料流向 (System Architecture & Data Flow)

```
┌──────────────────────────┐
│  機構管理端 (React SPA)   │   桌機瀏覽器
│  uban-api/uban-admin     │
└───────────┬──────────────┘
            │ HTTPS，同源 /api（正式）
            │ Bearer <staff JWT，typ="staff">
            ▼
┌──────────────────────────────────────────────┐
│  FastAPI (uban-api) :8000                    │
│   routers/institution.py      認證＋唯讀統計  │
│   routers/institution_ops.py  排班／派工寫入  │
│   routers/institution_common.py 越權守衛      │
│   auth_staff.py               staff JWT       │
└───────────┬──────────────────────────────────┘
            │ db_cursor() + %s（禁 ORM）
            ▼
┌──────────────────────────────────────────────┐
│  MySQL 9.6 `uban`                            │
│   新增 8 張表（見 ❹）                          │
│   聚合既有 activity_log / call_record /        │
│         emergency_alerts / subscription_status│
└──────────────────────────────────────────────┘
```

正式環境前端由 FastAPI 以 `StaticFiles` 掛在 `/admin`，與 API 同源，
沿用 Tailscale Funnel 既有的 HTTPS，不需要額外主機或 CORS 設定。

### 兩個必須繞過的資料模型坑

這兩點決定了幾乎所有查詢的寫法：

1. **`activity_log` 沒有 `elder_id`，只有 `user_id`。**
   任何跨長輩統計都得先 `JOIN elder_profile` 把 `elder_id → user_id` 轉出來
   （`institution_common.elder_user_id_map()`）。

2. **`call_record.caller_id` / `callee_id` 是 `VARCHAR(20)` 存 user_id 字串，
   且實際資料裡可能是空字串。** 比對前一律轉字串。
   另外 `start_time` 在正式 DB 是 `NOT NULL`（與
   `DATABASE_SCHEMA_CRITICAL.md` 記載的「ringing 時為 NULL」不符，以實際結構為準），
   所以「通話時長」只在 `status='ended'` 時才有意義。

### 為什麼步數要另開一張表

`elder_profile.step_total` 是「本輪累計」計數器，會被
`routers/game.py::do_distribute_appearances()` 歸零，因此系統原本**完全沒有**
逐日步數歷史，畫不出趨勢。新增 `elder_daily_step`，由 `game.py` 的三個計步端點
共用的 `_record_daily_steps()` 以 `INSERT … ON DUPLICATE KEY UPDATE` 累加。

其餘趨勢（對話、通話、警報、任務、工時）**一律即時聚合**（`GROUP BY DATE(...)`），
不建 rollup 表 —— 資料量小、永遠正確、沒有排程相依、不會有「昨天的數字沒跑到」。

---

## ❹ 代碼修改與路徑定義 (Implementation & File References)

### 資料庫（8 張新表）

`uban-api/scripts/migrations/001_institution.sql`
（`main.py::run_sql_migrations()` 開機時冪等執行；SQLite 備援模式自動跳過）

| 表 | 用途 | 關鍵約束 |
|----|------|----------|
| `institution` | 機構 | — |
| `care_staff` | 員工 | `UNIQUE(staff_email)`；FK→institution CASCADE |
| `institution_elder` | 收案 | `UNIQUE(institution_id, elder_id)` |
| `staff_elder_assignment` | 主責指派 | `UNIQUE(staff_id, elder_id)` |
| `care_shift` | 班表 | `UNIQUE(staff_id, shift_date, shift_type)` ← 撞班保護 |
| `shift_swap_request` | 換班申請 | FK→care_shift CASCADE |
| `care_task` | 派工任務 | `staff_id` 可為 NULL（待派工）；`source`/`source_ref_id` 可溯源自警報 |
| `elder_daily_step` | 逐日步數 | `UNIQUE(elder_id, metric_date)` |

全部 InnoDB / utf8mb4_0900_ai_ci，`elder_id` 一律 `VARCHAR(4)` 以對齊
`elder_profile.elder_id`（型別或定序不一致外鍵會建不起來）。

### 後端

| 檔案 | 內容 |
|------|------|
| `uban-api/auth_staff.py` | `create_staff_token` / `get_current_staff`（驗 `typ=="staff"`）/ `require_staff_role`（等級比較，admin 自動涵蓋 supervisor）/ 與 `routers/auth.py` 同格式的 passlib scrypt 雜湊 |
| `uban-api/routers/institution.py` | 登入、`/auth/me`、`/overview`、`/trends`、`/elders`、`/elders/{id}`(+`/metrics`,`/timeline`)、`/alerts`、`/alerts/{id}/acknowledge` |
| `uban-api/routers/institution_ops.py` | `/staff`(CRUD+`/workload`)、`/assignments`、`/shifts`(CRUD+`/check-in`,`/check-out`,`/coverage`)、`/swaps`、`/tasks` |
| `uban-api/routers/institution_common.py` | `assert_elder_in_institution` / `assert_staff_in_institution` / `assert_shift_in_institution`、`elder_user_id_map`、`densify`（補齊沒有資料的日期）、`clamp_days` |
| `uban-api/main.py` | 註冊兩個 router、`run_sql_migrations()`、`/admin` 的 `SPAStaticFiles`（history fallback） |
| `uban-api/routers/game.py` | 新增 `_record_daily_steps()`，接上 `update_steps` / `elder/update_steps` / `save_steps` 三個既有端點（純新增，不改原行為） |
| `uban-api/scripts/seed_demo_institution.py` | 示範資料產生器，冪等 + `--purge` |

### 前端（`uban-api/uban-admin`）

React 19 + Vite + TypeScript + React Router + TanStack Query + Recharts。
放在 `uban-api` repo 內，因為部署只會拉這個 repo。

| 路由 | 內容 |
|------|------|
| `/login` | 機構員工登入 |
| `/` | 總覽：hero（待處理警報）＋ KPI ＋ 互動／通話／任務完成率／警報四張趨勢圖 ＋ 今日班別人力 ＋ 待處理警報清單 |
| `/elders` | 長輩總表，風險排序、篩選、每列 14 日 sparkline |
| `/elders/:elderId` | 個案：步數折線、互動組成堆疊、通話堆疊、事件時間軸 |
| `/alerts` | 整院警報中心，可確認並自動開追蹤任務 |
| `/tasks` | 派工看板（依狀態分欄）＋ 各護工負載 ＋ 明細表 |
| `/schedule` | 覆蓋缺口熱力圖 ＋ 週班表（可直接排班／刪除）＋ 換班審核 ＋ 打卡 |
| `/staff` `/staff/:staffId` | 護工工時／負載橫條圖、名冊、個人月工時與班表 |

---

## ❺ 核心數學公式與演算法 (Core Models)

### 風險分級（`institution.py::_risk_level`）

規則刻意簡單且可解釋 —— 機構人員要能一眼說出「他為什麼是紅的」，
不是給一個黑箱分數：

```
active_alerts > 0                              → high
days_since_interaction >= 5                    → high
missed_calls_7d >= 3  或  interactions_7d == 0 → medium
days_since_interaction >= 2                    → medium
其餘                                            → low
```

排序鍵為 `(risk_rank, -days_since_interaction)`，同級別下最久沒互動的排前面。

### 人力覆蓋缺口（`institution_ops.py::shift_coverage`）

```
effective = max(0, scheduled - absent)
gap       = max(0, required_per_shift - effective)
```

`required_per_shift` 由前端傳入（1–3 人，後端 clamp 到 0–20），預設 2。

### 工時

```
worked_minutes = Σ TIMESTAMPDIFF(MINUTE, check_in_at, check_out_at)
                 （僅計 check_in_at 與 check_out_at 皆非 NULL 的班次）
```

**刻意不計「已排定但還沒上的班」**，否則「本月工時」會虛胖。

### 完成率／出勤率

```
task_completion_rate = done / total     （total = 0 時回 null，不是 0）
attendance_rate      = (checked_in + completed) / total_shifts
```

回 `null` 而非 `0` 是為了讓折線圖在「當天沒有任務」時斷開，而不是掉到底部
假裝完成率 0%。

---

## ❻ UI/UX 視覺美學與無障礙規範 (Aesthetics & Accessibility)

色票取自 dataviz 規範的 reference palette，並用其 `validate_palette.js`
對本專案實際使用的類別色槽在亮暗兩種底色下各驗過一次：

| 模式 | 色槽 | 結果 |
|------|------|------|
| 亮 | `#2a78d6, #eb6834, #1baf7a` | all-pairs 全通過（aqua 對亮底 2.74:1 < 3:1 → 套用 relief rule） |
| 暗 | `#3987e5, #d95926, #199e70` | all-pairs 全通過 |

落實到實作的規則：

- **文字永遠用 ink token，不穿系列色**；識別靠文字旁邊的色塊
- **格線／座標軸是 1px 實線、單階離底色**，不用虛線
- **每張圖都有「數據」表格檢視**（亮色 aqua 的 relief 手段，也讓人能抄數字）
- **≥2 系列一定有圖例**；單一系列不放圖例框（標題已經說明畫的是什麼）
- **堆疊段與相鄰長條之間用 2px 表面色間隙分隔**，不畫外框
- **狀態徽章一律「色點 + 文字」**，永不只靠顏色（狀態色在亮底有兩個低於 3:1）
- **一個檢視只有一個 hero 數字**（總覽是「待處理緊急警報」——真正要人動作的數字）
- **篩選器一列放在所有圖表之上**，不做每張圖各自的篩選器
- **重新抓資料時維持前一次畫面並降透明度**（`.refetching`），不閃 skeleton
- 深色模式是**為深底重新取階**，不是自動反轉；支援「系統／亮／暗」三段切換

---

## ❼ 安全性防護與越權防制 (Safety & Tenancy)

| 防線 | 實作 |
|------|------|
| 家屬 token 不可越權 | `auth_staff._decode_staff_token()` 驗 `payload["typ"] == "staff"`，非 staff token 一律 401 |
| 跨機構隔離 | **所有端點以 token 內的 `institution_id` 過濾，不接受呼叫端傳入** |
| 查別家資料 | 回 **404 而非 403** —— 403 等於確認「這個 ID 存在」，可用來列舉別家機構的長輩 |
| 角色權限 | `require_staff_role()` 用等級比較（caregiver 1 < supervisor 2 < admin 3） |
| 自我提權 | 只有 admin 能建立／指派 admin 角色；只有 admin 能啟用停用帳號 |
| 停用自己 | 明確擋掉（否則機構可能鎖死沒有管理員） |
| 撞班 | `UNIQUE(staff_id, shift_date, shift_type)` + 建立／換班核准前先查一次回友善 409 |
| 刪除已打卡班次 | 降級為「取消」而非真刪 —— 那是出勤紀錄 |
| 帳號列舉 | 登入時「帳號不存在」與「密碼錯誤」回同一個訊息 |
| 查詢爆量 | `days` clamp 到 7–180；班表區間上限 92 天；清單 limit 上限 |
| 密碼 | passlib scrypt/bcrypt，與 `routers/auth.py` 同格式 |

### 一個刻意的取捨

`emergency_alerts.acknowledged_by` 的外鍵指向 `user_account_data`，而機構員工在
`care_staff` —— 兩者是不同身分域，硬塞 `staff_id` 會違反外鍵。
因此機構端確認警報時**只更新狀態與時間**，「誰處理的」記在自動建立的
`care_task`（`source='alert'`, `source_ref_id=alert_id`, `staff_id=確認者`）上。

---

## ❽ 測試與驗證計畫與結果 (Test Plan & Results)

### 自動化測試

`uban-api/tests/test_institution.py` —— **22 passed**（2026-08-03，對線上 MySQL）

```bash
cd uban-api
DB_HOST=100.73.39.14 DB_USER=root DB_PASSWORD=115207 DB_NAME=uban \
  python -m pytest tests/test_institution.py -q
```

涵蓋：家屬 JWT／無 token／亂碼 token 一律 401、跨機構讀長輩／員工／排班／
建任務全部 404、照服員不可建員工／建班／審換班、督導不可建 admin／不可停用員工、
admin 不可停用自己、班次生命週期（建立→409→未上班先下班 400→打卡→冪等→
下班→刪除降級為取消）、換班審核流程、`/overview` KPI 與直接 SQL 一致、
`/trends` 回連續日期且 `days` 被 clamp、任務 `status` 與 `completed_at` 一致性。

> 測試資料用保留命名空間（`elder_id` `T00`/`T01`、email `@uban.qa`），teardown
> 精準刪除。**不可改用 `@uban.test`** —— `.test` 是 RFC 2606 保留 TLD，
> `EmailStr` 會擋掉導致登入 422；也不可用 `@uban.demo`，那是種子腳本的
> 命名空間，它的 `--purge` 會把測試帳號一起刪掉。
>
> 本檔自備輕量 `client` fixture（只掛兩個 institution router），因此
> `tests/conftest.py` 的 `from main import app` 已改為在 fixture 內延遲 import。
> 既有測試行為不變（`test_ai_fallback.py` 本來就自己 import main）。

### 手動端到端驗證（2026-08-03）

以 `scripts/seed_demo_institution.py` 灌入示範資料後，於 Chrome 逐頁確認：

| 項目 | 結果 |
|------|------|
| 登入 → 總覽 | ✅ KPI：長輩 20／今日活躍 19／警報 4／任務 19-39／出勤 5-6／PRO 8 |
| 四張趨勢圖 | ✅ 30 日連續、無缺日；任務完成率在無任務日正確斷開 |
| `/elders` 風險排序 | ✅ 4 位高風險排最前，且未互動天數／未接／警報三個佐證欄位一致 |
| `/elders/D000` | ✅ 步數、互動組成、通話、時間軸（含 activity/call/alert/task 四種）皆有資料 |
| `/schedule` | ✅ 週末缺口在熱力圖顯示 `0/2 缺 2`；排班、刪除、打卡、換班核准皆生效 |
| `/tasks` | ✅ 看板五欄；標記完成後重整仍為完成 |
| `/alerts` | ✅ 確認警報後從 active 消失並自動建立追蹤任務 |
| 亮／暗主題 | ✅ 兩種模式皆已檢視，無對比或溢出問題 |
| 1280 / 1600 寬 | ✅ 表格與圖表皆不橫向溢出 |
| `/admin` SPA fallback | ✅ `/admin`、`/admin/elders`、`/admin/elders/D000` 皆回 index.html；資產 content-type 正確 |

### 部署風險評估（實際讀過 `deploy.yml` 後）

`deploy.yml` 的順序是：

```
set -e
podman build -t uban-api .      # ← 第 77 行
podman image prune -f
podman rm -f uban-api || true   # ← 第 83 行
podman run -d --name uban-api …
```

因為 `set -e`，**若 `podman build` 失敗，腳本會在第 77 行就中止**，
根本走不到第 83 行的 `podman rm`。也就是說：

> **node build stage 失敗 → GitHub Actions 顯示紅字，但舊容器繼續跑，API 不會斷。**

失效模式是「部署沒生效」，不是「服務掛掉」。這比新增 build stage 之前的
直覺風險小很多。

### webbuild stage 的乾跑驗證（2026-08-03）

沒有本機 podman，改為在乾淨目錄逐步重現 Dockerfile 的三個步驟：

| 步驟 | 結果 |
|------|------|
| `npm ci`（只給 package.json + package-lock.json） | ✅ 通過（**修過 lockfile 後**，見下） |
| 複製原始碼（比照 `COPY uban-admin/ ./`，排除 node_modules/dist） | ✅ |
| `npm run build` | ✅ 產出 dist/（index.html + assets） |
| 產物檢查 | ✅ bundle 內 `VITE_API_BASE` 被編譯成 `` `/api` ``（同源），**0 個** Tailscale 開發網址殘留 |

**過程中修掉一個會讓每次部署都失敗的真問題**：原本的 `package-lock.json` 有一筆
`node_modules/rolldown/node_modules/@rolldown/binding-android-arm64` **缺少 `version` 欄位**
（npm 11 + rolldown 產生的畸形 lockfile），`npm ci` 會直接死在
`npm error Invalid Version:`。刪掉重新 `npm install` 產生的 lockfile 已無此問題，
並實測 `npm ci` 可從 lockfile 單獨還原。

> ⚠️ 之後若升級 vite / rolldown 並重產 lockfile，**請務必再跑一次乾淨的 `npm ci`**
> 確認沒有再出現缺 `version` 的條目 —— 這個錯誤在本機 `npm install` 完全看不出來，
> 只有 `npm ci`（也就是 Docker build）會爆。

**基底映像選 `node:22-alpine` 的理由**：vite 8 / rolldown 的 `engines` 是
`^20.19.0 || >=22.12.0`，而 `node:20` 是浮動 tag，萬一解析到 20.19 之前的版本就會
建置失敗；22 LTS 不會踩到這個邊界。alpine 是 musl，已確認 lockfile 內含
`@rolldown/binding-linux-x64-musl`，原生 binding 沒問題。

### 仍未驗證

- **仍未實際在 Fedora 主機 `podman build` 過**。乾跑已涵蓋 `npm ci` / `npm run build`
  這兩個最可能出事的步驟，剩下的未知只有「主機能不能拉 `docker.io/node:22-alpine`」
  與「build 期間能不能連 npm registry」—— 這台主機每次 build 本來就會拉
  pytorch 映像並跑 `pip install`，所以這兩件事風險很低。
- 種子腳本尚未在「真正的備份 DB」上驗過 `--purge`（已在線上 DB 驗過一次
  完整 purge→re-seed 循環，真實資料筆數未變）。

---

## ❾ 已知限制與後續工作

1. **多機構尚無「機構自助註冊」**。目前建立機構與第一位管理員得手動下 SQL
   或跑種子腳本。
2. **`/staff` 只有讀與改，沒有前端的新增表單**。後端 `POST /staff` 已完成
   並有權限測試，前端尚未做建立 UI。
3. **家屬端三張假資料圖表仍未接**。`health_trends_screen.dart`、
   `emotion_timeline_screen.dart`、`alert_center_screen.dart` 依然是
   `_generateMockData()`。本模組做出來的聚合端點可以回頭餵給它們，但不在本次範圍。
4. **`emergency_alerts` 真實資料為 0 筆**。警報圖表在沒有示範資料的正式環境會是空的，
   要等 YOLO（`yolo_detector_service.py`）實際跑起來才有資料。
5. **前端 bundle 721 kB（gzip 209 kB）未做 code splitting**。桌機內網使用可接受，
   之後可按路由切。
6. **護工端沒有行動介面**。照服員的打卡與任務更新目前得用桌機網頁；
   權限已經開好（照服員可打自己的卡、更新自己的任務），缺的是手機版 UI。
