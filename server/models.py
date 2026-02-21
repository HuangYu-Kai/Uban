from datetime import datetime
from extensions import db

class User(db.Model):
    id = db.Column(db.Integer, primary_key=True) #對應 user_id
    user_name = db.Column(db.String(32), nullable=False)
    user_email = db.Column(db.String(64), nullable=False, unique=True)
    password = db.Column(db.String(128), nullable=False)
    gender = db.Column(db.String(1), nullable=False) # 'M' or 'F'
    age = db.Column(db.Integer, nullable=False)
    user_authority = db.Column(db.String(20), nullable=False, default='Normal') # Normal, Sub1, Sub2, admin, root
    role = db.Column(db.String(20), nullable=False)  # 'elder' 或 'family'
    created_at = db.Column(db.DateTime, default=datetime.utcnow) #對應 account_create_time
    last_seen = db.Column(db.DateTime, default=datetime.utcnow)

class PairingCode(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    code = db.Column(db.String(6), unique=True, nullable=False)
    creator_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    is_used = db.Column(db.Boolean, default=False)
    expires_at = db.Column(db.DateTime, nullable=False)

class Relationship(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    elder_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    family_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)

class ActivityLog(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    event_type = db.Column(db.String(50), nullable=False)  # 'exercise', 'medication', 'mood', 'chat'
    content = db.Column(db.Text, nullable=False)
    timestamp = db.Column(db.DateTime, default=datetime.utcnow)
    
    # 用於儲存更詳細的機器可讀數據 (JSON 格式字串)
    extra_data = db.Column(db.Text, nullable=True) 
