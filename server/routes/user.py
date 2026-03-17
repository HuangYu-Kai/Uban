import io
import os
import uuid
from flask import Blueprint, jsonify, request, send_from_directory, send_file
from models import UserAccountData, FamilyElderRelationship, ElderProfile, FamilyMessage
from extensions import db
from datetime import datetime
from werkzeug.utils import secure_filename

user_bp = Blueprint('user', __name__)

UPLOAD_FOLDER = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'uploads', 'avatars')
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

@user_bp.route('/profile/<int:user_id>', methods=['GET'])
def get_profile(user_id):
    """獲取使用者詳細資料 (家屬或長輩)"""
    account = UserAccountData.query.get(user_id)
    if not account:
        return jsonify({'error': 'User not found'}), 404

    profile = ElderProfile.query.filter_by(user_id=user_id).first()
    
    profile_data = {
        'user_id': account.user_id,
        'user_name': account.user_name,
        'email': account.user_email,
        'authority': account.user_authority,
        'is_elder': profile is not None
    }

    if profile:
        profile_data.update({
            'elder_id': profile.elder_id,
            'elder_name': profile.elder_name,
            'appellation': profile.elder_appellation,
            'gender': profile.gender,
            'age': profile.age,
            'medication_notes': profile.medication_notes,
            'chronic_diseases': profile.chronic_diseases,
            'location': profile.location,
            'ai_emotion_tone': profile.ai_emotion_tone,
            'ai_text_verbosity': profile.ai_text_verbosity
        })

    return jsonify(profile_data)

@user_bp.route('/<int:user_id>/avatar', methods=['POST'])
def upload_avatar(user_id):
    if 'avatar' not in request.files:
        return jsonify({'error': 'No file part'}), 400
    file = request.files['avatar']
    if file.filename == '':
        return jsonify({'error': 'No selected file'}), 400
    
    if file:
        filename = secure_filename(f"avatar_{user_id}.jpg")
        filepath = os.path.join(UPLOAD_FOLDER, filename)
        file.save(filepath)
        return jsonify({'message': 'Avatar uploaded successfully', 'avatar_url': f'/api/user/{user_id}/avatar'})

@user_bp.route('/<int:user_id>/avatar', methods=['GET'])
def get_avatar(user_id):
    filename = f"avatar_{user_id}.jpg"
    if os.path.exists(os.path.join(UPLOAD_FOLDER, filename)):
        return send_from_directory(UPLOAD_FOLDER, filename)
    else:
        # 回傳透明圖片避免前端報錯
        import base64
        transparent_png = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=")
        return send_file(io.BytesIO(transparent_png), mimetype='image/png')

@user_bp.route('/profile/<int:user_id>', methods=['POST', 'PUT'])
def update_profile(user_id):
    """更新使用者資料"""
    data = request.json
    account = UserAccountData.query.get(user_id)
    if not account:
        return jsonify({'error': 'User not found'}), 404

    if 'user_name' in data: account.user_name = data['user_name']
    
    profile = ElderProfile.query.filter_by(user_id=user_id).first()
    if profile:
        if 'elder_name' in data: profile.elder_name = data['elder_name']
        if 'appellation' in data: profile.elder_appellation = data['appellation']
        if 'gender' in data: profile.gender = data['gender']
        if 'age' in data: profile.age = data['age']
        if 'medication_notes' in data: profile.medication_notes = data['medication_notes']
        if 'chronic_diseases' in data: profile.chronic_diseases = data['chronic_diseases']
        if 'location' in data: profile.location = data['location']
        if 'ai_emotion_tone' in data: profile.ai_emotion_tone = data['ai_emotion_tone']
        if 'ai_text_verbosity' in data: profile.ai_text_verbosity = data['ai_text_verbosity']

    db.session.commit()
    return jsonify({'message': 'Profile updated successfully'})

@user_bp.route('/<int:user_id>/elders', methods=['GET'])
def get_paired_elders(user_id):
    """獲取與家屬綁定的長輩列表"""
    relationships = FamilyElderRelationship.query.filter_by(family_id=user_id).all()
    elders_list = []
    
    for rel in relationships:
        profile = ElderProfile.query.filter_by(elder_id=rel.elder_id).first()
        if profile:
            elders_list.append({
                'id': profile.user_id,             # Flutter expects 'id'
                'user_id': profile.user_id,        # Keep for compatibility
                'elder_id': profile.elder_id,
                'user_name': profile.elder_name,   # Flutter expects 'user_name'
                'gender': profile.gender,
                'age': profile.age,
                'location': profile.location or "未知",
                'is_online': True                  # Mock online status
            })
            
    return jsonify(elders_list)

@user_bp.route('/status/<int:user_id>', methods=['GET'])
def get_status(user_id):
    """取得使用者狀態與角色判定"""
    profile = ElderProfile.query.filter_by(user_id=user_id).first()
    role = 'elder' if profile else 'family'
    return jsonify({
        'status': 'online', 
        'user_id': user_id,
        'role': role
    })
