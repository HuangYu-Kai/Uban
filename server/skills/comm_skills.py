from extensions import db
from models import FamilyMessage, UserAccountData, ElderProfile, ActivityLog
from datetime import datetime
import json

def get_family_messages(user_id: int):
    """讀取家屬留給長輩的未讀訊息 (文字或語音摘要)。
    Args:
        user_id: 使用者的資料庫 ID (由系統自動注入)
    """
    if not user_id: return "無法識別用戶。"
    try:
        messages = FamilyMessage.query.filter_by(elder_id=user_id, is_read=False).order_by(FamilyMessage.created_at.desc()).all()
        if not messages:
            return "目前沒有新的家屬留言。"
        
        result = "發現以下新留言：\n"
        for msg in messages:
            result += f"- 來自家屬 (ID:{msg.family_id}): 「{msg.content}」 (發送於 {msg.created_at.strftime('%m/%d %H:%M')})\n"
        return result
    except Exception as e:
        return f"讀取留言時發生錯誤：{str(e)}"

def initiate_video_call(user_id: int, contact_name: str = "家人"):
    """發起視訊通話邀請。
    Args:
        user_id: 使用者的資料庫 ID (由系統自動注入)
        contact_name: 想要撥打的對象名稱 (例如: '兒子', '女兒', '家人')
    """
    # 這裡的邏輯在獨立測試時僅會返回描述。在系統整合後會發送 Socket 訊號。
    print(f"📞 [Skill] Initiating Video Call from User {user_id} to {contact_name}")
    
    # 這裡可以模擬寫入一個通話請求 log
    try:
        new_log = ActivityLog(
            user_id=user_id,
            event_type='call_request',
            content=f"長輩請求撥打視訊電話給：{contact_name}"
        )
        db.session.add(new_log)
        db.session.commit()
    except:
        pass

    return f"好的，我正在為您撥打視訊電話給{contact_name}，請稍候片刻並看向螢幕中心。"
