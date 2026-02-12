import os
import mysql.connector
from pymongo import MongoClient
from dotenv import load_dotenv

load_dotenv()

class DatabaseManager:
    def __init__(self):
        self.mongo_client = None
        self.mongo_db = None
        self.mysql_conn = None

    def connect_mongo(self):
        uri = os.getenv('MONGO_URI')
        db_name = os.getenv('MONGO_DB_NAME')
        try:
            self.mongo_client = MongoClient(uri)
            self.mongo_db = self.mongo_client[db_name]
            # 測試連線
            self.mongo_client.admin.command('ping')
            print(f"✅ [MongoDB] 連線成功: {uri}")
        except Exception as e:
            print(f"❌ [MongoDB] 連線失敗: {e}")

    def connect_mysql(self):
        try:
            self.mysql_conn = mysql.connector.connect(
                host=os.getenv('MYSQL_HOST'),
                user=os.getenv('MYSQL_USER'),
                password=os.getenv('MYSQL_PASSWORD'),
                database=os.getenv('MYSQL_DB_NAME'),
                port=int(os.getenv('MYSQL_PORT', 3306))
            )
            if self.mysql_conn.is_connected():
                 print(f"✅ [MySQL] 連線成功: {os.getenv('MYSQL_HOST')}")
        except Exception as e:
            print(f"❌ [MySQL] 連線失敗: {e}")

    def get_mongo_collection(self, collection_name):
        if self.mongo_db is None:
            self.connect_mongo()
        return self.mongo_db[collection_name]

    def get_mysql_cursor(self):
        if self.mysql_conn is None or not self.mysql_conn.is_connected():
            self.connect_mysql()
        return self.mysql_conn.cursor(dictionary=True) # dictionary=True 讓回傳結果變成字典，方便操作


# 建立全域實體
db = DatabaseManager()

# ▼▼▼ 新增這段測試代碼 ▼▼▼
if __name__ == "__main__":
    print("--- 開始測試資料庫連線 ---")
    
    # 測試 MongoDB
    print("正在嘗試連線 MongoDB...")
    db.connect_mongo()
    
    # 測試 MySQL
    print("正在嘗試連線 MySQL...")
    db.connect_mysql()
    
    print("--- 測試結束 ---")