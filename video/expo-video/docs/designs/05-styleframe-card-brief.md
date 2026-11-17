# 05　styleframe 鏡頭卡換皮：共用派工說明

> 2026-11-16。使用者看了純 HTML 樣稿後回饋：「看不出來用了鏡頭卡」「豬用我畫的」「App icon 用我們自己的」「手機畫面跟框對不上」「時間不用」。
> 所以第 3 關 styleframe 改成：**每張 = 一張 video-shotcraft 鏡頭卡的 demo 原檔複製後換皮**，輸出關鍵靜幀＋短片。

## 鐵則（違反就是白做）

1. **先完整讀**卡片文件 `vendor/_ext/video-shotcraft/references/shots/<分類>/<卡名>.md`，再**完整讀** demo 原檔 `vendor/_ext/video-shotcraft/demos/<分類>/<卡名>/*.tsx`。
2. **複製** demo 原檔到 `remotion/src/shots/sf/SfN.tsx`，在複本上改。**不准自己重寫一套近似動畫。**
3. 只改 import 路徑：`'remotion'` → `'../../remotion30'`；`'../../_fixtures/X'` → `'../../fixtures/X'`（`remotion/src/fixtures/` 已有 Brand、Look、Motion、Polish、PageCam2D、Fixtures）。
4. **保留**所有時值、緩動、彈簧參數、相位差、過衝、卡片「已知坑／命門」寫的數值。只換：文字、素材、品牌 token、顏色、必要的構圖座標與尺寸。
5. 檔案必須 export `SFN_DURATION`（30 fps 格數，= demo 原長）與元件 `SfN`。Root.tsx 已註冊 `SF1`–`SF4`，**不要改 Root.tsx、theme.ts、fixtures、其他人的 Sf 檔**；fixture 不夠用就在自己檔內寫 local 版本。
6. 時間單位：`remotion30` 的 `useCurrentFrame()` 回傳 30 fps 格；合成是 60 fps，所以 `remotion still --frame=` 要填 **30 fps 格 × 2**。

## Uban 換皮規格

- 色票：`remotion/src/theme.ts` 的 `C`（brand `#59B294`、brandDeep `#2F7D66`、brandSoft、mint、ember `#F2994A`、emberSoft、ink、inkSoft）與 `DAY`（dawn／morning／night 三個時段的舞台色）。demo 原本的強調色、霓虹色、暖沙色全部換成這組。
- 字：標題 `Huninn`（粉圓），內文 `Noto Sans TC`，數字與英文 `DM Sans`。要讀的字 ≥ 60 px，次要字 ≥ 32 px。
- 左上章標籤：`import { ChapterLabel } from '../../lib/ChapterLabel'`（第 0 章開場不用）。
- **不要時鐘、不要彩色 emoji、不要 video-shotcraft 的標誌或字樣**（`ShotcraftMark`、`BRAND`、`PITCH` 一律換成 Uban 內容或移除）。
- 畫面最下方 15%（y > 918）不放要讀的字，留給日後旁白字幕。
- 素材（`remotion/public/`，用 `staticFile()`）：
  - `brand/app_icon.png`：Uban App 圖示（1024²，綠底圓角方形，白色人形加愛心）
  - `pigs_hand/pig_stage_1.png`–`pig_stage_5.png`：組員手繪油畫小豬，五個成長階段（非正方形、透明底、邊緣有柔邊筆觸，**不可硬裁切或加描邊**）
  - `screens/elder_*.png`：長輩端真實截圖 1080×2160（剛好 1:2）
- **手機框規格（使用者指出畫面跟框對不上）：** 螢幕區的長寬比必須等於截圖的 1:2，`object-fit` 不得裁到內容；螢幕圓角 = 外框圓角 − 邊框厚度，讓螢幕四角與框內緣同心；邊框不要太粗。

## 輸出與自我驗收

1. `cd remotion && npx tsc --noEmit -p .` 要過。
2. 關鍵靜幀：`npx remotion still src/index.ts SFN out/sf/sfN_<格>.png --frame=<30fps格×2>`，至少 3 張（入場中、峰值、落定 hold）。**用 Read 打開每張圖親眼看**，有字壓字、出框、素材變形、殘留 shotcraft 字樣就修。
3. 短片：`npx remotion render src/index.ts SFN out/sf/sfN.mp4`。
4. 回報（繁體中文）：卡名・style-key、demo 原檔路徑、改了哪些（逐項）、哪些參數原封保留、靜幀檔名與對應格數、已知問題。
