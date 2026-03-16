from flask import Blueprint, request, jsonify
from datetime import datetime, timedelta
import uuid
from models import UserAccountData, PairingCode, FamilyElderRelationship, ElderProfile
from extensions import db
from utils import generate_random_code
from werkzeug.security import generate_password_hash

pairing_bp = Blueprint('pairing', __name__)

@pairing_bp.route('/request_code', methods=['POST'])
def request_code():
    """長輩端 (VM) 請求配對代碼"""
    code = generate_random_code(4) # 生成 4 位數字配對碼
    while PairingCode.query.filter_by(code=code, is_used=False).first():
        code = generate_random_code()

    new_pairing = PairingCode(
        code=code,
        creator_id=0, # 初始為 0
        expires_at=datetime.utcnow() + timedelta(minutes=10)
    )
    db.session.add(new_pairing)
    db.session.commit()

    return jsonify({
        'pairing_code': code,
        'expires_in_seconds': 600
    })

@pairing_bp.route('/confirm', methods=['POST'])
def confirm_pairing():
    """家屬端 (手機) 輸入代碼進行配對並初始化長輩帳號與檔案"""
    data = request.json
    family_id = data.get('family_id')
    code = data.get('code')
    elder_name = data.get('elder_name')
    gender = data.get('gender', 'M')
    age = data.get('age', 70)

    if not all([family_id, code, elder_name]):
        return jsonify({'error': 'Missing required fields'}), 400

    pairing = PairingCode.query.filter_by(code=code, is_used=False).first()
    if not pairing or pairing.expires_at < datetime.utcnow():
        return jsonify({'error': 'Invalid or expired code'}), 404

    # 1. 自動建立長輩帳號
    # 基於新 ERD：UserAccountData 包含名稱
    elder_email = f"elder_{generate_random_code(4)}@uban.com"
    new_account = UserAccountData(
        user_name=elder_name,
        user_email=elder_email,
        password=generate_password_hash("password123"),
        registered_platform='Local'
    )
    db.session.add(new_account)
    db.session.flush()

    # 2. 初始化長輩專屬檔案 (ElderProfile)
    # 基於新 ERD：包含 gender, age
    elder_uuid = str(uuid.uuid4())
    new_profile = ElderProfile(
        elder_id=elder_uuid,
        user_id=new_account.user_id,
        elder_name=elder_name,
        gender=gender,
        age=age,
        ai_emotion_tone=50,
        ai_text_verbosity=50
    )
    db.session.add(new_profile)

    # 3. 建立綁定關係
    # 基於新 ERD：FamilyElderRelationship 使用 elder_id (VARCHAR)
    new_rel = FamilyElderRelationship(
        elder_id=elder_uuid,
        family_id=family_id
    )
    db.session.add(new_rel)

    # 4. 更新代碼狀態
    pairing.is_used = True
    pairing.creator_id = family_id
    
    db.session.commit()

    return jsonify({
        'message': 'Successfully paired and elder profile initialized!',
        'elder_id': new_account.user_id,
        'elder_profile_id': elder_uuid
    })

@pairing_bp.route('/check_status/<code>', methods=['GET'])
def check_status(code):
    """長輩端輪詢配對狀態"""
    pairing = PairingCode.query.filter_by(code=code, is_used=True).first()
    if pairing:
        # 基於新 ERD：找到與此家屬綁定的最新長輩
        relationship = FamilyElderRelationship.query.filter_by(family_id=pairing.creator_id).order_by(FamilyElderRelationship.relationship_id.desc()).first()
        if relationship:
             profile = ElderProfile.query.filter_by(elder_id=relationship.elder_id).first()
             return jsonify({
                 'status': 'paired', 
                 'elder_id': profile.user_id if profile else 0,
                 'elder_name': profile.elder_name if profile else "長輩"
             })
    
    return jsonify({'status': 'waiting'})

@pairing_bp.route('/<int:family_id>/<int:elder_id>', methods=['DELETE'])
def unbind_elder(family_id, elder_id):
    """解除綁定 (清理關係與內容，但保留帳號)"""
    try:
        from models import ActivityLog
        # 1. 找到長輩的 profile 取得 UUID
        profile = ElderProfile.query.filter_by(user_id=elder_id).first()
        if profile:
            # 刪除關係
            FamilyElderRelationship.query.filter_by(family_id=family_id, elder_id=profile.elder_id).delete()
            # 刪除日誌
            ActivityLog.query.filter_by(user_id=elder_id).delete()
            
        db.session.commit()
        return jsonify({'message': 'Unbound successfully'}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({'error': str(e)}), 500
