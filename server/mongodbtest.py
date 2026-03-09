from pymongo import MongoClient
from datetime import datetime, timedelta

# 1. 建立與本地端 MongoDB 的連線
print("正在連線到 MongoDB...")
client = MongoClient('mongodb://localhost:27017/')

# 2. 指定資料庫與集合 (如果不存在，MongoDB 會在寫入時自動建立)
db = client['uban_db']
chat_collection = db['ai_chat_history']

# 3. 準備要寫入的資料 (Python 的字典格式)
# 這裡我們模擬長輩 (elder_id: A123) 收到了一則 AI 語音提醒
now = datetime.utcnow()
retention_days = 7 # 假設這位長輩的家屬是 Sub1 訂閱層級，保留 7 天

chat_document = {
    "elder_id": "A123",
    "role": "ai",
    "message_text": "阿公，外面變冷了，記得多穿一件外套喔！",
    "audio_url": "https://your-r2-bucket.com/voice/A123/remind_coat.mp3", # 模擬 R2 的網址
    "created_at": now,
    "expire_at": now + timedelta(days=retention_days) # Python 幫你精準算好 7 天後的時間
}

# 4. 執行寫入動作
print("正在寫入資料...")
result = chat_collection.insert_one(chat_document)

# 5. 印出成功訊息與 MongoDB 自動配發的專屬 ID
print(f"✅ 寫入成功！這筆資料的專屬 ID 是: {result.inserted_id}")