from flask import Blueprint, request, jsonify
from datetime import datetime, timedelta
from models import User, PairingCode, Relationship
from extensions import db
from utils import generate_random_code
from werkzeug.security import generate_password_hash

pairing_bp = Blueprint('pairing', __name__)

# --- Elder (VM) Flow ---

@pairing_bp.route('/request_code', methods=['POST'])
def request_code():
    """
    長輩端 (VM) 請求一個代碼來顯示。
    這裡暫時不綁定 ID，因為長輩還沒註冊，只是產生一個 PIN 並記住是誰生成的（如果是已登入狀態）。
    但在目前設計中，長輩端是未登入狀態，所以 PIN 只是暫時存放。
    """
    # 產生 4 位數代碼
    code = generate_random_code()
    while PairingCode.query.filter_by(code=code, is_used=False).first():
        code = generate_random_code()

    # 這裡 creator_id 先帶 0 代表是長輩端請求的待配對碼 (或者用一個特殊的 ID)
    new_pairing = PairingCode(
        code=code,
        creator_id=0, # 0 表示由長輩端發起，等待家屬認領
        expires_at=datetime.utcnow() + timedelta(minutes=10)
    )
    db.session.add(new_pairing)
    db.session.commit()

    return jsonify({
        'pairing_code': code,
        'expires_in_seconds': 600
    })

@pairing_bp.route('/check_status/<code>', methods=['GET'])
def check_status(code):
    """
    長輩端輪詢是否已配對成功。
    """
    pairing = PairingCode.query.filter_by(code=code, is_used=True).first()
    if pairing:
        # 找到對應的關係
        relationship = Relationship.query.filter_by(family_id=pairing.creator_id).filter(Relationship.elder_id != 0).order_by(Relationship.id.desc()).first()
        if relationship:
             elder = User.query.get(relationship.elder_id)
             return jsonify({
                 'status': 'paired', 
                 'elder_id': relationship.elder_id,
                 'elder_name': elder.user_name if elder else "長輩"
             })
    
    return jsonify({'status': 'waiting'})

# --- Caregiver (Phone) Flow ---

@pairing_bp.route('/confirm', methods=['POST'])
def confirm_pairing():
    """
    家屬端 (手機) 輸入代碼與長輩名稱。
    這會同時：
    1. 建立長輩 User 帳號
    2. 建立 Relationship
    3. 標記 PairingCode 為已使用
    """
    data = request.json
    family_id = data.get('family_id')
    code = data.get('code')
    elder_name = data.get('elder_name')
    gender = data.get('gender', 'M')
    age = data.get('age', 70)

    if not all([family_id, code, elder_name]):
        return jsonify({'error': 'Missing required data'}), 400

    # 1. 驗證代碼
    pairing = PairingCode.query.filter_by(code=code, is_used=False).first()
    if not pairing or pairing.expires_at < datetime.utcnow():
        return jsonify({'error': 'Invalid or expired code'}), 404

    # 2. 自動為長輩建立帳號
    # 為長輩產生隨機 Email
    random_id = generate_random_code(6)
    elder_email = f"elder_{random_id}@uban.com"
    hashed_pw = generate_password_hash("password123") # 預設密碼

    new_elder = User(
        user_name=elder_name,
        user_email=elder_email,
        password=hashed_pw,
        gender=gender,
        age=age,
        role='elder',
        user_authority='Normal'
    )
    db.session.add(new_elder)
    db.session.flush() # 取得 new_elder.id

    # 3. 建立關係
    new_rel = Relationship(elder_id=new_elder.id, family_id=family_id)
    db.session.add(new_rel)

    # 4. 更新代碼狀態 (將家屬 ID 存入 creator_id，供長輩端查詢)
    pairing.is_used = True
    pairing.creator_id = family_id
    
    db.session.commit()

    return jsonify({
        'message': 'Successfully paired and elder account created!',
        'elder_id': new_elder.id
    })
