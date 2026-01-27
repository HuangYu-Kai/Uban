import os
import asyncio
import pygame
import datetime
from openai import OpenAI
import edge_tts
from duckduckgo_search import DDGS

# --- 設定區 ---
NVIDIA_API_KEY = "-"  # ★★★ 請填回您的 NVIDIA API Key ★★★
TTS_VOICE = "zh-TW-HsiaoYuNeural" 

# --- 初始化客戶端 ---
client = OpenAI(
    base_url="https://integrate.api.nvidia.com/v1",
    api_key=NVIDIA_API_KEY
)

# --- 工具函式 ---
def get_current_time_str():
    now = datetime.datetime.now()
    week_days = ["一", "二", "三", "四", "五", "六", "日"]
    weekday = week_days[now.weekday()]
    return now.strftime(f"%Y年%m月%d日 星期{weekday} %p %I:%M")

def search_web(query):
    print(f"   [系統] 執行聯網搜尋: {query}...")
    try:
        results = DDGS().text(query, region="wt-wt", max_results=3) 
        if results:
            context_str = ""
            for i, res in enumerate(results):
                context_str += f"{i+1}. {res['body']}\n"
            print(f"   [系統] 搜尋成功，取得 {len(results)} 筆資料")
            return context_str
    except Exception as e:
        print(f"   [搜尋失敗]: {e}")
    return ""

async def speak_response(text):
    output_file = "temp_response.mp3"
    communicate = edge_tts.Communicate(text, TTS_VOICE, rate="-20%")
    await communicate.save(output_file)
    try:
        pygame.mixer.init()
        pygame.mixer.music.load(output_file)
        pygame.mixer.music.play()
        while pygame.mixer.music.get_busy():
            await asyncio.sleep(0.1)
        pygame.mixer.music.unload()
        pygame.mixer.quit()
        if os.path.exists(output_file):
            os.remove(output_file)
    except Exception as e:
        print(f"[播放錯誤]: {e}")

# --- 【核心新功能】意圖判斷 (AI 路由) ---
def check_intent(user_input):
    """
    讓 AI 判斷使用者的意圖是 [閒聊] 還是 [查資料]
    """
    print("   [系統] 正在思考要不要上網...")
    
    prompt = f"""
    你是一個意圖分類器。請分析使用者的輸入。
    
    規則：
    1. 如果使用者問的是：天氣、新聞、即時資訊、特定知識、價格、地點、或是你不知道的事實。 -> 回答 "SEARCH"
    2. 如果使用者是：打招呼、閒聊、問你的名字、問候身體、情感抒發、翻譯句子。 -> 回答 "CHAT"
    
    只回答 "SEARCH" 或 "CHAT"，不要有其他文字。
    
    使用者輸入："{user_input}"
    """

    try:
        response = client.chat.completions.create(
            model="yentinglin/llama-3-taiwan-70b-instruct",
            messages=[{"role": "user", "content": prompt}],
            temperature=0.1, # 溫度低一點，讓判斷更準確固定
            max_tokens=10
        )
        intent = response.choices[0].message.content.strip()
        # 清理一下可能的雜訊 (有些模型會回 "Answer: SEARCH")
        if "SEARCH" in intent: return "SEARCH"
        return "CHAT"
    except:
        return "CHAT" # 發生錯誤預設就當閒聊

# --- 主程式 ---
async def main():
    print(f"=== 台語 AI 萬事通 (智慧路由版) ===")
    
    # 這裡可以存放對話歷史，讓它有短期記憶
    conversation_history = [] 

    while True:
        user_input = await asyncio.to_thread(input, "\n你：")
        
        if user_input.lower() in ["exit", "quit", "離開"]:
            print("AI：多謝你的使用，再會！")
            await speak_response("多謝你的使用，再會！")
            break
        
        current_time = get_current_time_str()
        web_context = ""
        
        # 1. 第一階段：AI 判斷意圖
        intent = await asyncio.to_thread(check_intent, user_input)
        
        if intent == "SEARCH":
            print("   [判定] 需要上網查詢資料 (SEARCH)")
            # 如果需要搜尋，去網路上抓資料
            # 這裡我們直接把使用者的整句話拿去搜尋，通常效果就不錯
            search_result = await asyncio.to_thread(search_web, user_input)
            if search_result:
                web_context = f"\n【網路即時資料】:\n{search_result}\n"
        else:
            print("   [判定] 純閒聊或記憶回答 (CHAT)")

        # 2. 第二階段：正式回答
        system_prompt = f"""
        現在時間是：{current_time}。
        你是一個精通「臺灣閩南語（台語）」的 AI 助理。
        請根據使用者的問題回答。
        
        規則：
        1. 優先使用「全漢字」或「漢羅混寫」回答。
        2. 語氣要親切、像在跟長輩聊天。
        3. 如果有提供【網路即時資料】，請根據資料回答；如果沒有，請依照你的知識庫回答。
        4. 回答要簡短，適合語音播報。
        """

        # 組合當次對話 (不使用累積歷史，避免 System Prompt 被擠掉，或 RAG 資料混亂)
        # 若需要記憶，可以將 conversation_history 加進來，但要小心 token 上限
        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": f"{web_context}使用者問題：{user_input}"}
        ]

        try:
            completion = client.chat.completions.create(
                model="yentinglin/llama-3-taiwan-70b-instruct",
                messages=messages,
                temperature=0.5,
                max_tokens=1024,
                stream=True
            )

            print("AI：", end="")
            full_response = ""

            for chunk in completion:
                if chunk.choices[0].delta.content is not None:
                    content = chunk.choices[0].delta.content
                    print(content, end="", flush=True)
                    full_response += content
            
            print() 

            if full_response.strip():
                await speak_response(full_response)

        except Exception as e:
            print(f"發生錯誤: {e}")

if __name__ == "__main__":
    asyncio.run(main())