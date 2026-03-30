import os
import sys
import re

# 將 server 目錄加入路徑，以便導入 services
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# 模擬一個簡單的 Flask App 環境以支援 SQLAlchemy
from flask import Flask
from extensions import db

app = Flask(__name__)
# 使用 SQLite 記憶體資料庫避免汙染正式環境
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///:memory:'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
db.init_app(app)

with app.app_context():
    # 延遲導入 ollama_service 以確保 db 已初始化
    from services.ollama_service import ollama_service

    def run_tests():
        print("🚀 [UniFlow Backend] 開始測試多媒體清理與連結轉化邏輯...\n")
        
        test_cases = [
            {
                "name": "測試 1: 移除幻覺的 Markdown 連結並轉化為 VIDEO_ID",
                "input": "當然可以！[點擊播放櫻花影片](https://www.youtube.com/watch?v=dQw4w9WgXcQ) 給您看。",
                "expected": r"\[VIDEO_ID:dQw4w9WgXcQ\]",
                "not_expected": ["https://", "[點擊播放櫻花影片]"]
            },
            {
                "name": "測試 2: 處理 YouTube 搜尋連結並觸發 Fallback",
                "input": "這裡有日本櫻花的影片：https://www.youtube.com/results?search_query=日本櫻花樹",
                "expected": r"\[VIDEO_ID:[a-zA-Z0-9_-]{11}\]", # 預期會呼叫 search 並補上 ID
                "not_expected": ["results?search_query="]
            },
            {
                "name": "測試 3: 移除幻覺的 Placeholder 圖片",
                "input": "希望這段影片您會喜歡！![播放圖示](https://via.placeholder.com/150)",
                "expected_text": "希望這段影片您會喜歡！",
                "not_expected": ["![播放圖示]", "placeholder.com"]
            },
            {
                "name": "測試 4: 繁體中文轉換檢查與術語修正",
                "input": "这個视频很鮮，我给您看。",
                "expected_text": "這個影片很鮮", 
            }
        ]

        for case in test_cases:
            print(f"--- {case['name']} ---")
            print(f"輸入: {case['input']}")
            
            # 執行清潔邏輯
            output = ollama_service._clean_response(case['input'])
            print(f"輸出: {output}")
            
            success = True
            if "expected" in case:
                if not re.search(case["expected"], output):
                    print(f"❌ 缺失預期格式 (Regex): {case['expected']}")
                    success = False
            
            if "expected_text" in case:
                if case["expected_text"] not in output:
                    print(f"❌ 缺失預期文字: {case['expected_text']}")
                    success = False
            
            if "not_expected" in case:
                for unexp in case['not_expected']:
                    if unexp in output:
                        print(f"❌ 包含了不應出現的文字: {unexp}")
                        success = False
            
            if success:
                print("✅ 測試通過")
            else:
                print("⚠️ 測試失敗")
            print("-" * 50)

    if __name__ == "__main__":
        run_tests()
