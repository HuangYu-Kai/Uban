from datetime import datetime
import requests
import re
import urllib.parse
import os

def get_current_time():
    """獲取現在的真實時間 (台灣)。格式：YYYY年MM月DD日 星期X AM/PM HH點MM分"""
    now = datetime.now()
    weekdays = ["一", "二", "三", "四", "五", "六", "日"]
    return f"現在時間是：{now.strftime('%Y年%m月%d日')} 星期{weekdays[now.weekday()]} {now.strftime('%p %I點%M分')}"

def get_weather_info(location: str = "台北"):
    """獲取指定地區的即時天氣資訊。包含氣溫與天氣概況。
    Args:
        location: 城市或地區名稱 (例如：'台北', '台中', '高雄')
    """
    try:
        # 簡單的地理編碼模擬
        city_coords = {
            "台北": (25.03, 121.56), "台中": (24.14, 120.67), "高雄": (22.62, 120.31),
            "台南": (22.99, 120.21), "桃園": (24.99, 121.30), "新竹": (24.81, 120.96)
        }
        lat, lon = city_coords.get(location, (25.03, 121.56))
        
        url = f"https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lon}&current_weather=true"
        resp = requests.get(url, timeout=5)
        data = resp.json()
        if "current_weather" in data:
            cw = data["current_weather"]
            temp = cw["temperature"]
            code = cw["weathercode"]
            # 簡易天氣代碼轉換
            status = "晴朗" if code == 0 else "多雲" if code < 50 else "有雨"
            return f"{location} 目前天氣{status}，氣溫約 {temp} 度。記得提醒長輩適時增減衣物喔！"
        return f"暫時無法獲取 {location} 的天氣資訊。"
    except Exception as e:
        return f"獲取天氣失敗：{str(e)}"

def save_elder_memory(fact: str, category: str = "重要事件"):
    """主動記錄關於長輩的重要生活事實、回憶、家人關係或健康狀況。
    當你在對話中得知長輩的具體細節（例如：兒子住在美國、以前是老師、喜歡吃紅燒肉、對某藥物過敏）時，
    請務必使用此工具永久記錄。這能讓你真正「記住」長輩的一生。
    
    Args:
        fact: 要記錄的事實描述 (例如：「長輩以前在大同公司上班，擔任工程師」)
        category: 資訊分類。可選：'重要事件', '情感偏好與習慣', '家人與關係', '健康與用藥'
    """
    valid_categories = ['重要事件', '情感偏好與習慣', '家人與關係', '健康與用藥']
    if category not in valid_categories:
        category = '重要事件'
        
    try:
        base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        file_path = os.path.join(base_dir, 'agent', 'MEMORY.md')
        
        content = ""
        if os.path.exists(file_path):
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
        else:
            # 建立基本結構
            content = "# MEMORY.md - 長期記憶庫\n\n這裡記錄了長輩生命中重要的片段。請持續從對話中提煉並更新。\n"

        header = f"## {category}"
        new_line = f"- {fact} (記錄於 {datetime.now().strftime('%Y-%m-%d')})"
        
        if header in content:
            # 在標題下方插入內容
            parts = content.split(header, 1)
            # 在標題後的第一個空行插入
            updated_content = parts[0] + header + "\n\n" + new_line + parts[1]
        else:
            # 標題不存在，直接追加
            updated_content = content.strip() + f"\n\n{header}\n\n{new_line}\n"
            
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(updated_content)
            
        return f"✅ 我已經把這件事記在心裡了：「{fact}」（已存入 {category}）"
    except Exception as e:
        return f"❌ 儲存記憶失敗：{str(e)}"

def search_youtube_video(query: str):
    """搜尋 YouTube 上的影片或音樂。當長輩想聽歌、看影片或學習新事物時使用。
    
    Args:
        query: 搜尋關鍵字 (例如：'江蕙 家後', '足球比賽集錦', '如何做紅燒肉')
    """
    # 這裡使用一個簡單的公開搜尋解析方式 (或可用 YouTube Data API)

    # 這裡使用一個簡單的公開搜尋解析方式 (或可用 YouTube Data API)
    # 為了穩定性，目前先建構一個搜尋連結並模擬回傳最相關的 ID
    # 為了避開官方不可嵌入的影片，強制補上 "歌詞版" 或 "lyrics"
    smarter_query = f"{query} 歌詞版"
    encoded_query = urllib.parse.quote(smarter_query)
    search_url = f"https://www.youtube.com/results?search_query={encoded_query}"
    
    try:
        headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"}
        response = requests.get(search_url, headers=headers, timeout=5)
        # 尋找 watch?v= 形式的 ID
        video_ids = re.findall(r"watch\?v=(\S{11})", response.text)
        
        # 精確抓取影片標題 (通常在 id="video-title" 的屬性中)
        titles = re.findall(r'id="video-title"[^>]*title="([^"]+)"', response.text)
        # 兼容性備案：有些版本標題在 aria-label 中
        if not titles:
            titles = re.findall(r'aria-label="([^"]+)"', response.text)
        
        # 過濾掉非影片標題的字眼
        clean_titles = [t for t in titles if len(t) > 3 and not any(bad in t for bad in ['YouTube', '重播', '訂閱'])]

        if video_ids:
            video_id = video_ids[0]
            # 取得最相關的一個標題
            found_title = clean_titles[0] if clean_titles else "相關影音"
            print(f"--- [YouTube Skill] Successfully found: {found_title} ({video_id}) ---")
            return f"影音搜尋結果：已找到「{found_title}」。 [VIDEO_ID:{video_id}]"
        
        print(f"--- [YouTube Skill] No video found for query: {query} ---")
        return f"我幫您找了「{query}」，但暫時沒看到合適的影片連結。"
    except Exception as e:
        return f"搜尋影音時發生錯誤：{str(e)}"

