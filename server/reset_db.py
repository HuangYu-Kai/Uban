from app import app
from extensions import db
from models import User, PairingCode, Relationship, ActivityLog

def reset_database():
    with app.app_context():
        print("正在重建資料庫結構...")
        try:
            db.drop_all()
            db.create_all()
            print("✅ 資料庫結構已重建，所有資料已重置！")
        except Exception as e:
            print(f"❌ 重置失敗: {e}")

if __name__ == "__main__":
    reset_database()
