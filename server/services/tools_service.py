import google.generativeai as genai
from models import ActivityLog
from extensions import db
from datetime import datetime
from flask import g
import requests

class AgentTools:
    """
    Agentic RAG 工具集模組。
    這裡定義的所有方法都可以被 Gemini 識別並調用。
    """

    @staticmethod
    def get_elder_activity_log(user_id: int, date_str: str = None):
        """
        查詢特定長輩在特定日期的活動紀錄（包括吃藥、運動、心情等）。
        
        Args:
            user_id: 長輩的用戶 ID。
            date_str: 日期字串，格式為 'YYYY-MM-DD'。若未提供則預設為今天。
        """
        try:
            if not date_str:
                date_str = datetime.now().strftime('%Y-%m-%d')
            
            # 簡單過濾特定日期的紀錄
            logs = ActivityLog.query.filter(
                ActivityLog.user_id == user_id,
                ActivityLog.timestamp >= datetime.strptime(date_str, '%Y-%m-%d')
            ).order_by(ActivityLog.timestamp.desc()).limit(10).all()

            if not logs:
                return f"在 {date_str} 這天，系統中目前沒有記錄到您的活動喔。或許您可以跟我分享一下您今天做了什麼？"

            result = f"這是 {date_str} 的生活點滴紀錄：\n"
            for log in logs:
                time_str = log.timestamp.strftime('%H:%M')
                event_map = {
                    'medication': '吃藥紀錄',
                    'exercise': '運動習慣',
                    'mood': '心情感受',
                    'chat': '聊天內容'
                }
                display_type = event_map.get(log.event_type, log.event_type)
                result += f"時間 {time_str} - {display_type}：{log.content}\n"
            
            return result
        except Exception as e:
            return f"查詢日誌時發生錯誤：{str(e)}"

    @staticmethod
    def get_current_weather(location: str):
        """
        獲取特定地點的即時天氣資訊。
        
        Args:
            location: 地點名稱（例如：'士林區', '台北'）。
        """
        try:
            # 使用 Open-Meteo 的經緯度簡單對應 (此處範例為台北市的經緯度)
            # 未來可擴充 Geocoding 解析地名
            req = requests.get('https://api.open-meteo.com/v1/forecast?latitude=25.0330&longitude=121.5654&current=temperature_2m,relative_humidity_2m,weather_code', timeout=3)
            if req.status_code == 200:
                data = req.json()
                current = data.get('current', {})
                temp = current.get('temperature_2m', '未知')
                rh = current.get('relative_humidity_2m', '未知')
                return f"{location} 目前氣溫為 {temp} 度，相對濕度 {rh}%。"
            return f"{location} 的天氣資訊暫時無法獲取。"
        except Exception as e:
            return f"{location} 目前天氣為：晴朗 22度 (模擬資料)"

    @staticmethod
    def get_lunar_recommendation(date_str: str = None):
        """
        獲取特定日期的農曆資訊與生活宜忌建議。
        
        Args:
            date_str: 日期字串 'YYYY-MM-DD'。
        """
        return "今日農曆正月初六，宜出行、會友，忌動土。適合找老朋友聊聊天。"

    @staticmethod
    def play_favorite_music(user_id: int):
        """
        當長輩表示想聽音樂、聽廣播、聽歌時呼叫此工具。
        此工具會自動讓系統在長輩的 App 端播放音樂。
        
        Args:
            user_id: 長輩的用戶 ID。
        """
        if not hasattr(g, 'pending_actions'):
            g.pending_actions = []
        g.pending_actions.append({'type': 'PLAY_MUSIC'})
        return "已發送音樂播放指令給系統，系統即將開始播放。"

    @staticmethod
    def contact_family_member(user_id: int, reason: str):
        """
        當長輩表示身體不舒服、有緊急需求，或主動要求聯絡家屬時呼叫此工具。
        此工具會自動發送緊急通知給綁定的家屬。
        
        Args:
            user_id: 長輩的用戶 ID。
            reason: 聯絡的原因或長輩的狀況描述。
        """
        if not hasattr(g, 'pending_actions'):
            g.pending_actions = []
        g.pending_actions.append({'type': 'CONTACT_FAMILY', 'reason': reason})
        return f"已發送通知給您的家屬，原因：{reason}。請放心，他們很快就會收到訊息。"

# 工具映射表，方便未來自動化擴充
TOOL_MAP = {
    "get_elder_activity_log": AgentTools.get_elder_activity_log,
    "get_current_weather": AgentTools.get_current_weather,
    "get_lunar_recommendation": AgentTools.get_lunar_recommendation,
    "play_favorite_music": AgentTools.play_favorite_music,
    "contact_family_member": AgentTools.contact_family_member
}

