import google.generativeai as genai
import os
import json
from dotenv import load_dotenv
from services.tools_service import TOOL_MAP, AgentTools

load_dotenv()

class GeminiService:
    def __init__(self, api_key=None):
        self.api_key = api_key or os.getenv("GEMINI_API_KEY")
        if self.api_key:
            genai.configure(api_key=self.api_key)
            self.api_configured = True
        else:
            self.api_configured = False

    def _get_personality(self, profile):
        """生成 AI 性格指令"""
        if not profile: return "語氣溫暖、體貼。"
        tone = "客觀專業" if profile.ai_emotion_tone < 50 else "熱情親切"
        verb = "簡潔扼要" if profile.ai_text_verbosity < 50 else "詳細會聊天"
        return f"你的性格關鍵字：{tone}、{verb}。對長輩的稱呼應使用「{profile.elder_appellation or '您'}」。"

    def get_response(self, prompt, user_id=None, history=None):
        if not self.api_configured: return "AI 密鑰未配置。"
        
        from models import ElderProfile
        profile = ElderProfile.query.filter_by(user_id=user_id).first() if user_id else None
        
        # 獲得最新背景資料並直接注入指令中
        context = AgentTools.get_elder_context(user_id)
        instruction = f"你是一位親切的長輩陪伴助手。{self._get_personality(profile)}\n{context}"
        
        model = genai.GenerativeModel(
            model_name="gemini-2.5-flash",
            tools=[AgentTools.get_elder_context, AgentTools.get_current_time, AgentTools.notify_family_SOS, AgentTools.get_weather_info],
            system_instruction=instruction
        )
        
        try:
            # get_response (非串流) 依然可以使用自動工具呼叫
            chat = model.start_chat(history=history or [], enable_automatic_function_calling=True)
            response = chat.send_message(prompt)
            return response.text
        except Exception as e:
            return f"AI 回應發生錯誤: {str(e)}"

    def get_response_stream(self, prompt, user_id=None, history=None):
        """串流版本：手動攔截並處理工具呼叫，以支援 SDK 限制下的串流工作"""
        if not self.api_configured: 
            yield "AI 密鑰未配置。"
            return
            
        from models import ElderProfile
        profile = ElderProfile.query.filter_by(user_id=user_id).first() if user_id else None
        context = AgentTools.get_elder_context(user_id)
        instruction = f"你是一位親切的長輩陪伴助手。{self._get_personality(profile)}\n{context}"
        
        print(f"--- [AI Stream] Starting request for user {user_id} ---")
        
        model = genai.GenerativeModel(
            model_name="gemini-2.5-flash", 
            system_instruction=instruction,
            tools=[AgentTools.get_elder_context, AgentTools.get_current_time, AgentTools.notify_family_SOS, AgentTools.get_weather_info]
        )
        
        try:
            # 關鍵：關閉自動工具呼叫，改由手動處理
            chat = model.start_chat(history=history or [], enable_automatic_function_calling=False)
            
            def process_response(response_iter, depth=0):
                if depth > 5: # 避免無限循環
                    print(f"!!! [AI Stream] Max recursion depth reached ({depth})")
                    yield "(對話查詢過於複雜，請重試)"
                    return
                
                print(f"--- [AI Stream] Processing iterator at depth {depth} ---")
                iterator = iter(response_iter)
                while True:
                    try:
                        chunk = next(iterator)
                        
                        # 檢查是否包含 function_call
                        has_fc = False
                        if chunk.candidates and chunk.candidates[0].content.parts:
                            for part in chunk.candidates[0].content.parts:
                                if hasattr(part, 'function_call') and getattr(part, 'function_call', None):
                                    fc = part.function_call
                                    has_fc = True
                                    tool_name = fc.name
                                    tool_args = {k: v for k, v in fc.args.items()}
                                    
                                    print(f"--- [AI Stream] AI requested tool: {tool_name} with {tool_args} ---")
                                    
                                    # 執行工具 (依賴注入 user_id)
                                    if tool_name == "get_elder_context":
                                        tool_args["user_id"] = user_id
                                    
                                    try:
                                        tool_func = TOOL_MAP.get(tool_name)
                                        tool_result = tool_func(**tool_args) if tool_func else f"Tool {tool_name} not found."
                                        print(f"--- [AI Stream] Tool result: {str(tool_result)[:100]}... ---")
                                    except Exception as te:
                                        tool_result = f"Error: {te}"
                                        print(f"--- [AI Stream] Tool error: {te} ---")
                                    
                                    # 將結果送回 AI 繼續生成
                                    print(f"--- [AI Stream] Feeding tool results back to AI ---")
                                    new_response = chat.send_message(
                                        [{
                                            "function_response": {
                                                "name": tool_name,
                                                "response": {"result": str(tool_result)}
                                            }
                                        }],
                                        stream=True
                                    )
                                    yield from process_response(new_response, depth + 1)
                                    return 

                        if not has_fc and chunk.text:
                            print(f"--- [AI Stream] Yielding text chunk: {chunk.text[:20]}... ---")
                            yield chunk.text
                            
                    except StopIteration:
                        print(f"--- [AI Stream] Iterator exhausted at depth {depth} ---")
                        break
                    except ValueError:
                        # 發生在 chunk 不含文字時 (例如只有封包 metadata)
                        continue
                    except Exception as e:
                        print(f"!!! [AI Stream] Inner error at depth {depth}: {e}")
                        raise e

            # 發送初次訊息
            print(f"--- [AI Stream] Sending initial user prompt ---")
            response = chat.send_message(prompt, stream=True)
            yield from process_response(response)

        except Exception as e:
            print(f"!!! [AI Stream] Fatal error: {str(e)}")
            yield f"(對話中斷或工具呼叫異常: {str(e)})"

gemini_service = GeminiService()
