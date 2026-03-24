import sys
import os
import json

# Add the server directory to the python path
sys.path.append(os.path.join(os.getcwd(), 'server'))

from services.gemini_service import gemini_service
from flask import Flask
from extensions import db
from models import ElderProfile, UserAccountData

app = Flask(__name__)
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///:memory:'
db.init_app(app)

with app.app_context():
    db.create_all()
    # Create a dummy user/profile if needed by the service
    user = UserAccountData(
        user_name="test_elder", 
        user_email="test@example.com",
        password="hashed_password",
        user_authority="Normal"
    )
    db.session.add(user)
    db.session.commit()
    
    profile = ElderProfile(
        elder_id="test-uuid",
        user_id=user.user_id, 
        elder_name="小明", 
        elder_appellation="爺爺",
        gender="M",
        age=80
    )
    db.session.add(profile)
    db.session.commit()

    print("--- Testing regular response ---")
    try:
        resp = gemini_service.get_response("你好，請問現在幾點？", user_id=user.user_id)
        print(f"AI Response: {resp}")
    except Exception as e:
        print(f"Regular Response Error: {e}")

    print("\n--- Testing tool call (Time) ---")
    try:
        resp_time = gemini_service.get_response("現在時間是？", user_id=user.user_id)
        print(f"AI Response with tool call: {resp_time}")
    except Exception as e:
        print(f"Tool Call Error: {e}")

    print("\n--- Testing streaming response ---")
    try:
        stream = gemini_service.get_response_stream("說個短笑話", user_id=user.user_id)
        for chunk in stream:
            print(chunk, end="", flush=True)
        print()
    except Exception as e:
        print(f"Streaming Error: {e}")
