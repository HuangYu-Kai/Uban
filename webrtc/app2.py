from flask import Flask, render_template, request
from flask_socketio import SocketIO, emit, join_room, leave_room

app = Flask(__name__)
app.config['SECRET_KEY'] = 'secret!'
socketio = SocketIO(app, cors_allowed_origins="*")

@app.route('/')
def index():
    # 這裡我們回傳新的多人版頁面
    return render_template('multi.html')

@socketio.on('join')
def on_join(data):
    room = data['room']
    join_room(room)
    # 告訴房間裡的「其他人」：有一個新的人 (SID) 加入了，請準備跟連線
    # include_self=False 代表不要發給自己
    emit('user-joined', request.sid, room=room, include_self=False)
    print(f"User {request.sid} joined room {room}")

@socketio.on('disconnect')
def on_disconnect():
    # 當有人斷線，通知房間所有人移除該使用者的影像
    room = "demo_room" # 簡化：假設大家都在 demo_room
    emit('user-left', request.sid, room=room)
    print(f"User {request.sid} disconnected")

@socketio.on('signal')
def on_signal(data):
    """
    這是一個通用的信令轉發函數
    data 結構: { 'target': 目標SID, 'type': 'offer'/'answer'/'candidate', 'payload': ... }
    """
    target_sid = data['target']
    
    # 轉發訊息給指定的目標，並附上發送者的 ID (sender_sid)
    # 這樣接收者才知道是誰傳來的，並建立對應的 PeerConnection
    payload = {
        'sender': request.sid,
        'type': data['type'],
        'data': data['data']
    }
    
    # 傳送給指定的 target_sid
    emit('signal', payload, room=target_sid)

if __name__ == '__main__':
    socketio.run(app, debug=True, port=5000)