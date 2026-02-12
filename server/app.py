from flask import Flask, request, jsonify
from flask_socketio import SocketIO, emit, join_room, leave_room
# 引入資料庫模組 (保留這行就好)
from db import db  

app = Flask(__name__)
app.config['SECRET_KEY'] = 'secret!'
# 這是最單純的寫法，不用 async_mode
socketio = SocketIO(app, cors_allowed_origins="*")

# 初始化資料庫
try:
    db.connect_mysql()
    db.connect_mongo()
except Exception as e:
    print(f"⚠️ 資料庫連線警告: {e}")

# --- [API] 這是您新增的資料庫功能 (保留) ---
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
            return jsonify({'status': 'success', 'elder_id': result['elder_id'], 'elder_name': result['elder_name']})
        else:
            return jsonify({'status': 'error', 'message': 'User not found'}), 404
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500

# --- [Socket] WebRTC 信令 (還原成最舊版本) ---

@socketio.on('join')
def on_join(data):
    room = data.get('room')
    role = data.get('role', 'unknown')
    sid = request.sid
    if room:
        join_room(room)
        print(f"✅ User {sid} ({role}) joined room: {room}")
        # 廣播給房間其他人
        emit('user-joined', {'id': sid, 'role': role}, to=room, include_self=False)

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
    print(f"📩 [Answer] From {request.sid}")

    if target:
        emit('answer', data, to=target)
    elif room:
        emit('answer', data, to=room, include_self=False)

@socketio.on('candidate')
def on_candidate(data):
    target = data.get('targetId')
    room = data.get('room')
    
    if target:
        emit('candidate', data, to=target)
    elif room:
        emit('candidate', data, to=room, include_self=False)

@socketio.on('disconnect')
def on_disconnect():
    print(f"❌ User {request.sid} disconnected")

# --- 啟動 (最單純的寫法) ---
if __name__ == '__main__':
    # 不需要 Gevent，直接 run，host 設為 0.0.0.0 讓手機可連
    socketio.run(app, debug=True, host='0.0.0.0', port=5000)