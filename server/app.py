# server/app.py
import eventlet
import ssl

# SSL 補丁 (針對 Python 3.13+)
if not hasattr(ssl, 'wrap_socket'):
    def dummy_wrap_socket(sock, *args, **kwargs):
        context = ssl.SSLContext(kwargs.get('ssl_version', ssl.PROTOCOL_TLS))
        return context.wrap_socket(sock, *args, **kwargs)
    ssl.wrap_socket = dummy_wrap_socket

eventlet.monkey_patch()

from flask import Flask, request, jsonify
from flask_socketio import SocketIO, emit, join_room, leave_room
from db import db  
import firebase_admin
from firebase_admin import credentials, messaging
import os

# 初始化 Firebase Admin SDK
try:
    if not firebase_admin._apps:
        cred_path = os.path.join(os.path.dirname(__file__), "serviceAccountKey.json")
        cred = credentials.Certificate(cred_path)
        firebase_admin.initialize_app(cred)
        print("✅ Firebase Admin SDK 已初始化")
    else:
        print("✅ Firebase Admin SDK 已取得現有實例")
except Exception as e:
    print(f"⚠️ Firebase 初始化失敗: {e}")

app = Flask(__name__)
#CORS(app) # 允許跨域請求
app.config['SECRET_KEY'] = 'secret!'

# 使用 Eventlet 模式
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='eventlet')

# 初始化資料庫
try:
    print("正在連接資料庫...")
    db.connect_mysql()
    #db.connect_mongo()
except Exception as e:
    print(f"⚠️ 資料庫連線警告: {e}")

# 房間管理結構：rooms_manager[room_id][socket_id] = {role, deviceName, deviceMode}
rooms_manager = {}
# FCM Token 持久化結構：room_fcm_tokens[room_id][fcm_token] = {role, deviceName}
room_fcm_tokens = {}

# --- [API] 獲取長輩列表 ---
@app.route('/api/get_elder_data', methods=['GET'])
def get_elder_data():
    user_id = request.args.get('user_id')
    if not user_id:
        return jsonify({'status': 'error', 'message': 'Missing user_id'}), 400

    try:
        cursor = db.get_mysql_cursor()
        query = "SELECT elder_id, elder_name FROM elder_user_data WHERE user_id = %s"
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
            return jsonify({'status': 'error', 'message': '查無資料'}), 404
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500

# --- [Socket] 信令邏輯 ---

@socketio.on('join')
def on_join(data):
    room = data.get('room')
    role = data.get('role', 'unknown')
    device_name = data.get('deviceName', 'Unknown Device')
    device_mode = data.get('deviceMode', 'comm') 
    fcm_token = data.get('fcmToken') # ★ 接收 FCM Token
    sid = request.sid

    if room:
        # ★★★ 檢查名稱重複 (僅限長輩端) ★★★
        if role == 'elder' and room in rooms_manager:
            for existing_sid, info in rooms_manager[room].items():
                if info['role'] == 'elder' and info['deviceName'] == device_name:
                    print(f"⛔ Join Failed: Name '{device_name}' exists in room {room}")
                    emit('join-failed', {'message': f'名稱 "{device_name}" 已被使用，請更換名稱'}, to=sid)
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
            'fcmToken': fcm_token # ★ 儲存 FCM Token
        }

        # ★ 備份 FCM Token 持久化
        if fcm_token:
            room_fcm_tokens[room][fcm_token] = {
                'role': role,
                'deviceName': device_name
            }
        
        print(f"✅ User {sid} ({role} - {device_name}) joined room: {room}")
        
        # 廣播加入
        emit('user-joined', {
            'id': sid, 
            'role': role, 
            'deviceName': device_name, 
            'deviceMode': device_mode
        }, to=room, include_self=False)

        # 回傳長輩列表給家屬
        if role == 'family':
            elder_devices = [
                {
                    'id': k, 
                    'deviceName': v['deviceName'], 
                    'deviceMode': v.get('deviceMode', 'comm')
                } 
                for k, v in rooms_manager[room].items() 
                if v['role'] == 'elder'
            ]
            emit('elder-devices-list', elder_devices, to=sid)

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

