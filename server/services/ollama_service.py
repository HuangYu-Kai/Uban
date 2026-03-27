import json
import ollama
import os
from skills import ALL_SKILLS

class OllamaService:
    def __init__(self, model_name="qwen2.5"):
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
            
            properties = {}
            required = []
            
            for name, param in sig.parameters.items():
                # 略過讓系統注入的 user_id
                if name == 'user_id': continue
                
                ptype = "string"
                if param.annotation == int: ptype = "integer"
                elif param.annotation == float: ptype = "number"
                elif param.annotation == bool: ptype = "boolean"
                
                properties[name] = {"type": ptype}
                # 如果沒有預設值，視為必要
                if param.default is inspect.Parameter.empty:
                    required.append(name)
            
            schemas.append({
                "type": "function",
                "function": {
                    "name": func.__name__,
                    "description": doc.split('\n')[0], # 只取第一行當描述
                    "parameters": {
                        "type": "object",
                        "properties": properties,
                        "required": required
                    }
                }
            })
        return schemas

    def _load_agent_file(self, filename):
        """讀取 agent 目錄下的 .md 檔案"""
        try:
            # 取得專案根目錄 (假設在 server/ 下執行或 path 正確)
            base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            file_path = os.path.join(base_dir, 'agent', filename)
            if os.path.exists(file_path):
                with open(file_path, 'r', encoding='utf-8') as f:
                    return f.read()
            return ""
        except Exception as e:
            print(f"Error loading {filename}: {e}")
            return ""

    def _to_traditional(self, text):
        """外科手術式過濾器：將最常見的簡體字轉換為繁體字"""
        if not text: return text
        mapping = {
            '说': '說', '这': '這', '会': '會', '个': '個', '为': '為', '样': '樣', 
            '电': '電', '国': '國', '发': '發', '对': '對', '么': '麼', '时': '時', 
            '种': '種', '动': '動', '后': '後', '实': '實', '现': '現', '点': '點', 
            '还': '還', '进': '進', '学': '學', '开': '開', '鲜': '鮮', '确': '確',
            '码': '碼', '亲': '親', '爱': '愛', '觉': '覺', '听': '聽', '给': '給',
            '话': '話', '认': '認', '识': '識', '间': '間', '见': '見', '观': '觀',
            '车': '車', '书': '書', '门': '門', '习': '習', '圣': '聖', '写': '寫',
            '体': '體', '变': '變', '东': '東', '西': '西', '气': '氣', '运': '運',
            '乐': '樂', '园': '園', '场': '場', '声': '聲', '报': '報', '图': '圖',
            '传': '傳', '备': '備', '设': '設', '处': '處', '复': '複', '应': '應', 
            '义': '義', '与': '與', '业': '業', '严': '嚴', '连': '連', '选': '選', 
            '术': '術', '标': '標', '准': '準', '师': '師', '单': '單', '众': '眾', 
            '爷': '爺', '奶': '奶', '妈': '媽', '爸': '爸', '姐': '姐', '弟': '弟', 
            '视': '視', '览': '覽', '过': '過', '离': '離', '难': '難', '确': '確',
            '实': '實', '样': '樣', '内': '內', '容': '容', '总': '總', '统': '統',
            '经': '經', '济': '濟', '测': '測', '验': '驗', '查': '查', '办': '辦'
        }
        for s, t in mapping.items():
            text = text.replace(s, t)
        return text

    def _clean_response(self, text):
        """清潔 AI 的回覆：移除可能出現的 Metadata 標籤（如 NIGHT!, MOOD: 等）"""
        if not text: return text
        import re
        # 移除開頭的大寫英文標籤 (如 NIGHT!, MORNING!, AI:, 甚至是 MOOD: HAPPY)
        # 過濾規則：匹配字串開頭的一個或多個大寫單字，後面接驚嘆號或冒號
        text = re.sub(r'^[A-Z\s!:]+\s*(!|:)\s*', '', text.strip())
        # 再次針對常見拼錯或特定關鍵字進行清理
        text = re.sub(r'(?i)^(NIGHT|MORNING|AFTERNOON|EVENING|HELLO|AI_RESPONSE|MOOD)\s*[!！:：]\s*', '', text).strip()
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
        
        # 讀取長期記憶與使用者資訊
        memory_content = self._load_agent_file('MEMORY.md')
        user_content = self._load_agent_file('USER.md')
        
        instruction = (
            "你是一位親切的長輩陪伴助手。\n"
            "### 【核心指令：語系與格式】\n"
            "1. **語系限制**：務必全程使用「繁體中文（zh-TW）」，絕對禁止使用簡體字。\n"
            "2. **字碼檢查**：嚴禁出現簡體字形（如：说、为、会、这、个、鲜、确、实、样、后、听、现、亲、爱）。若輸出簡體字，視為嚴重錯誤。\n"
            "3. **在地用語**：使用台灣地區慣用語（如：影片、軟體、全家、計程車、捷運）。\n"
            f"{self._get_personality(profile)}\n"
        )
        
        if memory_content:
            instruction += f"\n### 長期記憶 (MEMORY.md):\n{memory_content}\n"
        if user_content:
            instruction += f"\n### 關於長輩 (USER.md):\n{user_content}\n"
            
        instruction += "\n### 【工具使用規範】\n"
        instruction += "1. 當長輩詢問天氣、時間、健康建議時，請呼叫對應工具。\n"
        instruction += "2. **重要：當長輩分享新資訊（如家人、回憶、姓名、藥品、愛好）時，請務必使用 `update_agent_memory` 來更新檔案，這是你保持長期記憶的唯一方式。**\n"
        instruction += "3. 在呼叫工具後，請根據工具回傳的結果，給予長輩溫暖的回應。"
        
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
            
            # 使用由 _generate_tool_schemas 產生的 JSON schemas
            response = ollama.chat(
                model=self.model_name,
                messages=messages,
                tools=self._tool_schemas
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

            return self._clean_response(response['message']['content'])
            
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
                res = ollama.chat(
                    model=self.model_name,
                    messages=messages,
                    tools=self._tool_schemas, 
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
            
            first_chunk_buffer = ""
            for chunk in stream_response:
                text = chunk.get('message', {}).get('content', '')
                if text:
                    if first_chunk_buffer is not None:
                        # 還在積累第一段緩衝區
                        first_chunk_buffer += text
                        # 如果積累到足夠長度 (例如 25 字) 或是看到換行/標點，才進行第一次清洗並輸出
                        if len(first_chunk_buffer) > 25 or any(p in text for p in ["\n", "。", "！", "？", "!", ":", "："]):
                            cleaned_start = self._clean_response(first_chunk_buffer)
                            first_chunk_buffer = None # 標記緩衝結束
                            if cleaned_start.strip():
                                yield cleaned_start
                    else:
                        # 正常輸出後續段落
                        yield self._to_traditional(text)
            
            # 如果結束了但緩衝區還有東西 (通常是極短的回覆)
            if first_chunk_buffer:
                cleaned_final = self._clean_response(first_chunk_buffer)
                if cleaned_final.strip():
                    yield cleaned_final
                    
        except Exception as e:
            print(f"!!! [Ollama Stream] Fatal error: {str(e)}")
            yield f"(對話中斷或工具呼叫異常: {str(e)})"

ollama_service = OllamaService()
