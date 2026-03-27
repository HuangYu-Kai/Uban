import os
from flask import Flask
from dotenv import load_dotenv, dotenv_values
from extensions import db
from models import (
    UserAccountData, PairingCode, FamilyElderRelationship,
    ElderProfile, ElderTalkTopic, ActivityLog, FamilyMessage
)

def reset_database():
    app = Flask(__name__)
    env_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '.env')
    load_dotenv(env_path, override=True)
    
    # 資料庫設定 (MySQL)
    env_config = dotenv_values(env_path)
    db_host = env_config.get('host', 'localhost')
    db_port = env_config.get('port', '3306')
    db_user = env_config.get('user', 'root')
    db_pass = env_config.get('password', '')
    db_name = env_config.get('name', 'uban')

    app.config['SQLALCHEMY_DATABASE_URI'] = f'mysql+pymysql://{db_user}:{db_pass}@{db_host}:{db_port}/{db_name}?charset=utf8mb4'
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
