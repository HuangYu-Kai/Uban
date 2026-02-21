from flask import Blueprint, request, jsonify
from datetime import datetime
from models import ActivityLog, User
from extensions import db
import json

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

    # 模擬 AI 推理與日誌檢索
    # 真實場景會從 ActivityLog 撈取數據整合進 Prompt
    
    # 範例回應邏輯
    response_text = ""
    if "吃藥" in user_message:
        response_text = "我幫您查了一下，您今天早上的藥已經吃過囉！真棒。"
    elif "運動" in user_message:
        response_text = "今天天氣不錯，待會要不要去公園散散步呢？"
    else:
        response_text = "收到！我會一直陪著您的。還有什麼想聊聊的嗎？"

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
