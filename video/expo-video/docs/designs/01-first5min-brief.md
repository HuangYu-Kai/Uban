# 前五分鐘樣片：派工說明（共用）

使用者要先看「前五分鐘」的效果再決定往下做。範圍：

| 全片時間 | 段落 | 風格 | 負責 |
|---|---|---|---|
| 0:00–1:00 | 第 0 章：60 秒原片 `C:/Users/kevin/Downloads/ad_60s.mp4`（不改） | — | 組裝時直接接 |
| 1:00–2:30 | 第 1 章 問題：獨居長輩與遠方子女（90 秒） | 紙張拼貼 | `chapters/ch01-collage/` |
| 2:30–3:30 | 第 2 章 進入 Uban 島：系統全景（60 秒） | 等軸 2.5D | `chapters/ch02-iso/` |
| 3:30–5:00 | 第 3 章 小嘎：會聽、會記得、會求救（90 秒） | Motion＋形變 | `chapters/ch03-motion/` |

## 必讀

1. `docs/designs/00-production-plan.md`：第 4、5、6 節（概念、設計語言、鏡頭聖經），第 7 節你負責的那一章，第 8、9 節（接縫）。
2. `seams/J*.json`：你這章兩端的接縫規格。**兩端的第一格、最後一格必須完全符合**，這是最重要的驗收項目。
3. `shared/` 下所有模組（很短，全部讀完）：
   - `tokens.js`：顏色、字型、`DOT`、`isoFaces()`。**章節程式不准寫死色碼**，一律 `import { color } from '/shared/tokens.js'`。
   - `easing.js`：`ease`、`prog`、`tween`、`env`、`step12`、`popScale`。
   - `camera.js`：共用攝影機，`key/hold/whip/shake/handheld/step/at/svgTransform/cssTransform/velocity/export`。
   - `dot.js`：小嘎光點。**光點只能用 `createDot` 畫**，接縫才對得上。
   - `overlay.js`：章名卡＋左上角章節標籤＋字幕。**每章都要用它**，字幕也走它。`loadFonts()` 完才能設 `__ready`。
   - `seeded.js`：`rng`、`hash01`、`noise1`。**禁止 `Math.random()`、`Date.now()`、CSS transition／animation。**
4. 風格參考（只讀）：`vendor/mg-styles-15/prompts/06-collage.md`（拼貼）、`03-isometric.md`（等軸）、`08-morph.md`、`01-flat-vector.md`，以及 `vendor/mg-styles-15/demos/` 下對應範例的原始碼。可以借技法，不要照抄它們的內容與文案。
5. 60 秒原片的關鍵格：`C:/Users/kevin/AppData/Local/Temp/claude/d05b72cde689599a/ccee6a9e-4388-4d6e-824e-dbe833154f38/scratchpad/ad/contact.png`（每 5 秒一格）與 `last2s.png`。原片是淡薄荷底、品牌綠、深墨字、圓潤乾淨，長片要和它看起來是同一家人。

## 畫面規格：60 fps（11-15 使用者指定）

- 全片改為 **1920×1080、60 fps**。`DEMO.fps = 60`。
- `renderAt(t)` 本來就只看秒數，所以動畫時間不用改；但凡是用「格數」寫的東西都要換成秒數（例如「8 格」＝ 8/30 秒，不是 8/60 秒），計畫書裡寫的格數一律以 30 fps 換算成秒。
- 拼貼章的定格手感維持原本的時間步進（`step12(t)` 與 `cam.step(2)` 的 fps 參數保持 30 → 每秒 15 次更新），不要因為 60 fps 變得更順。
- 接縫格：最後一格是 `t = duration − 1/60`。

## 頁面合約

```html
<!doctype html><html lang="zh-Hant"><head><meta charset="utf-8">
<link rel="stylesheet" href="/shared/fonts/fonts.css">
<style>html,body{margin:0;overflow:hidden;background:…}#stage{position:relative;width:1920px;height:1080px;overflow:hidden}</style>
</head><body><div id="stage">…</div>
<script type="module" src="./js/main.js"></script></body></html>
```

