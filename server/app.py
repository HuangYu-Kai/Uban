import os
from flask import Flask, request
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

@socketio.on('join')
def on_join(data):
    room = data.get('room')
    role = data.get('role', 'unknown')
    sid = request.sid

    if room:
        join_room(room)
        if room not in rooms_manager:
            rooms_manager[room] = {}
        rooms_manager[room][sid] = role
        
        print(f"User {sid} ({role}) joined room: {room}")
        emit('user-joined', {'id': sid, 'role': role}, to=room, include_self=False)

        if role == 'family':
            current_users = [{'id': k, 'role': v} for k, v in rooms_manager[room].items() if k != sid]
            emit('user-list', current_users, to=sid)

@socketio.on('disconnect')
def on_disconnect():
    sid = request.sid
    for room, users in rooms_manager.items():
        if sid in users:
            del users[sid]
            emit('user-left', {'id': sid}, to=room)
            print(f"User {sid} disconnected")
            break

# --- 關鍵修正：同時支援 P2P (監控) 與 Broadcast (雙向視訊) ---

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
    data['senderId'] = request.sid

    if target:
        emit('candidate', data, to=target)
    elif room:
        emit('candidate', data, to=room, include_self=False)

if __name__ == '__main__':
    socketio.run(app, debug=True, host='0.0.0.0', port=5000)
