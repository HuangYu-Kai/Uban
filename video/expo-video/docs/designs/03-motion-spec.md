# 03　Motion 版製作規格（video-shotcraft 自主自由創作）

> 2026-11-16 起草。上游決定見 `02-motion-style-pivot.md` 第 10 節。
> 依 shotcraft `references/pipeline.md` 階段 0–3 的產出寫成：產品簡報、tokens、功能→鏡頭對照、分鏡。

## 1. 產品簡報與約束

| 項目 | 內容 |
|---|---|
| 產品 | Uban：AI 跨世代照護系統。長輩端（用說的就能用、AI 助理小嘎）＋家屬端（遠端關心）＋後端 |
| 用途 | 專題展播放的 20 分鐘介紹片；觀眾是評審老師、來賓、長輩與家屬 |
| 長度 | **整 20 分鐘（1200 秒）**，不含 60 秒原片 |
| 規格 | 1920×1080、**60 fps**、H.264；卡片參數一律以 30 fps 格數撰寫（`src/remotion30.tsx` 換算） |
| 素材 | App 真實截圖（模擬器長輩帳號 user_id=2；家屬端另截）；App 圖示；2D 小豬圖；不出現組員真名、新聞人物照、網址、IP |
| 旁白 | 未定（`00` 的 D1）。本規格先以畫面字卡＋字幕條撐住，每段都要有字（shotcraft C1） |
| 配樂 | 原創電子節拍，自己作曲渲染。**112.5 BPM → 一拍 = 16 格（30 fps）**，一小節 64 格；鏡頭邊界用 `beatF(n)` |
| 字級下限 | 要讀的字 ≥ 56 px（建議 60）；次要 ≥ 32 px；其他當裝飾並調淡（shotcraft Q11） |

## 2. 視覺 tokens（從 App 長出來，shotcraft 理念 2）

| token | 值 | 來源 |
|---|---|---|
| `bg` | `#F4F1EA` 暖白瓷 | App cream `#FFF6E9` 降飽和，作為舞台 |
| `bgMint` | `#E9F4EF` | App mint |
| `brand` | `#59B294`／`brandDeep` `#2F7D66`／`brandSoft` `#BFE3D3` | App 主綠 |
| `ember` | `#F2994A`／`emberSoft` `#FFD8A8` | App 暖橘（第二強調） |
| `alert` | `#E5484D` | **只在第 7 章** |
| `ink` | `#1E2A2A`／`inkSoft` `#5B6B68` | 文字 |
| 漸層 blob | mint＋brandSoft＋emberSoft 三色柔焦 | 取代參考片的粉紫橘 |
| 字 | 標題 jf open 粉圓（Huninn）；內文 Noto Sans TC；數字與英文 DM Sans | 沿用 |
| 圓角 | 卡片 24、手機 56、膠囊 999 | App |
| 陰影 | `softShadow`（Polish.tsx），淺色舞台用 | shotcraft |

舞台用 shotcraft `Look.tsx` 的亮場（porcelain／sand）骨架，改成上面的色值。

## 3. 動態 tokens

品牌落在「平靜關懷」與「親和友好」之間（能量中低、調性溫和偏活潑）：

| 項目 | 值 |
|---|---|
| 主時長 | 約 30 格（1 秒） |
| 入場緩動 | `bezier(0.25,0.46,0.45,0.94)`；有落地意象的動作用回彈（y1 > 1） |
| 過衝 | ≤ 1.04 |
| 擠壓伸展 | ≤ 0.06 |
| 停留 | 關鍵資訊落定 ≥ 30 格；品牌字 ≥ 30 格；批次動作收尾靜止 15 格 |
| 整畫面衝擊 | 全片 ≤ 3 次：第 0 章品牌落定、第 7 章跌倒、第 13 章全員合照 |
| 手持晃動 | 全片不用 |

三個詞描述成片動效：**溫和、清楚、有節拍**。

## 4. 20 分鐘時間分配

| 章 | 主題 | 秒 | 起點 |
|---|---|---|---|
| 0 | 開場：小嘎光點 → Uban 字標 | 45 | 0:00 |
| 1 | 長輩的一天與家人的擔心 | 90 | 0:45 |
| 2 | Uban 系統全景 | 60 | 2:15 |
| 3 | 小嘎：會聽、會記得、會求救 | 90 | 3:15 |
| 4 | 長輩端五個分頁 | 105 | 4:45 |
| 5 | 主動關懷與記憶 | 75 | 6:30 |
| 6 | 視訊通話與雙軌架構 | 105 | 7:45 |
| 7 | 監控與跌倒警報 | 75 | 9:30 |
| 8 | GPS 軌跡與安心提醒 | 90 | 10:45 |
| 9 | 家屬端與小嘎轉交子女 | 90 | 12:15 |
| 10 | 家庭社群時光牆 | 90 | 13:45 |
| 11 | 福氣小豬與每日祝賀圖 | 75 | 15:15 |
| 12 | 技術總覽與 PRO 訂閱 | 75 | 16:30 |
| 13 | Uban 的一天（全員合照） | 75 | 17:45 |
| 14 | 片尾：團隊與致謝 | 60 | 19:00 |
| | **合計** | **1200** | 20:00 |

**里程碑一：前五分鐘** ＝ 第 0–3 章（4:45）＋第 4 章開頭 15 秒。

## 5. 功能 → 鏡頭卡對照

規則：同一張卡全片只當一次主角（P4）；能量曲線低開、功能段與呼吸段交替、第 13 章最高。

