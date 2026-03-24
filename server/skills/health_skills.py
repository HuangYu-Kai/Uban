from extensions import db
from models import ActivityLog
from datetime import datetime

def record_elder_activity(user_id: int, activity_description: str, mood: str = "普通"):
    """主動紀錄長輩的活動、心情或健康狀態。當長輩提到「我吃過藥了」、「今天心情很好」或「我去公園走走」時使用。
    Args:
        user_id: 使用者的資料庫 ID (由系統自動注入)
        activity_description: 活動內容描述
        mood: 長輩當下的心情 (如: 開心, 愉快, 疲倦, 不舒服, 普通)
    """
    if not user_id: return "無法識別用戶。"
    try:
        new_log = ActivityLog(
            user_id=user_id,
            event_type='activity',
            content=f"【活動紀錄】{activity_description} | 心情：{mood}",
            timestamp=datetime.now()
        )
        db.session.add(new_log)
        db.session.commit()
        return f"我已經幫您記下來了：『{activity_description}』，我也感覺到您目前的狀態是『{mood}』，真好！"
    except Exception as e:
        return f"紀錄活動失敗：{str(e)}"
