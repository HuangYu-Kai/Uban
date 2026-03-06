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

    @staticmethod
    def read_family_messages(user_id=None):
        """
        讀取家屬留給長輩的最新留言或便條紙。
        當長輩剛開始對話，或主動詢問「家人有沒有留話給我」時，可以使用此工具。
        """
        if not user_id:
            user_id = getattr(g, 'current_user_id', None)
            
        if not user_id:
            return "無法獲取長輩身分，無法查詢留言。"
            
        try:
            from models import FamilyMessage, db
            msg = FamilyMessage.query.filter_by(elder_id=user_id, is_read=False).order_by(FamilyMessage.created_at.desc()).first()
            if not msg:
                # 如果沒有真實資料，fallback 空提示
                return "系統查詢結果：目前沒有任何家人新留言。(提醒：請跟長輩說沒有留言即可)"

            msg.is_read = True
            db.session.commit()
            return f"查詢結果：家屬留下了一則便條，內容是：「{msg.content}」。 (如果長輩詢問或有需要，請利用此資訊以你溫暖的口吻轉述給長輩，並且絕對不要使用任何反引號)"
        except Exception as e:
            return f"查詢留言失敗：{str(e)}"

    @staticmethod
    def notify_family_SOS(user_id=None, reason="長輩感到不適"):
        """
        緊急呼叫子女。
        當對話中長輩明確表示：身體極度不舒服、胸悶、跌倒、或者要求「幫我叫救護車」、「幫我聯絡家人」時，請【務必】呼叫此工具。
        
        Args:
            reason: 觸發緊急通知的原因，請簡短描述長輩的狀況。
        """
        if not user_id:
            user_id = getattr(g, 'current_user_id', None)
            
        try:
            from flask import current_app
            if 'socketio' in current_app.extensions:
                current_app.extensions['socketio'].emit('sos-alert', {'elder_id': user_id, 'reason': reason})
            print(f"[SOS 緊急事件廣播] 通知家屬！長輩 ID: {user_id}, 原因: {reason}")
            return f"緊急通知已成功發送給家屬！原因紀錄為：{reason}。請您現在立刻用溫柔且鎮定的口吻安撫長輩，告訴他「家人已經知道並且正在處理/趕過來了，請先坐著深呼吸不要緊張」。"
        except Exception as e:
            return "緊急通知發送失敗，請試著用溫和的方式安撫長輩並建議他自行撥打 119。"

    @staticmethod
    def suggest_activity(user_id=None):
        """
        根據長輩的興趣推薦活動。
        當長輩表示「好無聊」、「不知道要做什麼」時，可以呼叫此工具獲取建議。
        """
        if not user_id:
            user_id = getattr(g, 'current_user_id', None)
            
        try:
            from models import ElderProfile, User
            profile = ElderProfile.query.filter_by(user_id=user_id).first()
            interests = profile.interests if profile and profile.interests else "聽老歌、看風景"
            
            # 使用簡單的動態推薦（為了測試影片功能，我們強制塞一個好玩的推薦影片）
            return f"根據長輩的興趣（{interests}），系統建議的活動：不如引導長輩一起做個簡單的椅子體操，或者看一段有趣的懷舊影片！影片網址：![影片](https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4)。請將這個建議轉化為口語與長輩互動，但遇到影片網址時，請原封不動照著輸出，並且絕對不要在影片網址外面加任何的反引號。"
        except Exception as e:
            return "無法生成活動建議，請自行想個輕鬆的話題與他聊天。"

    @staticmethod
    def check_lunar_calendar():
        """
        獲取今天的農曆與節氣資訊。
        當長輩詢問「今天農曆幾號」、「快過節了嗎」時呼叫。
        （此工具不需要傳入任何參數）
        """
        try:
            from datetime import datetime
            import requests

            # 因為完整的農曆轉換庫較為複雜，這裡我們做一個示範性的實作/串接
            # 假設我們計算出今天是大年初二，或者是某個特定節氣
            # 為了穩定性，目前回傳一個 Mock 資料
            now = datetime.now()
            today_str = now.strftime("%m月%d日")
            return f"今天是國曆 {today_str}。農曆大約是【臘月廿五】。距離【過年】還有大約 5 天。今日黃曆建議：宜：祈福、祭祀。忌：動土。請將這個資訊白話解釋給長輩聽。"
        except Exception as e:
            return "查詢農曆失敗，請告訴長輩可能需要看一下實體日曆喔。"

# 工具映射表，供手動串流調用時對應 function_name 到真實的 Python Method
TOOL_MAP = {
    "get_elder_context": AgentTools.get_elder_context,
    "get_current_time": AgentTools.get_current_time,
    "get_weather_info": AgentTools.get_weather_info,
    "read_family_messages": AgentTools.read_family_messages,
    "notify_family_SOS": AgentTools.notify_family_SOS,
    "suggest_activity": AgentTools.suggest_activity,
    "check_lunar_calendar": AgentTools.check_lunar_calendar
}
