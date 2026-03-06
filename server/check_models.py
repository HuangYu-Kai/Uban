import google.generativeai as genai
import os
from dotenv import load_dotenv

# 載入 .env 文件
load_dotenv()

def check_available_models():
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        print("❌ 錯誤：找不到 GEMINI_API_KEY。請檢查 server/.env 檔案。")
        return

    try:
        genai.configure(api_key=api_key)
        print("🔍 正在獲取可用模型清單...\n")
        
        # 列出所有可用的模型
        models = genai.list_models()
        
        print(f"{'模型名稱':<40} | {'支援功能'}")
        print("-" * 70)
        
        available_count = 0
        for m in models:
            if 'generateContent' in m.supported_generation_methods:
                print(f"{m.name:<40} | {', '.join(m.supported_generation_methods)}")
                available_count += 1
        
        print(f"\n✅ 檢查完成！共找到 {available_count} 個支援生成內容的模型。")
        print("\n💡 提示：目前的 App 使用的是 'models/gemini-2.0-flash'。")
        
    except Exception as e:
        print(f"❌ 發生錯誤：{str(e)}")

if __name__ == "__main__":
    check_available_models()
