import json
import ollama
import os
import re
from datetime import datetime
from skills import ALL_SKILLS

class OllamaService:
    def __init__(self, model_name="qwen2.5:14b"):
        self.model_name = model_name
        # 快取工具的 OpenAI-like Schemas
        self._tool_schemas = self._generate_tool_schemas(ALL_SKILLS)

    def _generate_tool_schemas(self, functions):
        """將 Python 函數列表轉換為 Ollama 期望的 JSON Schemas"""
        import inspect
        schemas = []
        for func in functions:
            sig = inspect.signature(func)
            doc = inspect.getdoc(func) or "No description provided."
            
            parameters = {
                "type": "object",
                "properties": {},
                "required": []
            }
            
            for name, param in sig.parameters.items():
                if name == 'user_id': continue
                
                # 簡單推斷類型
                p_type = "string"
                if param.annotation == int: p_type = "integer"
                elif param.annotation == bool: p_type = "boolean"
                
                parameters["properties"][name] = {
                    "type": p_type,
                    "description": f"Parameter {name}"
                }
                if param.default == inspect.Parameter.empty:
                    parameters["required"].append(name)
            
            schemas.append({
                "type": "function",
                "function": {
                    "name": func.__name__,
                    "description": doc,
                    "parameters": parameters
                }
            })
        return schemas

    def _load_agent_file(self, filename):
        """讀取 server/agent/ 目錄下的 Markdown 設定檔"""
        try:
            base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            file_path = os.path.join(base_dir, 'agent', filename)
            if os.path.exists(file_path):
                with open(file_path, 'r', encoding='utf-8') as f:
                    return f.read()
            return ""
        except Exception:
            return ""

    def _to_traditional(self, text):
        """簡單的簡轉繁 (針對常見關鍵字)"""
        replacements = {
            "视频": "影片", "软件": "軟體", "网络": "網路", "由于": "由於",
            "联系": "聯繫", "号码": "號碼", "设置": "設定", "信息": "資訊"
        }
        for k, v in replacements.items():
            text = text.replace(k, v)
        return text

    def _clean_response(self, text):
        """清理 AI 回應中的技術標記與多餘空行"""
        found_video_id = None
        match = re.search(r'\[VIDEO_ID:([^\]]+)\]', text)
        if match:
            found_video_id = match.group(1)
            text = re.sub(r'\[VIDEO_ID:[^\]]+\]', '', text)

        text = re.sub(r'<thought>.*?</thought>', '', text, flags=re.DOTALL).strip()
        text = re.sub(r'<thinking>.*?</thinking>', '', text, flags=re.DOTALL).strip()
        text = re.sub(r'<[^>]+>.*?</[^>]+>', '', text, flags=re.DOTALL).strip()
        text = re.sub(r'<[^>]+>', '', text).strip()
        
        if found_video_id and f"[VIDEO_ID:{found_video_id}]" not in text:
            text += f"\n\n[VIDEO_ID:{found_video_id}]"
            
        return self._to_traditional(text)

    def _get_personality(self, profile):
        """生成 AI 性格指令，優先讀取 SOUL.md"""
        soul_content = self._load_agent_file('SOUL.md')
        identity_content = self._load_agent_file('IDENTITY.md')
        
        personality = ""
        if soul_content:
            personality += f"\n### 你的靈魂核心 (SOUL.md):\n{soul_content}\n"
        if identity_content:
            personality += f"\n### 你的身分 (IDENTITY.md):\n{identity_content}\n"
            
        if not soul_content and profile:
            tone = "客觀專業" if profile.ai_emotion_tone < 50 else "熱情親切"
            verb = "簡潔扼要" if profile.ai_text_verbosity < 50 else "詳細會聊天"
            personality += f"你的性格關鍵字：{tone}、{verb}。對長輩的稱呼應使用「{profile.elder_appellation or '您'}」。"
            
        return personality

    def _prepare_messages(self, prompt, user_id, history):
        from models import ElderProfile
        profile = ElderProfile.query.filter_by(user_id=user_id).first() if user_id else None
        
        memory_content = self._load_agent_file('MEMORY.md')
        user_content = self._load_agent_file('USER.md')
        
        memory_rule = (
            "### 【重要：強勢紀錄規則】\n"
            "作為陪伴者，你必須「記住長輩的一切」。\n"
            "▶ 觸發：長輩提到任何關於自己、家人、往事、喜好、健康、心情時。\n"
            "▶ 動作：你必須『先』呼叫 `save_elder_memory` 工具記錄事實內容，『後』再進行對話。\n"
            "▶ 要求：即使資訊微小也請記錄。記錄後請溫暖告知長輩你已幫他記住了。\n"
        )

        personality = self._get_personality(profile)
        system_instruction = (
            "你是一位親切陪伴助手。\n"
            "### 【靈魂核心】\n"
            f"{personality}\n\n"
            "1. **絕對繁體中文**：全程限用繁體中文回覆。嚴禁英文、嚴禁簡體字。\n"
            "2. **語氣**：溫順、親切。\n"
        )
        
        fact_context = "### 【已知的長輩個人資訊】\n"
        if user_content: fact_context += f"{user_content}\n"
        if memory_content: fact_context += f"{memory_content}\n"
        
        messages = [
            {"role": "system", "content": memory_rule},
            {"role": "system", "content": system_instruction},
            {"role": "system", "content": fact_context}
        ]
        
        if history:
            for h in history:
                role = "assistant" if h.get("role") == "model" else h.get("role", "user")
                content = h.get("parts", [""])[0] if isinstance(h.get("parts"), list) else ""
                messages.append({"role": role, "content": content})
                
        messages.append({
            "role": "user", 
            "content": f"{prompt}\n\n(注意：請絕對使用繁體中文。若得知新事實，請務必先呼叫 save_elder_memory。)"
        })
        
        return messages

    def get_response_stream(self, prompt, user_id=None, history=None):
        try:
            messages = self._prepare_messages(prompt, user_id, history)
            tool_results = []

            while True:
                res = ollama.chat(
                    model=self.model_name,
                    messages=messages,
                    tools=self._tool_schemas,
                    stream=False
                )
                
                if res.get('message', {}).get('tool_calls'):
                    msg = res['message']
                    messages.append(msg)
                    for tool_call in msg['tool_calls']:
                        tool_name = tool_call['function']['name']
                        tool_args = tool_call['function'].get('arguments', {})
                        print(f"--- [Ollama] 使用工具: {tool_name} ---")
                        
                        tool_result = self._execute_tool(tool_name, tool_args, user_id)
                        tool_results.append(str(tool_result))
                        messages.append({'role': 'tool', 'content': str(tool_result), 'name': tool_name})
                    continue
                
                full_response = ""
                for chunk in ollama.chat(
                    model=self.model_name,
                    messages=messages,
                    stream=True
                ):
                    if 'message' in chunk and 'content' in chunk['message']:
                        full_response += chunk['message']['content']
                
                cleaned_response = self._clean_response(full_response)
                # 附加 VIDEO_ID (若有)
                for res_str in tool_results:
                    match = re.search(r'\[VIDEO_ID:([^\]]+)\]', res_str)
                    if match:
                        cleaned_response += f"\n\n[VIDEO_ID:{match.group(1)}]"
                        break
                
                if cleaned_response.strip():
                    yield cleaned_response
                break
        except Exception as e:
            yield f"(服務中斷: {str(e)})"

    def _execute_tool(self, name, args, user_id):
        try:
            func = next((f for f in ALL_SKILLS if f.__name__ == name), None)
            if not func: return "工具未找到。"
            import inspect
            sig = inspect.signature(func)
            if 'user_id' in sig.parameters: args['user_id'] = user_id
            return func(**args)
        except Exception as e:
            return f"執行錯誤: {str(e)}"

ollama_service = OllamaService()
