# Uban 小豬吉祥物素材指南

本文件詳述了 Uban App 中「智慧小豬」吉祥物的使用規範，方便後續作畫、更換素材或新增動作。

## 1. 核心形象規範 (Character Design)
- **品種**：粉紅色可愛小豬。
- **特徵**：圓潤身軀、藍色項圈配金色圓形名牌。
- **風格**：2D 向量插畫風（2D Cartoon / Vector Art），色彩鮮豔，線條簡潔。

## 2. 素材列表與存放位置

### A. 智慧總結專家 (Summary Expert)
- **檔案路徑**：`mobile_app/assets/images/pig_summary_expert.png`
- **外觀描述**：戴著圓框眼鏡，雙手（或蹄）拿著一個展開的捲軸（代表新聞總結）。
- **出現位置**：
  - `NewsListenPlayerScreen` (新聞播放頁)：右上角浮動按鈕，點擊觸發 AI 總結。
  - `SummaryDialog` (總結對話框)：對話框左側，作為說話者頭像。

### B. 桌面寵物 / 基礎形象 (Base Mascot)
- **檔案路徑**：`mobile_app/assets/images/pig_mascot_transparent.png`
- **外觀描述**：基礎坐姿，表情友善，無特殊配件。
- **出現位置**：
  - `MainScreen` (主畫面)：導航欄上方或新聞卡片角落。

## 3. 更換素材流程

### 步驟 1：產出新圖
建議使用 `generate_image` 工具，並在 Prompt 中包含關鍵字：
> `A cute pink pig mascot, pink skin, blue collar with gold tag, 2D cartoon style, isolated on pure white background.`

### 步驟 2：去背處理
如果產出的圖片帶有白色背景或棋盤格，請使用工作區內的去背腳本：
```powershell
# 執行路徑：c:\Users\tung0\Desktop\Uban\uban-api
python "C:\Users\tung0\.gemini\antigravity\brain\fd9baf46-4fd3-40a3-aab1-752d5ebeaf0c\scratch\remove_bg.py"
```
*(註：腳本內的路徑需手動更新為新的素材路徑)*

### 步驟 3：更新資源
將處理好的 `.png` 覆蓋至 `mobile_app/assets/images/` 對應路徑，並執行 `hot_restart`。

## 4. 未來擴充建議 (Upcoming Actions)
- **思考中**：手托下巴，眼睛斜向上看。
- **播報中**：嘴巴微張，旁邊有音波符號。
- **休息中**：閉眼睡覺，頭上有 `Zzz`。
