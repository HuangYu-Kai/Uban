import os
import asyncio
import pygame
import datetime
from collections import deque
from openai import OpenAI
import edge_tts
# 這裡使用官方建議的標準引入方式
from duckduckgo_search import DDGS 

# --- 設定區 ---
# ★★★ 請確認您的 API Key ★★★
NVIDIA_API_KEY = "nvapi----" 
TTS_VOICE = "zh-TW-HsiaoYuNeural" 

# --- 初始化客戶端 ---
client = OpenAI(
    base_url="https://integrate.api.nvidia.com/v1",
    api_key=NVIDIA_API_KEY
)

# 記憶佇列
conversation_history = deque(maxlen=10)

# --- 工具函式 ---
def get_current_time_str():
    now = datetime.datetime.now()
    week_days = ["一", "二", "三", "四", "五", "六", "日"]
    weekday = week_days[now.weekday()]
    return now.strftime(f"%Y年%m月%d日")

# ★★★ 修改後的搜尋函式 (使用 with DDGS() 模式) ★★★
def search_web(user_query):
    # 1. 關鍵字優化
    search_term = user_query
    # 針對菜價特別優化搜尋詞
    if "菜" in user_query and ("價" in user_query or "便宜" in user_query):
        search_term = f"{get_current_time_str()} 台灣 蔬菜批發行情"
    elif "天氣" in user_query:
        search_term = f"{user_query} 氣象"
    
    print(f"   [系統] 正在搜尋: {search_term}...")

    try:
        # 2. 使用 Context Manager (with 語法)
        # 這能避免 socket 佔用問題，大幅減少連線錯誤
        with DDGS() as ddgs:
            # backend="html" 是最穩定的模式，模擬傳統網頁請求
            results = ddgs.text(
                keywords=search_term,
                region="wt-wt", # 台灣地區
                backend="html", # 關鍵：抗封鎖模式
                max_results=5
            )
            
            context_str = ""
            if results:
                count = 0
                for res in results:
                    count += 1
                    # 抓取標題與內文
                    context_str += f"[{count}] {res['title']}: {res['body']}\n"
                
                print(f"   [系統] 搜尋成功，取得 {count} 筆資料")
                return context_str
            else:
                print("   [系統] 搜尋結果為空 (可能無相關資料)")
                return ""
            
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

# --- 意圖判斷 ---
def check_intent(user_input):
    print("   [系統] 思考意圖中...")
    # 關鍵字快篩
    keywords = ["天氣", "氣溫", "價格", "多少錢", "誰", "哪裡", "便宜", "新聞", "比分", "幾度"]
    if any(k in user_input for k in keywords):
        return "SEARCH"

    # AI 複查
    prompt = f"""
    判斷使用者意圖。
    需聯網查詢(如天氣、價格、新聞、事實) -> 回答 "SEARCH"
    閒聊或記憶 -> 回答 "CHAT"
    使用者輸入："{user_input}"
    """
    try:
        response = client.chat.completions.create(
            model="yentinglin/llama-3-taiwan-70b-instruct",
            messages=[{"role": "user", "content": prompt}],
            temperature=0.1,
            max_tokens=5
        )
        intent = response.choices[0].message.content.strip().upper()
        if "SEARCH" in intent: return "SEARCH"
        return "CHAT"
    except:
        return "CHAT"

# --- 主程式 ---
async def main():
    print(f"=== AI 小幫手 ===")
    
    base_system_prompt = """
    你是一個精通「臺灣閩南語（台語）」的 AI 助理。
    
    規則：
    1. 優先使用「一般台灣中文」回答，避免使用流行用語。
    2. 語氣要親切、像在跟長輩聊天。
    3. 記住使用者的名字。
    4. 若有【網路搜尋資料】，請根據資料中的數字回答(例如菜價、溫度)；若無，則老實說不知道。
    5. 回答盡量簡短。
    """

    while True:
        user_input = await asyncio.to_thread(input, "\n你：")
        
        if user_input.lower() in ["exit", "quit", "離開"]:
            print("AI：多謝你的使用，再會！")
            await speak_response("多謝你的使用，再會！")
            break
        
        intent = await asyncio.to_thread(check_intent, user_input)
        
        web_context = ""
        
        if intent == "SEARCH":
            print("   [判定] 需要聯網 (SEARCH)")
            search_result = await asyncio.to_thread(search_web, user_input)
            if search_result:
                web_context = f"\n【網路搜尋資料】:\n{search_result}\n"
        else:
            print("   [判定] 使用記憶/閒聊 (CHAT)")

        # 組合 Prompt
        messages = [{"role": "system", "content": base_system_prompt}]
        messages.extend(conversation_history)
        final_user_content = f"{web_context}使用者說：{user_input}"
        messages.append({"role": "user", "content": final_user_content})

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
                conversation_history.append({"role": "user", "content": user_input})
                conversation_history.append({"role": "assistant", "content": full_response})
                await speak_response(full_response)

        except Exception as e:
            print(f"發生錯誤: {e}")

if __name__ == "__main__":
    asyncio.run(main())