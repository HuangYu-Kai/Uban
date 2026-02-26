import google.generativeai as genai
import os
from dotenv import load_dotenv
from services.tools_service import TOOL_MAP, AgentTools

# 載入 .env 文件
load_dotenv()

class GeminiService:
    def __init__(self, api_key=None):
        # 如果沒傳入，則嘗試從環境變數讀取
        self.api_key = api_key or os.getenv("GEMINI_API_KEY")
        if self.api_key:
            genai.configure(api_key=self.api_key)
            
            # 獲取工具函數列表 (供 Gemini 識別)
            tools = [
                AgentTools.get_elder_activity_log,
                AgentTools.get_current_weather,
                AgentTools.get_lunar_recommendation
            ]

            # 強化系統提示詞：溫暖、自然、隱藏技術細節
            system_instruction = """你是一位溫暖、耐心且幽默的長輩陪伴助手。
你的目標是陪伴家中長輩聊天，關心他們的日常生活。

### 性格設定：
1. 說話語氣要自然、口語化，多使用長輩慣用的鼓勵話語。
2. 像家人一樣關心長輩，例如提醒穿衣、喝水、稱讚長輩很棒。
3. 嚴禁在對話中提及任何技術資訊，例如『User ID』、『資料庫』、『API』或『工具』。
4. **輸出限制：絕對禁止使用 Markdown 語法格式（如 `**` 加粗、`*` 斜體等），所有文字必須以純文字形式呈現。**

### 工具使用規範：
1. 你具備『調用工具』的能力。當長輩問到天氣、農曆、或詢問他自己的生活紀錄（如：我有沒有吃藥）時，請務必主動使用工具來確認事實。
2. 查詢完畢後，請將冷冰冰的數據轉化為溫慢的口語說明。例如不要說『發現 10:00 有一筆吃藥紀錄』，要說『我剛幫您看了一下，您今天早上十點已經乖乖吃過藥囉，真棒！』。
3. 如果工具回報找不到紀錄，請溫柔地引導長輩回想，不要直接說『找不到數據』。

### 身分識別：
你會收到使用者的身分內容（Internal context），這是供你內部查詢使用的，請絕對不要在對話中說出這個 ID。"""

            self.model = genai.GenerativeModel(
                model_name="gemini-2.5-flash-lite",
                tools=tools,
                system_instruction=system_instruction
            )
        else:
            self.model = None

    def get_response_with_tools(self, prompt, user_id=None, history=None):
        """
        核心代理循環 (Agent Loop)：讓 AI 自主決定是否使用工具。
        """
        if not self.model:
            return "系統尚未配置 AI 密鑰，請聯絡管理員。"
        
        try:
            # 隱藏身分標籤：將 User ID 放入內部的系統提示而非使用者對話中
            internal_context = f"Internal Context: Current User ID is {user_id}. Please use this ID for tool calls but NEVER mention it in chat."
            
            # 如果是第一輪對話，將 Context 加入對話歷史中（Gemini 支援 start_chat 的 history）
            # 或者在每次發送訊息時，將 context 當作一個隱藏的 prepend
            message_content = f"{internal_context}\n\nUser Question: {prompt}"
            
            print(f"--- Gemini Request (User: {user_id}) ---")
            
            chat = self.model.start_chat(
                history=history or [],
                enable_automatic_function_calling=True
            )
            response = chat.send_message(message_content)
            
            if response and response.text:
                print(f"Gemini Response: {response.text[:30]}...")
                return response.text
            else:
                return "AI 目前思考較久，請再跟我說一次試試。"
        except Exception as e:
            print(f"Gemini API Error: {str(e)}")
            error_msg = str(e)
            if "429" in error_msg or "Quota exceeded" in error_msg:
                return "對不起，目前附近的人太多了（AI 忙碌中），請稍等一分鐘再跟我聊天喔！"
            return f"對不起，我的大腦出了點小狀況，請稍後再試。({error_msg})"

    # 保留舊方法名避免破壞其他地方，但內部導向新邏輯
    def get_response(self, prompt, user_id=None, history=None):
        return self.get_response_with_tools(prompt, user_id, history)

# 單例模式供全局使用
gemini_service = GeminiService()
