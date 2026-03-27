import eventlet
import json
import os
from datetime import datetime

class HeartbeatManager:
    def __init__(self, socketio, ollama_service, rooms_manager):
        self.socketio = socketio
        self.ollama_service = ollama_service
        self.rooms_manager = rooms_manager
        self.running = False
        self.log_file = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'heartbeat_debug.log')

    def log(self, message):
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        with open(self.log_file, 'a', encoding='utf-8') as f:
            f.write(f"[{timestamp}] {message}\n")
        print(f"💓 {message}")

    def start(self):
        if not self.running:
            self.running = True
            eventlet.spawn(self._run_loop)
            self.log("Manager thread started.")

    def _run_loop(self):
        # 給系統一點啟動緩衝時間 (30 秒)
        eventlet.sleep(30)
        while self.running:
            self.log(f"Cycle starting... (Rooms: {len(self.rooms_manager)})")
            try:
                self._process_heartbeats()
            except Exception as e:
                self.log(f"Loop error: {e}")
            
            # 正式環境建議 5-10 分鐘 (如 600 秒)
            eventlet.sleep(1200)

    def _process_heartbeats(self):
        from app import app
        from models import ActivityLog, ElderProfile
        from extensions import db
        
        with app.app_context():
            rooms_to_check = list(self.rooms_manager.keys())
            
            for room_id in rooms_to_check:
                devices = self.rooms_manager.get(room_id, {})
                # 找出是否有長輩在線
                elder_sessions = [sid for sid, info in devices.items() if info.get('role') == 'elder']
                
                if elder_sessions:
                    # 取得第一個長輩的資料庫 ID
                    user_id = devices[elder_sessions[0]].get('userId')
                    if not user_id:
                        self.log(f"Room {room_id}: Elder connected but missing userId. Skipping.")
                        continue
                    
                    self.log(f"Processing heartbeat for user {user_id} in room {room_id}")
                    
                    # 讀取 HEARTBEAT.md 指令
                    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
                    heartbeat_md_path = os.path.join(base_dir, 'agent', 'HEARTBEAT.md')
                    heartbeat_rules = ""
                    if os.path.exists(heartbeat_md_path):
                        with open(heartbeat_md_path, 'r', encoding='utf-8') as f:
                            heartbeat_rules = f.read()

                    # 建立 Heartbeat 專屬提示
                    current_time_str = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                    prompt = (
                        f"現在時間是：{current_time_str}\n"
                        "你現在正在進行後台自動巡檢。請檢查待辦清單 `HEARTBEAT.md` 中的任務，特別是「急迫事件」。\n"
                        f"### HEARTBEAT.md 指令內容:\n{heartbeat_rules}\n"
                        "--- \n"
                        "🚫 嚴格要求：\n"
                        "1. **語系限制**：務必使用「繁體中文（zh-TW）」，絕對不要出現簡體字。\n"
                        "2. **狀態碼回覆**：如果判斷不需要發話，請**保持空白**或回覆：AI_SILENT。不要有任何其他文字。\n"
                        "3. **發話內容**：如果需要發話，請直接回覆對話內容。內容中「絕對不能」包含 'AI_SILENT'、'HEARTBEAT' 或任何英文狀態碼文字。\n"
                        "4. **風格與長度**：遵循 `SOUL.md` 的溫暖晚輩語氣，字數控制在 30 字內。"
                    )

                    # 取得最近對話脈絡 (避免重複發話)
                    past_logs = ActivityLog.query.filter_by(user_id=user_id, event_type='chat').order_by(ActivityLog.timestamp.desc()).limit(3).all()
                    history = []
                    for log in reversed(past_logs):
                        if " | AI 回應：" in log.content:
                            parts = log.content.split(" | AI 回應：")
                            history.append({"role": "user", "parts": [parts[0].replace("長者詢問：", "")]})
                            history.append({"role": "model", "parts": [parts[1]]})

                    # 調用 AI
                    response = self.ollama_service.get_response(prompt, user_id=user_id, history=history)
                    ai_reply = response.strip()
                    
                    # 檢查是否為狀態碼 (更廣泛的模糊匹配，包含常見拼錯)
                    status_keywords = ["AI_SILENT", "HEARTBEAT", "HEARTHBEAT", "STATUS", "_OK", " OK"]
                    is_status_only = any(x in ai_reply.upper() for x in status_keywords) and len(ai_reply) < 20
                    
                    if not is_status_only and len(ai_reply) > 2:
                        # 再次防呆：使用正則表達式強制移除「任何位置」的狀態碼與其帶隨的語助詞
                        import re
                        # 移除 AI_SILENT, HEARTBEAT_OK, Hearthbeat 等關鍵字及其常見尾綴
                        clean_reply = re.sub(r'(?i)(AI_SILENT|HEARTH?BEAT(_OK)?|STATUS_OK)\s*[！!！啦呵呢啊吧]*', '', ai_reply).strip()
                        
                        if len(clean_reply) > 1:
                            self.log(f"Triggered message: {clean_reply}")
                            
                            # 透過 Socket.io 發報
                            self.socketio.emit('heartbeat-message', {'reply': clean_reply}, room=room_id)
                            
                            # 同時儲存到資料庫日誌
                            new_log = ActivityLog(
                                user_id=user_id,
                                event_type='chat',
                                content=f"系統主動關懷 | AI 回應：{clean_reply}"
                            )
                            db.session.add(new_log)
                            db.session.commit()
                        else:
                            self.log(f"Room {room_id} (User {user_id}): AI returned status-like text: {ai_reply}")
                    else:
                        self.log(f"Room {room_id} (User {user_id}): AI is SILENT (Reply: {ai_reply})")

heartbeat_manager = None
