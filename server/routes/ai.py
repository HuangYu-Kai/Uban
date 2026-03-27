from flask import Blueprint, request, jsonify, g
from datetime import datetime
from models import ActivityLog, UserAccountData, ElderProfile
from extensions import db
from services.ollama_service import ollama_service
import json
import threading

ai_bp = Blueprint('ai', __name__)

@ai_bp.route('/chat', methods=['POST'])
def ai_chat():
    """標準 AI 對話接口 (非串流)"""
    data = request.json
    user_id = data.get('user_id')
    user_message = data.get('message')

    if not user_id or not user_message:
        return jsonify({'error': 'Missing user_id or message'}), 400

    # 取得歷史對話 (基於新 ERD：使用 log_id)
    history = []
    past_logs = ActivityLog.query.filter_by(
        user_id=user_id, 
        event_type='chat'
    ).order_by(ActivityLog.timestamp.desc()).limit(5).all()
    
    for log in reversed(past_logs):
        if " | AI 回應：" in log.content:
            parts = log.content.split(" | AI 回應：")
            user_part = parts[0].replace("長者詢問：", "")
            ai_part = parts[1]
            history.append({"role": "user", "parts": [user_part]})
            history.append({"role": "model", "parts": [ai_part]})

    # 調用 Ollama
    g.current_user_id = user_id
    response_text = ollama_service.get_response(user_message, user_id=user_id, history=history)

    # 儲存日誌 (基於新 ERD：ActivityLog)
    new_log = ActivityLog(
        user_id=user_id,
        event_type='chat',
        content=f"長者詢問：{user_message} | AI 回應：{response_text}"
    )
    db.session.add(new_log)
    db.session.commit()

    return jsonify({
        'reply': response_text,
        'status': 'success'
    })

@ai_bp.route('/chat_stream', methods=['POST'])
def ai_chat_stream():
    """AI 對話接口 (串流模式)"""
    data = request.json
    user_id = data.get('user_id')
    user_message = data.get('message')

    if not user_id or not user_message:
        return jsonify({'error': 'Missing required fields'}), 400

    from flask import Response
    def generate_response():
        history = []
        from app import app
        with app.app_context():
            # 取得脈絡
            past_logs = ActivityLog.query.filter_by(user_id=user_id, event_type='chat').order_by(ActivityLog.timestamp.desc()).limit(5).all()
            for log in reversed(past_logs):
                if " | AI 回應：" in log.content:
                    parts = log.content.split(" | AI 回應：")
                    history.append({"role": "user", "parts": [parts[0].replace("長者詢問：", "")]})
                    history.append({"role": "model", "parts": [parts[1]]})

            full_reply = ""
            for chunk in ollama_service.get_response_stream(user_message, user_id=user_id, history=history):
                full_reply += chunk
                yield f"data: {json.dumps({'chunk': chunk}, ensure_ascii=False)}\n\n"
            
            # 結尾儲存
            new_log = ActivityLog(
                user_id=user_id,
                event_type='chat',
                content=f"長者詢問：{user_message} | AI 回應：{full_reply}"
            )
            db.session.add(new_log)
            db.session.commit()
            yield f"data: {json.dumps({'done': True}, ensure_ascii=False)}\n\n"

    return Response(generate_response(), mimetype='text/event-stream')

@ai_bp.route('/log_activity', methods=['POST'])
def log_activity():
    """儲存活動日誌 (由前端發起)"""
    data = request.json
    user_id = data.get('user_id')
    event_type = data.get('event_type')
    content = data.get('content')
    extra_data = data.get('extra_data') # JSON String or dict

    if not user_id or not event_type or not content:
        return jsonify({'error': 'Missing required fields'}), 400

    new_log = ActivityLog(
        user_id=user_id,
        event_type=event_type,
        content=content,
        extra_data=str(extra_data) if extra_data else None
    )
    db.session.add(new_log)
    db.session.commit()

    return jsonify({'status': 'success', 'log_id': new_log.log_id})
