# -*- coding: utf-8 -*-
"""逐一驗證工作台裡「行號 → 該處應該有什麼」的承重引用。
每筆是 (檔案, 行號或區間, 必須命中的關鍵字之一, 這條支撐什麼說法)。
"""
import io, os

API = r"C:\Users\kevin\Desktop\115207\uban-api"
LIB = r"C:\Users\kevin\Desktop\115207\Uban\mobile_app\lib"
ADM = os.path.join(API, "uban-admin", "src")

CHECKS = [
    # ── 分端與登入 ──
    (LIB+r"\screens\splash_screen.dart", (215, 334), ["getStatus", "role"], "權威分流點以後端 role 為準"),
    (LIB+r"\screens\splash_screen.dart", (465, 490), ["PrivacyPolicyScreen", "prefsKey"], "隱私同意守門"),
    (LIB+r"\main.dart", (290, 302), ["PrivacyPolicyScreen", "prefsKey"], "先同意再要權限"),
    (API+r"\routers\pairing.py", (1001, 1030), ["generate_random_code(4)", "minutes=10"], "4 碼配對碼 10 分鐘"),
    (API+r"\routers\pairing.py", (1456, 1515), ["6 位數", "minutes=15"], "6 碼復原碼 15 分鐘"),
    (API+r"\routers\user.py", (287, 320), ["status"], "GET /status/{user_id}"),

    # ── AI 語音 ──
    (LIB+r"\screens\elder_home_screen.dart", (66, 400), ["嘎蛙", "SpeechToText", "wakeWord"], "喚醒詞常駐監聽"),
    (LIB+r"\screens\elder_chat_screen.dart", (355, 430), ["transcribe", "record"], "錄音送 ASR"),
    (LIB+r"\screens\elder_chat_screen.dart", (560, 580), ["tts/stream", "tts"], "後端串流 TTS"),
    (API+r"\routers\ai.py", (560, 580), ["chat_stream", "stream"], "SSE 串流端點"),
    (API+r"\services\tools_service.py", (360, 378), ["TOOL_MAP"], "工具表"),
    (LIB+r"\widgets\google_assistant_overlay.dart", (430, 440), ["天氣"], "天氣走語音而非獨立頁"),

    # ── 提醒 ──
    (API+r"\main.py", (329, 340), ["remote_reminder", "reminder"], "check_remote_reminders_job"),
    (API+r"\main.py", (460, 470), ["check_remote_reminders_job"], "每分鐘註冊"),
    (API+r"\routers\reminder.py", (145, 160), ["complete"], "回報完成端點"),
    (API+r"\routers\reminder.py", (130, 140), ["batch_create"], "批次建立"),

    # ── 通話與監控 ──
    (API+r"\services\socket_app.py", (240, 250), ["rooms_manager", "call_registry"], "信令層有狀態"),
    (API+r"\services\socket_app.py", (2055, 2065), ["call-request", "call_request"], "call-request handler"),
    (API+r"\services\socket_app.py", (2415, 2430), ["emergency", "emergency-call"], "emergency-call handler"),
    (API+r"\services\socket_app.py", (2790, 2805), ["end-call", "end_call"], "end-call handler"),
    (LIB+r"\services\signaling.dart", (820, 835), ["new-pond-leaf", "pond"], "落葉事件仍在收"),
    (LIB+r"\screens\family\family_interaction_tab.dart", (1982, 2400), ["Monitor", "監控"], "監控區"),
    (LIB+r"\screens\family\family_interaction_tab.dart", (1275, 1290), ["Copilot", "共創", "AI"], "AI 共創助理入口"),
    (LIB+r"\screens\family_main_screen.dart", (860, 875), ["targetSocketId"], "不綁單一 socket"),

    # ── 警報與誤報 ──
    (API+r"\routers\alert.py", (245, 260), ["false-alarm", "false_alarm"], "誤報端點"),
    (API+r"\routers\alert.py", (430, 445), ["cctv/frame", "frame"], "推幀端點"),
    (LIB+r"\screens\family\alert_center_screen.dart", (335, 545), ["誤報", "FalseAlarm", "false"], "標記誤報 UI"),
    (API+r"\main.py", (495, 545), ["yolo_monitor_job"], "30 秒看門狗"),
    (API+r"\services\yolo_alert_dispatcher.py", (65, 80), ["socket_app", "cctv-alert", "emit"], "派送警報"),

    # ── 訂閱 ──
    (LIB+r"\screens\family\family_subscription_screen.dart", (345, 360), ["TODO", "RevenueCat"], "正式訂閱頁仍是 TODO"),
    (API+r"\routers\subscription.py", (30, 70), ["free", "gold", "diamond"], "三層訂閱"),
    (API+r"\routers\subscription.py", (170, 185), ["webhook"], "RevenueCat webhook"),

    # ── 個人資料 ──
    (LIB+r"\screens\elder_profile_edit_screen.dart", (445, 460), ["僅供", "統計"], "居住地僅供統計可不填"),
    (LIB+r"\screens\elder_profile_edit_screen.dart", (115, 130), ["residence_city"], "優先採結構化欄位"),
    (LIB+r"\screens\family\family_data_tab.dart", (300, 310), ["ElderProfileEditScreen"], "家屬代填入口"),
    (LIB+r"\screens\family\family_settings_view.dart", (65, 220), ["residenceCity", "residence_city"], "家屬本人年齡居住地"),
    (LIB+r"\screens\family\family_data_tab.dart", (1120, 1135), ["Memoir", "回憶"], "回憶錄入口"),

    # ── 生命回顧 ──
    (LIB+r"\services\memoir_service.dart", (14, 20), ["uban_memoirs_"], "本機儲存鍵"),
    (LIB+r"\services\memoir_service.dart", (64, 96), ["SharedPreferences", "memoir_00"], "只讀本機並過濾假資料"),

    # ── 開發者管理端 ──
    (API+r"\main.py", (655, 692), ["SPAStaticFiles", "/admin"], "SPA 掛載"),
    (API+r"\main.py", (1190, 1197), ["socketio.ASGIApp"], "Socket.IO 包住 FastAPI"),
    (API+r"\auth_developer.py", (30, 45), ["DEVELOPER_TOKEN_EXPIRE_HOURS"], "12 小時"),
    (API+r"\auth_developer.py", (100, 115), ["get_current_developer"], "開發者驗證"),
    (API+r"\routers\developer.py", (78, 115), ["login", "me"], "登入與 me"),
    (API+r"\routers\developer.py", (130, 200), ["accounts", "password"], "帳號與改密碼"),
    (API+r"\routers\admin.py", (20, 35), ["account_ban", "登入", "ban"], "停權未擋登入"),
    (API+r"\routers\admin.py", (155, 205), ["BUG_REPORT_STATUSES", "wontfix"], "BUG 狀態機"),
    (API+r"\routers\admin.py", (85, 105), ["require_admin_or_developer"], "管理端守門"),
    (API+r"\routers\admin.py", (635, 650), ["reset", "season"], "賽季重置"),
    (API+r"\routers\admin_stats.py", (1, 70), ["elder_profile", "家屬"], "家屬判定方式"),
    (API+r"\routers\developer_users.py", (390, 400), ["timeline"], "時間軸端點"),

    # ── 寵物 ──
    (API+r"\database.py", (645, 670), ["pet_stage_threshold", "20000"], "5 階等距 20 公斤"),
    (API+r"\database.py", (688, 700), ["pet_season"], "賽季表"),
    (API+r"\routers\pet.py", (330, 340), ["food-unlocks", "food"], "果實解鎖"),

    # ── 社群 ──
    (API+r"\database.py", (563, 610), ["elder_friendship", "friend_post"], "長輩朋友圈表"),
    (API+r"\database.py", (776, 830), ["family_friend"], "家屬朋友圈表"),
    (API+r"\routers\friend.py", (140, 180), ["search", "request"], "好友搜尋與邀請"),
    (API+r"\routers\family_friend.py", (198, 215), ["my-code", "search"], "家屬代碼"),

    # ── 問題回報 ──
    (API+r"\routers\admin.py", (214, 250), ["bug-report", "bug_report"], "回報端點"),
    (API+r"\database.py", (858, 878), ["bug_report"], "回報表"),
]

def read_range(path, a, b):
    lines = io.open(path, encoding='utf-8', errors='ignore').read().splitlines()
    return '\n'.join(lines[max(0, a-1):b])

fails, oks = [], 0
for path, (a, b), kws, what in CHECKS:
    if not os.path.isfile(path):
        fails.append((os.path.basename(path), '%d-%d' % (a, b), what, '檔案不存在'))
        continue
    seg = read_range(path, a, b)
    if any(k in seg for k in kws):
        oks += 1
    else:
        fails.append((os.path.basename(path), '%d-%d' % (a, b), what, '找不到關鍵字 %s' % kws))

print('承重引用檢查：%d 筆，通過 %d，失敗 %d' % (len(CHECKS), oks, len(fails)))
if fails:
    print('\n--- 需要修正 ---')
    for f in fails:
        print('  X %-38s %-12s %s  → %s' % f)