# --- 響鈴與接聽 (Handshake) ---
@socketio.on('call-request')
def on_call_request(data):
    room = data.get('room')
    sender_id = request.sid
    sender_role = data.get('role') or rooms_manager.get(room, {}).get(sender_id, {}).get('role')
    target_role = 'elder' if sender_role == 'family' else 'family'

    print(f"🔔 Call Request from {sender_id} ({sender_role}) to {target_role} in {room}")
    
    # 1. 針對房間內符合目標角色的 Socket 發送
    if room in rooms_manager:
        for sid, info in rooms_manager[room].items():
            if info.get('role') == target_role:
                emit('call-request', {'senderId': sender_id, 'room': room}, to=sid)

    # 2. 針對目標角色發送 FCM 靜默推播喚醒
    if room in room_fcm_tokens:
        for token, info in room_fcm_tokens[room].items():
            if info.get('role') == target_role:
                try:
                    message = messaging.Message(
                        data={'type': 'call-request', 'senderId': sender_id, 'roomId': room},
                        token=token,
                        android=messaging.AndroidConfig(priority='high')
                    )
                    messaging.send(message)
                except Exception as e:
                    print(f"⚠️ FCM 推播發送失敗 ({info['role']}): {e}")

@socketio.on('cancel-call')
def on_cancel_call(data):
    room = data.get('room')
    sender_id = request.sid
    sender_role = data.get('role') or rooms_manager.get(room, {}).get(sender_id, {}).get('role')
    target_role = 'elder' if sender_role == 'family' else 'family'

    print(f"🔕 Cancel Call Request from {sender_id} to {target_role} in {room}")
    
    if room in rooms_manager:
        for sid, info in rooms_manager[room].items():
            if info.get('role') == target_role:
                emit('cancel-call', {'senderId': sender_id, 'room': room}, to=sid)

    if room in room_fcm_tokens:
        for token, info in room_fcm_tokens[room].items():
            if info.get('role') == target_role:
                try:
                    message = messaging.Message(
                        data={'type': 'cancel-call', 'senderId': sender_id, 'roomId': room},
                        token=token,
                        android=messaging.AndroidConfig(priority='high')
                    )
                    messaging.send(message)
                except Exception:
                    pass

@socketio.on('emergency-call')
def on_emergency_call(data):
    room = data.get('room')
    sender_id = request.sid
    sender_role = data.get('role') or rooms_manager.get(room, {}).get(sender_id, {}).get('role')
    target_role = 'elder' if sender_role == 'family' else 'family'

    print(f"🚨 Emergency Call Request from {sender_id} to {target_role} in {room}")
    
    if room in rooms_manager:
        for sid, info in rooms_manager[room].items():
            if info.get('role') == target_role:
                emit('emergency-call', {'senderId': sender_id, 'room': room}, to=sid)

    if room in room_fcm_tokens:
        for token, info in room_fcm_tokens[room].items():
            if info.get('role') == target_role:
                try:
                    message = messaging.Message(
                        data={'type': 'emergency-call', 'senderId': sender_id, 'roomId': room},
                        token=token,
                        android=messaging.AndroidConfig(priority='high')
                    )
                    messaging.send(message)
                except Exception as e:
                    print(f"⚠️ FCM 緊急推播失敗 ({info['role']}): {e}")

@socketio.on('call-accept')
def on_call_accept(data):
    target_id = data.get('targetId')
    print(f"📞 Call Accepted by {request.sid}, notifying {target_id}")
    emit('call-accept', {'accepterId': request.sid}, to=target_id)

@socketio.on('call-busy')
def on_call_busy(data):
    target_id = data.get('targetId')
    print(f"🚫 Call Busy from {request.sid}, notifying {target_id}")
    emit('call-busy', {'targetId': request.sid}, to=target_id)

# --- WebRTC 信令 ---
@socketio.on('offer')
def on_offer(data):
    target = data.get('targetId')
    data['senderId'] = request.sid 
    
    # 優先傳送給指定對象
    if target:
        emit('offer', data, to=target)
    else:
        # 若無 target，則廣播 (通常只有長輩廣播給家屬時會用到)
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
    print(f"📴 End Call from {request.sid}")
    
    if target:
        emit('end-call', {'senderId': request.sid}, to=target)

if __name__ == '__main__':
    print("🚀 Server starting on port 5000...")
    import eventlet.wsgi
    eventlet.wsgi.server(eventlet.listen(('0.0.0.0', 5000)), app)
