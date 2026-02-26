import google.generativeai as genai
from models import ActivityLog
from extensions import db
from datetime import datetime

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
            location: 地地點名稱（例如：'士林區', '台北'）。
        """
        # 這裡未來可以對接真實 Weather API (如 OpenWeather)
        # 目前先回傳模擬數據以供 Agent 邏輯測試
        return f"{location} 目前天氣晴朗，氣溫約 22 度，適合外出散步。"

    @staticmethod
    def get_lunar_recommendation(date_str: str = None):
        """
        獲取特定日期的農曆資訊與生活宜忌建議。
        
        Args:
            date_str: 日期字串 'YYYY-MM-DD'。
        """
        # 未來對接 lunar 庫
        return "今日農曆正月初六，宜出行、會友，忌動土。適合找老朋友聊聊天。"

# 工具映射表，方便未來自動化擴充
TOOL_MAP = {
    "get_elder_activity_log": AgentTools.get_elder_activity_log,
    "get_current_weather": AgentTools.get_current_weather,
    "get_lunar_recommendation": AgentTools.get_lunar_recommendation
}