def search_web(query):
    """
    使用 DuckDuckGo 進行網頁搜尋，回傳前幾個結果的標題與摘要。
    這能幫助 AI 獲取即時資訊，避免編造虛假事實。
    """
    print(f"--- [Web Search] Searching for: {query} ---")
    
    # 嘗試 Google 搜尋 (輕量版)
    url = f"https://www.google.com/search?q={urllib.parse.quote(query)}&hl=zh-TW"
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
    }
    
    try:
        response = requests.get(url, headers=headers, timeout=10)
        # 抓取標題與摘要 (Google 傳統頁面標籤)
        # 在 <h3 ...><div ...> 結構中
        titles = re.findall(r'<h3[^>]*><div[^>]*>(.*?)</div>', response.text)
        if not titles:
            titles = re.findall(r'<h3[^>]*>(.*?)</h3>', response.text)
        
        # 簡單摘要抓取
        snippets = re.findall(r'style="-webkit-line-clamp:2"[^>]*>(.*?)</div>', response.text)
        if not snippets:
            snippets = re.findall(r'class="VwiC3b[^"]*"[^>]*>(.*?)</div>', response.text)

        if not titles:
            # 嘗試 DDG 的原始備案 (如果之前失敗，這裡可能也失敗)
            return f"目前在網路上暫時查不到關於「{query}」的實體資訊，請確認關鍵字是否正確。"

        results_text = f"關於「{query}」的網頁搜尋結果：\n\n"
        for i in range(min(4, len(titles))):
            t = re.sub(r'<[^>]+>', '', titles[i])
            s = re.sub(r'<[^>]+>', '', snippets[i]) if i < len(snippets) else "點擊進入查看詳情"
            results_text += f"{i+1}. **{t}**\n   {s}\n\n"
        
        results_text += "請根據以上真實資訊回答長輩的問題。"
        return results_text

    except Exception as e:
        print(f"Web search error: {e}")
        return f"網頁搜尋目前暫時無法連線：{str(e)}"

def get_music_recommendations(artist):
    """
    獲取指定歌手在 YouTube 上的熱門歌曲標題。
    當長輩詢問某位歌手有什麼歌、或要求推薦歌曲時，必須先使用此工具獲取真實清單。
    """
    print(f"--- [Music Skill] Getting recommendations for: {artist} ---")
    query = f"{artist} 經典歌曲"
    encoded_query = urllib.parse.quote(query)
    search_url = f"https://www.youtube.com/results?search_query={encoded_query}"
    
    try:
        headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"}
        response = requests.get(search_url, headers=headers, timeout=5)
        # YouTube 標題通常在 JSON 數據中： "title":{"runs":[{"text":"YOUR_TITLE"}]
        titles = re.findall(r'"title":\{"runs":\[\{"text":"(.*?)"\}\]', response.text)
        
        # 過濾標題 (過濾掉系統字眼與重複項)
        clean_titles = []
        seen = set()
        bad_keywords = ['YouTube', '重播', '訂閱', '首頁', '探索', '媒體庫', '更多內容']
        for t in titles:
            # 處理 unicode 轉義符
            t = t.encode('utf-8').decode('unicode-escape', errors='ignore')
            t_clean = re.sub(r'\[.*?\]|\(.*?\)|\d{4}|官方|高清|字幕|KTV|MV', '', t).strip()
            if len(t_clean) > 2 and t_clean not in seen and not any(bad in t for bad in bad_keywords):
                clean_titles.append(t)
                seen.add(t_clean)
            if len(clean_titles) >= 5: break

        if not clean_titles:
            # 備案：如果 JSON 抓不到，嘗試原始的 title=" 模式
            titles_backup = re.findall(r'title="([^"]+)"', response.text)
            clean_titles = [t for t in titles_backup if len(t) > 3 and not any(bad in t for bad in bad_keywords)][:5]

        if not clean_titles:
            return f"抱歉，我目前無法為 {artist} 自動抓取即時歌單。您可以直接告訴我想聽哪一首，我會盡力搜尋。"

        result = f"以下是關於「{artist}」在 YouTube 上的熱門搜尋結果：\n"
        for i, t in enumerate(clean_titles):
            result += f"{i+1}. {t}\n"
        result += "\n請從中挑選適合長輩的歌名進行對話，如果要播放，請調用 search_youtube_video。"
        return result
    except Exception as e:
        return f"獲取歌單時發生錯誤：{str(e)}"
