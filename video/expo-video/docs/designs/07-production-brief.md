# 07　量產：共用骨架與逐章實作說明

> 2026-11-16。分鏡已由使用者確認放行（`04-shotcraft-guided.md`「第 5–6 關確認結果」）。本檔是所有實作子代理的共同規則。

## 必讀

1. `docs/designs/04-shotcraft-guided.md`：第 1–3 關確認結果、「第 4 關修正：每章要排滿」、「轉場系統」、「第 5–6 關確認結果」。
2. `docs/designs/05-styleframe-card-brief.md`：**鏡頭卡換皮的鐵則**（複製 demo 原檔、只改 import／文字／素材／色票／構圖，時值與已知坑參數不准動）與 Uban 換皮規格。量產完全沿用。
3. 你負責章的 `docs/designs/storyboard/chNN.md`（第 3 章在 04 檔的樣本）。**分鏡是已確認的規格**：畫面、字卡文字、接下一鏡的做法都照做；做不到的地方回報，不要自己改劇情。
4. 用到的每張鏡頭卡全文與 demo 原檔全文（`vendor/_ext/video-shotcraft/references/shots/…`、`…/demos/…`），以及 `references/aesthetic-rules.md`。
5. 已完成的樣稿 `remotion/src/shots/sf/Sf1–Sf4.tsx`：換皮後的品質與寫法基準，SF1（0-2）、SF2（3-6）、SF3（11-2）、SF4（14-2）直接沿用。

## 時間表（唯一事實源）

- `remotion/src/film/shots.json` 由 `python -I tools/build_timeline.py` 從分鏡產生，**不要手改**。每鏡有 `id、ch、kind、cards、startBeat、beats、from30、dur30、picture、caption、seamType、seam`。
- 112.5 BPM，一拍 16 格（30 fps）；全片 2250 拍；章起點都在小節頭。所有程式一律從 `remotion30` import（30 fps 格，60 fps 渲染）。
- 鏡頭長度以 `shots.json` 的 `dur30` 為準（已對拍，和分鏡秒數最多差半拍）。主角鏡的 demo 原長若比 `dur30` 短，多出來的是落定後的靜止；若比 `dur30` 長，**回報**，不要壓縮 demo 的時值。
- 轉場占用的格數從前後兩鏡劃走：前一鏡的最後幾格與後一鏡的前幾格重疊演出，鏡頭邊界（拍點）是「交接完成」的那一格或交接中點，視做法而定，寫在程式註解裡。

## 專案結構

```
remotion/src/film/
  shots.json            生成檔
  timeline.ts           型別、shot(id)、chapter(n)、useShotFrame(id)（回傳該鏡的區域格數）
  Film.tsx              全片：依 chapters 排 <Sequence>，底層是 DayStage
  shared/
    DayStage.tsx        「一天的光」背景：依全片格數在各章時段色之間連續漸變（章接縫前後各約 2 小節內過渡）
    GreenDot.tsx        小嘎光點（全片標準：畫面正中央 960,540，半徑 44；theme.ts 的 DOT）
    TitleDemote.tsx     章名卡：title-demote-to-label demo 換皮，落定後就是左上常駐章標籤
    ChapterLabel        沿用 src/lib/ChapterLabel.tsx（位置、字級不變）
    Phone.tsx           手機框：螢幕比例 1080:2424，螢幕圓角 = 外框圓角 − 邊框，深墨細框（照 Sf2.tsx）
    CaptionCard.tsx     ▲ 字卡：一句 ≥ 60 px，Huninn 標題體，逐詞顯影（blur-slide 基本款）
    ShotCaption.tsx     ◆ 工作鏡旁的那句字（≥ 60 px），位置在畫面左或右側空白，**不放進最下方 15%（y > 918）**
    seams.ts(x)         W 甩鏡、H 前景遮擋、P 穿窗：各自複製 shot-transitions／transition-hidden-cut 的 demo 換皮成可重用元件
  ch00/ … ch14/         每章一個資料夾：ChNN.tsx（章組裝）＋每鏡一個檔 S00_01.tsx …
```

- `Root.tsx` 註冊：`Film`（全片）與 `Ch00`–`Ch14`（單章，方便渲染與驗收）。舊的 `shots/ch00/Ch00Opening.tsx` 只留檔參考，取消註冊。
- 各時段色在 `theme.ts` 的 `DAY` 擴充（已有 dawn／morning／night；補 earlyMorning 清晨偏冷灰藍、forenoon、noon、afternoon mint、dusk、sunset、nightfall、midnight；顏色參考 `styleframes/index.html` 第 5 張的色帶）。手機畫面：長輩端維持 App 亮色；**家屬端一律深色**（使用者 11-17 指定，App 預設即深色）。
- 字：要讀的字 ≥ 60 px；章標籤 32 px；其餘當裝飾。不用彩色 emoji、不出現 video-shotcraft 字樣、不出現真名／網址／IP。
- 紅色：**警報紅 `C.alert` 只在第 7 章**；截圖裡真實介面的掛斷鍵可保留原色。

## 素材

- 已有：`public/screens_full/`（長輩首頁、國語／台語聊天，1080×2424）、`public/brand/app_icon.png`、`public/pigs_breed/`（小豬＋耳標）、`public/fonts/`。
- 缺的截圖：**先用同尺寸的佔位圖**（淺灰底＋中央寫「待補：<內容>」，放 `public/placeholders/`），並在回報中列出；不要自己畫假的 App 介面冒充截圖。
- 自製圖示、示意圖：單色線條、圓角，用 SVG 寫在程式裡或放 `public/art/`。

## 驗收（每章）

1. `npx tsc --noEmit -p .` 通過。
2. 每鏡至少 2 張靜幀（動作中、落定），存 `remotion/out/qa/chNN/`；**每張都用 Read 打開親眼看**：字有沒有被壓到、出框、小於 60 px、殘留原 demo 文字、背景時段色對不對。
3. 每個接縫前後各取 1 張，確認沒有裸切、前後元素接得上。
4. 整章渲染 `npx remotion render src/index.ts ChNN out/chNN.mp4`。
5. 回報（繁體中文）：每鏡用了哪張卡／哪個 demo 原檔、哪些參數原封保留、demo 原長與 `dur30` 的差異、用了哪些佔位圖、已知問題、你沒照分鏡做的地方與原因。

## 圖示與光點分工（11-17 使用者：「圓球用太多，大部分換成 App 圖示」）

- **`shared/AppMark.tsx`（Uban App 圖示）是全片的接力主角**：章接縫的接力物、匯聚點、收束點、開場與片尾、「Uban 在中間牽起兩代」的意思、一個東西「交給 Uban 處理」的落點。分鏡裡寫「綠色光點」「小嘎光點」的地方，**預設改用 AppMark**。
- **`GreenDot` 只留在**：①小嘎這個角色正在說話／思考／被點名的那一刻（例：「小嘎」兩字收成的點、聊天頁上小嘎的聲波旁）；②SF1 開場的游標；③章標籤上的小圓點（32 px 標籤內的裝飾，不換）。拿不準時用 AppMark。
- 標準：AppMark 畫面正中央 960,540、邊長 128；第 0 章第一格＝第 14 章最後一格＝DAY.dawn＋標準 AppMark、完全靜止（循環接縫）。
- 圖示不要做成「一排複製」，也不要當浮水印常駐角落。
