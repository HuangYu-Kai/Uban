from datetime import datetime
from extensions import db

class User(db.Model):
    __tablename__ = 'user'
    id = db.Column(db.Integer, primary_key=True)
    user_name = db.Column(db.String(32), nullable=False)
    user_email = db.Column(db.String(64), nullable=False, unique=True)
    password = db.Column(db.String(128), nullable=False)
    gender = db.Column(db.String(1), nullable=False)
    age = db.Column(db.Integer, nullable=False)
    user_authority = db.Column(db.String(20), nullable=False, default='Normal')
    role = db.Column(db.String(20), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow) # This might need name='created_at' but it's already default
    last_seen = db.Column(db.DateTime, default=datetime.utcnow)

class PairingCode(db.Model):
    __tablename__ = 'pairing_code'
    id = db.Column(db.Integer, primary_key=True, name='code_id')
    code = db.Column(db.String(6), unique=True, nullable=False)
    creator_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    is_used = db.Column(db.Boolean, default=False)
    expires_at = db.Column(db.DateTime, nullable=False)

class Relationship(db.Model):
    __tablename__ = 'family_elder_relationship'
    id = db.Column(db.Integer, primary_key=True, name='relation_id')
    elder_id = db.Column(db.String(4), db.ForeignKey('elder_profile.elder_id'), nullable=False)
    family_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)

class ActivityLog(db.Model):
    __tablename__ = 'activity_log'
    id = db.Column(db.Integer, primary_key=True, name='log_id')
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    event_type = db.Column(db.String(50), nullable=False)  # 'exercise', 'medication', 'mood', 'chat'
    content = db.Column(db.Text, nullable=False)
    timestamp = db.Column(db.DateTime, default=datetime.utcnow)
    
    # 用於儲存更詳細的機器可讀數據 (JSON 格式字串)
    extra_data = db.Column(db.Text, nullable=True) 

class ElderProfile(db.Model):
    __tablename__ = 'elder_profile'
    elder_id = db.Column(db.String(4), primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False, unique=True)
    elder_name = db.Column(db.String(32), nullable=True)
    elder_appellation = db.Column(db.String(16), nullable=True)
    gender = db.Column(db.String(1), nullable=True)
    age = db.Column(db.Integer, nullable=True)
    phone = db.Column(db.String(20), nullable=True)
    location = db.Column(db.String(100), nullable=True)
    ai_persona = db.Column(db.String(50), nullable=True, default='溫暖孫子')
    medication_notes = db.Column(db.Text, nullable=True)
    chronic_diseases = db.Column(db.Text, nullable=True)
    interests = db.Column(db.Text, nullable=True)
    ai_emotion_tone = db.Column(db.String(50), nullable=True)
    ai_text_verbosity = db.Column(db.String(50), nullable=True)
    step_total = db.Column(db.Integer, default=0)
    create_ts = db.Column(db.DateTime, default=datetime.utcnow)

class GawaAppearance(db.Model):
    __tablename__ = 'gawa_appearance'
    gawa_id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    gawa_name = db.Column(db.String(16), nullable=False)
    gawa_rarity = db.Column(db.String(10), nullable=False) # 'common', 'rare', 'epic', 'legendary'

class GetAppearanceList(db.Model):
    __tablename__ = 'get_appearance_list'
    elder_id = db.Column(db.String(4), db.ForeignKey('elder_profile.elder_id'), primary_key=True)
    gawa_id = db.Column(db.Integer, db.ForeignKey('gawa_appearance.gawa_id'), primary_key=True)
    feed_starttime = db.Column(db.DateTime, default=datetime.utcnow)
    feed_endtime = db.Column(db.DateTime, nullable=False)
    gawa_size = db.Column(db.Integer, default=0)

class ElderFellowshipData(db.Model):
    __tablename__ = 'elder_fellowship_data'
    requester_id = db.Column(db.String(4), primary_key=True)
    addressee_id = db.Column(db.String(4), primary_key=True)
    status = db.Column(db.String(20), nullable=False) # 'success', 'blocked'
    create_ts = db.Column(db.DateTime, default=datetime.utcnow)

class FamilyMessage(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    family_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    elder_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    content = db.Column(db.Text, nullable=False)
    is_read = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
