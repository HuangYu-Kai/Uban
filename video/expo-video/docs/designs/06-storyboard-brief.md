# 06　各章鏡頭清單起草：共用派工說明

> 2026-11-16。使用者已確認：四類鏡頭結構、轉場系統、第 3 章樣本格式（見 `04-shotcraft-guided.md` 最後三節）。現在照同一格式把其餘各章排出來。

## 必讀（先讀完再動筆）

1. `docs/designs/04-shotcraft-guided.md` 全文，尤其：第 1–3 關確認結果、第 4 關對照表（含使用者偏好）、「第 4 關修正：每章要排滿」、「轉場系統」、「樣本：第 3 章完整鏡頭清單」。**第 3 章樣本就是格式與密度的標準。**
2. `docs/designs/00-production-plan.md` 第 7 節你負責的章（舊版分鏡，**只取內容與敘事，不取風格**：舊版的紙張拼貼、等軸島嶼、斑鳩琴都已作廢，現在全片是 Motion 風格＋「一天的光」）。
3. 你要用的每張鏡頭卡：`vendor/_ext/video-shotcraft/references/shots/<分類>/<卡名>.md`（至少讀 frontmatter 的「适用、时长、能量」與「已知坑」），秒數照卡片時長排，不要把 4 秒的卡硬撐成 15 秒。

## 已定事項（不要改、不要再問）

- 全片 1200 秒、60 fps、無配音、展場循環；字卡 ≥ 60 px、一句 ≤ 16 字、停 ≥ 2.5 秒。
- 各章秒數：0 開場 45｜1 長輩的一天 90｜2 系統全景 60｜3 小嘎 90｜4 五個分頁 105｜5 主動關懷 75｜6 視訊通話 105｜7 監控跌倒 75｜8 GPS 90｜9 家屬端 90｜10 朋友圈 90｜11 福氣小豬 75｜12 技術與 PRO 75｜13 Uban 的一天 75｜14 片尾 60。
- 時段（背景色）：0 黎明｜1 清晨｜2 早上｜3–4 上午｜5 正午｜6–7 午後｜8 傍晚｜9 黃昏｜10 入夜｜11 夜晚｜12 深夜｜13 快轉一天｜14 黎明。
- 素材：App 真實截圖（模擬器測試帳號，長輩稱「阿公」、家屬稱「兒子」，不出現真名、網址、IP、新聞人物照；有真人照片的區塊打碼）；App 圖示 `app_icon.png`；小豬用 `pet_breeds/pink_front_1–5`＋耳標 `ear_tag_1–5`；照片用 CC0。第 1 章可在 2–3 鏡用 CC0 人物剪影；高齡數據用政府公開統計並註明出處。
- 紅色 `alert` 只在第 7 章。全片衝擊 3 次：第 0 章字標落定、第 7 章跌倒、第 13 章全員合照。

## 鏡頭卡分配（防止各章撞卡）

**主角鏡（★）只能用：** 你負責章在 04 第 4 關對照表中的首選卡＋下表分給該章的專屬卡。別章的卡一律不准當主角。不必全部用完；用不到就不用。◆工作鏡、▲字卡、●章名卡不受此限。

