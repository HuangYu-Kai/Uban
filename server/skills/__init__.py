from .common_skills import get_current_time, get_weather_info
from .elder_skills import get_elder_context, notify_family_SOS, suggest_activity

# 將所有 Skill 匯整為一個列表，方便 GeminiService 直接載入
ALL_SKILLS = [
    get_current_time,
    get_weather_info,
    get_elder_context,
    notify_family_SOS,
    suggest_activity
]
