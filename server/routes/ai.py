from flask import Blueprint, request, jsonify, g
from datetime import datetime
from models import ActivityLog, User
from extensions import db
from services.gemini_service import gemini_service
import json
import os
import threading

ai_bp = Blueprint('ai', __name__)

def _summarize_chat_history(user_id):
    """
    在背景執行的任務：當對話滿 10 筆時，自動進行總結並存為 chat_summary。
    需在 local app context 下執行以存取 DB。
    """
    # 避免 circular import，在此引入 app
    from app import app
    with app.app_context():
        logs = ActivityLog.query.filter_by(user_id=user_id, event_type='chat')\
                               .order_by(ActivityLog.timestamp.desc()).limit(10).all()
        if len(logs) < 10:
            return
            
        text_to_summarize = "以下是長輩最近的一段對話紀錄：\n"
        for log in reversed(logs):
            text_to_summarize += f"- {log.content}\n"
            
        import google.generativeai as genai
        try:
            model = genai.GenerativeModel("gemini-2.5-flash-lite")
            prompt = f"{text_to_summarize}\n請總結這段對話中長輩的狀態，包含：身體狀況、心情、重點關注事項。請用繁體中文，盡量簡短(約 100 字)，以第三人稱客觀描述長輩的狀況。"
            response = model.generate_content(prompt)
            summary = response.text.strip()
            
            new_log = ActivityLog(
                user_id=user_id,
                event_type='chat_summary',
                content=summary
            )
            db.session.add(new_log)
            db.session.commit()
            print(f"DEBUG: Background summary saved for user {user_id}")
        except Exception as e:
            print(f"DEBUG: Failed to summarize chat: {e}")

@ai_bp.route('/log_activity', methods=['POST'])
def log_activity():
    """
    接收來自長者端或系統自動偵測的活動紀錄
    """
    data = request.json
    user_id = data.get('user_id')
    event_type = data.get('event_type')  # medication, exercise, mood, chat_summary
    content = data.get('content')
    extra_data = data.get('extra_data') # json string

    if not user_id or not event_type or not content:
        return jsonify({'error': 'Missing required fields'}), 400

    new_log = ActivityLog(
        user_id=user_id,
        event_type=event_type,
        content=content,
        extra_data=extra_data
    )
    db.session.add(new_log)
    db.session.commit()

    return jsonify({'message': 'Activity logged successfully', 'id': new_log.id})

@ai_bp.route('/chat', methods=['POST'])
def ai_chat():
    """
    處理來自長者的聊天請求，並回傳 AI 生成的回應。
    在此階段僅實作模擬邏輯，之後可接入 OpenAI 或本地 TLM。
    """
    data = request.json
    user_id = data.get('user_id')
    user_message = data.get('message')

    if not user_id or not user_message:
        return jsonify({'error': 'Missing user_id or message'}), 400

    # --- 整合 Gemini 2.5 (Agentic RAG + Memory) ---
    # 1. 嘗試從 ActivityLog 獲取最近的對話歷史 (最近 5 輪/10 筆)
    history = []
    past_logs = ActivityLog.query.filter_by(
        user_id=user_id, 
        event_type='chat'
    ).order_by(ActivityLog.timestamp.desc()).limit(5).all()
    
    print(f"DEBUG: Found {len(past_logs)} past logs for user {user_id}")
    
    # 將歷史反轉為正序，並格式化為 Gemini 要求的格式
    for log in reversed(past_logs):
        try:
            # 格式解析：長者詢問：XXX | AI 回應：YYY
            parts = log.content.split(" | AI 回應：")
            if len(parts) == 2:
                user_part = parts[0].replace("長者詢問：", "")
                ai_part = parts[1]
                history.append({"role": "user", "parts": [user_part]})
                history.append({"role": "model", "parts": [ai_part]})
        except Exception as e:
            print(f"DEBUG: Error parsing history log: {e}")
            continue

    print(f"DEBUG: Formatted history length: {len(history)} items")

    # 2. 傳入 history 讓 AI 具備上下文記憶
    g.current_user_id = user_id
    print(f"DEBUG: Sending message to Gemini: {user_message}")
    response_text = gemini_service.get_response(user_message, user_id=user_id, history=history)
    print(f"DEBUG: Gemini response received: {response_text[:50]}...")
    
    # 獲取工具執行期間存入的 actions
    actions = getattr(g, 'pending_actions', [])

    # 自動記錄聊天意圖到 ActivityLog
    log_content = f"長者詢問：{user_message} | AI 回應：{response_text}"
    new_log = ActivityLog(
        user_id=user_id,
        event_type='chat',
        content=log_content
    )
    db.session.add(new_log)
    db.session.commit()

    # 觸發長期記憶總結機制
    chat_count = ActivityLog.query.filter_by(user_id=user_id, event_type='chat').count()
    if chat_count > 0 and chat_count % 10 == 0:
        threading.Thread(target=_summarize_chat_history, args=(user_id,)).start()

    return jsonify({
        'reply': response_text,
        'actions': actions,
        'status': 'success'
    })

from flask import Response

@ai_bp.route('/chat_stream', methods=['POST', 'GET'])
def ai_chat_stream():
    """
    使用 Server-Sent Events (SSE) 將 AI 的回覆以串流方式回傳給前端。
    支援 GET (將資料附在 URL 參數) 或 POST (JSON)
    """
    if request.method == 'POST':
        data = request.json
    else:
        # 允許前端使用 GET 方法傳遞參數，方便某些 SSE 客戶端實作
        data = {
            'user_id': request.args.get('user_id'),
            'message': request.args.get('message')
        }

    user_id = data.get('user_id')
    user_message = data.get('message')

    if not user_id or not user_message:
        return jsonify({'error': 'Missing user_id or message'}), 400

    def generate_response():
        # --- 整合 Gemini 2.5 (Agentic RAG + Memory) ---
        history = []
        # 因為 DB 查詢在 yield 前需要 app_context
        from app import app
        with app.app_context():
            past_logs = ActivityLog.query.filter_by(
                user_id=user_id, 
                event_type='chat'
            ).order_by(ActivityLog.timestamp.desc()).limit(5).all()
            
            for log in reversed(past_logs):
                try:
                    parts = log.content.split(" | AI 回應：")
                    if len(parts) == 2:
                        user_part = parts[0].replace("長者詢問：", "")
                        ai_part = parts[1]
                        history.append({"role": "user", "parts": [user_part]})
                        history.append({"role": "model", "parts": [ai_part]})
                except Exception:
                    continue

            # 傳遞資料到 Gemini Service
            full_reply = ""
            for chunk in gemini_service.get_response_stream(user_message, user_id=user_id, history=history):
                full_reply += chunk
                # 遵循 SSE 格式：data: <json string>\n\n
                yield f"data: {json.dumps({'chunk': chunk}, ensure_ascii=False)}\n\n"
            
            # 串流結束後，儲存對話紀錄
            log_content = f"長者詢問：{user_message} | AI 回應：{full_reply}"
            new_log = ActivityLog(
                user_id=user_id,
                event_type='chat',
                content=log_content
            )
            db.session.add(new_log)
            db.session.commit()

            # 發送結束標記，讓前端知道完成了
            yield f"data: {json.dumps({'done': True}, ensure_ascii=False)}\n\n"

            # 觸發長期記憶
            chat_count = ActivityLog.query.filter_by(user_id=user_id, event_type='chat').count()
            if chat_count > 0 and chat_count % 10 == 0:
                threading.Thread(target=_summarize_chat_history, args=(user_id,)).start()

    return Response(generate_response(), mimetype='text/event-stream')
