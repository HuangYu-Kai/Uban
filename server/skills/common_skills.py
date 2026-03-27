from datetime import datetime
import requests

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

def update_agent_memory(filename: str, content: str):
    """更新長輩的長期記憶庫 (MEMORY.md) 或使用者基本資料 (USER.md)。
    當你在對話中得知重要訊息（如：孫子姓名、藥物種類、興趣習慣）時，應主動更新對應檔案。
    
    Args:
        filename: 要更新的檔案名稱 (限 'MEMORY.md' 或 'USER.md')
        content: 更新後的完整 Markdown 內容 (請保留既有資訊並加上新的發現)
    """
    import os
    if filename not in ['MEMORY.md', 'USER.md']:
        return "錯誤：目前僅支援更新 MEMORY.md 與 USER.md。"
    
    try:
        # 根據目錄結構定位 server/agent/
        base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        file_path = os.path.join(base_dir, 'agent', filename)
        
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
            
        return f"✅ 已成功更新 {filename}！我現在已經記住這些重要細節了。"
    except Exception as e:
        return f"❌ 更新記憶失敗：{str(e)}"
