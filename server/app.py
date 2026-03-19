# server/app.py
from flask import Flask, request, jsonify
from flask_socketio import SocketIO, emit, join_room, leave_room
from flask_cors import CORS
from extensions import db  # 使用 extensions.db
import firebase_admin
from firebase_admin import credentials, messaging
import os
import uuid
from dotenv import load_dotenv
from datetime import datetime
from models import CallRecord

# 引入路由
from routes.auth import auth_bp
from routes.user import user_bp
from routes.pairing import pairing_bp
from routes.ai import ai_bp

load_dotenv()

# 初始化 Firebase Admin SDK (容錯化處理)
firebase_enabled = False
try:
    if not firebase_admin._apps:
        cred_path = os.path.join(os.path.dirname(__file__), "serviceAccountKey.json")
        if os.path.exists(cred_path):
            cred = credentials.Certificate(cred_path)
            firebase_admin.initialize_app(cred)
            firebase_enabled = True
            print("✅ Firebase Admin SDK 已初始化")
        else:
            print("⚠️ Firebase serviceAccountKey.json 缺失，將停用 FCM 功能")
    else:
        firebase_enabled = True
        print("✅ Firebase Admin SDK 已取得現有實例")
except Exception as e:
    print(f"⚠️ Firebase 啟動失敗 (將停用推播功能): {e}")

app = Flask(__name__)
CORS(app)
app.config['SECRET_KEY'] = 'secret!'

# 資料庫設定 (SQLite)
base_dir = os.path.dirname(os.path.abspath(__file__))
db_path = os.path.join(base_dir, 'instance', 'uban.db')
if not os.path.exists(os.path.join(base_dir, 'instance')):
    os.makedirs(os.path.join(base_dir, 'instance'))

app.config['SQLALCHEMY_DATABASE_URI'] = f'sqlite:///{db_path}'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

# 初始化 SQLAlchemy
db.init_app(app)

# 註冊藍圖
app.register_blueprint(auth_bp, url_prefix='/api/auth')
app.register_blueprint(user_bp, url_prefix='/api/user')
app.register_blueprint(pairing_bp, url_prefix='/api/pairing')
app.register_blueprint(ai_bp, url_prefix='/api/ai')

# 使用 Eventlet 模式
# cors_allowed_origins="*" 放在最後初始化 app 之後
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='threading')

with app.app_context():
    import models  # 確保模型被讀取
    db.create_all()
    print("✅ 資料庫表已同步(或已存在)")

# 房間管理結構：rooms_manager[room_id][socket_id] = {role, deviceName, deviceMode}
rooms_manager = {}
# FCM Token 持久化結構：room_fcm_tokens[room_id][fcm_token] = {role, deviceName}
room_fcm_tokens = {}

