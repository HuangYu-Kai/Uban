import json
import ollama
from skills import ALL_SKILLS

class OllamaService:
    def __init__(self, model_name="qwen2.5"):
        self.model_name = model_name

    def _get_personality(self, profile):
        """生成 AI 性格指令"""
        if not profile: return "語氣溫暖、體貼。"
        tone = "客觀專業" if profile.ai_emotion_tone < 50 else "熱情親切"
        verb = "簡潔扼要" if profile.ai_text_verbosity < 50 else "詳細會聊天"
        return f"你的性格關鍵字：{tone}、{verb}。對長輩的稱呼應使用「{profile.elder_appellation or '您'}」。"

    def _prepare_messages(self, prompt, user_id, history):
        from models import ElderProfile
        profile = ElderProfile.query.filter_by(user_id=user_id).first() if user_id else None
        
        instruction = (
            f"你是一位親切的長輩陪伴助手。{self._get_personality(profile)}\n"
            "當長輩需要幫助、詢問天氣、時間、健康建議或發生緊急狀況時，請務必使用對應的「工具（技能）」來獲取資訊或執行動作。"
        )
        
        messages = [{"role": "system", "content": instruction}]
        
        # 轉換 Gemini history 格式到 Ollama 格式
        if history:
            for h in history:
                role = "assistant" if h.get("role") == "model" else h.get("role", "user")
                content = h.get("parts", [""])[0] if isinstance(h.get("parts"), list) else ""
                messages.append({"role": role, "content": content})
                
        # 加入新提問
        messages.append({"role": "user", "content": prompt})
        return messages

    def get_response(self, prompt, user_id=None, history=None):
        try:
            messages = self._prepare_messages(prompt, user_id, history)
            
            # 使用 tools 進行自動工具呼叫 (Ollama 會處理 schema)
            response = ollama.chat(
                model=self.model_name,
                messages=messages,
                tools=ALL_SKILLS
            )
            
            # 如果 Ollama 決定呼叫 tool
            while response.get('message', {}).get('tool_calls'):
                messages.append(response['message'])
                
                for tool_call in response['message']['tool_calls']:
                    tool_name = tool_call['function']['name']
                    tool_args = tool_call['function'].get('arguments', {})
                    print(f"--- [Ollama] AI requested tool: {tool_name} with {tool_args} ---")
                    
                    try:
                        tool_func = next((f for f in ALL_SKILLS if f.__name__ == tool_name), None)
                        if tool_func:
                            import inspect
                            params = inspect.signature(tool_func).parameters
                            if 'user_id' in params:
                                tool_args['user_id'] = user_id
                                
                            tool_result = tool_func(**tool_args)
                        else:
                            tool_result = f"Tool {tool_name} not found."
                    except Exception as e:
                        tool_result = f"Error executing {tool_name}: {e}"
                        
                    messages.append({'role': 'tool', 'content': str(tool_result), 'name': tool_name})
                    
                # 把 tool_result 送回 Ollama 繼續生成
                response = ollama.chat(
                    model=self.model_name,
                    messages=messages,
                    tools=ALL_SKILLS
                )

            return response['message']['content']
            
        except Exception as e:
            print(f"!!! [Ollama] Error: {e}")
            return f"AI 回應發生錯誤: {str(e)}"

    def get_response_stream(self, prompt, user_id=None, history=None):
        try:
            messages = self._prepare_messages(prompt, user_id, history)
            
            print(f"--- [Ollama Stream] Starting request for user {user_id} ---")

            # 在串流模式下，Ollama 若判定需要 tool call，會一次性返回整個 message 不會串流，
            # 因此我們先用非 stream 檢查是否有 tool_calls。
            # 如果確認沒有 toll_calls，再正式串流。
            
            while True:
                # 為了避免無限迴圈或過度呼叫，我們只攔截 tool
                res = ollama.chat(
                    model=self.model_name,
                    messages=messages,
                    tools=ALL_SKILLS, 
                    stream=False
                )
                
                if res.get('message', {}).get('tool_calls'):
                    messages.append(res['message'])
                    for tool_call in res['message']['tool_calls']:
                        tool_name = tool_call['function']['name']
                        tool_args = tool_call['function'].get('arguments', {})
                        print(f"--- [Ollama Stream] AI requested tool: {tool_name} with {tool_args} ---")
                        
                        try:
                            tool_func = next((f for f in ALL_SKILLS if f.__name__ == tool_name), None)
                            if tool_func:
                                import inspect
                                params = inspect.signature(tool_func).parameters
                                if 'user_id' in params:
                                    tool_args['user_id'] = user_id
                                tool_result = tool_func(**tool_args)
                            else:
                                tool_result = f"Tool {tool_name} not found."
                        except Exception as te:
                            tool_result = f"Error: {te}"
                            print(f"--- [Ollama Stream] Tool error: {te} ---")
                            
                        messages.append({'role': 'tool', 'content': str(tool_result), 'name': tool_name})
                    
                    # Tool 執行完後回到 while True 讓 Ollama 用具備 tool response 的 messages 再想一次
                else:
                    break # 沒有 tool calls，跳出迴圈正常串流生成

            # 確認沒有 function calls 後，我們執行標準串流返回結果給前端
            stream_response = ollama.chat(
                model=self.model_name,
                messages=messages,
                stream=True
            )
            
            for chunk in stream_response:
                text = chunk.get('message', {}).get('content', '')
                if text:
                    yield text
                    
        except Exception as e:
            print(f"!!! [Ollama Stream] Fatal error: {str(e)}")
            yield f"(對話中斷或工具呼叫異常: {str(e)})"

ollama_service = OllamaService()