```js
window.DEMO = { width: 1920, height: 1080, fps: 60, duration: <章長秒數> };
window.renderAt = async (t) => { /* 純函式：只看 t。同一個 t 永遠同一格，不依賴前一格 */ };
await loadFonts('<本章用到的所有中文字>');
window.__ready = true;
```

- 伺服器根目錄是 `expo-video/`，所以絕對路徑 `/shared/...`、`/node_modules/three/build/three.module.js`、`/node_modules/flubber/build/flubber.min.js`（UMD，用 `<script>` 載入後是 `window.flubber`）都可以用。可用套件：three 0.186、gsap 3.13（若用，必須 `paused` 後以 `tl.seek(t)` 驅動）、flubber、simplex-noise。
- 章內時間 `t` 從 0 到 `duration`。`duration` 等於章長（第 1 章 90、第 2 章 60、第 3 章 90），不加把手。

## 渲染指令（在 `expo-video/` 下執行）

```bash
node harness/render.mjs chapters/ch0X-xxx --stills 0,5,12.5,30,45,60,89.96      # 抽格 PNG → chapters/ch0X-xxx/out/stills/
node harness/render.mjs chapters/ch0X-xxx --scale 0.5 --out out/ch0X_preview.mp4  # 半解析度預覽
node harness/render.mjs chapters/ch0X-xxx --workers 3 --mkv out/ch0X.mkv          # 交件：全解析度無失真
```

ffmpeg 已自動指向 imageio 內建版（不在 PATH 上，路徑在 `harness/render.mjs` 的 `IMAGEIO_FF`），渲染器會自己找到。一格約 0.04–0.3 秒。

**你一定要用 Read 工具看自己的抽格 PNG**，邊看邊改，至少三輪；每一輪都問自己：構圖平衡嗎？字夠大（最小 36 px，重點 64 px 以上）？主體有沒有掉進下方 12% 字幕區（y > 950）？有沒有空洞、穿幫、豆腐字？這一格放在專題展的電視上好看嗎？

## 內容與文字

- 字幕＝暫時旁白（配音還沒決定，展場也吵，所以字幕本身要能說完故事）。每行 ≤ 16 字，每句停留 ≥ 字數 ÷ 5 + 0.5 秒。用 overlay 的 `captions`。
- 內容只能來自計畫書第 7 節該章的「旁白重點」；不要發明 Uban 沒有的功能。不出現真實網址、IP、人名、價格。
- 畫面上的文字一律繁體中文、台灣用語。
- 介面不要彩色 emoji（使用者的規則）；需要圖示就自己畫簡單向量。
- 章名卡：第 1 章 `01`／為什麼需要 Uban／獨居長輩與遠方的子女；第 2 章 `02`／Uban 島／一套 AI 跨世代照護系統；第 3 章 `03`／小嘎／會聽、會記得、會求救的 AI。每章前 10 秒內出現，最後 1 秒前收掉（`tagUntil`），接縫那一格畫面上不能有章名或字幕。

## 品質門檻（你自己先檢查，交件時逐條回報）

1. 兩端接縫格完全符合 `seams/*.json`（用 `--stills 0,<duration-0.017>` 抽出來看，並用 Python 量第一格／最後一格中心與角落的像素色值，回報數字）。
2. 鏡頭動作符合計畫書第 6 節：有理由才動、緩動正確、讀字時不動、前進方向向右。
3. 每一段都有東西在動，沒有超過 3 秒的死畫面（停住讀字時也要有微動：呼吸、飄動、閃爍）。
4. `renderAt` 可重現：同一個 t 渲兩次，PNG 雜湊相同（用 `--stills 30,30` 不行，請渲兩次比對）。
5. 程式裡搜不到 `#` 開頭的色碼（tokens 以外）、`Math.random`、`Date.now`。
6. 交件：`chapters/chNN-xxx/`（index.html、js/、`camera.json` ＝ `cam.export()` 的輸出）、`out/chNN.mkv`、一份 `chapters/chNN-xxx/NOTES.md`（鏡頭表實際時間、字幕全文、已知問題）。

## 不准做的事

- 不改 `shared/`、`harness/`、其他章節、`docs/`。shared 有 bug 就在 NOTES.md 寫出來並在章節內繞過。
- 不 git commit、不 push、不安裝全域軟體。需要 npm 套件時先在 NOTES.md 說明理由，盡量用現有的。
