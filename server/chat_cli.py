import sys
import os
import re

# 確保能讀取到 services
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# 模擬一個簡單的 Profile 物件，避開資料庫需求
class MockProfile:
    elder_appellation = "您"
    ai_emotion_tone = 80
    ai_text_verbosity = 80

# 建立對話腳本
def main():
    try:
        from services.ollama_service import OllamaService
        # 如果導入過程中會觸發 models，我們需要攔截它
        import unittest.mock as mock
        
        # 建立一個 Mock 以避開 SQLAlchemy
        with mock.patch('models.ElderProfile') as mock_profile:
            mock_profile.query.filter_by.return_value.first.return_value = MockProfile()
            
            # 初始化服務 (預設會使用 qwen2.5:14b)
            service = OllamaService()
            
            # 模擬歷史紀錄
            history = []
            user_id = 1 
            
            print("="*50)
            print(f"Uban AI 文字測試終端 (Standalone Mode)")
            print(f"當前使用的模型: {service.model_name}")
            print("輸入 'exit' 或 'quit' 結束對話")
            print("="*50)
            print("\n[系統訊息] 正在載入本地設定檔 (SOUL.md, MEMORY.md)...")

            while True:
                try:
                    user_input = input("\n長輩詢問 > ").strip()
                    
                    if not user_input:
                        continue
                    if user_input.lower() in ['exit', 'quit', '離開']:
                        print("再見！祝您有美好的一天。")
                        break

                    print("AI 思考中...", end="\r")
                    
                    full_reply = ""
                    print("AI 回應 > ", end="", flush=True)
                    
                    # 執行對話 (串流模式)
                    for chunk in service.get_response_stream(user_input, user_id=user_id, history=history):
                        # 過濾掉技術標記
                        clean_chunk = re.sub(r'\[VIDEO_ID:[^\]]+\]', '', chunk)
                        if clean_chunk:
                            # 檢查是否包含工具執行的成功標誌 (來自 save_elder_memory)
                            if "✅" in clean_chunk:
                                print(f"\n\033[92m[記憶存入] {clean_chunk}\033[0m")
                                full_reply += clean_chunk
                            else:
                                print(clean_chunk, end="", flush=True)
                                full_reply += clean_chunk
                    
                    print("\n")
                    
                    # 更新歷史紀錄 (保留最近 5 輪)
                    history.append({"role": "user", "parts": [user_input]})
                    history.append({"role": "model", "parts": [full_reply]})
                    if len(history) > 10:
                        history = history[-10:]

                except KeyboardInterrupt:
                    print("\n強制退出。")
                    break
                except Exception as e:
                    print(f"\n[對話錯誤] {e}")

    except Exception as e:
        print(f"啟動失敗: {e}")
        print("\n請確認是否已下載模型: ollama pull qwen2.5:14b")

if __name__ == "__main__":
    main()
