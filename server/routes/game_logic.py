from flask import Blueprint, jsonify, request
from models import ElderProfile, GawaAppearance, GetAppearanceList, ElderFellowshipData, db
from datetime import datetime, timedelta, timezone
import random
import os
import json

CONFIG_FILE = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'schedule_config.json')

def load_schedule_time():
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, 'r') as f:
                data = json.load(f)
                return data.get('distribution_time')
        except:
            pass
    return None

def save_schedule_time(iso_time_str):
    with open(CONFIG_FILE, 'w') as f:
        json.dump({'distribution_time': iso_time_str}, f)

game_logic_bp = Blueprint('game_logic', __name__)

GLOBAL_RESET_DATE = datetime(2026, 12, 31, 23, 59, 59)

def get_level(steps):
    """
    根據步數計算等級:
    Lv1: 0~1,000
    Lv2: 1,001~20,000
    Lv3: 20,001~50,000
    Lv4: 50,001~150,000
    Lv5: 150,001~300,000
    Lv6: 300,001~700,000
    Lv7: 700,001~1,000,000
    Lv8: 1,000,001以上
    """
    if steps <= 1000: return 1
    if steps <= 20000: return 2
    if steps <= 50000: return 3
    if steps <= 150000: return 4
    if steps <= 300000: return 5
    if steps <= 700000: return 6
    if steps <= 1000000: return 7
    return 8

@game_logic_bp.route('/distribute_appearances', methods=['POST'])
def distribute_appearances():
    res, status_code = do_distribute_appearances()
    return jsonify(res), status_code

def do_distribute_appearances(app_context=None):
    try:
        elders = ElderProfile.query.all()
        appearances = GawaAppearance.query.all()
        
        if not elders:
             return {"error": "No elders found to process"}, 400
        if not appearances:
            return {"error": "No appearances found in database"}, 400
            
        distributed = 0
        now = datetime.now(timezone.utc)
        
        for elder in elders:
            if elder.gawa_id:
                history_entry = GetAppearanceList(
                    elder_id=elder.elder_id,
                    gawa_id=elder.gawa_id,
                    feed_starttime=elder.feed_starttime or elder.create_ts,
                    feed_endtime=now,
                    gawa_size=elder.step_total if elder.step_total is not None else 0
                )
                db.session.add(history_entry)
            
            # gawa_xp 欄位不存在或不使用，僅處理 step_total 重置邏輯 (依需求保留步數重置或轉移)
            # if elder.step_total:
            #     elder.gawa_xp = (elder.gawa_xp or 0) + elder.step_total
            elder.step_total = 0
            
            random_appearance = random.choice(appearances)
            elder.gawa_id = random_appearance.gawa_id
            elder.feed_starttime = now
            distributed += 1
            
        db.session.commit()
        return {
            "status": "success",
            "message": f"Distributed appearances to {distributed} elders",
            "timestamp": now.isoformat()
        }, 200
    except Exception as e:
        db.session.rollback()
        import traceback
        traceback.print_exc()
        return {"status": "error", "message": str(e)}, 500

@game_logic_bp.route('/admin/set_distribution_time', methods=['POST'])
def set_distribution_time():
    data = request.json or {}
    dist_time = data.get('distribution_time') 
    if not dist_time:
        return jsonify({"status": "error", "message": "Missing distribution_time"}), 400
        
    save_schedule_time(dist_time)
    
    return jsonify({
        "status": "success", 
        "message": f"Global distribution scheduled for {dist_time}"
    })

