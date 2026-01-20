from flask import Blueprint, request, jsonify
from datetime import datetime, timedelta
from models import User, PairingCode, Relationship
from extensions import db
from utils import generate_random_code

pairing_bp = Blueprint('pairing', __name__)

@pairing_bp.route('/generate', methods=['POST'])
def generate_code():
    data = request.json
    family_id = data.get('family_id')

    # 驗證家屬身分
    user = User.query.get(family_id)
    if not user or user.role != 'family':
        return jsonify({'error': 'Invalid family ID'}), 403

    # 產心 4 位數配對碼，效期 10 分鐘
    code = generate_random_code()
    # 避免重複 (簡單實作)
    while PairingCode.query.filter_by(code=code, is_used=False).first():
        code = generate_random_code()

    new_pairing = PairingCode(
        code=code,
        creator_id=family_id,
        expires_at=datetime.utcnow() + timedelta(minutes=10)
    )
    db.session.add(new_pairing)
    db.session.commit()

    return jsonify({
        'pairing_code': code,
        'expires_in_seconds': 600
    })

@pairing_bp.route('/verify', methods=['POST'])
def verify_code():
    data = request.json
    elder_id = data.get('elder_id')
    code = data.get('code')

    if not elder_id or not code:
        return jsonify({'error': 'Missing data'}), 400

    # 找到有效且未使用的配對碼
    pairing = PairingCode.query.filter_by(code=code, is_used=False).first()

    if not pairing:
        return jsonify({'error': 'Invalid or expired code'}), 404

    if pairing.expires_at < datetime.utcnow():
        pairing.is_used = True
        db.session.commit()
        return jsonify({'error': 'Code expired'}), 404

    # 建立關係
    new_rel = Relationship(elder_id=elder_id, family_id=pairing.creator_id)
    pairing.is_used = True
    db.session.add(new_rel)
    db.session.commit()

    return jsonify({
        'message': 'Successfully paired!',
        'family_id': pairing.creator_id
    })
