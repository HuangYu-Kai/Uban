import os
from flask import Flask
from extensions import db
from models import (
    UserAccountData, PairingCode, FamilyElderRelationship,
    ElderProfile, ElderTalkTopic, ActivityLog, FamilyMessage
)

def reset_database():
    app = Flask(__name__)
    
    # 資料庫設定 (與 app.py 內容保持一致)
    base_dir = os.path.dirname(os.path.abspath(__file__))
    db_path = os.path.join(base_dir, 'instance', 'uban.db')
    app.config['SQLALCHEMY_DATABASE_URI'] = f'sqlite:///{db_path}'
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
    
    db.init_app(app)
    
    with app.app_context():
        if not os.path.exists(os.path.dirname(db_path)):
            os.makedirs(os.path.dirname(db_path))
            
        print("正在重建資料庫結構 (基於新 ERD)...")
        try:
            db.drop_all()
            db.create_all()
            print("✅ 資料庫結構已重建，所有資料已重置！")
        except Exception as e:
            print(f"❌ 重置失敗: {e}")

if __name__ == "__main__":
    reset_database()
