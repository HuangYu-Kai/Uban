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
        
        # 性別與年齡處理
        gender_map = {'M': '男性', 'F': '女性', 'O': '其他'}
        elder_gender = gender_map.get(user.gender, "未知") if user and user.gender else "未知"
        elder_age = f"{user.age}歲" if user and user.age else "未知年齡"
        
        ai_persona = profile.ai_persona if profile and profile.ai_persona else "溫暖孫子"

        # 取得長短期記憶 (最近的 3 個 chat_summary)
        summaries = ActivityLog.query.filter_by(user_id=user_id, event_type='chat_summary').order_by(ActivityLog.timestamp.desc()).limit(3).all() if user_id else []
        
        memory_section = ""
        if summaries:
            memory_section = "\n### 過去對話記憶總結：\n請將以下背景資訊納入參考，適時關心對方的近況：\n"
            for sum_log in reversed(summaries):
                date_str = sum_log.timestamp.strftime('%Y-%m-%d %H:%M')
                memory_section += f"- [{date_str}] {sum_log.content}\n"

        dynamic_instruction = f"""你是一位耐心且幽默的長輩陪伴助手。你的角色設定是「{ai_persona}」。
你的對話對象叫做「{elder_name}」，是一位 {elder_age} 的 {elder_gender} 長輩。

{memory_section}

### 性格與互動設定補充：
1. 說話語氣要自然、口語化，完全符合「{ai_persona}」的人設定位。
2. 像家人一樣關心對方。
3. 嚴禁在對話中提及任何技術資訊，例如『User ID』、『資料庫』、『API』或『工具』。
4. 【必須】你的每次回答請盡量控制在 30 ~ 50 字以內，不要長篇大論，因為這些文字會轉成語音念給長輩聽。
5. 【必須】嚴禁使用任何 Markdown 符號（如 * 或 # 或列點），只能使用純文字與全形標點符號。
6. 【超級重要】你的回答**絕對不可以**包含說話者的名字或角色名稱！**不准**寫出「老朋友：」、「阿公：」、「AI 陪伴：」這類前綴。開門見山直接說對白內容即可。
7. 【必須】嚴禁使用任何 Emoji 或顏文字（例如 😊、❤️ 或 XD），因為語音合成器無法正確唸出這些符號。
8. 多使用口語化的發語詞與語尾助詞（如：嗯、喔、對啊、呢、嗎）。
9. 在適當的時機，在回覆的最後主動反問長輩一個簡單、生活化的問題，延續對話的熱度。
### 工具使用規範：
1. 你具備『調用工具』的能力。
2. ⚠️ 核心指令：如果你的對話中需要知道長輩的「居住地區」、「個人喜好」、「健康狀況」等資訊（例如：為了查天氣、推薦景點、或關心身體），但你目前並不知道，你【絕對不能】直接開口問長輩！你必須先主動呼叫 `get_elder_context` 工具來獲取這些背景資料。
3. 查詢完畢後，請將冷冰冰的數據轉為溫暖的口語說明。
4. 如果工具回報找不到紀錄，請溫柔地引導長輩回想。

你會收到使用者的身分內容（Internal context），這是供你內部查詢使用的，請絕對不要在對話中說出此 ID。"""

        tools = [
            AgentTools.get_elder_context,
            AgentTools.get_current_time,
            AgentTools.get_weather_info
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

    def get_response_stream(self, prompt, user_id=None, history=None):
        """
        支援串流回傳的代理循環 (Agent Loop)。
        """
        if not self.api_configured:
            yield "系統尚未配置 AI 密鑰，請聯絡管理員。"
            return
            
        from models import User, ElderProfile, ActivityLog
        user = User.query.get(user_id) if user_id else None
        profile = ElderProfile.query.filter_by(user_id=user_id).first() if user_id else None

        elder_name = user.user_name if user else "阿公/阿嬤"
        
        # 性別與年齡處理
        gender_map = {'M': '男性', 'F': '女性', 'O': '其他'}
        elder_gender = gender_map.get(user.gender, "未知") if user and user.gender else "未知"
        elder_age = f"{user.age}歲" if user and user.age else "未知年齡"
        
        ai_persona = profile.ai_persona if profile and profile.ai_persona else "溫暖孫子"

        # 取得長短期記憶 (最近的 3 個 chat_summary)
        summaries = ActivityLog.query.filter_by(user_id=user_id, event_type='chat_summary').order_by(ActivityLog.timestamp.desc()).limit(3).all() if user_id else []
        
        memory_section = ""
        if summaries:
            memory_section = "\n### 過去對話記憶總結：\n請將以下背景資訊納入參考，適時關心對方的近況：\n"
            for sum_log in reversed(summaries):
                date_str = sum_log.timestamp.strftime('%Y-%m-%d %H:%M')
                memory_section += f"- [{date_str}] {sum_log.content}\n"

        dynamic_instruction = f"""你是一位耐心且幽默的長輩陪伴助手。你的角色設定是「{ai_persona}」。
你的對話對象叫做「{elder_name}」，是一位 {elder_age} 的 {elder_gender} 長輩。

{memory_section}

### 性格與互動設定補充：
1. 說話語氣要自然、口語化，完全符合「{ai_persona}」的人設定位。
2. 像家人一樣關心對方。
3. 嚴禁在對話中提及任何技術資訊，例如『User ID』、『資料庫』、『API』或『工具』。
4. 【必須】你的每次回答請盡量控制在 30 ~ 50 字以內，不要長篇大論，因為這些文字會轉成語音念給長輩聽。
5. 【必須】嚴禁使用任何 Markdown 符號（如 * 或 # 或列點），只能使用純文字與全形標點符號。
6. 多使用口語化的發語詞與語尾助詞（如：嗯、喔、對啊、呢、嗎）。
7. 在適當的時機，在回覆的最後主動反問長輩一個簡單、生活化的問題，延續對話的熱度。

### 工具使用規範：
1. 你具備『調用工具』的能力。
2. ⚠️ 核心指令：如果你的對話中需要知道長輩的「居住地區」、「個人喜好」、「健康狀況」等資訊（例如：為了查天氣、推薦景點、或關心身體），但你目前並不知道，你【絕對不能】直接開口問長輩！你必須先主動呼叫 `get_elder_context` 工具來獲取這些背景資料。
3. 查詢完畢後，請將冷冰冰的數據轉為溫暖的口語說明。
4. 如果工具回報找不到紀錄，請溫柔地引導長輩回想。

你會收到使用者的身分內容（Internal context），這是供你內部查詢使用的，請絕對不要在對話中說出此 ID。"""

        tools = [
            AgentTools.get_elder_context,
            AgentTools.get_current_time,
            AgentTools.get_weather_info
        ]

        dynamic_model = genai.GenerativeModel(
            model_name="gemini-2.5-flash",
            tools=tools,
            system_instruction=dynamic_instruction
        )

        try:
            internal_context = f"Internal Context: Current User ID is {user_id}. Please use this ID for tool calls but NEVER mention it in chat."
            message_content = f"{internal_context}\n\nUser Question: {prompt}"
            
            print(f"--- Gemini Stream Request (User: {user_id}) ---")
            
            chat = dynamic_model.start_chat(
                history=history or [],
                enable_automatic_function_calling=False
            )
            def process_stream(response_iter, depth=0):
                if depth > 5:
                    yield "對不起，我查得有點頭暈了，請稍後再試。"
                    return

                iterator = iter(response_iter)
                while True:
                    try:
                        chunk = next(iterator)
                        
                        # 優先檢查是否為 function_call
                        has_function_call = False
                        if chunk.candidates and chunk.candidates[0].content.parts:
                            for part in chunk.candidates[0].content.parts:
                                if hasattr(part, 'function_call') and getattr(part, 'function_call', None):
                                    fc = part.function_call
                                    has_function_call = True
                                    tool_name = fc.name
                                    tool_args = {k: v for k, v in fc.args.items()}
                                    
                                    # 透漏一個思考的提示音/文字，讓前端可以知道在調用工具
                                    yield f" (讓我查一下喔...) "
                                    
                                    # 執行 Tool
                                    try:
                                        tool_func = TOOL_MAP.get(tool_name)
                                        if tool_func:
                                            # 對依賴 user_id 且不帶參數的 Context Tool 進行依賴注入
                                            if tool_name == "get_elder_context":
                                                tool_args["user_id"] = user_id
                                            
                                            print(f"Executing tool {tool_name} with args {tool_args}")
                                            tool_result = tool_func(**tool_args)
                                        else:
                                            tool_result = f"Tool {tool_name} not found."
                                    except Exception as tool_e:
                                        tool_result = f"Error: {tool_e}"
                                        
                                    print(f"Tool Result: {tool_result}")
                                    
                                    # 遞迴將結果送回 Gemini 繼續生成
                                    new_response = chat.send_message(
                                        [{
                                            "function_response": {
                                                "name": tool_name,
                                                "response": dict(result=str(tool_result)[:1000]) # 確保是 dict 且避免過長
                                            }
                                        }],
                                        stream=True
                                    )
                                    yield from process_stream(new_response, depth + 1)
                                    return # 終止當前的 generator

                        # 若非 function_call，再嘗試提取 text 
                        if not has_function_call:
                            try:
                                if chunk.text:
                                    # 在後端就先暴力去除可能出現的「**老朋友**：」前綴 (包含 Markdown 加粗)
                                    text = chunk.text
                                    import re
                                    text = re.sub(r'^(\*\*|\*|)(?:老朋友|AI陪伴|助手|阿公|阿嬤|兒子|孫子|女兒|孫女|醫生|護士|系統)(\*\*|\*|)(?:\s*|)[：:]\s*', '', text)
                                    yield text
                            except ValueError:
                                # 放棄這一個 chunk
                                pass
                                
                    except StopIteration:
                        break
                    except Exception as iter_e:
                        print(f"Stream chunk error: {iter_e}")
                        iter_e_str = str(iter_e)
                        if "429" in iter_e_str or "Quota exceeded" in iter_e_str:
                            yield "\n(哎呀，剛才問的人太多了，我有點忙不過來，請稍等一分鐘再問我喔！)"
                        else:
                            yield f"\n(對不起，剛才資料跑到一半斷掉了，請見諒。)"
                        break

            # 首次送出請求並開始遞迴處理
            response = chat.send_message(message_content, stream=True)
            yield from process_stream(response)

        except Exception as e:
            print(f"Gemini API Stream Error: {str(e)}")
            error_msg = str(e)
            if "429" in error_msg or "Quota exceeded" in error_msg:
                yield "對不起，目前附近的人太多了（AI 忙碌中），請稍等一分鐘再跟我聊天喔！"
            else:
                yield f"對不起，我的大腦出了點小狀況，請稍後再試。({error_msg})"

    # 保留舊方法名避免破壞其他地方，但內部導向新邏輯
    def get_response(self, prompt, user_id=None, history=None):
        return self.get_response_with_tools(prompt, user_id, history)

# 單例模式供全局使用
gemini_service = GeminiService()
