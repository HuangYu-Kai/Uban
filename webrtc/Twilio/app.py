from flask import Flask, render_template, request, jsonify
from flask_socketio import SocketIO, emit, join_room
from twilio.rest import Client
import os

app = Flask(__name__)
app.config['SECRET_KEY'] = 'secret!'
socketio = SocketIO(app, cors_allowed_origins="*")

# ==========================================
# ★★★ 請在此填入你的 Twilio 帳號資訊 ★★★
# ==========================================
#TWILIO_ACCOUNT_SID = '--'
#TWILIO_AUTH_TOKEN = '---'

@app.route('/')
def index():
    return render_template('multi.html')

@app.route('/get_ice_servers')
def get_ice_servers():
    """
    動態向 Twilio 申請一組臨時的 TURN 帳號密碼給前端
    這樣就不用把帳密寫死在 HTML 裡，也更安全
    """
    try:
        client = Client(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN)
        # 這行程式碼會產生一組短效期的 TURN 憑證
        token = client.tokens.create()
        return jsonify(token.ice_servers)
    except Exception as e:
        print(f"Twilio 錯誤 (可能帳號沒填對): {e}")
        # 如果失敗，回傳 Google 的 STUN 當作免費備案 (僅能區域網路連線)
        return jsonify([{'urls': 'stun:stun.l.google.com:19302'}])

@socketio.on('join')
def on_join(data):
    room = data.get('room', 'demo_room')
    join_room(room)
    # 通知房間內的其他人：有新用戶加入
    emit('user-joined', request.sid, room=room, include_self=False)

@socketio.on('disconnect')
def on_disconnect():
    room = "demo_room"
    emit('user-left', request.sid, room=room)

@socketio.on('signal')
def on_signal(data):
    # 點對點信令轉發
    target_sid = data.get('target')
    payload = {
        'sender': request.sid,
        'type': data['type'],
        'data': data['data']
    }
    if target_sid:
        emit('signal', payload, room=target_sid)

if __name__ == '__main__':
    # host='0.0.0.0' 確保區網/外網可連入
    socketio.run(app, debug=True, host='0.0.0.0', port=5000)