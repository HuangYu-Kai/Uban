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
        register_platform='Local',
        account_create_time=datetime.utcnow(),
        user_authority='Normal',
        payment_channel=''
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

@auth_bp.route('/test_oidc', methods=['POST'])
def test_oidc():
    """測試 OIDC 並將結果寫入根目錄檔案"""
    import os
    data = request.json
    provider = data.get('provider')
    email = data.get('email', 'N/A')
    uid = data.get('uid', 'N/A')
    token = data.get('token', 'N/A')

    # 取得專案根目錄 (UniFlow)
    # 目前檔案在 UniFlow/server/routes/auth.py
    # 根目錄應為 ../../../ (相對於此檔)
    # 但更簡單的方式是 os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    root_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    file_path = os.path.join(root_dir, 'oidc_test_results.txt')

    content = f"""
========================================
OIDC Test Results ({datetime.now().strftime('%Y-%m-%d %H:%M:%S')})
========================================
Provider: {provider}
UID: {uid}
Email: {email}
Token Snippet: {token[:20]}...{token[-10:] if len(token) > 30 else ''}
========================================
"""
    try:
        with open(file_path, 'a', encoding='utf-8') as f:
            f.write(content)
        return jsonify({'status': 'success', 'file': file_path}), 200
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500
