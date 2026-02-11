from app import app
from extensions import db
from models import User, PairingCode, Relationship, ActivityLog

def reset_database():
    with app.app_context():
        print("正在清理資料表內容...")
        
        # 依照依賴關係清理 (從子資料表開始)
        try:
            db.session.query(ActivityLog).delete()
            db.session.query(Relationship).delete()
            db.session.query(PairingCode).delete()
            db.session.query(User).delete()
            
            db.session.commit()
            print("✅ 所有資料表已清空！")
        except Exception as e:
            db.session.rollback()
            print(f"❌ 清理失敗: {e}")

if __name__ == "__main__":
    reset_database()
