from datetime import datetime
from extensions import db

class UserAccountData(db.Model):
    """帳號核心資料：處理登入、身分驗證與基本資訊"""
    __tablename__ = 'user_account_data'
    user_id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    user_name = db.Column(db.String(32), nullable=False)
    user_email = db.Column(db.String(64), nullable=False, unique=True)
    password = db.Column(db.String(255), nullable=False) # 增加長度以支援雜湊
    account_create_time = db.Column(db.DateTime, default=datetime.utcnow)
    user_authority = db.Column(db.Enum('Normal', 'Sub1', 'Sub2', 'admin', 'root'), nullable=False, default='Normal')
    payment_channel = db.Column(db.String(32), nullable=True)
    registered_platform = db.Column(db.Enum('Local', 'Google'), nullable=False, default='Local')
    
    # 關聯
    elder_profile = db.relationship('ElderProfile', backref='account', uselist=False, cascade="all, delete-orphan")

class PairingCode(db.Model):
    """配對機制：用於家屬綁定長者"""
    __tablename__ = 'pairing_code'
    code_id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    creator_id = db.Column(db.Integer, db.ForeignKey('user_account_data.user_id'), nullable=False)
    code = db.Column(db.String(4), unique=True, nullable=False) # 改為 4 碼數字
    is_used = db.Column(db.Boolean, default=False)
    expires_at = db.Column(db.DateTime, nullable=False)

class FamilyElderRelationship(db.Model):
    """綁定關係：連結家屬與長者檔案"""
    __tablename__ = 'family_elder_relationship'
    relationship_id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    elder_id = db.Column(db.String(64), db.ForeignKey('elder_profile.elder_id'), nullable=False)
    family_id = db.Column(db.Integer, db.ForeignKey('user_account_data.user_id'), nullable=False)
    create_ts = db.Column(db.DateTime, default=datetime.utcnow)

class ElderProfile(db.Model):
    """長者整合檔案：包含生理資訊、地區與 AI 個性設定"""
    __tablename__ = 'elder_profile'
    elder_id = db.Column(db.String(64), primary_key=True) # UUID 或 代碼
    user_id = db.Column(db.Integer, db.ForeignKey('user_account_data.user_id'), unique=True, nullable=False)
    elder_name = db.Column(db.String(32), nullable=False)
    elder_appellation = db.Column(db.String(16), nullable=True) # 對 AI 的稱呼 (如: 奶奶)
    gender = db.Column(db.Enum('M', 'F'), nullable=False)
    age = db.Column(db.Integer, nullable=False)
    medication_notes = db.Column(db.Text, nullable=True)
    ai_emotion_tone = db.Column(db.Integer, default=50) # 0-100 數值滑桿
    ai_text_verbosity = db.Column(db.Integer, default=50) # 0-100 數值滑桿
    step_goal = db.Column(db.Integer, default=0)
    create_ts = db.Column(db.DateTime, default=datetime.utcnow)
    
    # 保留部分欄位以支援現有工具 (如位置)
    location = db.Column(db.String(100), nullable=True)
    chronic_diseases = db.Column(db.Text, nullable=True)
    interests = db.Column(db.Text, nullable=True)
    phone = db.Column(db.String(20), nullable=True)

class ElderTalkTopic(db.Model):
    """對話話題清單：透過標籤管理 AI 的對話傾向"""
    __tablename__ = 'elder_talk_topics'
    topic_id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    elder_id = db.Column(db.String(64), db.ForeignKey('elder_profile.elder_id'), nullable=False)
    keyword = db.Column(db.String(32), nullable=False)
    topic_type = db.Column(db.Enum('priority', 'safe', 'avoid', 'forbidden'), nullable=False, default='safe')
    create_ts = db.Column(db.DateTime, default=datetime.utcnow)

class ActivityLog(db.Model):
    """活動日誌：紀錄聊天歷史與健康數據"""
    __tablename__ = 'activity_log'
    log_id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user_account_data.user_id'), nullable=False)
    event_type = db.Column(db.String(50), nullable=False) # 'exercise', 'medication', 'mood', 'chat', 'chat_summary'
    content = db.Column(db.Text, nullable=False)
    timestamp = db.Column(db.DateTime, default=datetime.utcnow)
    extra_data = db.Column(db.Text, nullable=True) # JSON 格式字串

class FamilyMessage(db.Model):
    """家屬留言中心"""
    __tablename__ = 'family_message'
    id = db.Column(db.Integer, primary_key=True)
    family_id = db.Column(db.Integer, db.ForeignKey('user_account_data.user_id'), nullable=False)
    elder_id = db.Column(db.Integer, db.ForeignKey('user_account_data.user_id'), nullable=False)
    content = db.Column(db.Text, nullable=False)
    is_read = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
