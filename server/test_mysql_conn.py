import os
import pymysql
from dotenv import load_dotenv

# 載入 .env 檔案
load_dotenv()

def test_mysql_connection():
    # 從環境變數讀取連線資訊
    host = os.getenv('host')
    port = int(os.getenv('port', 3306))
    user = os.getenv('username')
    password = os.getenv('password')
    db_name = os.getenv('name')

    print(f"--- 開始測試 MySQL 連線 ---")
    print(f"嘗試連線至: {host}:{port}, 資料庫: {db_name}, 使用者: {user}")

    try:
        # 建立連線
        connection = pymysql.connect(
            host=host,
            port=port,
            user=user,
            password=password,
            database=db_name,
            charset='utf8mb4',
            cursorclass=pymysql.cursors.DictCursor
        )

        with connection.cursor() as cursor:
            # 測試簡單查詢：獲取資料庫版本
            cursor.execute("SELECT VERSION()")
            version = cursor.fetchone()
            print(f"✅ 連線成功！MySQL 版本: {version['VERSION()']}")

            # 測試讀取資料：列出所有資料表
            cursor.execute("SHOW TABLES")
            tables = cursor.fetchall()
            print(f"✅ 成功讀取資料庫，共有 {len(tables)} 個資料表：")
            for table in tables:
                # pymysql DictCursor 會回傳 {'Tables_in_dbname': 'tablename'}
                print(f"  - {list(table.values())[0]}")

        connection.close()
        print(f"--- 測試結束 ---")
        return True

    except Exception as e:
        print(f"❌ 連線失敗: {e}")
        print(f"--- 測試結束 ---")
        return False

if __name__ == "__main__":
    test_mysql_connection()
