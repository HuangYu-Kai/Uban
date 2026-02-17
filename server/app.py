# server/app.py
#pip install "eventlet>=0.36.1" "Flask==3.0.3" "Flask-SocketIO==5.3.6" "Werkzeug==3.0.3"
# ★★★ 關鍵修正 1：在引入任何庫之前，先修正 Eventlet 在 Python 3.13 的 SSL 問題 ★★★
import eventlet
import ssl

# 如果 ssl 模組沒有 wrap_socket (Python 3.12+ 移除了)，我們手動補上一個假的
if not hasattr(ssl, 'wrap_socket'):
    def dummy_wrap_socket(sock, *args, **kwargs):
        context = ssl.SSLContext(kwargs.get('ssl_version', ssl.PROTOCOL_TLS))
        return context.wrap_socket(sock, *args, **kwargs)
    ssl.wrap_socket = dummy_wrap_socket

# 啟用 Eventlet 的非同步補丁
eventlet.monkey_patch()

# --- 以下是正常的程式碼 ---
from flask import Flask, request, jsonify
from flask_socketio import SocketIO, emit, join_room, leave_room
from db import db  

app = Flask(__name__)
app.config['SECRET_KEY'] = 'secret!'

# ★★★ 關鍵修正 2：明確指定 async_mode 為 eventlet ★★★
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='eventlet')

# 初始化資料庫連線
try:
    print("正在連接資料庫...")
    db.connect_mysql()
    db.connect_mongo()
except Exception as e:
    print(f"⚠️ 資料庫連線警告: {e}")

rooms_manager = {}

# --- [API] 資料庫查詢 ---
@app.route('/api/get_elder_data', methods=['GET'])
def get_elder_data():
    user_id = request.args.get('user_id')
    if not user_id:
        return jsonify({'status': 'error', 'message': 'Missing user_id'}), 400

    try:
        cursor = db.get_mysql_cursor()
        query = "SELECT elder_id, elder_name FROM elder_user_data WHERE user_id = %s LIMIT 1"
        cursor.execute(query, (user_id,))
        result = cursor.fetchone()
        cursor.close()
        
        if result:
            print(f"✅ API 查詢成功: User {user_id} -> Elder {result['elder_id']}")
            return jsonify({
                'status': 'success', 
                'elder_id': result['elder_id'], 
                'elder_name': result['elder_name']
            })
        else:
            return jsonify({'status': 'error', 'message': '查無此 User ID 對應的長輩資料'}), 404
    except Exception as e:
        print(f"❌ Database Error: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500

# --- [Socket] WebRTC 信令 ---
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
            if not users:
                del rooms_manager[room]
            break

@socketio.on('offer')
def on_offer(data):
    target = data.get('targetId')
    room = data.get('room')
    data['senderId'] = request.sid 
    print(f"📩 [Offer] From {request.sid} to {target or room}")
    if target:
        emit('offer', data, to=target)
    elif room:
        emit('offer', data, to=room, include_self=False)

@socketio.on('answer')
def on_answer(data):
    target = data.get('targetId')
    room = data.get('room')
    data['senderId'] = request.sid
    print(f"📩 [Answer] From {request.sid}")
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
    print("🚀 Server starting with Eventlet on port 5000...")
    # 這裡不需要 socketio.run，直接用 eventlet 的 WSGIServer 啟動最穩
    import eventlet.wsgi
    eventlet.wsgi.server(eventlet.listen(('0.0.0.0', 5000)), app)