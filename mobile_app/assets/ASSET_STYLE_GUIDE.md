# DesktopPet 視覺資產風格指南 (v4/v5)

為了確保未來擴充小豬狀態時，畫風、顏色與特徵能保持 100% 統一，請遵循以下規範。

## 1. 核心視覺特徵
- **主體色 (Main Pink)**: `櫻花粉 (#FFC0CB)`。
- **邊緣線 (Outline)**: 深粉色或深灰色細線。
- **關鍵飾品**: 
  - **橘色/紅色項圈** (Orange/Red Collar)。
  - **金黃色圓形鈴鐺** (Golden Bell) 懸掛於項圈正中央。
- **面部特徵**:
  - 眼睛：實心黑點 (或帶有微小高光的白底黑點)。
  - 腮紅：兩側淺粉色橢圓。
- **畫風**: 極簡 2D 平面向量 (Flat Vector)，無複雜漸層。

## 2. 各型態生成紀錄 (Prompts)

### [IDLE] 閒置狀態
- **Prompt**: `A 2D cute pink piglet character, flat vector style, facing side, orange collar with golden bell, neutral expression, white background.`

### [WALKING] 走路狀態 (Frame 1-2)
- **Prompt**: `A 2D cute pink piglet walking, side view, legs moving, flat vector style, orange collar with golden bell, white background.`

### [HAPPY] 開心狀態
- **Prompt**: `A 2D cute pink piglet jumping happily, wide smile, eyes squeezed shut or hearts, flat vector style, orange collar with golden bell, white background.`

### [PICKED_UP] 被拎起狀態 (v5)
- **Prompt**: `Based on the provided pig character [Reference: idle], generate a variation being lifted up. Surprised face, eyes wide open, mouth small open. Four short legs dangling down, struggling pose. Keep same colors, collar, and bell. Flat vector style, white background.`

## 3. 技術處理流程 (去背規範)
- 所有生成的圖片必須使用 `Flood Fill` 演算法去除白色背景。
- **注意**: 必須從邊角 (0,0) 開始填充透明度，以防止將小豬內部的白色區域（如眼睛、鈴鐺反光）也一併去掉。

## 4. 擴充建議
- **生氣 (Angry)**: 眉毛微挑，噴氣效果。
- **生病 (Sick)**: 臉色發綠，頭上帶冰袋。
- **等級進化**: 隨著等級提升，可以考慮給項圈增加寶石或是給小豬戴上小帽子。