| 章 | 對照表已定的首選（必用） | 本章專屬可加用 |
|---|---|---|
| 0 | brace-expand、lead-word-zoom-assemble、word-relay-geometry | icon-field-colorize、radial-wave |
| 1 | vertical-word-roll-blur-cycle、gauge-readout-moves、list-stack-press、aurora-bloom-bg-flip | typewriter-moves、panel-grid-moves、tension-camera-moves、countdown-arc-scatter、marker-underline-title、outline-word-fill |
| 2 | depth-layer-moves、bezier-source-converge-merge | basic-3d-scene、integration-hub-map、canvas-materialize-moves、orbit-ring-title-open |
| 4 | carousel-3d、cursor-flyover、element-body-moves、theme-switch-moves | mosaic-reframe、type-and-filter、spotlight-hero-card |
| 5 | picker-carousel-feature-cycle、doc-park-left-pill-deal、document-typewriter-reveal | timeline-travel、research-card-stack-scroll、hashtag-to-pill-materialize、word-relay-filmstrip、type-assembly-moves |
| 6 | line-carry-transition、quad-split-parallel-scenes | space-camera-moves、pill-slot-cycle、scanline-annotate-focus |
| 7 | scan-bracket-sweep、crash-zoom-punch、slam-entrance-moves、chip-grid-single-select-blackout | rhythm-interrupt-moves、chart-live-moves |
| 8 | overhead-camera-moves、scroll-brake-moves、card-stack | speed-ramp-freeze、steep-tilt-glide、pill-chip-slot-cycle-handled |
| 9 | graze-face-tour、shot-transitions · whip-pan、row-embed | product-card-progressive-assemble、assemble-then-type-flyin、bottom-push-stack-wipe |
| 10 | deck-deal-flyin、impact-feedback、spotlight-sweep-moves | page-waterfall-wall、light-play-moves、magician-card-flourish、wall-reveal-moves |
| 11 | icon-performance-moves（SF3 已做）、avatar-bracket-carousel、list-reveal、before-after-slider-scrub | value-stagger-gradient、cloner-depth-echo、stroke-segment-build、sakuga-timing-shift |
| 12 | beat-step-list-theme-cycle、glow-flyline-moves、segmented-thumb-hero | text-column-converge、neon-frame-forerun、flying-words、type-rhythm-sync、dataviz-landscape-open |
| 13 | gradient-transition、outro-group-photo-launch | crane-rise-reveal、card-flock-tumble、beat-cut-moves、gradient-word-sweep |
| 14 | logo-shrink-wordmark-lockup（SF4 已做）、paper-title-card | ui-to-brand-morph、grain-dissolve、letterspace-materialize、type-entrance-moves |

（第 3 章已完成，不要動。）

## 轉場配額（章內接縫）

R 元素接力、C 連續運鏡不限量（但要有具體寫法，不准只寫「R」）。其餘依下表，**不得超過**：

| 章 | W 甩鏡 | P 穿窗 | H 前景遮擋 | wipe-transitions 幾何擦除 |
|---|---|---|---|---|
| 0、2、5、7、11、13、14 | 0 | 0 | 0 | 0 |
| 1 | 0 | 0 | 1 | 0 |
| 4 | 3 | 1 | 0 | 1 |
| 6 | 1 | 0 | 1 | 0 |
| 8 | 1 | 0 | 1 | 0 |
| 9 | 2 | 1 | 0 | 0 |
| 10 | 0 | 0 | 1 | 0 |
| 12 | 1 | 1 | 1 | 1 |

章與章的接縫已在 04「轉場系統」的 14 接縫表定好，每章最後一鏡的「接下一鏡」照抄那張表；每章第一鏡是 `title-demote-to-label` 章名卡（第 0 章除外：第 0 章第一鏡要能接上第 14 章最後一格，暖白＋中央光點）。光效藏切（白閃、漏光）只有 9→10 那一次，別章不准用。

## 輸出

- 每章一個檔：`docs/designs/storyboard/chNN.md`（NN 兩位數），**不要改 04 檔或別人的檔**。
- 內容：章標題＋一句本章要讓觀眾記住什麼；鏡頭表，欄位與第 3 章樣本完全相同：`| # | 秒 | 類型 | 鏡頭 | 畫面 | 字卡 | 接下一鏡 |`；表後統計：鏡數、各類型數、各接縫代號數；最後列「本章需要的截圖／素材」與「風險」。
- 秒數加總必須剛好等於本章秒數；鏡數約為 本章秒數 ÷ 5.5（±2）。
- 不連續兩個★；每個★後至少一拍讓觀眾讀。字卡文字要寫出來，且是自然的繁體中文。
- 回報（繁體中文）：每章鏡數、★用了哪些卡、轉場配額用量、需要的截圖清單、你不確定的地方。
