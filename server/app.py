import os
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
from flask_cors import CORS
from flask_socketio import SocketIO, emit, join_room, leave_room
from extensions import db
from routes.auth import auth_bp
from routes.pairing import pairing_bp
from routes.user import user_bp
from routes.ai import ai_bp

from flask_cors import CORS

app = Flask(__name__)
CORS(app) # 允許跨域請求
app.config['SECRET_KEY'] = 'secret!'

# 資料庫設定
base_dir = os.path.dirname(os.path.abspath(__file__))
db_path = os.path.join(base_dir, 'instance', 'uban.db')
app.config['SQLALCHEMY_DATABASE_URI'] = f'sqlite:///{db_path}'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

# 初始化擴充功能
db.init_app(app)
socketio = SocketIO(app, cors_allowed_origins="*")

# 註冊藍圖 (API 路由)
app.register_blueprint(auth_bp, url_prefix='/api/auth')
app.register_blueprint(pairing_bp, url_prefix='/api/pairing')
app.register_blueprint(user_bp, url_prefix='/api/user')
app.register_blueprint(ai_bp, url_prefix='/api/ai')

@app.route('/')
def index():
    return "UBan Backend is Running! 🚀"

@app.route('/api/health')
def health():
    return {"status": "ok", "message": "Backend is reachable"}

# 自動建立資料表
with app.app_context():
    if not os.path.exists(os.path.dirname(db_path)):
        os.makedirs(os.path.dirname(db_path))
    db.create_all()
    print("✅ 資料庫與資料表已初始化。")

rooms_manager = {}

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
    sid = request.sid

    if room:
        join_room(room)
        if room not in rooms_manager:
            rooms_manager[room] = {}
        
        rooms_manager[room][sid] = {
            'role': role,
            'deviceName': device_name,
            'deviceMode': device_mode,
            'fcmToken': fcm_token # ★ 儲存 FCM Token
        }
        
        print(f"User {sid} ({role}) joined room: {room}")
        emit('user-joined', {'id': sid, 'role': role}, to=room, include_self=False)

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
            print(f"User {sid} disconnected")
            break

# --- 響鈴與接聽 (Handshake) ---
@socketio.on('call-request')
def on_call_request(data):
    room = data.get('room')
    sender_id = request.sid
    print(f"🔔 Call Request from {sender_id} in {room}")
    
    # 1. 廣播給房間內所有還活著的 Socket
    emit('call-request', {'senderId': sender_id, 'room': room}, to=room, include_self=False)

    # 2. 針對房間內的所有註冊用戶發送 FCM 靜默推播喚醒 (Data Message)
    if room in rooms_manager:
        for sid, info in rooms_manager[room].items():
            if sid != sender_id and 'fcmToken' in info and info['fcmToken']:
                token = info['fcmToken']
                try:
                    message = messaging.Message(
                        data={
                            'type': 'call-request',
                            'senderId': sender_id,
                            'roomId': room
                        },
                        token=token,
                        # 使用 Android 高優先級確保能穿透 Doze mode
                        android=messaging.AndroidConfig(priority='extreme')
                    )
                    response = messaging.send(message)
                    print(f"✅ FCM 推播已發送至 {info['role']} ({info['deviceName']}): {response}")
                except Exception as e:
                    print(f"⚠️ FCM 推播發送失敗 ({info['role']}): {e}")

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
    room = data.get('room')
    data['senderId'] = request.sid 

    if target:
        # 模式 A: 指定對象 (監控用)
        emit('offer', data, to=target)
    elif room:
        # 模式 B: 廣播給房間其他人 (雙向視訊用)
        emit('offer', data, to=room, include_self=False)

@socketio.on('answer')
def on_answer(data):
    target = data.get('targetId')
    room = data.get('room')
    data['senderId'] = request.sid

    if target:
        emit('answer', data, to=target)
    elif room:
        emit('answer', data, to=room, include_self=False)

@socketio.on('candidate')
def on_candidate(data):
    target = data.get('targetId')
    room = data.get('room')
    print(f"📴 End Call from {request.sid}")
    
    if target:
        emit('end-call', {'senderId': request.sid}, to=target)

if __name__ == '__main__':
    socketio.run(app, debug=True, use_reloader=False, host='0.0.0.0', port=5001)
