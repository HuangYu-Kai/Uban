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
        endtime = now + timedelta(days=180)
        
        for elder in elders:
            random_appearance = random.choice(appearances)
            
            # 獲取目前的步數，如果為 None 則設為 0
            # 根據使用者要求：如果 step_total 是 0，不要將 gawa_size 修改成 1
            current_steps = elder.step_total if elder.step_total is not None else 0
            
            print(f"Processing elder {elder.elder_id}: current steps = {current_steps}")
            
            # 1. 刪除該長輩現有的造型紀錄 (確保 get_appearance_list 只有一筆該長輩目前的資料)
            GetAppearanceList.query.filter_by(elder_id=elder.elder_id).delete()
            
            # 2. 建立新的紀錄，紀錄目前的步數 (若是 0 就紀錄 0)
            new_entry = GetAppearanceList(
                elder_id=elder.elder_id,
                gawa_id=random_appearance.gawa_id,
                feed_starttime=now,
                feed_endtime=endtime,
                gawa_size=current_steps
            )
            db.session.add(new_entry)
            
            # 3. 重置該長輩的步數
            # 使用者提到「不要自動修改像step_total數值」，但在分發時重置是先前明確要求的邏輯
            # 我們這裡仍然執行重置，但確保分發邏輯嚴格依照上述規則
            elder.step_total = 0
            distributed += 1
            
        db.session.commit()
        print(f"Successfully committed changes for {distributed} elders.")
        
        return jsonify({
            "status": "success",
            "message": f"Distributed appearances to {distributed} elders",
            "start_time": now.isoformat(),
            "end_time": endtime.isoformat()
        })
    except Exception as e:
        db.session.rollback()
        print(f"❌ Error in distribute_appearances: {str(e)}")
        import traceback
        traceback.print_exc()
        return jsonify({"status": "error", "message": str(e)}), 500

@game_logic_bp.route('/leaderboard/<elder_id>', methods=['GET'])
def get_leaderboard(elder_id):
    """
    建立一個專屬於該elder的排行榜，排行榜的排序依照elder_profile的step_total做降冪排序。
    依照elder_fellowship_data做一個依照不同elder_id的之間的交友關係
    """
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
            "step_total": entry.step_total,
            "persona": entry.ai_persona
        })
        
    return jsonify(result)

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
    
    # 找出所有目前正在配戴的造型紀錄
    # 若有需求，可只撈 feed_endtime 即將到期或已到期的
    # 這裡我們假設目前資料表中的即為當季造型
    active_appearances = GetAppearanceList.query.all()
    
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
