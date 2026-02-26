from flask import Blueprint, request, jsonify
from datetime import datetime
from models import ActivityLog, User
from extensions import db
from services.gemini_service import gemini_service
import json
import os

ai_bp = Blueprint('ai', __name__)

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
    print(f"DEBUG: Sending message to Gemini: {user_message}")
    response_text = gemini_service.get_response(user_message, user_id=user_id, history=history)
    print(f"DEBUG: Gemini response received: {response_text[:50]}...")

    # 自動記錄聊天意圖到 ActivityLog
    log_content = f"長者詢問：{user_message} | AI 回應：{response_text}"
    new_log = ActivityLog(
        user_id=user_id,
        event_type='chat',
        content=log_content
    )
    db.session.add(new_log)
    db.session.commit()

    return jsonify({
        'reply': response_text,
        'status': 'success'
    })
