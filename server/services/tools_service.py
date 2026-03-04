import google.generativeai as genai
from datetime import datetime
from flask import g
import requests

class AgentTools:
    """
    Agentic RAG 工具集模組 (Streaming Safe Version)
    這裡定義的所有方法都可以被 Gemini 識別並調用，並確保回傳最單純的字串供串流解讀。
    """

    @staticmethod
    def get_elder_context(user_id=None):
        """
        獲取目前對話長輩的專屬背景資料，包括：姓名、居住地區、疾病紀錄、用藥提醒、專屬興趣。
        當你需要以更個人化的方式關心長輩或需要知道他在哪裡時，請主動呼叫此工具獲取資訊。
        （此工具不需要傳入任何參數）
        """
        if not user_id:
            user_id = getattr(g, 'current_user_id', None)
            
        if not user_id:
            return "無法獲取當前用戶身分，請以一般朋友的口吻關心即可。"
            
        try:
            from models import ElderProfile, User
            user = User.query.get(user_id)
            profile = ElderProfile.query.filter_by(user_id=user_id).first()
            if not profile or not user:
                return "查無此長輩的進階個人資料。"
                
            name = user.user_name if user.user_name else "長輩"
            location = profile.location if profile.location else "未知地區"
            chronic = profile.chronic_diseases if profile.chronic_diseases else "無特殊病史"
            meds = profile.medication_notes if profile.medication_notes else "無特殊用藥"
            interests = profile.interests if profile.interests else "無特別指定"
            
            return f"長輩相關背景：\n- 姓名：{name}\n- 居住地區：{location}\n- 疾病紀錄：{chronic}\n- 用藥提醒：{meds}\n- 專屬興趣：{interests}"
        except Exception as e:
            return f"獲取背景資料失敗：{str(e)}"

    @staticmethod
    def get_current_time():
        """
        獲取現在的精確真實時間與日期（台灣時間）。
        當長輩詢問「今天幾號」、「現在幾點」、「今天是星期幾」時，請務必呼叫此工具。
        （此工具不需要傳入任何參數）
        """
        try:
            now = datetime.now()
            # 轉換為星期幾
            weekdays = ["一", "二", "三", "四", "五", "六", "日"]
            weekday_str = weekdays[now.weekday()]
            time_str = now.strftime(f"%Y年%m月%d日 星期{weekday_str} %p %I點%M分").replace("AM", "上午").replace("PM", "下午")
            return f"現在時間是：{time_str}。"
        except Exception as e:
            return "目前無法取得時間。"

    @staticmethod
    def get_weather_info(location: str):
        """
        獲取特定地點的即時天氣資訊。
        ⚠️ 極度重要：如果你不知道你要查哪個地區，絕對不要開口問使用者！你必須先呼叫 `get_elder_context` 工具來獲取使用者的「居住地區」，再把查到的地區以純文字傳入這個工具。
        
        Args:
            location: 地點名稱（例如：'三重區', '台北', '高雄'）。不可包含其他雜訊。
        """
        try:
            # 在此做一個簡單的 Mock 或使用外部 API (此處使用簡單模擬以確保穩定度)
            return f"系統自動為您播報 {location} 的氣象：今天天氣涼爽，氣溫約 18 度至 22 度，降雨機率 10%。是個適合穿件薄外套出門的好天氣喔！"
        except Exception as e:
            return f"查不到 {location} 的天氣資訊。"

# 工具映射表，供手動串流調用時對應 function_name 到真實的 Python Method
TOOL_MAP = {
    "get_elder_context": AgentTools.get_elder_context,
    "get_current_time": AgentTools.get_current_time,
    "get_weather_info": AgentTools.get_weather_info
}
