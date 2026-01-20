from flask import Blueprint, request, jsonify
from models import User
from extensions import db

auth_bp = Blueprint('auth', __name__)

@auth_bp.route('/register', methods=['POST'])
def register():
    data = request.json
    username = data.get('username')
    role = data.get('role') # 'elder' or 'family'

    if not username or not role:
        return jsonify({'error': 'Missing data'}), 400

    new_user = User(username=username, role=role)
    db.session.add(new_user)
    db.session.commit()

    return jsonify({
        'message': 'User registered',
        'user_id': new_user.id,
        'username': new_user.username,
        'role': new_user.role
    }), 201
