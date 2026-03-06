from services.gemini_service import gemini_service
from services.tools_service import AgentTools
from extensions import db
from models import ActivityLog, User
from app import app
import os

def test_agentic_rag():
    with app.app_context():
        # 1. 準備測試數據 (模擬一個長輩)
        test_user = User.query.filter_by(role='elder').first()
        if not test_user:
            print("找不到測試長輩，請先運行 app 以初始化數據。")
            return
        
        user_id = test_user.id
        print(f"--- 測試開始 (User ID: {user_id}) ---")

        # 2. 模擬一條「已吃藥」紀錄
        new_log = ActivityLog(
            user_id=user_id,
            event_type='medication',
            content='已服用早晨降血壓藥 (脈優 5mg)'
        )
        db.session.add(new_log)
        db.session.commit()
        print("✅ 已插入模擬吃藥紀錄。")

        # 3. 測試問題 1：詢問吃藥情況
        print("\n[測試 1] 詢問 AI：『我今天吃藥了嗎？』")
        response1 = gemini_service.get_response("我今天吃藥了嗎？", user_id=user_id)
        print(f"🤖 AI 回覆 1：\n{response1}")

        # 模擬記錄第一輪對話 (現實中是由路由記錄，這裡為了測試手動加)
        log_content = f"長者詢問：我今天吃藥了嗎？ | AI 回應：{response1}"
        new_log2 = ActivityLog(user_id=user_id, event_type='chat', content=log_content)
        db.session.add(new_log2)
        db.session.commit()

        # 4. 測試問題 2：追問 (測試記憶)
        print("\n[測試 2] 詢問 AI：『那是什麼時候吃的？』")
        # 這裡從資料庫抓歷史
        past_logs = ActivityLog.query.filter_by(user_id=user_id, event_type='chat').order_by(ActivityLog.timestamp.desc()).limit(5).all()
        history = []
        for log in reversed(past_logs):
            parts = log.content.split(" | AI 回應：")
            if len(parts) == 2:
                history.append({"role": "user", "parts": [parts[0].replace("長者詢問：", "")]})
                history.append({"role": "model", "parts": [parts[1]]})
        
        response2 = gemini_service.get_response("那是什麼時候吃的？", user_id=user_id, history=history)
        print(f"🤖 AI 回覆 2：\n{response2}")

if __name__ == "__main__":
    test_agentic_rag()