| 章 | 主要鏡頭卡（卡名 · 樣式） | 備註 |
|---|---|---|
| 0 | 光點主角弧線（自寫，依 Q5）→ `brace-expand` → `blur-slide` → `radial-ripple-phone-chips` → `title-demote-to-label` | 衝擊 1/3：字標落定 |
| 1 | `pill-slot-cycle`（「今天＿＿了嗎？」）→ `card-stack`（擔心通知越疊越快）→ `tension-camera-moves · pull-back` → `text-column-converge`（長輩 ↔ 子女） | 呼吸段結尾 |
| 2 | `basic-3d-scene`（Three.js：長輩端／小嘎／家屬端三張卡在 3D 空間）→ `bezier-source-converge-merge`（資料匯流） | |
| 3 | `voice-waveform-live`（Hey 嘎蛙）→ `glass-pill-dictation-typing` → `pill-chip-slot-cycle-handled`（小嘎［聽得懂／說台語／記得你／會求救］）→ `card-flip-reveal`（國語 ↔ 台語截圖）→ `research-card-stack-scroll`（記憶卡，亮場重配色）→ `draw-svg-trace`（手機小幫手圈出按鈕） | |
| 4 | `carousel-3d` 或 `mosaic-reframe` 展開五分頁 → `cursor-flyover`／`PageCam` 逐頁推近一次後橫移 → `theme-switch-moves`（深色模式） | |
| 5 | `timeline-travel`（08:00、15:00）→ `word-relay-filmstrip`（記憶話題） | |
| 6 | `line-carry-transition` → `glow-flyline-moves · flyline-arc`（亮場重配色：信令線／影音線兩條）→ `quad-split-parallel-scenes`（鎖屏／冷啟動／語音升級視訊） | |
| 7 | `scan-bracket-sweep`／`fui-hud-moves`（監控取景框）→ `crash-zoom-punch`（衝擊 2/3，閃白，不晃）→ `chip-grid-single-select-blackout`（切換鏡頭） | 唯一紅色 |
| 8 | `steep-tilt-glide` 或 `overhead-camera-moves`（地圖截圖）→ `gauge-readout-moves`（停留時間） | 安心提醒用 ember |
| 9 | `shot-transitions · whip-pan`（兩支手機間甩鏡）→ `bezier`／`row-embed`（問題轉交進收件匣） | |
| 10 | `page-waterfall-wall`（照片牆）→ `list-stack-press`（按讚留言） | |
| 11 | `icon-performance-moves`（小豬）→ `value-stagger-gradient`（成長階段）→ `before-after-slider-scrub`（祝賀圖貼上小豬前後） | |
| 12 | `beat-step-list-theme-cycle`（技術名詞逐拍）→ `segmented-thumb-hero`（免費 ↔ PRO） | |
| 13 | `outro-group-photo-launch`（每章一個代表元素飛入合照） | 衝擊 3/3 |
| 14 | `logo-shrink-wordmark-lockup` → 名單 `paper-title-card` | 字標停 ≥ 1 秒 |

實作時每張卡都要：查 `gallery/api/library.json` → 讀卡片全文 → 讀「參考實現」指到的 demo TSX 全文 → 複製進 `remotion/src/shots/<章>/` 改皮（色、字、素材），**卡上「已知坑／命門」的參數不准降檔**。

## 6. 前五分鐘分鏡（第 0–3 章）

時間以拍數表示（1 拍 = 16 格 @30fps ≈ 0.533 秒；1 小節 = 4 拍）。

### 第 0 章（45 秒 ≈ 84 拍）

| # | 拍 | 畫面 | 卡 | 字 |
|---|---|---|---|---|
| 0-1 | 0–12 | 暖白舞台，綠色光點從畫面深處浮出、推近、輕浮、落定在中央（完整主角弧線 ≥ 3 秒） | 自寫 | — |
| 0-2 | 12–28 | 光點變成輸入游標，硬切成一對小括號，彈開揭示「Uban」，落定後字距鬆一口氣；副標逐詞浮現 | `brace-expand` | Uban／AI 跨世代照護系統 |
| 0-3 | 28–44 | 標語逐詞模糊滑入，兩行 | `blur-slide` | 讓長輩用說的　讓家人放心 |
| 0-4 | 44–72 | 同心圓水波呼吸，中央手機是長輩首頁真實截圖，兩側白色功能膠囊（小嘎、打卡、通話、小豬、家人） | `radial-ripple-phone-chips` | 膠囊字 ≥ 40 px |
| 0-5 | 72–84 | 「Uban」縮成左上角章標籤，畫面留白，光點留在中央 → 第 1 章 | `title-demote-to-label` | 01 長輩的一天 |

### 第 1–3 章

第 0 章樣片通過後補寫（同一格式），避免方向未定先排滿細節。

## 7. 專案結構

```
expo-video/remotion/
  src/remotion30.tsx      30 fps 相容層（所有 import 都走這裡）
  src/fixtures/           shotcraft demos/_fixtures（已改 import）
  src/lib/                shotcraft assets/lib
  src/theme.ts            第 2、3 節 tokens
  src/shots/ch00/…        各章鏡頭
  src/Film.tsx            全片時間表 SHOTS（唯一事實源）
  public/fonts screens pigs audio
```

## 8. 驗收

- 每個鏡頭兩個驗收格：`npx remotion still`，存 `out/qa/`。
- 每章完成整章渲染，抽格回看。
- 每個里程碑交給使用者前，派乾淨上下文的子代理照 shotcraft `final-review.md`＋`aesthetic-rules.md` 審查。
