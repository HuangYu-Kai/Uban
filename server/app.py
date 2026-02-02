# 路徑: server/app.py
from flask import Flask
from flask_socketio import SocketIO, emit

app = Flask(__name__)
app.config['SECRET_KEY'] = 'secret!'
# cors_allowed_origins="*" 允許跨域連線，避免連線被擋
socketio = SocketIO(app, cors_allowed_origins="*") 

@socketio.on('offer')
def handle_offer(data):
    # 廣播 Offer 給別人 (不含自己)
    emit('offer', data, broadcast=True, include_self=False)

@socketio.on('answer')
def handle_answer(data):
    # 廣播 Answer 給別人
    emit('answer', data, broadcast=True, include_self=False)

@socketio.on('candidate')
def handle_candidate(data):
    # 交換網路路徑資訊
    emit('candidate', data, broadcast=True, include_self=False)

@app.route('/')
def index():
    return "CompanionFlow Signaling Server is Running..."

if __name__ == '__main__':
    # host='0.0.0.0' 讓區域網路內的手機可以連進來
    print("Server starting on port 5000...")
    socketio.run(app, host='0.0.0.0', port=5000, debug=True)