@game_logic_bp.route('/leaderboard/<elder_id>', methods=['GET'])
def get_leaderboard(elder_id):
    """
    撱箇?銝??撅祆閰涪lder??銵?嚗?銵???摨??呈lder_profile?tep_total???芣?摨?
    靘elder_fellowship_data?????找??lder_id????鈭文???
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
        
        # Query ElderProfile and sort by step_total DESC
        leaderboard_data = ElderProfile.query.filter(ElderProfile.elder_id.in_(friend_ids)).order_by(ElderProfile.step_total.desc()).all()
        
        result = []
        user_entry = None
        user_rank = -1
        
        for index, entry in enumerate(leaderboard_data):
            steps = entry.step_total if entry.step_total is not None else 0
            entry_dict = {
                "elder_id": entry.elder_id,
                "elder_name": entry.elder_name,
                "step_total": steps,
                "level": get_level(steps),
                "rank": index + 1
            }
            if entry.elder_id == elder_id:
                user_entry = entry_dict
                user_rank = index + 1
            result.append(entry_dict)
            
        # 蝭拚??10 ??
        top_10 = result[:10]
        
        # 憒?雿輻???典? 10 ??撠??敺?
        if user_rank > 10 and user_entry:
            top_10.append(user_entry)
            
        return jsonify(top_10)
    except Exception as e:
        db.session.rollback()
        import traceback
        traceback.print_exc()
        return jsonify({"status": "error", "message": str(e)}), 500

@game_logic_bp.route('/check_reset', methods=['POST'])
def check_reset():
    """
    蝞∠??身摰????唳??舐恣?撥?嗆???蝵格?嚗?
    撠???step_total?脣??狂et_appearance_list銝剔?gawa_size甈?嚗?
    銝阡?蝵容lder_profile銝剔?step_total????
    """
    now = datetime.now(timezone.utc)
    data = request.json or {}
    force_reset = data.get('force', False)
    
    # ?亙??芸???蝵格???銝?銝阡???撘瑕?蔭嚗?銝銵?
    if now < GLOBAL_RESET_DATE and not force_reset:
        return jsonify({"status": "success", "message": "No reset needed, time not reached yet"})
    
    # ?曉????芸???嗅迤嚗???蝝??
    # ER?＊蝷?(elder_id, gawa_id) ?箄??蜓?蛛?隞?”?舫?風?莎??隞乩??賜??query.all()嚗???嗅迤(feed_endtime == GLOBAL_RESET_DATE ?憭扳甇文)
    active_appearances = GetAppearanceList.query.filter(GetAppearanceList.feed_endtime >= now).all()
    
    updated_count = 0
    for app in active_appearances:
        elder = ElderProfile.query.filter_by(elder_id=app.elder_id).first()
        if elder:
            # 1. ?脣? step_total ??gawa_size
            app.gawa_size = elder.step_total if elder.step_total is not None else 0
            
            # 2. 蝯???閮剔?曉 (憒??臬撥?園?蝵桃?閰?
            app.feed_endtime = now
            
            # 3. ?蔭憭扳郊??
            # 3. 步數重置邏輯 (若需要)
            # if elder.step_total:
            #     elder.gawa_xp = (elder.gawa_xp or 0) + elder.step_total
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
    
    steps = elder.step_total if elder.step_total is not None else 0
    
    return jsonify({
        "status": "success",
        "elder_name": elder.elder_name,
        "step_total": steps,
        "level": get_level(steps),
        "gawa_id": elder.gawa_id,
        "gawa_name": appearance.gawa_name if appearance else "無",
        "feed_starttime": elder.feed_starttime.isoformat() if elder.feed_starttime else None
    })

# --- [Elder API] ???????蜇?? ---
@game_logic_bp.route('/elder/collection/<elder_id>', methods=['GET'])
def get_elder_collection(elder_id):
    try:
        # 取得目前使用中的造型
        elder = ElderProfile.query.filter_by(elder_id=elder_id).first()
        current_gawa_id = elder.gawa_id if elder else None

        # 根據需求：目前造型只需顯示當前在elder_profile的gawa_id即可，不需要顯示包含get_appearance_list裡的所有擁有過的造型紀錄
        gawa_ids = [current_gawa_id] if current_gawa_id else []
        
        if not gawa_ids:
            return jsonify({
                "status": "success",
                "total_bonus": 0.0,
                "collection": []
            })
            
        appearances = GawaAppearance.query.filter(GawaAppearance.gawa_id.in_(gawa_ids)).all()
        total_bonus = sum([a.bonus for a in appearances if a.bonus is not None])
        
        collection = []
        for app in appearances:
            collection.append({
                "gawa_id": app.gawa_id,
                "gawa_name": app.gawa_name,
                "gawa_rarity": app.gawa_rarity,
                "bonus": app.bonus if app.bonus is not None else 0.0
            })
            
        return jsonify({
            "status": "success",
            "total_bonus": total_bonus,
            "collection": collection
        })
    except Exception as e:
        import traceback
        traceback.print_exc()
        return jsonify({"status": "error", "message": str(e)}), 500

# --- [Elder API] 更新長輩步數 ---
@game_logic_bp.route('/elder/update_steps', methods=['POST'])
def update_steps():
    data = request.json or {}
    elder_id = data.get('elder_id')
    try:
        delta_steps = int(data.get('delta_steps', 0))
    except (ValueError, TypeError):
        delta_steps = 0
        
    if not elder_id or delta_steps <= 0:
        return jsonify({"status": "error", "message": "Invalid elder_id or delta_steps"}), 400
        
    try:
        elder = ElderProfile.query.filter_by(elder_id=elder_id).first()
        if not elder:
            return jsonify({"status": "error", "message": "Elder not found"}), 404
            
        if elder.step_total is None:
            elder.step_total = 0
            
        elder.step_total += delta_steps
        # elder.gawa_xp 欄位不使用
        db.session.commit()
        
        return jsonify({
            "status": "success", 
            "message": f"Added {delta_steps} steps",
            "new_total": elder.step_total
        })
    except Exception as e:
        db.session.rollback()
        import traceback
        traceback.print_exc()
        return jsonify({"status": "error", "message": str(e)}), 500

# --- [Admin API] 查詢指派長輩資料 ---
@game_logic_bp.route('/admin/elder_info/<elder_id>', methods=['GET'])
def get_admin_elder_info(elder_id):
    elder = ElderProfile.query.filter_by(elder_id=elder_id).first()
    if not elder:
        return jsonify({"status": "error", "message": "Elder not found"}), 404
        
    # 根據需求：目前造型只需顯示當前在elder_profile的gawa_id即可
    gawa_ids = [elder.gawa_id] if elder.gawa_id else []
        
    appearances = GawaAppearance.query.filter(GawaAppearance.gawa_id.in_(gawa_ids)).all() if gawa_ids else []
    total_bonus = sum([a.bonus for a in appearances if a.bonus is not None])
    
    collection = [{"gawa_id": a.gawa_id, "gawa_name": a.gawa_name, "bonus": a.bonus if a.bonus is not None else 0.0} for a in appearances]
    
    return jsonify({
        "status": "success",
        "elder_id": elder.elder_id,
        "elder_name": elder.elder_name,
        "step_total": elder.step_total if elder.step_total is not None else 0,
        "total_bonus": total_bonus,
        "owned_count": len(appearances),
        "collection": collection
    })

# --- [Admin API] ?桃???? ---
@game_logic_bp.route('/admin/assign_appearance', methods=['POST'])
def assign_appearance():
    data = request.json or {}
    elder_id = data.get('elder_id')
    gawa_id = data.get('gawa_id')
    
    if not elder_id or not gawa_id:
        return jsonify({"status": "error", "message": "Missing elder_id or gawa_id"}), 400
        
    try:
        elder = ElderProfile.query.filter_by(elder_id=elder_id).first()
        appearance = GawaAppearance.query.get(gawa_id)
        
        if not elder or not appearance:
            return jsonify({"status": "error", "message": "Elder or Appearance not found"}), 404
            
        now = datetime.now(timezone.utc)
        
        # 1. ?遢?桀???甇瑕蝝??
        if elder.gawa_id:
            history_entry = GetAppearanceList(
                elder_id=elder.elder_id,
                gawa_id=elder.gawa_id,
                feed_starttime=elder.feed_starttime or elder.create_ts,
                feed_endtime=now,
                gawa_size=elder.step_total if elder.step_total is not None else 0
            )
            db.session.add(history_entry)
            
        # 2. ?蔭???
        elder.step_total = 0
        
        # 3. ???圈?銝西身摰????
        elder.gawa_id = appearance.gawa_id
        elder.feed_starttime = now
        
        db.session.commit()
        return jsonify({
            "status": "success", 
            "message": f"Assigned appearance {appearance.gawa_name} to {elder.elder_name}"
        })
    except Exception as e:
        db.session.rollback()
        import traceback
        traceback.print_exc()
        return jsonify({"status": "error", "message": str(e)}), 500

@game_logic_bp.route('/save_steps', methods=['POST'])
def save_steps():
    data = request.json or {}
    elder_id = data.get('elder_id')
    steps = data.get('steps', 0)
    
    if not elder_id:
        return jsonify({"status": "error", "message": "Missing elder_id"}), 400
        
    elder = ElderProfile.query.filter_by(elder_id=elder_id).first()
    if not elder:
        return jsonify({"status": "error", "message": "Elder not found"}), 404
        
    elder.step_total = (elder.step_total or 0) + (steps or 0)
    db.session.commit()
    return jsonify({"status": "success", "step_total": elder.step_total})

