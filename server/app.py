# server/app.py
import ssl

# SSL 補丁 (針對 Python 3.13+)
# 由於核心庫與 eventlet 的運作機制，手動補上 wrap_socket 以維持相容性
if not hasattr(ssl, 'wrap_socket'):
    def dummy_wrap_socket(sock, *args, **kwargs):
        context = ssl.SSLContext(kwargs.get('ssl_version', ssl.PROTOCOL_TLS))
        return context.wrap_socket(sock, *args, **kwargs)
    ssl.wrap_socket = dummy_wrap_socket

from flask import Flask, request, jsonify
from flask_socketio import SocketIO, emit, join_room, leave_room
from db import db
import uuid, os
from dotenv import load_dotenv

load_dotenv()
import firebase_admin
from firebase_admin import credentials, messaging
from extensions import db as sqlalchemy_db
from routes.user import user_bp
from routes.game_logic import game_logic_bp

# 初始化 Firebase Admin SDK (用於傳送撥號通知)
try:
    if not firebase_admin._apps:
        cred_path = os.path.join(os.path.dirname(__file__), "serviceAccountKey.json")
        cred = credentials.Certificate(cred_path)
        firebase_admin.initialize_app(cred)
        print("Firebase Admin SDK Initialized")
    else:
        print("Firebase Admin SDK instance already exists")
except Exception as e:
    print(f"Warning: Firebase initialization failed: {e}")

app = Flask(__name__)
# CORS(app) # 視需求開啟跨域請求
app.config['SECRET_KEY'] = 'secret!'

# 使用 threading 模式 (在 Windows 下比 Eventlet 更穩定，且與 PyMySQL 相容性好)
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='threading')

# SQLAlchemy 初始化 (使用 PyMySQL 驅動)
app.config['SQLALCHEMY_DATABASE_URI'] = f"mysql+pymysql://{os.getenv('MYSQL_USER')}:{os.getenv('MYSQL_PASSWORD')}@{os.getenv('MYSQL_HOST')}/{os.getenv('MYSQL_DB_NAME')}?ssl_disabled=true"
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
sqlalchemy_db.init_app(app)

# 註冊 API 藍圖
app.register_blueprint(user_bp, url_prefix='/api/user')
app.register_blueprint(game_logic_bp, url_prefix='/api/game')

from apscheduler.schedulers.background import BackgroundScheduler
from routes.game_logic import do_distribute_appearances, load_schedule_time, save_schedule_time
from datetime import datetime

# 啟動排程器 (設定時間自動派發造型)
scheduler = BackgroundScheduler()

def check_and_distribute():
    dist_time_str = load_schedule_time()
    if not dist_time_str:
        return
        
    try:
        dist_time = datetime.fromisoformat(dist_time_str)
        now = datetime.utcnow()
        if now >= dist_time:
            print(f"Executing scheduled distribution for time: {dist_time_str}")
            with app.app_context():
                do_distribute_appearances()
            save_schedule_time(None)
    except Exception as e:
        print(f"Error checking schedule: {e}")

scheduler.add_job(check_and_distribute, 'interval', minutes=1)

# 房間管理結構：rooms_manager[room_id][socket_id] = {role, deviceName, deviceMode}
rooms_manager = {}
# FCM Token 管理對照表：room_fcm_tokens[room_id][fcm_token] = {role, deviceName}
room_fcm_tokens = {}

# --- [API] 取得長輩列表 ---
@app.route('/api/get_elder_data', methods=['GET'])
def get_elder_data():
    user_id = request.args.get('user_id')
    if not user_id:
        return jsonify({'status': 'error', 'message': 'Missing user_id'}), 400

    try:
        cursor = db.get_mysql_cursor()
        query = "SELECT elder_id, elder_name FROM elder_profile WHERE user_id = %s"
        cursor.execute(query, (user_id,))
        results = cursor.fetchall()
        cursor.close()
        
        if results:
            elders_list = [
                {'elder_id': row['elder_id'], 'elder_name': row['elder_name']}
                for row in results
            ]
            return jsonify({'status': 'success', 'elders': elders_list})
        else:
            return jsonify({'status': 'error', 'message': '目前無資料'}), 404
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500

# --- [Socket] 房間與連線管理 ---

