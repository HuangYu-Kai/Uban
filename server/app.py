from flask import Flask, request, jsonify
from flask_socketio import SocketIO, emit, join_room, leave_room
# 引入您的資料庫模組
from db import db  

app = Flask(__name__)
app.config['SECRET_KEY'] = 'secret!'
# 使用標準 Threading 模式 (最穩定，不強制依賴 gevent)
socketio = SocketIO(app, cors_allowed_origins="*")

# 初始化資料庫連線
try:
    print("正在連接資料庫...")
    db.connect_mysql()
    db.connect_mongo()
except Exception as e:
    print(f"⚠️ 資料庫連線警告: {e}")

# 用來記錄房間內的使用者 (監控列表功能依賴此變數)
rooms_manager = {}

# --- [API] 資料庫查詢功能 (新增部分) ---

@app.route('/api/get_elder_data', methods=['GET'])
def get_elder_data():
    # 獲取前端傳來的 user_id
    user_id = request.args.get('user_id')
    
    if not user_id:
        return jsonify({'status': 'error', 'message': 'Missing user_id'}), 400

    try:
        cursor = db.get_mysql_cursor()
        
        # 查詢語法：從 elder_user_data 表中查找
        query = "SELECT elder_id, elder_name FROM elder_user_data WHERE user_id = %s LIMIT 1" #這會限制user_id只能使用最上面的elder_id，但user_id會有很多elder_id，之後再修改
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


# --- [Socket] WebRTC 信令 (保留您提供的穩定邏輯) ---

@socketio.on('join')
def on_join(data):
    room = data.get('room')
    role = data.get('role', 'unknown')
    sid = request.sid

    if room:
        join_room(room)
        
        # 維護房間名單 (為了讓家屬端能看到長輩設備列表)
        if room not in rooms_manager:
            rooms_manager[room] = {}
        rooms_manager[room][sid] = role
        
        print(f"User {sid} ({role}) joined room: {room}")
        
        # 廣播給房間其他人
        emit('user-joined', {'id': sid, 'role': role}, to=room, include_self=False)

        # 如果是家屬(family)，回傳目前房間內的名單給他
        if role == 'family':
            current_users = [{'id': k, 'role': v} for k, v in rooms_manager[room].items() if k != sid]
            emit('user-list', current_users, to=sid)

@socketio.on('disconnect')
def on_disconnect():
    sid = request.sid
    # 從名單中移除
    for room, users in rooms_manager.items():
        if sid in users:
            del users[sid]
            emit('user-left', {'id': sid}, to=room)
            print(f"User {sid} disconnected")
            # 如果房間空了，可以選擇刪除 room key (可選)
            if not users:
                del rooms_manager[room]
            break

# --- 關鍵修正：同時支援 P2P (監控) 與 Broadcast (雙向視訊) ---

@socketio.on('offer')
def on_offer(data):
    target = data.get('targetId')
    room = data.get('room')
    data['senderId'] = request.sid 
    
    # 增加 Log 方便除錯
    print(f"📩 [Offer] From {request.sid} to {target or room}")

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
    # host='0.0.0.0' 確保區網內手機可連線
    print("🚀 Server starting on port 5000...")
    socketio.run(app, debug=True, host='0.0.0.0', port=5000)