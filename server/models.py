from datetime import datetime, timezone
from extensions import db

class User(db.Model):
    __tablename__ = 'user_account_data'
    id = db.Column(db.Integer, primary_key=True, name='user_id')
    user_name = db.Column(db.String(32), nullable=False)
    user_email = db.Column(db.String(64), nullable=False, unique=True)
    password = db.Column(db.String(128), nullable=False)
    # 支援舊有資料表缺乏的欄位 (加上預設值)
    gender = db.Column(db.String(1), nullable=True, default='M')
    age = db.Column(db.Integer, nullable=True, default=20)
    user_authority = db.Column(db.String(20), nullable=True, default='Normal')
    role = db.Column(db.String(20), nullable=True, default='family') # 預設為家屬
    created_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc), name='account_create_time')
    last_seen = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))

class PairingCode(db.Model):
    __tablename__ = 'pairing_code'
    id = db.Column(db.Integer, primary_key=True, name='code_id')
    code = db.Column(db.String(6), unique=True, nullable=False)
    creator_id = db.Column(db.Integer, db.ForeignKey('user_account_data.user_id'), nullable=False)
    is_used = db.Column(db.Boolean, default=False)
    expires_at = db.Column(db.DateTime, nullable=False)

class Relationship(db.Model):
    __tablename__ = 'family_elder_relationship'
    id = db.Column(db.Integer, primary_key=True, name='relation_id')
    elder_id = db.Column(db.String(4), db.ForeignKey('elder_profile.elder_id'), nullable=False)
    family_id = db.Column(db.Integer, db.ForeignKey('user_account_data.user_id'), nullable=False)

class ActivityLog(db.Model):
    __tablename__ = 'activity_log'
    id = db.Column(db.Integer, primary_key=True, name='log_id')
    user_id = db.Column(db.Integer, db.ForeignKey('user_account_data.user_id'), nullable=False)
    event_type = db.Column(db.String(50), nullable=False)  # 'exercise', 'medication', 'mood', 'chat'
    content = db.Column(db.Text, nullable=False)
    timestamp = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))
    
    # 用於儲存更詳細的機器可讀數據 (JSON 格式字串)
    extra_data = db.Column(db.Text, nullable=True) 

class ElderProfile(db.Model):
    __tablename__ = 'elder_profile'
    elder_id = db.Column(db.String(4), primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user_account_data.user_id'), nullable=False, unique=True)
    elder_name = db.Column(db.String(32), nullable=True)
    elder_appellation = db.Column(db.String(16), nullable=True)
    step_total = db.Column(db.Integer, default=0)
    # gawa_xp = db.Column(db.Integer, default=0)  # Database column does not exist
    create_ts = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))
    gawa_id = db.Column(db.Integer, db.ForeignKey('gawa_appearance.gawa_id'), nullable=True)
    feed_starttime = db.Column(db.DateTime, nullable=True)

class GawaAppearance(db.Model):
    __tablename__ = 'gawa_appearance'
    gawa_id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    gawa_name = db.Column(db.String(16), nullable=False)
    gawa_rarity = db.Column(db.String(10), nullable=False) # 'common', 'rare', 'epic', 'legendary'
    bonus = db.Column(db.Float, default=0.0)

class GetAppearanceList(db.Model):
    __tablename__ = 'get_appearance_list'
    elder_id = db.Column(db.String(4), db.ForeignKey('elder_profile.elder_id'), primary_key=True)
    gawa_id = db.Column(db.Integer, db.ForeignKey('gawa_appearance.gawa_id'), primary_key=True)
    feed_starttime = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))
    feed_endtime = db.Column(db.DateTime, nullable=False)
    gawa_size = db.Column(db.Integer, default=0)

class ElderFellowshipData(db.Model):
    __tablename__ = 'elder_fellowship_data'
    requester_id = db.Column(db.String(4), primary_key=True)
    addressee_id = db.Column(db.String(4), primary_key=True)
    status = db.Column(db.String(20), nullable=False) # 'success', 'blocked'
    create_ts = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))

class FamilyMessage(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    family_id = db.Column(db.Integer, db.ForeignKey('user_account_data.user_id'), nullable=False)
    elder_id = db.Column(db.Integer, db.ForeignKey('user_account_data.user_id'), nullable=False)
    content = db.Column(db.Text, nullable=False)
    is_read = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))