# --- [API] 健康檢查 ---
@app.route('/api/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'ok'})

# --- [API] 獲取長輩列表 (相容舊版邏輯) ---
@app.route('/api/get_elder_data', methods=['GET'])
def get_elder_data():
    user_id = request.args.get('user_id')
    if not user_id:
        return jsonify({'status': 'error', 'message': 'Missing user_id'}), 400

    try:
        from models import ElderProfile
        results = ElderProfile.query.filter_by(user_id=user_id).all()
        
        if results:
            elders_list = [
                {'elder_id': row.elder_id, 'elder_name': row.elder_name}
                for row in results
            ]
            return jsonify({'status': 'success', 'elders': elders_list})
        else:
            return jsonify({'status': 'error', 'message': '查無資料'}), 404
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500

# --- [API] 獲取通話紀錄 ---
@app.route('/api/call_history', methods=['GET'])
def get_call_history():
    room_id = request.args.get('room_id')
    if not room_id:
        return jsonify({'status': 'error', 'message': 'Missing room_id'}), 400

    try:
        records = CallRecord.query.filter_by(room_id=room_id).order_by(CallRecord.start_time.desc()).limit(50).all()
        history = []
        for r in records:
            history.append({
                'call_id': r.call_id,
                'caller_id': r.caller_id,
                'callee_id': r.callee_id,
                'start_time': r.start_time.isoformat() if r.start_time else None,
                'end_time': r.end_time.isoformat() if r.end_time else None,
                'status': r.status,
                'caller_name': r.caller.user_name if r.caller else "未知",
                'callee_name': r.callee.user_name if r.callee else "未知"
            })
        return jsonify({'status': 'success', 'history': history})
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500

# --- [Socket] 信令邏輯 ---

@socketio.on('join')
def on_join(data):
    room = data.get('room')
    role = data.get('role', 'unknown')
    device_name = data.get('deviceName', 'Unknown Device')
    device_mode = data.get('deviceMode', 'comm') 
    fcm_token = data.get('fcmToken')
    sid = request.sid

    if room:
        if role == 'elder' and room in rooms_manager:
            sids_to_remove = []
            for existing_sid, info in rooms_manager[room].items():
                if info['role'] == 'elder' and info['deviceName'] == device_name and existing_sid != sid:
                    print(f"⚠️ Conflict detected: Removing old session {existing_sid} for {device_name}")
                    sids_to_remove.append(existing_sid)
            for old_sid in sids_to_remove:
                del rooms_manager[room][old_sid]

        join_room(room)
        
        if room not in rooms_manager:
            rooms_manager[room] = {}
        if room not in room_fcm_tokens:
            room_fcm_tokens[room] = {}
        
        user_id = data.get('userId') # 從客戶端傳來的資料庫 ID
        rooms_manager[room][sid] = {
            'role': role,
            'deviceName': device_name,
            'deviceMode': device_mode,
            'fcmToken': fcm_token,
            'userId': user_id # 儲存資料庫 ID 綁定到 SID
        }

        if fcm_token:
            room_fcm_tokens[room][fcm_token] = {
                'role': role,
                'deviceName': device_name,
                'deviceMode': device_mode
            }
        
        print(f"✅ User {sid} ({role} - {device_name}) joined room: {room}")
        emit('user-joined', {
            'id': sid, 
            'role': role, 
            'deviceName': device_name, 
            'deviceMode': device_mode
        }, to=room, include_self=False)

        if role == 'family':
            elder_devices = []
            online_device_names = set()

            if room in rooms_manager:
                for k, v in rooms_manager[room].items():
                    if v.get('role') == 'elder':
                        elder_devices.append({
                            'id': k, 
                            'deviceName': v['deviceName'], 
                            'deviceMode': v.get('deviceMode', 'comm'),
                            'isOnline': True
                        })
                        online_device_names.add(v['deviceName'])

            if room in room_fcm_tokens:
                for token, info in room_fcm_tokens[room].items():
                    if info.get('role') == 'elder' and info['deviceName'] not in online_device_names:
                        elder_devices.append({
                            'id': f"offline_{token[-8:]}", 
                            'deviceName': info['deviceName'],
                            'deviceMode': info.get('deviceMode', 'comm'),
                            'isOnline': False
                        })
                        
            emit('elder-devices-update', elder_devices, to=sid)

@socketio.on('get-elder-devices')
def on_get_elder_devices(room):
    sid = request.sid
    elder_devices = []
    online_device_names = set()

    if room in rooms_manager:
        for k, v in rooms_manager[room].items():
            if v.get('role') == 'elder':
                elder_devices.append({
                    'id': k, 
                    'deviceName': v['deviceName'], 
                    'deviceMode': v.get('deviceMode', 'comm'),
                    'isOnline': True
                })
                online_device_names.add(v['deviceName'])

    if room in room_fcm_tokens:
        for token, info in room_fcm_tokens[room].items():
            if info.get('role') == 'elder' and info['deviceName'] not in online_device_names:
                elder_devices.append({
                    'id': f"offline_{token[-8:]}", 
                    'deviceName': info['deviceName'],
                    'deviceMode': info.get('deviceMode', 'comm'),
                    'isOnline': False
                })
                
    emit('elder-devices-update', elder_devices, to=sid)

@socketio.on('disconnect')
def on_disconnect():
    sid = request.sid
    for room, users in rooms_manager.items():
        if sid in users:
            del users[sid]
            emit('user-left', {'id': sid}, to=room)
            print(f"❌ User {sid} disconnected")
            if not users:
                del rooms_manager[room]
            break

@socketio.on('call-request')
def on_call_request(data):
    sid = request.sid
    room = data.get('room')
    sender_id = request.sid
    sender_role = data.get('role') or rooms_manager.get(room, {}).get(sender_id, {}).get('role')
    target_role = 'elder' if sender_role == 'family' else 'family'
    target_id = data.get('targetId')
    call_id = str(uuid.uuid4())

    print(f"📡 [Call Request] From: {sid} In: {room} -> Target: {target_id} (CallId: {call_id})")
    
    # [CRUD] 建立通話紀錄
    try:
        caller_user_id = data.get('callerUserId') or rooms_manager.get(room, {}).get(sender_id, {}).get('userId')
        if caller_user_id:
            new_call = CallRecord(
                call_id=call_id,
                room_id=room,
                caller_id=int(caller_user_id),
                status='ringing'
            )
            db.session.add(new_call)
            db.session.commit()
            print(f"📝 Call record created: {call_id}")
    except Exception as e:
        print(f"⚠️ Failed to create call record: {e}")
        db.session.rollback()

    if room in rooms_manager:
        for target_sid, info in rooms_manager[room].items():
            if info.get('role') == target_role:
                emit('call-request', {'senderId': sender_id, 'room': room, 'role': sender_role, 'callId': call_id}, to=target_sid)

    if room in room_fcm_tokens:
        for token, info in room_fcm_tokens[room].items():
            if info.get('role') == target_role:
                try:
                    message = messaging.Message(
                        data={'type': 'call-request', 'senderId': sender_id, 'roomId': room, 'role': str(sender_role), 'callId': call_id},
                        token=token,
                        android=messaging.AndroidConfig(priority='high', notification=messaging.AndroidNotification(channel_id='Call_Ring_Channel')),
                        apns=messaging.APNSConfig(payload=messaging.APNSPayload(aps=messaging.Aps(content_available=True)))
                    )
                    if firebase_enabled:
                        messaging.send(message)
                except Exception as e:
                    print(f"⚠️ FCM 推播發送失敗 ({info['role']}): {e}")

@socketio.on('cancel-call')
def on_cancel_call(data):
    room = data.get('room')
    sender_id = request.sid
    sender_role = data.get('role') or rooms_manager.get(room, {}).get(sender_id, {}).get('role')
    target_role = 'elder' if sender_role == 'family' else 'family'
    call_id = data.get('callId')

    if room in rooms_manager:
        for target_sid, info in rooms_manager[room].items():
            if info.get('role') == target_role:
                emit('cancel-call', {'senderId': sender_id, 'room': room, 'callId': call_id}, to=target_sid)

    if room in room_fcm_tokens:
        for token, info in room_fcm_tokens[room].items():
            if info.get('role') == target_role:
                try:
                    message = messaging.Message(
                        data={'type': 'cancel-call', 'senderId': sender_id, 'roomId': room, 'callId': call_id},
                        token=token,
                        android=messaging.AndroidConfig(priority='high'),
                        apns=messaging.APNSConfig(payload=messaging.APNSPayload(aps=messaging.Aps(content_available=True)))
                    )
                    if firebase_enabled:
                        messaging.send(message)
                except Exception: pass

    # [CRUD] 更新為未接
    if call_id:
        try:
            record = CallRecord.query.filter_by(call_id=call_id).first()
            if record:
                record.status = 'missed'
                record.end_time = datetime.utcnow()
                db.session.commit()
        except Exception: pass

@socketio.on('emergency-call')
def on_emergency_call(data):
    room = data.get('room')
    sender_id = request.sid
    sender_role = data.get('role') or rooms_manager.get(room, {}).get(sender_id, {}).get('role')
    target_role = 'elder' if sender_role == 'family' else 'family'
    call_id = str(uuid.uuid4())

    if room in rooms_manager:
        for target_sid, info in rooms_manager[room].items():
            if info.get('role') == target_role:
                emit('emergency-call', {'senderId': sender_id, 'room': room, 'callId': call_id}, to=target_sid)

    if room in room_fcm_tokens:
        for token, info in room_fcm_tokens[room].items():
            if info.get('role') == target_role:
                try:
                    message = messaging.Message(
                        data={'type': 'emergency-call', 'senderId': sender_id, 'roomId': room, 'callId': call_id},
                        token=token,
                        android=messaging.AndroidConfig(priority='high', notification=messaging.AndroidNotification(channel_id='Emergency_Ring_Channel')),
                        apns=messaging.APNSConfig(payload=messaging.APNSPayload(aps=messaging.Aps(content_available=True)))
                    )
                    if firebase_enabled:
                        messaging.send(message)
                except Exception as e:
                    print(f"⚠️ FCM 緊急推播失敗 ({info['role']}): {e}")

@socketio.on('call-accept')
def on_call_accept(data):
    sid = request.sid
    target_id = data.get('targetId')
    call_id = data.get('callId')
    print(f"📞 [Call Accept] {sid} accepted for Target: {target_id} (CallId: {call_id})")
    
    # [CRUD] 更新通話紀錄狀態為已接聽
    if call_id:
        try:
            record = CallRecord.query.filter_by(call_id=call_id).first()
            if record:
                # 獲取接聽者的 userId
                accepter_user_id = None
                for rm in rooms_manager.values():
                    if sid in rm:
                        accepter_user_id = rm[sid].get('userId')
                        break
                
                if accepter_user_id:
                    record.callee_id = int(accepter_user_id)
                record.status = 'connected'
                db.session.commit()
        except Exception as e:
            print(f"⚠️ Failed to update call accept: {e}")

    emit('call-accept', {'accepterId': sid, 'callId': call_id}, to=target_id)

@socketio.on('call-busy')
def on_call_busy(data):
    target_id = data.get('targetId')
    call_id = data.get('callId')
    print(f"🚫 Call Busy from {request.sid}, notifying {target_id} (CallId: {call_id})")

    # [CRUD] 更新為拒絕
    if call_id:
        try:
            record = CallRecord.query.filter_by(call_id=call_id).first()
            if record:
                record.status = 'rejected'
                record.end_time = datetime.utcnow()
                db.session.commit()
        except Exception: pass

    emit('call-busy', {'targetId': request.sid, 'callId': call_id}, to=target_id)

@socketio.on('offer')
def on_offer(data):
    target = data.get('targetId')
    data['senderId'] = request.sid 
    if target:
        emit('offer', data, to=target)
    else:
        room = data.get('room')
        if room: emit('offer', data, to=room, include_self=False)

@socketio.on('answer')
def on_answer(data):
    target = data.get('targetId')
    if target: emit('answer', data, to=target)

@socketio.on('candidate')
def on_candidate(data):
    target = data.get('targetId')
    if target: emit('candidate', data, to=target)

@socketio.on('end-call')
def on_end_call(data):
    target = data.get('targetId')
    room = data.get('room')
    call_id = data.get('callId')
    
    # [CRUD] 更新通話結束時間
    if call_id:
        try:
            record = CallRecord.query.filter_by(call_id=call_id).first()
            if record:
                record.status = 'ended'
                record.end_time = datetime.utcnow()
                db.session.commit()
                print(f"🏁 Call record ended: {call_id}")
        except Exception: pass

    if target: 
        emit('end-call', {'room': room}, to=target)

@socketio.on('delete-device')
def on_delete_device(data):
    room = data.get('room')
    target_id = data.get('targetId')
    sender_id = request.sid
    resolved_device_name = None

    if room in rooms_manager and target_id in rooms_manager[room]:
        resolved_device_name = rooms_manager[room][target_id].get('deviceName')

    if not resolved_device_name and room in room_fcm_tokens:
        for token, info in room_fcm_tokens[room].items():
            if token == target_id or f"offline_{token[-8:]}" == target_id:
                resolved_device_name = info.get('deviceName')
                break

    if not resolved_device_name: return

    if room in rooms_manager:
        sids_to_kick = [sid for sid, info in rooms_manager[room].items() if info.get('deviceName') == resolved_device_name]
        for kick_sid in sids_to_kick:
            emit('force-logout', {}, to=kick_sid)
            del rooms_manager[room][kick_sid]
            emit('user-left', kick_sid, to=room)

    if room in room_fcm_tokens:
        tokens_to_wipe = [token for token, info in room_fcm_tokens[room].items() if info.get('deviceName') == resolved_device_name]
        for token in tokens_to_wipe:
            try:
                message = messaging.Message(data={'type': 'force-logout', 'roomId': room}, token=token, android=messaging.AndroidConfig(priority='high'))
                if firebase_enabled: messaging.send(message)
            except Exception: pass
            del room_fcm_tokens[room][token]

    if room in rooms_manager and sender_id in rooms_manager[room]:
        elder_devices = []
        online_names = set()
        for k, v in rooms_manager[room].items():
            if v.get('role') == 'elder':
                elder_devices.append({'id': k, 'deviceName': v['deviceName'], 'deviceMode': v.get('deviceMode', 'comm'), 'isOnline': True})
                online_names.add(v['deviceName'])
        if room in room_fcm_tokens:
            for token, info in room_fcm_tokens[room].items():
                if info.get('role') == 'elder' and info['deviceName'] not in online_names:
                    elder_devices.append({'id': f"offline_{token[-8:]}", 'deviceName': info['deviceName'], 'deviceMode': info.get('deviceMode', 'comm'), 'isOnline': False})
        emit('elder-devices-list', elder_devices, to=sender_id)

if __name__ == '__main__':
    print("🚀 Server starting on port 5001...")
    socketio.run(app, host='0.0.0.0', port=5001, debug=True)
