import io
from flask import Blueprint, jsonify, request, send_from_directory, send_file
from models import User, Relationship, ElderProfile
from extensions import db
from datetime import datetime
from werkzeug.utils import secure_filename
import os

user_bp = Blueprint('user', __name__)

UPLOAD_FOLDER = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'uploads', 'avatars')
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

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
        # Return a 1x1 transparent PNG to prevent Flutter Image.network 404 exceptions
        transparent_png = b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\xfa\x0f\x00\x01\x05\x01\x02\xcf\xa0.\xcd\x00\x00\x00\x00IEND\xaeB`\x82'
        return send_file(io.BytesIO(transparent_png), mimetype='image/png')


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

@user_bp.route('/profile/<int:user_id>', methods=['GET'])
def get_elder_profile(user_id):
    profile = ElderProfile.query.filter_by(user_id=user_id).first()
    if not profile:
        return jsonify({
            'phone': '', 'location': '台北市士林區', 'ai_persona': '溫暖孫子',
            'chronic_diseases': '', 'medication_notes': '', 'interests': ''
        })
    return jsonify({
        'phone': profile.phone,
        'location': profile.location,
        'ai_persona': profile.ai_persona,
        'chronic_diseases': profile.chronic_diseases,
        'medication_notes': profile.medication_notes,
        'interests': profile.interests
    })

@user_bp.route('/profile/<int:user_id>', methods=['POST'])
def update_elder_profile(user_id):
    data = request.json
    profile = ElderProfile.query.filter_by(user_id=user_id).first()
    
    if not profile:
        profile = ElderProfile(user_id=user_id)
        db.session.add(profile)
        
    profile.phone = data.get('phone', profile.phone)
    profile.location = data.get('location', profile.location)
    profile.ai_persona = data.get('ai_persona', profile.ai_persona)
    profile.chronic_diseases = data.get('chronic_diseases', profile.chronic_diseases)
    profile.medication_notes = data.get('medication_notes', profile.medication_notes)
    profile.interests = data.get('interests', profile.interests)
    
    db.session.commit()
    return jsonify({'message': 'Profile updated successfully'})

