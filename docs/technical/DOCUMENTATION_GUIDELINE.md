# Uban 專案技術紀錄撰寫規範 (DOCUMENTATION_GUIDELINE)

本文件定義了 Uban 系統內所有「詳細技術文件 (`docs/technical/*`)」的撰寫標準與結構規範。每當完成一項核心功能時，開發者必須建立或更新對應的 Markdown 文件，並確保其內容的嚴謹性與詳細度。

---

## 1. 文件結構規範 (Standard Outline)

一份合格的詳細技術文檔必須包含以下八大核心章節。若該功能無涉及特定章節（例如：純後端 API 無 UI 設計），可精簡該章節，但須以「無」進行註記，不可直接刪除標題。

### ❶ 元數據 (Metadata Header)
置於文件最頂部，標明文件的基本屬性：
```markdown
# [功能中文名稱] 技術設計與實作紀錄
* 建立日期：YYYY-MM-DD
* 最近更新：YYYY-MM-DD
* 適用版本：vX.Y.Z
* 負責組件：[前端/後端/AI/信令]
```

### ❷ 功能背景與設計初衷 (Objectives & Background)
* **為了解決什麼痛點**：明確陳述原系統的限制，以及對長輩端（或家屬端）帶來的影響。
* **照護價值與 UX 考量**：闡述本功能在跨世代照護或非壓力型陪伴上的設計考量。

### ❸ 系統架構與資料流向 (System Architecture & Data Flow)
* **架構拓撲**：利用 `mermaid` 繪製組件關係圖、狀態轉移圖或資料流向圖。
* **資料傳輸規格**：
  * 對於 REST API，必須記錄詳細路由、請求方法（GET/POST）、Port、逾時時間與 JSON Payload 格式。
  * 對於 Socket.IO 事件，必須標明事件名稱、發送端/接收端角色（`elder`/`family`）、以及 Payload 結構。
  * 對於 WebRTC 信令，必須繪製完整的 Offer/Answer 協商時序圖。

### ❹ 代碼修改與路徑定義 (Implementation & File References)
* **精準檔案變動**：使用 `[NEW]`、`[MODIFY]`、`[DELETE]` 標記檔案，且所有檔案名稱必須為**可點擊的本地 Scheme 連結**（格式如 `[zen_pond_screen.dart](file:///c:/Users/tung0/Desktop/Uban/Uban/mobile_app/lib/screens/zen_pond/zen_pond_screen.dart)`）。
* **程式碼與 API 規格**：記錄新增或修改的關鍵類別、方法、服務，並附帶關鍵邏輯片段。

### ❺ 核心數學公式與物理演算法 (Core Mathematical Models)
對於涉及動畫、物理模擬、陀螺儀體感或數值對映的功能，必須使用 **LaTeX** 語法詳細記錄其底層數學模型：
* **公式推導**：明確定義變數與物理意義（例如：時間週期、縮放因子、阻力係數）。
* **常數設定**：詳細列出代碼中寫死的常數（如最大轉角、彈性係數等）及其設定原因。

### ❻ UI/UX 視覺美學與無障礙規範 (Aesthetics & Accessibility)
針對前端組件，必須詳細記錄視覺設計規範：
* **配色系統**：使用 HEX 或 HSL 顏色代碼，並符合「莫蘭迪禪意暖色調」或專案的主題配色。
* **大字體無障礙**：符合銀髮族使用規範（如：長輩端核心對話文字必須為 **24pt**，列表標題必須為 **20-22pt**，且搭配大點擊熱區）。
* **微動畫與微互動**：記錄動畫曲線（Curves）、變形時間（Duration）與回彈效果。

### ❼ 安全性防護與防誤觸機制 (Safety & Debouncing)
* **防點擊暴兵**：按鈕防重按機制（Debounce/Throttle）、載入狀態（Loading State）鎖定。
* **多租戶資料隔離**：記錄資料庫/向量庫查詢時如何利用 `user_id` 進行絕對邏輯隔離。
* **緊急回退與防誤觸**：例如 SOS 連擊次數、時間窗口限制與冷卻時間（Cooldown）。

### ❽ 測試與驗證計畫 (Test Plan & Checklist)
* **靜態分析**：執行 `flutter analyze` 規格與結果。
* **功能測試 Checklist**：條列明確的測試步驟，包含空數據處理、網路超時/超時回退與邊界情況。

---

## 2. 撰寫風格與品質準則 (Writing Style Guide)

1. **圖表優先**：對於複雜流程，優先使用 `mermaid` 流程圖或時序圖進行可視化。
2. **公式嚴謹**：物理移動或動畫計算不使用模糊文字帶過，必須寫出 LaTeX 數學公式。
3. **路徑完整**：凡是提及程式檔案，均需提供 clickable 連結。
4. **老人友善思維**：說明手冊與技術文件中需點出銀髮族無障礙（Accessibility）與認知負擔降低的考量。
