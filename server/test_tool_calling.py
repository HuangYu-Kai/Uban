"""
test_tool_calling.py - 純文字版（相容 Windows PowerShell）
測試 LLM 是否正確呼叫 search_youtube_video 工具
執行：python test_tool_calling.py
"""

import os
import sys
import re

sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from flask import Flask
from extensions import db

app = Flask(__name__)
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///:memory:'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
db.init_app(app)

with app.app_context():
    from services.ollama_service import ollama_service
    import skills.common_skills as cs
    from skills import ALL_SKILLS

    # --- Monkey-patch: 攔截工具呼叫 ---
    tool_call_log = []
    _original_search = cs.search_youtube_video

    def patched_search(query: str):
        tool_call_log.append(("search_youtube_video", query))
        print(f"\n[TOOL CALLED] search_youtube_video(query='{query}')")
        result = _original_search(query)
        print(f"[TOOL RESULT] {result[:150]}")
        return result

    cs.search_youtube_video = patched_search
    for i, f in enumerate(ALL_SKILLS):
        if f.__name__ == 'search_youtube_video':
            ALL_SKILLS[i] = patched_search
            break

    # --- 測試案例 ---
    TEST_CASES = [
        {"name": "Case1: 明確點歌", "prompt": "我想聽張雨生的大海", "expect_tool": True},
        {"name": "Case2: 含歌手", "prompt": "幫我找一下周興哲的你好不好", "expect_tool": True},
        {"name": "Case3: 模糊老歌", "prompt": "播一首台語老歌", "expect_tool": True},
        {"name": "Case4: 非音樂", "prompt": "今天天氣怎麼樣？", "expect_tool": False},
    ]

    print("\n" + "="*60)
    print(f"Uban LLM Tool-Calling Test | Model: {ollama_service.model_name}")
    print("="*60)

    results = []
    for case in TEST_CASES:
        tool_call_log.clear()
        print(f"\n--- {case['name']} ---")
        print(f"User: {case['prompt']}")

        response = ollama_service.get_response(case['prompt'], user_id=None)

        print(f"\nAI Response:\n{response}\n")

        called     = len(tool_call_log) > 0
        has_vid    = bool(re.search(r'\[VIDEO_ID:[^\]]+\]', response))
        fake_vid   = 'example_vid' in response or 'example_video_id' in response

        print(f"[DIAG] tool_called={called} | has_VIDEO_ID={has_vid} | fake_id={fake_vid}")

        if case['expect_tool']:
            if called and has_vid and not fake_vid:
                print("[PASS] Tool called and real VIDEO_ID found")
            elif not called:
                print("[FAIL] Tool was NOT called - LLM hallucinated response!")
            elif fake_vid:
                print("[FAIL] VIDEO_ID is a fake placeholder (example_vid)")
            elif not has_vid:
                print("[FAIL] Tool called but VIDEO_ID missing from final response")
        else:
            print(f"[INFO] Non-music query - tool_called={called} (expected: False)")

        results.append({
            "name": case['name'],
            "called": called,
            "has_vid": has_vid,
            "fake_vid": fake_vid
        })

    print("\n" + "="*60)
    print("SUMMARY")
    print("="*60)
    for r in results:
        tag = "PASS" if (r['called'] and r['has_vid'] and not r['fake_vid']) else "FAIL"
        print(f"[{tag}] {r['name']} | tool={r['called']} | vid={r['has_vid']} | fake={r['fake_vid']}")
    print()
