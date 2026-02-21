from flask import Blueprint, jsonify, request
from models import User, Relationship
from extensions import db
from datetime import datetime

user_bp = Blueprint('user', __name__)

# ... (existing routes)

@user_bp.route('/update_elder', methods=['POST'])
def update_elder():
    data = request.json
    family_id = data.get('family_id')
    elder_id = data.get('elder_id')
    new_name = data.get('user_name')
    new_age = data.get('age')
    new_gender = data.get('gender')

    if not all([family_id, elder_id]):
        return jsonify({'error': 'Missing required identification'}), 400

    # 驗證權限：該家屬是否真的綁定了這位長輩
    rel = Relationship.query.filter_by(family_id=family_id, elder_id=elder_id).first()
    if not rel:
        return jsonify({'error': 'UnAuthorized: Relationship not found'}), 403

    elder = User.query.get(elder_id)
    if not elder:
        return jsonify({'error': 'Elder not found'}), 404

    # 更新欄位
    if new_name: elder.user_name = new_name
    if new_age: elder.age = new_age
    if new_gender: elder.gender = new_gender

    db.session.commit()
    return jsonify({'message': 'Elder info updated successfully'})

@user_bp.route('/status/<int:user_id>', methods=['GET'])
def get_status(user_id):
    user = User.query.get(user_id)
    if not user:
        return jsonify({'error': 'User not found'}), 404

    # 查詢關聯對象
    if user.role == 'elder':
        rel = Relationship.query.filter_by(elder_id=user_id).first()
        partner = User.query.get(rel.family_id) if rel else None
    else:
        rel = Relationship.query.filter_by(family_id=user_id).first()
        partner = User.query.get(rel.elder_id) if rel else None

    return jsonify({
        'user_name': user.user_name,
        'role': user.role,
        'partner_name': partner.user_name if partner else None
    })

@user_bp.route('/<int:user_id>/elders', methods=['GET'])
def get_paired_elders(user_id):
    user = User.query.get(user_id)
    if not user:
        return jsonify({'error': 'User not found'}), 404
        
    if user.role != 'family':
        return jsonify({'error': 'Only family members can fetch paired elders'}), 403
        
    elders = []
    now = datetime.utcnow()
    # Correctly query the relationships from the database
    user_relationships = Relationship.query.filter_by(family_id=user_id).all()
    for rel in user_relationships:
        elder = User.query.get(rel.elder_id)
        if elder:
            # 判斷在線狀態 (例如 5 分鐘內有活動視為在線)
            is_online = (now - elder.last_seen).total_seconds() < 300 if elder.last_seen else False
            elders.append({
                'id': elder.id,
                'user_name': elder.user_name,
                'gender': elder.gender,
                'age': elder.age,
                'is_online': is_online,
                'last_seen': elder.last_seen.isoformat() if elder.last_seen else None
            })
            
    return jsonify(elders)