@socketio.on('join')
def on_join(data):
    room = data.get('room')
    role = data.get('role', 'unknown')
    device_name = data.get('deviceName', 'Unknown Device')
    device_mode = data.get('deviceMode', 'comm') 
    fcm_token = data.get('fcmToken')
    sid = request.sid

    if room:
        # 重複名稱檢查
        if role == 'elder' and room in rooms_manager:
            for existing_sid, info in rooms_manager[room].items():
                if info['role'] == 'elder' and info['deviceName'] == device_name:
                    print(f"Join Failed: Name '{device_name}' exists in room {room}")
                    emit('join-failed', {'message': f'名稱 "{device_name}" 已被使用，請更改名稱'}, to=sid)
                    return 

        join_room(room)
        
        if room not in rooms_manager:
            rooms_manager[room] = {}
        if room not in room_fcm_tokens:
            room_fcm_tokens[room] = {}
        
        rooms_manager[room][sid] = {
            'role': role,
            'deviceName': device_name,
            'deviceMode': device_mode,
            'fcmToken': fcm_token
        }

        # 儲存或更新 FCM Token
        if fcm_token:
            room_fcm_tokens[room][fcm_token] = {
                'role': role,
                'deviceName': device_name,
                'deviceMode': device_mode
            }
        
        print(f"User {sid} ({role} - {device_name}) joined room: {room}")
        
        # 通知房間內其他成員
        emit('user-joined', {
            'id': sid, 
            'role': role, 
            'deviceName': device_name, 
            'deviceMode': device_mode
        }, to=room, include_self=False)

        # 家屬端同步長輩設備清單
        if role == 'family':
            update_elder_devices(room, sid)

@socketio.on('get-elder-devices')
def on_get_elder_devices(room):
    sid = request.sid
    print(f"[Get Devices] Request from {sid} for room {room}")
    update_elder_devices(room, sid)

def update_elder_devices(room, target_sid):
    elder_devices = []
    online_device_names = set()

    # 1. 取得目前在線上的長輩設備
    if room in rooms_manager:
        for ks, vs in rooms_manager[room].items():
            if vs.get('role') == 'elder':
                elder_devices.append({
                    'id': ks, 
                    'deviceName': vs['deviceName'], 
                    'deviceMode': vs.get('deviceMode', 'comm'),
                    'isOnline': True
                })
                online_device_names.add(vs['deviceName'])

    # 2. 取得離線但有 FCM Token 的長輩設備
    if room in room_fcm_tokens:
        for token, info in room_fcm_tokens[room].items():
            if info.get('role') == 'elder' and info['deviceName'] not in online_device_names:
                elder_devices.append({
                    'id': f"offline_{token[-8:]}", 
                    'deviceName': info['deviceName'],
                    'deviceMode': info.get('deviceMode', 'comm'),
                    'isOnline': False
                })
                
    emit('elder-devices-update', elder_devices, to=target_sid)

@socketio.on('disconnect')
def on_disconnect():
    sid = request.sid
    for room, users in rooms_manager.items():
        if sid in users:
            del users[sid]
            emit('user-left', {'id': sid}, to=room)
            print(f"User {sid} disconnected from room {room}")
            if not users:
                del rooms_manager[room]
            break

# --- [Socket] 通話握手 (Handshake) ---
@socketio.on('call-request')
def on_call_request(data):
    room = data.get('room')
    sender_id = request.sid
    sender_role = data.get('role') or (rooms_manager.get(room, {}).get(sender_id, {}).get('role'))
    target_role = 'elder' if sender_role == 'family' else 'family'
    target_id = data.get('targetId')
    call_id = str(uuid.uuid4())

    print(f"[Call Request] {sender_role} ({sender_id}) in {room} -> Target: {target_id or target_role}")
    
    # 1. 向在線上的目標 Socket 發送通知
    if room in rooms_manager:
        for tsid, info in rooms_manager[room].items():
            if info.get('role') == target_role:
                emit('call-request', {'senderId': sender_id, 'room': room, 'role': sender_role, 'callId': call_id}, to=tsid)

    # 2. 向目標設備發送 FCM 推播通知 (喚醒後台 App)
    if room in room_fcm_tokens:
        for token, info in room_fcm_tokens[room].items():
            if info.get('role') == target_role:
                try:
                    message = messaging.Message(
                        data={'type': 'call-request', 'senderId': sender_id, 'roomId': room, 'role': str(sender_role), 'callId': call_id},
                        token=token,
                        android=messaging.AndroidConfig(
                            priority='high',
                            notification=messaging.AndroidNotification(channel_id='Call_Ring_Channel')
                        )
                    )
                    messaging.send(message)
                except Exception as e:
                    print(f"FCM 推送失敗 ({info['role']}): {e}")

