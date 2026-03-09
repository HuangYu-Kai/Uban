import sqlite3
import os
db_path = os.path.join(os.path.dirname(__file__), 'instance', 'uban.db')
if not os.path.exists(db_path):
    db_path = os.path.join(os.path.dirname(__file__), 'uban.db')
conn = sqlite3.connect(db_path)
for row in conn.execute("SELECT sql FROM sqlite_master WHERE type='table'"):
    if row[0]:
        print(row[0])
conn.close()
