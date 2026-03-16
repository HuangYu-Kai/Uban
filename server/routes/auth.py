from flask import Blueprint, request, jsonify
from models import UserAccountData, FamilyElderRelationship
from extensions import db
from werkzeug.security import generate_password_hash, check_password_hash
from datetime import datetime

auth_bp = Blueprint('auth', __name__)

@auth_bp.route('/register', methods=['POST'])
def register():
    """註冊新使用者 (家屬或長輩)"""
    data = request.json
    user_name = data.get('username') or data.get('user_name')
    user_email = data.get('email') or data.get('user_email')
    password = data.get('password')
    role = data.get('role', 'family') # 'elder' or 'family'

    if not all([user_name, user_email, password]):
        return jsonify({'error': 'Missing required fields (need user_name/username, user_email/email, password)'}), 400

    if UserAccountData.query.filter_by(user_email=user_email).first():
        return jsonify({'error': 'Email already exists'}), 409

    hashed_pw = generate_password_hash(password)
    
    # 基於新 ERD：基本資料直接存在帳號表
    new_account = UserAccountData(
        user_name=user_name,
        user_email=user_email,
        password=hashed_pw,
        registered_platform='Local',
        account_create_time=datetime.utcnow(),
        user_authority='Normal'
    )
    db.session.add(new_account)
    db.session.commit()

    return jsonify({
        'message': 'User registered successfully',
        'user_id': new_account.user_id,
        'user_name': new_account.user_name
    }), 201

@auth_bp.route('/login', methods=['POST'])
def login():
    """使用者登入"""
    data = request.json
    email = data.get('email')
    password = data.get('password')

    if not email or not password:
        return jsonify({'error': 'Email and password required'}), 400

    account = UserAccountData.query.filter_by(user_email=email).first()
    if not account or not check_password_hash(account.password, password):
        return jsonify({'error': 'Invalid email or password'}), 401

    # 檢查是否已配對長輩 (家屬端邏輯)
    has_paired_elder = FamilyElderRelationship.query.filter_by(family_id=account.user_id).first() is not None

    return jsonify({
        'message': 'Login successful',
        'user_id': account.user_id,
        'user_name': account.user_name,
        'has_paired_elder': has_paired_elder
    }), 200
