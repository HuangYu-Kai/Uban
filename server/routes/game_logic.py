from flask import Blueprint, jsonify, request
from models import ElderProfile, GawaAppearance, GetAppearanceList, ElderFellowshipData, db
from datetime import datetime, timedelta
import random

game_logic_bp = Blueprint('game_logic', __name__)

# 開發者可自由更改此日期，作為外觀資料更換及步數結算的統一重置時間
GLOBAL_RESET_DATE = datetime(2026, 12, 31, 23, 59, 59)

@game_logic_bp.route('/distribute_appearances', methods=['POST'])
def distribute_appearances():
    """
    每一段時間為每一個elder隨機發放一個來自gawa_appearance紀錄裡面的隨機一筆資料
    並在隨機分配後將記錄儲存在get_appearance_list
    """
    # 獲取請求資料
    data = request.json or {}
    target_elder_id = data.get('elder_id')
    
    # 1. 決定要發放的長輩對象
    if target_elder_id:
        elders = ElderProfile.query.filter_by(elder_id=target_elder_id).all()
        if not elders:
             return jsonify({"error": f"Elder with ID {target_elder_id} not found"}), 404
    else:
        elders = ElderProfile.query.filter(ElderProfile.elder_id.isnot(None)).all()
        
    # 2. 獲取所有造型
    appearances = GawaAppearance.query.all()
    
    if not elders:
         return jsonify({"error": "No elders found to process"}), 400
    if not appearances:
        return jsonify({"error": "No appearances found in database"}), 400
        
    try:
        distributed = 0
        now = datetime.utcnow()
        
        for elder in elders:
            # 💡 依照使用者定義的 3 步驟順序：
            
            # 【一：備份目前狀態至歷史紀錄 (GetAppearanceList)】
            # 將目前 `elder_profile` 的狀態寫入歷史，包括當前步數與目前的造型開始時間
            if elder.gawa_id:
                history_entry = GetAppearanceList(
                    elder_id=elder.elder_id,
                    gawa_id=elder.gawa_id,
                    feed_starttime=elder.feed_starttime or elder.create_ts, # 使用目前的開始時間，若無則用建立時間
                    feed_endtime=now, # 結束時間即為目前執行動作的時間
                    gawa_size=elder.step_total if elder.step_total is not None else 0
                )
                db.session.add(history_entry)
            
            # 【二：重置狀態】
            elder.step_total = 0
            # (邏輯上下一步會直接覆蓋 feed_starttime，故不需顯式刪除)
            
            # 【三：分配新造型並設定新開始時間】
            # 獲取尚未擁有的外觀 (若已經全買了，則從全部裡面挑)
            owned_gawas = GetAppearanceList.query.filter_by(elder_id=elder.elder_id).all()
            owned_ids = [g.gawa_id for g in owned_gawas]
            available = [a for a in appearances if a.gawa_id not in owned_ids]
            
            if not available:
                # 若全部都擁有過，則隨機從所有造型裡挑一個
                new_appearance = random.choice(appearances)
            else:
                new_appearance = random.choice(available)
            
            elder.gawa_id = new_appearance.gawa_id
            elder.feed_starttime = now
            
            distributed += 1
            
        db.session.commit()
        print(f"Successfully processed distribution for {distributed} elders.")
        
        return jsonify({
            "status": "success",
            "message": f"Distributed appearances to {distributed} elders",
            "timestamp": now.isoformat()
        })
    except Exception as e:
        db.session.rollback()
        print(f"Error in distribute_appearances: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({"status": "error", "message": str(e)}), 500

@game_logic_bp.route('/leaderboard/<elder_id>', methods=['GET'])
def get_leaderboard(elder_id):
    """
    建立一個專屬於該elder的排行榜，排行榜的排序依照elder_profile的step_total做降冪排序。
    依照elder_fellowship_data做一個依照不同elder_id的之間的交友關係
    """
    try:
        # Find all successful fellowships for this elder
        relations = ElderFellowshipData.query.filter(
            ((ElderFellowshipData.requester_id == elder_id) | (ElderFellowshipData.addressee_id == elder_id)) &
            (ElderFellowshipData.status == 'success')
        ).all()
        
        friend_ids = {elder_id}
        for rel in relations:
            friend_ids.add(rel.requester_id)
            friend_ids.add(rel.addressee_id)
        
        # Query ElderProfile for these IDs and sort by step_total descending
        leaderboard_data = ElderProfile.query.filter(ElderProfile.elder_id.in_(friend_ids)).order_by(ElderProfile.step_total.desc()).all()
        
        result = []
        for entry in leaderboard_data:
            result.append({
                "elder_id": entry.elder_id,
                "elder_name": entry.elder_name, # 💡 加上長輩名稱，以便介面顯示
                "step_total": entry.step_total if entry.step_total is not None else 0
            })
            
        return jsonify(result)
    except Exception as e:
        db.session.rollback()
        import traceback
        traceback.print_exc()
        return jsonify({"status": "error", "message": str(e)}), 500

@game_logic_bp.route('/check_reset', methods=['POST'])
def check_reset():
    """
    管理者設定的時間到或是管理者強制手動重置時：
    將原先的step_total儲存在get_appearance_list中的gawa_size欄位，
    並重置elder_profile中的step_total為0。
    """
    now = datetime.utcnow()
    data = request.json or {}
    force_reset = data.get('force', False)
    
    # 若尚未到達全域重置時間，且也並非手動強制重置，則不執行
    if now < GLOBAL_RESET_DATE and not force_reset:
        return jsonify({"status": "success", "message": "No reset needed, time not reached yet"})
    
    # 找出所有尚未到期（當季）的造型紀錄
    # ER圖顯示 (elder_id, gawa_id) 為複合主鍵，代表是陣列歷史，所以不能直接 query.all()，必須找當季(feed_endtime == GLOBAL_RESET_DATE 或是大於此刻)
    active_appearances = GetAppearanceList.query.filter(GetAppearanceList.feed_endtime >= now).all()
    
    updated_count = 0
    for app in active_appearances:
        elder = ElderProfile.query.filter_by(elder_id=app.elder_id).first()
        if elder:
            # 1. 儲存 step_total 到 gawa_size
            app.gawa_size = elder.step_total if elder.step_total is not None else 0
            
            # 2. 結束時間設為現在 (如果是強制重置的話)
            app.feed_endtime = now
            
            # 3. 重置大步數
            elder.step_total = 0
            
            updated_count += 1
            
    db.session.commit()
    
    return jsonify({
        "status": "success", 
        "message": f"Successfully cached step_total and reset for {updated_count} elders"
    })
@game_logic_bp.route('/elder_status/<string:elder_id>', methods=['GET'])
def get_elder_status(elder_id):
    elder = ElderProfile.query.filter_by(elder_id=elder_id).first()
    if not elder:
        return jsonify({"status": "error", "message": "Elder not found"}), 404
        
    appearance = GawaAppearance.query.get(elder.gawa_id) if elder.gawa_id else None
    
    return jsonify({
        "status": "success",
        "elder_name": elder.elder_name,
        "step_total": elder.step_total,
        "gawa_id": elder.gawa_id,
        "gawa_name": appearance.gawa_name if appearance else "無",
        "feed_starttime": elder.feed_starttime.isoformat() if elder.feed_starttime else None
    })
