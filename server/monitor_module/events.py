# 路徑: server/monitor_module/events.py
from flask_socketio import emit

def register_monitor_events(socketio):
    """
    將 SocketIO 事件註冊到這個函式中，
    避免所有邏輯都寫在 app.py 裡。
    """

    @socketio.on('offer')
    def handle_offer(data):
        print(f"Received Offer")
        # 廣播給房間內除了自己以外的人 (簡單實作則使用 broadcast=True)
        emit('offer', data, broadcast=True, include_self=False)

    @socketio.on('answer')
    def handle_answer(data):
        print(f"Received Answer")
        emit('answer', data, broadcast=True, include_self=False)

    @socketio.on('candidate')
    def handle_candidate(data):
        print(f"Received Candidate")
        emit('candidate', data, broadcast=True, include_self=False)