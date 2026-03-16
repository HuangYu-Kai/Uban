import pymysql
import os
from dotenv import load_dotenv

def test_connection():
    # Load environment variables from .env if it exists
    load_dotenv()

    # Configuration - Replace these with your actual MySQL credentials
    # or add them to your .env file
    host = os.getenv("MYSQL_HOST")
    user = os.getenv("MYSQL_USER")
    password = os.getenv("MYSQL_PASSWORD")
    database = os.getenv("MYSQL_DB")
    port = int(os.getenv("MYSQL_PORT"))

    print(f"--- 正在嘗試連接到 MySQL 伺服器: {host}:{port} ---")
    
    try:
        connection = pymysql.connect(
            host=host,
            user=user,
            password=password,
            database=database,
            port=port,
            cursorclass=pymysql.cursors.DictCursor
        )
        with connection.cursor() as cursor:
            # 執行簡單查詢
            cursor.execute("SELECT VERSION();")
            version = cursor.fetchone()
            print(f"✅ 連接成功!")
            print(f"MySQL 版本: {version.get('VERSION()')}")
        
        connection.close()
    except pymysql.MySQLError as e:
        print(f"❌ 連接失敗!")
        print(f"錯誤代碼: {e.args[0]}")
        print(f"錯誤訊息: {e.args[1]}")
    except Exception as e:
        print(f"❌ 發生非預期錯誤: {str(e)}")

if __name__ == "__main__":
    # 檢查是否安裝了 pymysql
    try:
        import pymysql
    except ImportError:
        print("❌ 找不到 'pymysql' 套件。")
        print("請執行: pip install pymysql")
    else:
        test_connection()
