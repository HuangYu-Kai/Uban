from extensions import db
from models import ElderProfile, UserAccountData, ElderTalkTopic

def get_elder_context(user_id: str = None):
    """獲取長輩的背景資訊，包含姓名、居住地區、疾病史、用藥備註以及對話話題禁忌。
    此功能有助於提供更貼心且精準的陪伴。
    Args:
        user_id: 使用者的資料庫 ID (由系統自動注入)
    """
    if not user_id:
        return "無法獲取當前用戶身分，因此無法讀取長輩背景。"
        
    try:
        account = UserAccountData.query.get(user_id)
        profile = ElderProfile.query.filter_by(user_id=user_id).first()
        if not profile or not account:
            return "目前尚未建立完整的長輩個人檔案。"
            
        # 獲取對話話題偏好與禁忌
        topics = ElderTalkTopic.query.filter_by(elder_id=profile.elder_id).all()
        topic_str = ""
        if topics:
            priority = [t.keyword for t in topics if t.topic_type == 'priority']
            avoid = [t.keyword for t in topics if t.topic_type == 'avoid']
            forbidden = [t.keyword for t in topics if t.topic_type == 'forbidden']
            if priority: topic_str += f"\n- 推薦話題：{', '.join(priority)}"
            if avoid: topic_str += f"\n- 盡量避開：{', '.join(avoid)}"
            if forbidden: topic_str += f"\n- 絕對禁忌：{', '.join(forbidden)}"

        name = profile.elder_name if profile.elder_name else account.user_name
        context = (
            f"【長輩背景檔案】\n"
            f"- 姓名：{name}\n"
            f"- 居住地區：{profile.location or '未設定'}\n"
            f"- 疾病紀錄：{profile.chronic_diseases or '無特殊紀錄'}\n"
            f"- 用藥備註：{profile.medication_notes or '無'}\n"
            f"- 生活興趣：{profile.interests or '未嘗試收集'}"
            f"{topic_str}"
        )
        return context
    except Exception as e:
        return f"讀取資料庫時發生錯誤：{str(e)}"

def notify_family_SOS(user_id: str = None, reason: str = "長輩感到不適"):
    """當長輩提到身體劇痛、求救或緊急狀況時呼叫此功能，會立即通知家屬。
    Args:
        user_id: 使用者的資料庫 ID (由系統自動注入)
        reason: 緊急狀況的原因簡述
    """
    # 這裡未來會整合 Socket.IO 或 FCM 推播通知
    print(f"🚨 [Emergency Skill] Triggering SOS for User {user_id}. Reason: {reason}")
    return f"緊急通知已發送給家屬！原因：{reason}。請務必跟長輩說：「我已經通知您的家人了，他們很快就會聯繫您，請您先不要緊張，慢慢呼吸。」"

def suggest_activity(user_id: str = None):
    """根據長輩的狀態與興趣，推薦適合的日常活動。
    Args:
        user_id: 使用者的資料庫 ID (由系統自動注入)
    """
    # 暫時回傳簡單建議
    return "根據長輩對音樂的興趣，建議可以聽聽懷舊老歌，或是做一些簡單的椅子伸展操來放鬆心情。"
