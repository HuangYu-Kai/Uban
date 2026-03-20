import os
import pymysql
#from pymongo import MongoClient
from dotenv import load_dotenv

load_dotenv()

class DatabaseManager:
    def __init__(self):
        self.mongo_client = None
        self.mongo_db = None
        self.mysql_conn = None
    
    def connect_mysql(self):
        try:
            self.mysql_conn = pymysql.connect(
                host=os.getenv('MYSQL_HOST'),
                user=os.getenv('MYSQL_USER'),
                password=os.getenv('MYSQL_PASSWORD'),
                database=os.getenv('MYSQL_DB_NAME'),
                port=int(os.getenv('MYSQL_PORT', 3306)),
                cursorclass=pymysql.cursors.DictCursor,
                autocommit=True # 自動提交
            )
            print(f"MySQL Connection Successful: {os.getenv('MYSQL_HOST')}")
        except Exception as e:
            print(f"MySQL Connection Failed: {e}")

    def get_mysql_cursor(self):
        if self.mysql_conn is None:
            self.connect_mysql()
        try:
            # 確保連線依然有效
            self.mysql_conn.ping(reconnect=True)
        except:
            self.connect_mysql()
        return self.mysql_conn.cursor()


# 建立全域實體
db = DatabaseManager()

# ▼▼▼ 新增這段測試代碼 ▼▼▼
if __name__ == "__main__":
    print("--- 開始測試資料庫連線 ---")
    
    # 測試 MongoDB
    #print("正在嘗試連線 MongoDB...")
    #db.connect_mongo()
    
    # 測試 MySQL
    print("正在嘗試連線 MySQL...")
    db.connect_mysql()
    
    print("--- 測試結束 ---")