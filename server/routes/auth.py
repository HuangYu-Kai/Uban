from flask import Blueprint, request, jsonify
from models import User, Relationship
from extensions import db
from werkzeug.security import generate_password_hash, check_password_hash

auth_bp = Blueprint('auth', __name__)

@auth_bp.route('/register', methods=['POST'])
def register():
    data = request.json
    user_name = data.get('username')
    user_email = data.get('email')
    password = data.get('password')
    gender = data.get('gender', 'M')
    age = data.get('age', 20)
    role = data.get('role') # 'elder' or 'family'

    if not user_name or not user_email or not password or not role:
        return jsonify({'error': 'Missing required fields'}), 400

    if User.query.filter_by(user_email=user_email).first():
        return jsonify({'error': 'Email already exists'}), 409

    hashed_pw = generate_password_hash(password)
    new_user = User(
        user_name=user_name,
        user_email=user_email,
        password=hashed_pw,
        gender=gender,
        age=age,
        role=role,
        user_authority='Normal'
    )
    db.session.add(new_user)
    db.session.commit()

    return jsonify({
        'message': 'User registered successfully',
        'user_id': new_user.id,
        'user_name': new_user.user_name,
        'role': new_user.role
    }), 201

@auth_bp.route('/login', methods=['POST'])
def login():
    data = request.json
    email = data.get('email')
    password = data.get('password')

    if not email or not password:
        return jsonify({'error': 'Email and password required'}), 400

    user = User.query.filter_by(user_email=email).first()
    if not user or not check_password_hash(user.password, password):
        return jsonify({'error': 'Invalid email or password'}), 401

    # 檢查是否已配對長輩 (如果是家屬)
    has_paired_elder = False
    if user.role == 'family':
        has_paired_elder = Relationship.query.filter_by(family_id=user.id).first() is not None

    return jsonify({
        'message': 'Login successful',
        'user_id': user.id,
        'user_name': user.user_name,
        'role': user.role,
        'has_paired_elder': has_paired_elder
    }), 200
