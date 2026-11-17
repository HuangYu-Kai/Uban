# 配樂 out/music_0-300.wav 說明

重現：`python audio/build_music.py`（確定性，不含隨機；約 1 分鐘）。輸出 `out/music_0-300.wav`（48 kHz 立體聲 24-bit，正好 300.000 秒）
與 `out/music_clip_ch{1,2,3}.wav`（各 20 秒試聽）。**不使用** `score_preview.py` 的合成配樂。

## 剪接表（全片秒數 ↔ 原曲秒數）

| 全片時間 | 段落 | 曲目 | 原曲取用 | 說明 |
|---|---|---|---|---|
| 0–59.0 | 原片自帶配樂 | — | — | 本軌樣本值全為 0 |
| 59.0–62.0 | 淡入（J-cut） | Cattails | 0.00 s 起 | 3 秒淡入，60 s 時約 −3 dB 已進入，原曲前奏 |
| 59.0–148.94 | 第 1 章 | Cattails | 0.00–89.94 s | 77 bpm，拍 0.779 s，小節 3.117 s；第 1 個小節線在 1.154 s，用到第 29 個小節線（原曲 88.44 s） |
| 145.94–148.94 | 交叉淡化 1 | Cattails→Fireflies | — | 3 秒等功率交叉淡化，中心＝全片 147.435 s，兩軌小節線在此重合（Cattails 第 28 小節＝4 小節樂句尾第 7 句；Fireflies 第 0 小節線） |
| 145.94–210.66 | 第 2 章 | Fireflies and Stardust | 0.20–64.9 s | 93 bpm，小節 2.572 s；從原曲 0.2 s（前奏）進，走 24 小節（3 個 8 小節樂句）到小節線 |
| 207.66–210.66 | 交叉淡化 2 | Fireflies→Still Pickin | — | 中心＝全片 209.157 s，同樣小節線對齊 |
| 207.66–300.0 | 第 3 章＋收尾 | Still Pickin | 0.87–93.2 s | 100 bpm，小節 2.400 s；最後 3 秒（297–300）淡出至靜音，300.000 秒樣本為 0 |

換曲點（147.4 s、209.2 s）略早於章節切點（150、210）：第 2 章音樂提前約 2.5 s 進入（延續 J-cut 手法），第 3 章幾乎對齊（早 0.8 s）。
Cattails 在全片 133–137 s（原曲 74–78 s）有一段刻意的「減樂器／休止」（RMS 降到約 −30 dB），是樂句 6 的呼吸點，
節拍格點與它吻合（全片 135.97 s 為小節線），若旁白剛好在此會顯得很安靜，可接受。

## 為什麼選這三首

- **Cattails（第 1 章）**：官方描述 "calm and pensive"；原聲吉他＋斑鳩琴撐起漂浮的律動，手風琴與二胡（也帶東亞色彩，貼近觀眾）緩慢嘆息般的旋律，
  77 bpm，孤單但柔和、懷舊。
- **Fireflies and Stardust（第 2 章）**：官方描述 "beautiful rural americana"，8 人真樂團（斑鳩琴、小提琴、曼陀林、吉他、貝斯、鼓），
  標籤 Bright/Calming/Relaxed，營火民謠感最強、展開且有希望。
- **Still Pickin（第 3 章）**：斑鳩琴＋口琴＋跺腳節奏，100 bpm "pickin and stompin"，輕快活潑，口琴恰是要求的樂器之一。

## 響度與峰值

- 整體積分響度 −16.0 LUFS（自寫 BS.1770-4 K 加權＋雙閘門量測，與 ffmpeg ebur128 一致：I −16.0 LUFS、LRA 2.9 LU）。
- 取樣峰值／True peak −2.2 dBFS（未使用限幅器），符合 ≤ −1 dBFS。
- 三段在混合前先個別對齊響度，換曲處不會有音量跳動。

## 片尾標註文字（CC BY 4.0，必須放在片尾）

```
Music: "Cattails", "Fireflies and Stardust", "Still Pickin"
Kevin MacLeod (incompetech.com)
Licensed under Creative Commons: By Attribution 4.0 License
http://creativecommons.org/licenses/by/4.0/
```

授權明細與其他 9 首候選見 `audio/library/LICENSES.md`。

## 已知風險

1. 沒有人耳可聽：我（agent）無法試聽，選曲依官方樂器／情緒標籤、響度包絡與節拍分析；請使用者先聽 `out/music_clip_ch*.wav`。
2. 小節線（downbeat）由 onset 強度推定，Cattails 的置信度高（候選 83 vs 43），Fireflies／Still Pickin 較低；最壞情況是換曲點偏半小節，3 秒交叉淡化下不易察覺。
3. Kevin MacLeod 的作品部分為取樣音源編排，並非全為現場錄音（Fireflies 官方稱 8 人樂團；Cattails 等不確定）。若使用者要求「全部真人錄音」需另行確認。
4. 站上有「付費買斷可免標註」選項，免費使用必須標註；展場公開播放與商用皆在 CC BY 範圍內。
5. 來源 mp3 為 256–320 kbps，非無損；已重取樣為 48 kHz（scipy resample_poly 160/147）。