@socketio.on('cancel-call')
def on_cancel_call(data):
    room = data.get('room')
    sender_id = request.sid
    sender_role = data.get('role') or (rooms_manager.get(room, {}).get(sender_id, {}).get('role'))
    target_role = 'elder' if sender_role == 'family' else 'family'
    call_id = data.get('callId')

    print(f"Cancel Call Request from {sender_id} to {target_role} in {room} (Call ID: {call_id})")
    
    if room in rooms_manager:
        for tsid, info in rooms_manager[room].items():
            if info.get('role') == target_role:
                emit('cancel-call', {'senderId': sender_id, 'room': room, 'callId': call_id}, to=tsid)

    if room in room_fcm_tokens:
        for token, info in room_fcm_tokens[room].items():
            if info.get('role') == target_role:
                try:
                    message = messaging.Message(
                        data={'type': 'cancel-call', 'senderId': sender_id, 'roomId': room, 'callId': call_id},
                        token=token,
                        android=messaging.AndroidConfig(priority='high')
                    )
                    messaging.send(message)
                except Exception: pass

@socketio.on('emergency-call')
def on_emergency_call(data):
    room = data.get('room')
    sender_id = request.sid
    sender_role = data.get('role') or (rooms_manager.get(room, {}).get(sender_id, {}).get('role'))
    target_role = 'elder' if sender_role == 'family' else 'family'
    call_id = str(uuid.uuid4())

    print(f"Emergency Call Request from {sender_id} to {target_role} in {room}")
    
    if room in rooms_manager:
        for tsid, info in rooms_manager[room].items():
            if info.get('role') == target_role:
                emit('emergency-call', {'senderId': sender_id, 'room': room, 'callId': call_id}, to=tsid)

    if room in room_fcm_tokens:
        for token, info in room_fcm_tokens[room].items():
            if info.get('role') == target_role:
                try:
                    message = messaging.Message(
                        data={'type': 'emergency-call', 'senderId': sender_id, 'roomId': room, 'callId': call_id},
                        token=token,
                        android=messaging.AndroidConfig(
                            priority='high',
                            notification=messaging.AndroidNotification(channel_id='Emergency_Ring_Channel')
                        )
                    )
                    messaging.send(message)
                except Exception as e:
                    print(f"FCM 緊急推送失敗: {e}")

@socketio.on('call-accept')
def on_call_accept(data):
    sid = request.sid
    target_id = data.get('targetId')
    call_id = data.get('callId')
    print(f"[Call Accept] {sid} accepted (Call ID: {call_id})")
    emit('call-accept', {'accepterId': sid, 'callId': call_id}, to=target_id)

@socketio.on('call-busy')
def on_call_busy(data):
    target_id = data.get('targetId')
    call_id = data.get('callId')
    print(f"Call Busy from {request.sid} (Call ID: {call_id})")
    emit('call-busy', {'targetId': request.sid, 'callId': call_id}, to=target_id)

# --- WebRTC 信令轉發 ---
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
    if target: 
        emit('end-call', {'room': room}, to=target)

# --- 遠端刪除設備 ---
@socketio.on('delete-device')
def on_delete_device(data):
    room = data.get('room')
    target_id = data.get('targetId')
    sender_id = request.sid
    print(f"Delete Device: {target_id} in room {room}")

    resolved_device_name = None
    # 1. 嘗試從線上清單解析名稱
    if room in rooms_manager and target_id in rooms_manager[room]:
        resolved_device_name = rooms_manager[room][target_id].get('deviceName')

    # 2. 嘗試從 FCM 清單解析
    if not resolved_device_name and room in room_fcm_tokens:
        for token, info in room_fcm_tokens[room].items():
            if token == target_id or f"offline_{token[-8:]}" == target_id:
                resolved_device_name = info.get('deviceName')
                break

    if not resolved_device_name: return

    # 3. 踢除所有相同名稱的線上 Socket
    if room in rooms_manager:
        sids_to_kick = [sid for sid, info in rooms_manager[room].items() if info.get('deviceName') == resolved_device_name]
        for skid in sids_to_kick:
            emit('force-logout', {}, to=skid)
            del rooms_manager[room][skid]
            emit('user-left', skid, to=room)

    # 4. 抹除所有相同名稱的 FCM 紀錄
    if room in room_fcm_tokens:
        tokens_to_wipe = [token for token, info in room_fcm_tokens[room].items() if info.get('deviceName') == resolved_device_name]
        for token in tokens_to_wipe:
            try:
                message = messaging.Message(data={'type': 'force-logout', 'roomId': room}, token=token)
                messaging.send(message)
            except: pass
            del room_fcm_tokens[room][token]

    # 5. 更新清單給家屬端
    update_elder_devices(room, sender_id)

if __name__ == '__main__':
    # 初始化資料庫連線
    try:
        print('Connecting to database...')
        db.connect_mysql()
    except Exception as e:
        print(f'Warning: Database connection issue: {e}')

    print('Server starting on port 5000...')
    # 啟動自動派發排程器
    scheduler.start()
    # 啟動 SocketIO 伺服器
    socketio.run(app, host='0.0.0.0', port=5000, debug=False, allow_unsafe_werkzeug=True)
