# 路徑: server/app.py
from flask import Flask
from flask_socketio import SocketIO
# 引入剛剛建立的模組邏輯
from monitor_module.events import register_monitor_events

app = Flask(__name__)
app.config['SECRET_KEY'] = 'companion_flow_secret'

# 允許跨域，方便開發
socketio = SocketIO(app, cors_allowed_origins="*")

# 註冊監控模組的事件
register_monitor_events(socketio)

@app.route('/')
def index():
    return "CompanionFlow Server is Running..."

if __name__ == '__main__':
    # host='0.0.0.0' 讓手機可以透過區網 IP 連線
    print("Server starting on port 5000...")
    socketio.run(app, host='0.0.0.0', port=5000, debug=True)