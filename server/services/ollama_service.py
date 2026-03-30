import json
import ollama
import os
import re
from skills import ALL_SKILLS

class OllamaService:
    def __init__(self, model_name="llama3-groq-tool-use:8b"):
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
                if name == 'user_id': continue
                
                ptype = "string"
                if param.annotation == int: ptype = "integer"
                elif param.annotation == float: ptype = "number"
                elif param.annotation == bool: ptype = "boolean"
                
                properties[name] = {"type": ptype}
                if param.default is inspect.Parameter.empty:
                    required.append(name)
            
            schemas.append({
                "type": "function",
                "function": {
                    "name": func.__name__,
                    "description": doc.split('\n')[0],
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
            base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            file_path = os.path.join(base_dir, 'agent', filename)
            if os.path.exists(file_path):
                print(f"--- [Agent] 讀取設定檔: {file_path} (成功) ---")
                with open(file_path, 'r', encoding='utf-8') as f:
                    return f.read()
            # print(f"--- [Agent] 設定檔不存在: {file_path} (略過) ---")
            return ""
        except Exception as e:
            print(f"Error loading {filename}: {e}")
            return ""

    def _to_traditional(self, text):
        """將常見簡體字轉換為繁體字並處理在地用語轉換"""
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
            '视': '視', '览': '覽', '过': '過', '离': '離', '难': '難', 
            '内': '內', '容': '容', '总': '總', '统': '統', '经': '經', '济': '濟', 
            '测': '測', '验': '驗', '查': '查', '办': '辦', '频': '頻', '线': '線',
            '联': '聯', '网': '網', '络': '絡'
        }
        word_mapping = {
            '视频': '影片', '服务器': '伺服器', '程序': '程式', '手机': '手機', '软件': '軟體'
        }
        for s, t in word_mapping.items():
            text = text.replace(s, t)
        for s, t in mapping.items():
            text = text.replace(s, t)
        return text

    def _clean_response(self, text):
        """清潔 AI 的回覆：移除可能出現的 Metadata 標籤與幻覺連結"""
        if not text: return text
        
        # 1. 移除開頭的大寫英文標籤
        text = re.sub(r'^[A-Z\s!:]+\s*(!|:)\s*', '', text.strip())
        text = re.sub(r'(?i)^(NIGHT|MORNING|AFTERNOON|EVENING|HELLO|AI_RESPONSE|MOOD)\s*[!！:：]\s*', '', text).strip()
        
        # 2. --- [YouTube URL Interceptor] ---
        video_id_match = re.search(r'(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\/)([a-zA-Z0-9_-]{11})', text)
        found_video_id = None
        if video_id_match:
            found_video_id = video_id_match.group(1)
            if found_video_id == "example_video_id":
                found_video_id = None
        
        search_query_match = re.search(r'youtube\.com\/results\?search_query=([^&\s\)]+)', text)
        if search_query_match and not found_video_id:
            from urllib.parse import unquote
            query = unquote(search_query_match.group(1).replace('+', ' '))
            print(f"--- [Fallback] Intercepted youtube search URL: {query} ---")
            try:
                from skills.common_skills import search_youtube_video
                result = search_youtube_video(query)
                id_in_result = re.search(r'\[VIDEO_ID:([^\]]+)\]', result)
                if id_in_result:
                    found_video_id = id_in_result.group(1)
            except Exception as e:
                print(f"Fallback search error: {e}")

        # 3. 移除所有已知形式的網址與 Markdown 連結
        text = re.sub(r'!\[.*?\]\(.*?\)', '', text)
        text = re.sub(r'\[.*?\]\(.*?\)', '', text)
        text = re.sub(r'https?:\/\/(?:www\.)?(?:youtube\.com|youtu\.be)\/\S+', '', text)
        
        # 4. --- [Skill Call Interceptor] ---
        youtube_pattern = r'search_youtube_video\s*\(\s*["\']([^"\']+)["\']\s*\)'
        youtube_match = re.search(youtube_pattern, text)
        if youtube_match and not found_video_id:
            query = youtube_match.group(1)
            try:
                from skills.common_skills import search_youtube_video
                result = search_youtube_video(query)
                id_in_result = re.search(r'\[VIDEO_ID:([^\]]+)\]', result)
                if id_in_result: found_video_id = id_in_result.group(1)
            except Exception: pass
        
        text = re.sub(r'[`]{1,3}[^`]*?search_youtube_video[^`]*?[`]{1,3}', '', text).strip()
        text = re.sub(r'(?i)[\w]*?search_youtube_video\s*\([^)]*\)', '', text).strip()
        
        text = re.sub(r'請點擊(.*?)(連結|影片|播放)(.*?)聆聽[：:]?', '', text).strip()
        text = re.sub(r'點擊(.*?)(連結|影片|播放)', '', text).strip()
        text = re.sub(r'前往\s*YouTube\s*聆聽[：:]', '', text).strip()
        
        # 3. 移除 XML 標籤（如 <thinking>, <call> 等）
        text = re.sub(r'<thought>.*?</thought>', '', text, flags=re.DOTALL).strip()
        text = re.sub(r'<thinking>.*?</thinking>', '', text, flags=re.DOTALL).strip()
        text = re.sub(r'<[^>]+>.*?</[^>]+>', '', text, flags=re.DOTALL).strip()
        text = re.sub(r'<[^>]+>', '', text).strip()
        
        if found_video_id and f"[VIDEO_ID:{found_video_id}]" not in text:
            text += f"\n\n[VIDEO_ID:{found_video_id}]"
            
        text = re.sub(r'example_video_id', '', text).strip()
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

    # ─────────────────────────────────────────────────────────────────────

    def _prepare_messages(self, prompt, user_id, history):
        from models import ElderProfile
        profile = ElderProfile.query.filter_by(user_id=user_id).first() if user_id else None
        
        # 1. 讀取各項設定檔
        soul_content = self._load_agent_file('SOUL.md')
        memory_content = self._load_agent_file('MEMORY.md')
        user_content = self._load_agent_file('USER.md')
        song_content = self._load_agent_file('KNOWLEDGE_SONGS.md')
        
        # 2. 建構人格與基本指令 (System Role)
        personality = self._get_personality(profile)
        system_instruction = (
            "你是一位親切、耐心且對長輩極度溫潤的台灣在地陪伴助手。\n"
            "### 【核心人格與原則】\n"
            f"{personality}\n\n"
            "### 【最高優先規則：語言與口吻】\n"
            "1. **絕對繁體中文**：全程僅限使用「繁體中文（zh-TW）」回覆。嚴禁簡體字，嚴禁英文（除非是專有名詞）。\n"
            "2. **在地感**：使用台灣慣用語（例：影片、軟體）。\n"
        )
        
        # 3. 建構核心事實區塊 (稍後注入)
        fact_context = "### 【核心事實：你必須記住的長輩資訊】\n"
        if user_content:
            fact_context += f"#### 長輩基本資料 (USER.md):\n{user_content}\n"
        if memory_content:
            fact_context += f"#### 重要長期記憶 (MEMORY.md):\n{memory_content}\n"
        if not user_content and not memory_content:
            fact_context += "（目前尚無特定的長輩記憶資料）\n"

        # 4. 建構影音播放規則
        media_instruction = (
            "### 【影音播放工具使用規則】\n"
            "▶ 觸發：當長輩明確要求「想聽」、「播放」或詢問特定歌手/歌曲時。\n"
            "▶ 動作：呼叫 `search_youtube_video` 工具。回覆中嚴禁出現任何網址或 [VIDEO_ID] 標籤。\n"
        )

        messages = [
            {"role": "system", "content": system_instruction},
            {"role": "system", "content": fact_context},
            {"role": "system", "content": media_instruction}
        ]
        
        # 5. 注入對話歷史
        if history:
            for h in history:
                role = "assistant" if h.get("role") == "model" else h.get("role", "user")
                content = h.get("parts", [""])[0] if isinstance(h.get("parts"), list) else ""
                messages.append({"role": role, "content": content})
                
        # 6. 當前使用者提問與「最後提醒」
        messages.append({
            "role": "user", 
            "content": f"{prompt}\n\n(注意：請基於上述「核心事實」與「靈魂核心」進行回覆。務必使用台灣繁體中文，絕對不可使用英文。)"
        })
        
        # 輸出日誌：方便使用者在終端機確認內容
        print(f"--- [Prompt Context Check] ---")
        print(f"Memory Loaded: {len(memory_content) > 0}, Fact Block Strings: {len(fact_context)} chars")
        if memory_content:
            # 擷取記憶中的一部分來確認讀取
            short_mem = memory_content.replace('\n', ' ')[:50]
            print(f"Memory Snapshot: {short_mem}...")
        print(f"--- [Prompt Context Check Done] ---")
        
        return messages

    def get_response(self, prompt, user_id=None, history=None):
        try:
            messages = self._prepare_messages(prompt, user_id, history)
            response = ollama.chat(
                model=self.model_name,
                messages=messages,
                tools=self._tool_schemas
            )
            
            # 追蹤所有工具結果，方便最後補上 VIDEO_ID
            tool_results = []
            
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
                    
                    print(f"--- [Ollama] Tool result: {str(tool_result)[:100]} ---")
                    tool_results.append(str(tool_result))
                    messages.append({'role': 'tool', 'content': str(tool_result), 'name': tool_name})
                    
                response = ollama.chat(
                    model=self.model_name,
                    messages=messages,
                    tools=self._tool_schemas
                )

            # 清理 AI 的自然語言回覆
            final_text = self._clean_response(response['message']['content'])
            
            # 【保障機制】若工具結果中有 VIDEO_ID，且最終文字仍未包含，則補上
            if "[VIDEO_ID:" not in final_text:
                for result_str in tool_results:
                    match = re.search(r'\[VIDEO_ID:([^\]]+)\]', result_str)
                    if match:
                        video_id = match.group(1)
                        print(f"--- [Ollama] Appending VIDEO_ID from tool result: {video_id} ---")
                        final_text += f"\n\n[VIDEO_ID:{video_id}]"
                        break
            
            return final_text
            
        except Exception as e:
            print(f"!!! [Ollama] Error: {e}")
            return f"AI 回應發生錯誤: {str(e)}"

    def _execute_tool(self, name, args, user_id):
        try:
            func = next((f for f in ALL_SKILLS if f.__name__ == name), None)
            if not func:
                return f"找不到工具 {name}。"
            
            import inspect
            sig = inspect.signature(func)
            if 'user_id' in sig.parameters:
                args['user_id'] = user_id
            
            return func(**args)
        except Exception as e:
            print(f"--- [Tool Execute Error] {name}: {e} ---")
            return f"執行工具 {name} 時發生錯誤：{str(e)}"

    def get_response_stream(self, prompt, user_id=None, history=None):
        try:
            messages = self._prepare_messages(prompt, user_id, history)
            print(f"--- [Ollama Stream] Starting request for user {user_id} ---")
            
            # 追蹤所有工具結果
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
                        print(f"--- [Ollama Stream] AI requested tool: {tool_name} with {tool_args} ---")
                        
                        tool_result = self._execute_tool(tool_name, tool_args, user_id)
                        print(f"--- [Ollama Stream] Tool result: {str(tool_result)[:120]} ---")
                        tool_results.append(str(tool_result))
                        messages.append({'role': 'tool', 'content': str(tool_result), 'name': tool_name})
                    continue
                
                # 【關鍵修復】先累積完整回應，再做一次性清理，避免 [VIDEO_ID] 被切斷
                full_response = ""
                for chunk in ollama.chat(
                    model=self.model_name,
                    messages=messages,
                    stream=True
                ):
                    if 'message' in chunk and 'content' in chunk['message']:
                        full_response += chunk['message']['content']
                
                # 對完整回應做一次清理後再 yield
                cleaned_response = self._clean_response(full_response)
                
                # 【保障機制】若工具結果有 VIDEO_ID，確保附加到最終文字
                if "[VIDEO_ID:" not in cleaned_response:
                    for result_str in tool_results:
                        match = re.search(r'\[VIDEO_ID:([^\]]+)\]', result_str)
                        if match:
                            video_id = match.group(1)
                            print(f"--- [Ollama Stream] Appending VIDEO_ID from tool: {video_id} ---")
                            cleaned_response += f"\n\n[VIDEO_ID:{video_id}]"
                            break
                
                if cleaned_response.strip():
                    yield cleaned_response
                break
                    
        except Exception as e:
            print(f"!!! [Ollama Stream] Fatal error: {str(e)}")
            yield f"(對話中斷或工具呼叫異常: {str(e)})"

ollama_service = OllamaService()
