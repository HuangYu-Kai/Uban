from flask import Flask, request
from flask_socketio import SocketIO, emit, join_room, leave_room

app = Flask(__name__)
app.config['SECRET_KEY'] = 'secret!'
socketio = SocketIO(app, cors_allowed_origins="*")

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