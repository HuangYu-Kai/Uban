# 路徑: server/app.py
from flask import Flask
from flask_cors import CORS
from flask_socketio import SocketIO, emit
from extensions import db
from routes.auth import auth_bp
from routes.pairing import pairing_bp
from routes.user import user_bp

def create_app():
    app = Flask(__name__)
    CORS(app)

    # SQLite 資料庫設定
    app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///uban.db'
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
    app.config['SECRET_KEY'] = 'secret!'

    # 初始化擴充功能
    db.init_app(app)

    # 註冊藍圖 (Blueprints)
    app.register_blueprint(auth_bp, url_prefix='/api')
    app.register_blueprint(pairing_bp, url_prefix='/api/pairing')
    app.register_blueprint(user_bp, url_prefix='/api/user')

    # 初始化資料庫
    with app.app_context():
        db.create_all()

    return app

app = create_app()
socketio = SocketIO(app, cors_allowed_origins="*")

@socketio.on('offer')
def handle_offer(data):
    emit('offer', data, broadcast=True, include_self=False)

@socketio.on('answer')
def handle_answer(data):
    emit('answer', data, broadcast=True, include_self=False)

@socketio.on('candidate')
def handle_candidate(data):
    emit('candidate', data, broadcast=True, include_self=False)

@app.route('/')
def index():
    return "UniFlow Backend & Signaling Server is Running..."

if __name__ == '__main__':
    print("Server starting on port 5000...")
    socketio.run(app, host='0.0.0.0', port=5000, debug=True)
