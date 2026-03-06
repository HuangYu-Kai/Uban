import os
from dotenv import load_dotenv
from app import app
from flask import g
from services.gemini_service import gemini_service

load_dotenv()

def test_stream(question, user_id=13):
    print(f"\n========== TEST: {question} ==========")
    # Run inside app context so g.current_user_id works
    with app.app_context():
        g.current_user_id = user_id
        g.pending_actions = []
        
        # Call the stream method (returns a generator)
        stream_generator = gemini_service.get_response_stream(question, user_id=user_id)
        
        try:
            for chunk in stream_generator:
                print(chunk, end="", flush=True)
            print("\n[STREAM COMPLETE]")
        except Exception as e:
            print(f"\n[STREAM FAILED] Exception: {e}")

if __name__ == "__main__":
    if not os.getenv("GEMINI_API_KEY"):
        print("ERROR: GEMINI_API_KEY is missing from environment.")
    else:
        test_stream("你好呀！")
        test_stream("你知道我叫什麼嗎？我的興趣是什麼？")
        test_stream("現在幾點了？")
        test_stream("台北今天天氣怎麼樣？")

