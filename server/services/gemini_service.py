import json
import os
import inspect
from openai import OpenAI
from dotenv import load_dotenv
from skills import ALL_SKILLS

load_dotenv()

class GeminiService:
    def __init__(self, api_key=None):
        # OpenClaw 配置
        self.base_url = "http://127.0.0.1:18789/v1"
        self.api_key = os.getenv("OPENCLAW_TOKEN", "463db01ad29f6aabd59828786872be346704f9f781711e57")
        self.model_name = "google/gemini-2.5-flash-lite"
        
        try:
            self.client = OpenAI(base_url=self.base_url, api_key=self.api_key)
            self.api_configured = True
        except Exception as e:
            print(f"OpenAI Client Init Error: {e}")
            self.api_configured = False

    def _get_personality(self, profile):
        """生成 AI 性格指令"""
        if not profile: return "語氣溫暖、體體。"
        tone = "客觀專業" if profile.ai_emotion_tone < 50 else "熱情親切"
        verb = "簡潔扼要" if profile.ai_text_verbosity < 50 else "詳細會聊天"
        return f"你的性格關鍵字：{tone}、{verb}。對長輩的稱呼應使用「{profile.elder_appellation or '您'}」。"

    def _get_openai_tools(self):
        """將 Python 函數轉換為 OpenAI 工具格式"""
        tools = []
        for func in ALL_SKILLS:
            sig = inspect.signature(func)
            doc = inspect.getdoc(func) or "執行該動作。"
            
            # 簡單解析 docstring 作為描述 (取第一行)
            desc = doc.split('\n')[0]
            
            parameters = {
                "type": "object",
                "properties": {},
                "required": []
            }
            
            for name, param in sig.parameters.items():
                if name == 'user_id': continue # 自動注入，不讓 AI 填寫
                
                param_type = "string"
                if param.annotation == int: param_type = "integer"
                elif param.annotation == bool: param_type = "boolean"
                
                parameters["properties"][name] = {
                    "type": param_type,
                    "description": f"參數 {name}"
                }
                if param.default == inspect.Parameter.empty:
                    parameters["required"].append(name)
            
            tools.append({
                "type": "function",
                "function": {
                    "name": func.__name__,
                    "description": desc,
                    "parameters": parameters,
                }
            })
        return tools

    def get_response(self, prompt, user_id=None, history=None):
        if not self.api_configured: return "AI 閘道未配置。"
        
        from models import ElderProfile
        profile = ElderProfile.query.filter_by(user_id=user_id).first() if user_id else None
        
        system_instruction = (
            f"你是一位親切的長輩陪伴助手。{self._get_personality(profile)}\n"
            "當長輩需要幫助、詢問天氣、時間、健康建議或發生緊急狀況時，請務必使用對應的工具來獲取資訊或執行動作。"
        )
        
        messages = [{"role": "system", "content": system_instruction}]
        if history:
            # 轉換歷史格式 (從 Gemini 格式轉為 OpenAI 格式)
            for h in history:
                role = "assistant" if h["role"] == "model" else h["role"]
                content = h["parts"][0] if isinstance(h["parts"], list) else h["parts"]
                messages.append({"role": role, "content": content})
        
        messages.append({"role": "user", "content": prompt})
        
        try:
            response = self.client.chat.completions.create(
                model=self.model_name,
                messages=messages,
                tools=self._get_openai_tools(),
                tool_choice="auto"
            )
            
            msg = response.choices[0].message
            if msg.tool_calls:
                # 簡單處理單次工具呼叫
                tool_call = msg.tool_calls[0]
                tool_name = tool_call.function.name
                tool_args = json.loads(tool_call.function.arguments)
                
                # 執行工具
                tool_func = next((f for f in ALL_SKILLS if f.__name__ == tool_name), None)
                if tool_func:
                    if 'user_id' in inspect.signature(tool_func).parameters:
                        tool_args['user_id'] = user_id
                    result = tool_func(**tool_args)
                    
                    # 將結果帶回 AI
                    messages.append(msg)
                    messages.append({
                        "role": "tool",
                        "tool_call_id": tool_call.id,
                        "name": tool_name,
                        "content": str(result)
                    })
                    
                    second_resp = self.client.chat.completions.create(
                        model=self.model_name,
                        messages=messages
                    )
                    return second_resp.choices[0].message.content
                
            return msg.content
        except Exception as e:
            return f"OpenClaw 回應錯誤: {str(e)}"

    def get_response_stream(self, prompt, user_id=None, history=None):
        """串流版本：暫時簡化，不處理串流下的工具呼叫 (或僅處理一次)"""
        if not self.api_configured:
            yield "AI 閘道未配置。"
            return

        from models import ElderProfile
        profile = ElderProfile.query.filter_by(user_id=user_id).first() if user_id else None
        system_instruction = f"你一位親切的長輩陪伴助手。{self._get_personality(profile)}"
        
        messages = [{"role": "system", "content": system_instruction}]
        if history:
            for h in history:
                role = "assistant" if h["role"] == "model" else h["role"]
                content = h["parts"][0] if isinstance(h["parts"], list) else h["parts"]
                messages.append({"role": role, "content": content})
        messages.append({"role": "user", "content": prompt})

        try:
            # 為了穩定性，串流模式先不啟用工具呼叫，或者在發現工具呼叫時改用非串流處理
            # 這裡先實現基本的文字串流
            stream = self.client.chat.completions.create(
                model=self.model_name,
                messages=messages,
                stream=True
            )
            for chunk in stream:
                if chunk.choices and chunk.choices[0].delta.content:
                    yield chunk.choices[0].delta.content
        except Exception as e:
            yield f"(對話中斷: {str(e)})"

gemini_service = GeminiService()
