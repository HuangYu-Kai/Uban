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
            self.api_configured = True
        else:
            self.api_configured = False

    def get_response_with_tools(self, prompt, user_id=None, history=None):
        """
        核心代理循環 (Agent Loop)：讓 AI 自主決定是否使用工具。
        """
        if not self.api_configured:
            return "系統尚未配置 AI 密鑰，請聯絡管理員。"
            
        from models import User, ElderProfile, ActivityLog
        user = User.query.get(user_id) if user_id else None
        profile = ElderProfile.query.filter_by(user_id=user_id).first() if user_id else None

        elder_name = user.user_name if user else "阿公/阿嬤"
        ai_persona = profile.ai_persona if profile and profile.ai_persona else "溫暖孫子"
        chronic_diseases = profile.chronic_diseases if profile and profile.chronic_diseases else "無特殊病史"
        medication_notes = profile.medication_notes if profile and profile.medication_notes else "無特殊用藥"
        interests = profile.interests if profile and profile.interests else "無特別指定"

        # 取得長短期記憶 (最近的 3 個 chat_summary)
        summaries = ActivityLog.query.filter_by(user_id=user_id, event_type='chat_summary').order_by(ActivityLog.timestamp.desc()).limit(3).all() if user_id else []
        
        memory_section = ""
        if summaries:
            memory_section = "\n### 過去對話記憶總結：\n請將以下背景資訊納入參考，適時關心對方的近況：\n"
            for sum_log in reversed(summaries):
                date_str = sum_log.timestamp.strftime('%Y-%m-%d %H:%M')
                memory_section += f"- [{date_str}] {sum_log.content}\n"

        dynamic_instruction = f"""你是一位耐心且幽默的長輩陪伴助手。你的角色設定是「{ai_persona}」。
你的對話對象叫做「{elder_name}」。

### 專屬檔案：
- 疾病紀錄：{chronic_diseases}
- 用藥提醒：{medication_notes}
- 專屬興趣：{interests}
{memory_section}

### 性格與互動設定：
1. 說話語氣要自然、口語化，完全符合「{ai_persona}」的人設定位。
2. 像家人一樣關心對方，適時融入專屬興趣的話題。
3. 若遇到與疾病或用藥相關的話題，請參考專屬檔案中的資訊溫柔提醒。
4. 嚴禁在對話中提及任何技術資訊，例如『User ID』、『資料庫』、『API』或『工具』。
5. **輸出限制：絕對禁止使用 Markdown 語法格式（如 `**` 加粗、`*` 斜體等），所有文字必須以純文字形式呈現。**

### 工具使用規範：
1. 你具備『調用工具』的能力。當長輩問到天氣、農曆、或活動紀錄時，請主動使用工具。
2. 查詢完畢後，請將冷冰冰的數據轉為溫暖的口語說明。
3. 如果工具回報找不到紀錄，請溫柔地引導長輩回想。

你會收到使用者的身分內容（Internal context），這是供你內部查詢使用的，請絕對不要在對話中說出此 ID。"""

        tools = [
            AgentTools.get_elder_activity_log,
            AgentTools.get_current_weather,
            AgentTools.get_lunar_recommendation,
            AgentTools.play_favorite_music,
            AgentTools.contact_family_member
        ]

        # 動態建立模型實例
        dynamic_model = genai.GenerativeModel(
            model_name="gemini-2.5-flash-lite",
            tools=tools,
            system_instruction=dynamic_instruction
        )

        try:
            # 隱藏身分標籤：將 User ID 放入內部的系統提示而非使用者對話中
            internal_context = f"Internal Context: Current User ID is {user_id}. Please use this ID for tool calls but NEVER mention it in chat."
            
            # 如果是第一輪對話，將 Context 加入對話歷史中（Gemini 支援 start_chat 的 history）
            # 或者在每次發送訊息時，將 context 當作一個隱藏的 prepend
            message_content = f"{internal_context}\n\nUser Question: {prompt}"
            
            print(f"--- Gemini Request (User: {user_id}) ---")
            
            chat = dynamic_model.start_chat(
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
