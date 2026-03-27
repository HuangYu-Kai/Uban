from .common_skills import get_current_time, get_weather_info, update_agent_memory
from .elder_skills import get_elder_context, notify_family_SOS, suggest_activity
from .comm_skills import get_family_messages, initiate_video_call
from .health_skills import record_elder_activity

# 匯出所有可供 Gemini 使用的技能函數
ALL_SKILLS = [
    get_current_time,
    get_weather_info,
    get_elder_context,
    notify_family_SOS,
    suggest_activity,
    get_family_messages,
    initiate_video_call,
    record_elder_activity,
    update_agent_memory
]
