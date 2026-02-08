import sqlite3
import os

def inspect_db():
    # 確保不論從哪裡執行，都能找到同目錄下的 uban.db
    base_dir = os.path.dirname(os.path.abspath(__file__))
    # Flask-SQLAlchemy 預設會把 db 放在 instance 夾內
    db_path = os.path.join(base_dir, 'instance', 'uban.db')
    
    if not os.path.exists(db_path):
        # 嘗試向上或向同級尋找 (以防開發環境差異)
        db_path = os.path.join(base_dir, 'uban.db')
        if not os.path.exists(db_path):
            print(f"找不到資料庫檔案: {os.path.join(base_dir, 'instance', 'uban.db')} 或 {db_path}")
            return

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # 取得所有資料表名稱
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = cursor.fetchall()

    print("=== UBan 資料庫內容概覽 ===")
    
    for table_name in tables:
        table_name = table_name[0]
        if table_name == 'sqlite_sequence':
            continue
            
        print(f"\n--- 資料表: {table_name} ---")
        
        # 取得欄位名稱
        cursor.execute(f"PRAGMA table_info({table_name})")
        columns = [col[1] for col in cursor.fetchall()]
        print(f"欄位: {' | '.join(columns)}")
        
        # 取得資料
        cursor.execute(f"SELECT * FROM {table_name}")
        rows = cursor.fetchall()
        
        if not rows:
            print("( 目前無資料 )")
        else:
            for row in rows:
                print(' | '.join(map(str, row)))
                
    conn.close()

if __name__ == '__main__':
    inspect_db()
