import os
import sqlite3
from dotenv import load_dotenv

load_dotenv()

class DatabaseManager:
    def __init__(self):
        self._db_path = None
        self._conn = None

    def _get_db_path(self):
        if self._db_path is None:
            # 確保找到 server/instance/uban.db
            base_dir = os.path.dirname(os.path.abspath(__file__))
            self._db_path = os.path.join(base_dir, 'instance', 'uban.db')
            
            # 如果 instance 夾內沒有，嘗試同級目錄
            if not os.path.exists(self._db_path):
                alt_path = os.path.join(base_dir, 'uban.db')
                if os.path.exists(alt_path):
                    self._db_path = alt_path
        return self._db_path

    def connect(self):
        """建立 SQLite 連線"""
        try:
            path = self._get_db_path()
            self._conn = sqlite3.connect(path, check_same_thread=False)
            # 設定 row_factory 讓結果可以像字典一樣存取 (Row['column_name'])
            self._conn.row_factory = sqlite3.Row
            print(f"✅ [SQLite] 連線成功: {path}")
            return self._conn
        except Exception as e:
            print(f"❌ [SQLite] 連線失敗: {e}")
            return None

    def get_cursor(self):
        """獲取資料庫 Cursor"""
        if self._conn is None:
            self.connect()
        try:
            # 檢查連線是否還在 (SQLite 通常不需要，但為了保持穩定)
            return self._conn.cursor()
        except sqlite3.ProgrammingError:
            self.connect()
            return self._conn.cursor()

# 建立全域實體
db = DatabaseManager()

if __name__ == "__main__":
    print("--- 開始測試 SQLite 連線 ---")
    db.connect()
    cursor = db.get_cursor()
    if cursor:
        print("✅ Cursor 獲取成功")
        cursor.close()
    print("--- 測試結束 ---")