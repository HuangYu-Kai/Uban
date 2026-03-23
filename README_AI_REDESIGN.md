# AI Chat Redesign - Skill-based Architecture

這個計畫旨在將 AI 對話邏輯從「硬編碼(Hardcoded)」遷移到「模組化(Modular Skills)」。

## 設計理念：什麼是 Skill？

在 Gemini 的 Native Function Calling (功能呼叫) 框架下，一個 **Skill** 僅僅是一個帶有**清晰 docstring** 的 Python 函數。

### 1. 標準 Skill 的核心要素

-   **函數名稱**：具備描述性 (如 `get_weather`)。
-   **具名參數 (Typed Args)**：必須定義型別 (如 `location: str`)，這有助於 AI 生成精確的參數。
-   **文檔字串 (Docstring)**：這是給 AI 的「說明書」。AI 會根據這段文字決定何時、以及如何呼叫該 Skill。

### 2. 資料結構優化目錄

建議將 Skill 按照功能分組存放：

-   `skills/health.py`: 醫療知識、用藥、運動建議。
-   `skills/util.py`: 時間、計算、翻譯。
-   `skills/external.py`: 天氣、新聞、Youtube 影片搜尋。

## 如何測試？

我已為您建立了一個單獨運作的測試程式：[ai_skill_test.py](file:///c:/Users/My_User/Desktop/program/CODE/UniFlow/UniFlow/ai_skill_test.py)

1.  **確認環境**：確保本機已安裝相關套件。

    ```bash
    pip install google-generativeai python-dotenv
    ```

2.  **填寫金鑰**：在根目錄的 `.env` 中確認 `GEMINI_API_KEY` 是否正確。

3.  **執行程式**：

    ```bash
    python ai_skill_test.py
    ```

## 未來整合建議

當您在測試程式中對 Skill 的表現滿意後，可以透過以下步驟整合進現有後端：

1.  將 Skill 函數移至單獨模組。
2.  在 `gemini_service.py` 中，將這些函數加入 `tools` 列表：

    ```python
    model = genai.GenerativeModel(
        model_name="...",
        tools=ALL_YOUR_MODULAR_SKILLS
    )
    ```

3.  設定 `enable_automatic_function_calling=True` (非串流) 或手動處理 (串流)。
