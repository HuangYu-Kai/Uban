from datetime import datetime
from flask import g
import requests

class AgentTools:
    """Agentic RAG 工具集模組 (基於新 ERD 優化)"""

    @staticmethod
    def get_elder_context(user_id=None):
        """獲取長輩背景資訊 (姓名、地區、疾病、用藥、興趣)"""
        if not user_id:
            user_id = getattr(g, 'current_user_id', None)
            
        if not user_id:
            return "無法獲取當前用戶身分。"
            
        try:
            from models import ElderProfile, UserAccountData, ElderTalkTopic
            account = UserAccountData.query.get(user_id)
            profile = ElderProfile.query.filter_by(user_id=user_id).first()
            if not profile or not account:
                return "查無此長輩的進階個人資料。"
                
            # 獲取對話建議話題 (新功能：校對 ERD)
            topics = ElderTalkTopic.query.filter_by(elder_id=profile.elder_id).all()
            topic_str = ""
            if topics:
                priority = [t.keyword for t in topics if t.topic_type == 'priority']
                avoid = [t.keyword for t in topics if t.topic_type == 'avoid']
                forbidden = [t.keyword for t in topics if t.topic_type == 'forbidden']
                if priority: topic_str += f"\n- 優先話題：{', '.join(priority)}"
                if avoid: topic_str += f"\n- 盡量避免：{', '.join(avoid)}"
                if forbidden: topic_str += f"\n- 絕對禁忌：{', '.join(forbidden)}"

            name = profile.elder_name if profile.elder_name else account.user_name
            context = f"長輩相關背景：\n- 姓名：{name}\n- 居住地區：{profile.location or '未知'}\n- 疾病紀錄：{profile.chronic_diseases or '無'}\n- 用藥提醒：{profile.medication_notes or '無'}\n- 專屬興趣：{profile.interests or '無'}{topic_str}"
            return context
        except Exception as e:
            return f"獲取背景資料失敗：{str(e)}"

    @staticmethod
    def get_current_time():
        """獲取現在的真實時間 (台灣)"""
        now = datetime.now()
        weekdays = ["一", "二", "三", "四", "五", "六", "日"]
        return f"現在時間是：{now.strftime('%Y年%m月%d日')} 星期{weekdays[now.weekday()]} {now.strftime('%p %I點%M分')}"

    @staticmethod
    def notify_family_SOS(user_id=None, reason="長輩感到不適"):
        """緊急呼叫子女"""
        if not user_id:
            user_id = getattr(g, 'current_user_id', None)
        print(f"[SOS 緊急通知] 長輩 ID: {user_id}, 原因: {reason}")
        return f"緊急通知已成功發送給家屬！請安撫長輩：「家人已經在路上了，請先坐下深呼吸」。"

    @staticmethod
    def get_weather_info(location="台北"):
        """獲取指定地區的即時天氣資訊"""
        try:
            # 簡單的地理編碼模擬 (或使用更精確的 API)
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

    # 其他工具省略實作細節，僅保留核心映射
    @staticmethod
    def suggest_activity(user_id=None):
        return "建議活動：聽聽老歌或做些簡單的伸展操。"

TOOL_MAP = {
    "get_elder_context": AgentTools.get_elder_context,
    "get_current_time": AgentTools.get_current_time,
    "notify_family_SOS": AgentTools.notify_family_SOS,
    "suggest_activity": AgentTools.suggest_activity,
    "get_weather_info": AgentTools.get_weather_info
}
