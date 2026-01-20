from flask import Blueprint, jsonify
from models import User, Relationship

user_bp = Blueprint('user', __name__)

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
        'user_id': user.id,
        'username': user.username,
        'role': user.role,
        'paired': rel is not None,
        'partner_name': partner.username if partner else None
    })
